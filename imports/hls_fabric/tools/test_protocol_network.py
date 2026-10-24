"""Qualify a finite source-driven feedback network, observation cuts and local component cost."""
from pathlib import Path
import argparse
import json
import os
import subprocess
from types import SimpleNamespace

from backend_paths import ROOT
from compiler_paths import PUBLIC
from compile_protocol_network import compile_network
from compile_protocol_transport import compile_clock
from backend_commands import run
from test_local_protocol import prove


def configuration(path: Path, function: str, arguments: str = '[]') -> None:
    """Bind current fixture sources to an explicit trusted topology constructor."""
    path.write_text('#{sources => [{"test/hls_protocol_network_fixture.erl",[]},'
                    '{"test/hls_protocol_inbox_fixture.erl",[]}],topology => '
                    '{hls_protocol_network_fixture,'+function+','+arguments+'},actor_limit => 3}.\n')


def simulate(fixture: Path, stage: Path, core: Path | None = None, reject: bool = False) -> None:
    """Score public outputs with automatic or held explicit start: order, feedback, stalls and reset."""
    manifest=json.loads((fixture/'network/manifest.json').read_text())
    explicit=manifest.get('activation')=='explicit_start'
    assert manifest['actors']==3 and manifest['links']==4 and manifest['additional_state_bits']==int(explicit)
    assert manifest['actor_runtime'] and not manifest['eligible']
    ports=manifest['inputs']+manifest['outputs']
    wires=[]; connections=['.clk(clk)']
    for port in ports:
        name,width=port['name'],port['width']; connections.append(f'.{name}({name})')
        if name!='reset': wires.append(f'wire [{width-1}:0] {name};')
    for boundary in manifest['boundaries']:
        name=boundary['name'];i=boundary['source_index']
        wires.extend([f'assign {name}_ready=ready[{i}];',f'assign valid[{i}]={name}_valid;',
                      f'assign data[{i}]={name}_data;'])
    if explicit: wires.append("assign start_valid=1'b1;")
    faults=[p['name'] for p in manifest['outputs'] if p['name'].endswith(('_fault','_failure'))]
    wires.append('wire [50:0] faults={'+','.join(faults)+'};')
    wires.append('protocol_network dut('+','.join(connections)+');')
    bench=stage/'bench.sv'
    bench.write_text((ROOT/'test/rtl/protocol_network_tb.sv').read_text().replace('@@WIRING@@','\n'.join(wires)))
    run(['iverilog','-g2012','-s','tb','-o',stage/'sim',bench,
         core or fixture/'network/core.v',fixture/'network/protocol_network.sv'],stage,'compile')
    with (stage/'simulate.log').open('x') as log:
        result=subprocess.run(['vvp',str(stage/'sim')],stdout=log,stderr=subprocess.STDOUT,timeout=30)
    text=(stage/'simulate.log').read_text()
    if reject:
        assert result.returncode!=0 and ('incomplete witness' in text or 'wrong frame/order' in text),text
    else:
        assert result.returncode==0 and 'PROTOCOL_NETWORK_PASS' in text,text


def negative_wiring(xls: Path, fixture: Path, stage: Path) -> None:
    """Require missing readiness and disconnected feedback to fail the same external scoreboard."""
    original=(fixture/'network/network.x').read_text()
    receiver=json.loads((fixture/'actors/receiver_0.x.json').read_text())
    link=receiver['inbox']['links'][0]['index']
    cases=[('drop-stalled-batch','output_ready: preview.source_0_ready','output_ready: true'),
           ('disconnect-feedback',f'link_{link}_selected: preview.link_{link}_selected',
            f'link_{link}_selected: bits[1]:0')]
    paths=[fixture/'actors',fixture/'dslx',ROOT/'priv/xls/lib',ROOT/'priv/xls/fabric',
           PUBLIC/'priv/xls/lib',PUBLIC/'priv/xls/fabric']
    for name,before,after in cases:
        part=stage/name;part.mkdir();source=part/'network.x'
        assert original.count(before)==1,before
        source.write_text(original.replace(before,after))
        # Deliberately corrupted test circuits bypass the production identity check.
        compile_clock(xls,source,part,'network_clock','protocol_network_core',paths)
        simulate(fixture,part,part/'core.v',reject=True)


def observation_cut(xls: Path, fixture: Path, stage: Path) -> None:
    """Prove the preview cut over every finite state/input bit pattern for this fixture."""
    ports=json.loads((fixture/'dslx/ports.json').read_text())
    controls=[p['name'] for p in ports['inputs'] if p['name'].endswith(('_take','_release_valid','_ready'))]
    assignments=', '.join(n+': updates.'+n for n in controls)
    source=stage/'network_cut.x'; raw=stage/'network_cut.ir'
    source.write_text('import transport;\n'
        '// Arbitrary independent retirement/readiness controls cannot affect observations.\n'
        'pub fn independent(s: transport::State, io: transport::Inputs, updates: transport::Inputs) -> bool {\n'
        'transport::tick(s, io).output == transport::tick(s, transport::Inputs {'+assignments+', ..io}).output }\n'
        '// Reset is deliberately not independent; the negative must yield a counterexample.\n'
        'pub fn wrong_reset(s: transport::State, io: transport::Inputs, reset: bool) -> bool {\n'
        'transport::tick(s, io).output == transport::tick(s, transport::Inputs { reset, ..io }).output }\n')
    run([xls/'ir_converter_main','--warnings_as_errors=false',
         '--dslx_path='+':'.join(map(str,[fixture/'dslx',ROOT/'priv/xls/lib',PUBLIC/'priv/xls/lib'])),
         '--dslx_stdlib_path='+str(xls/'xls/dslx/stdlib'),source],stage,'cut-convert',raw)
    args=SimpleNamespace(xls=xls,yosys='yosys')
    results=[prove(args,stage,raw,'network_cut',name,positive)
             for name,positive in [('independent',True),('wrong_reset',False)]]
    (stage/'cut-result.json').write_text(json.dumps({'results':results,
        'domain':'All finite transport state and independent input bit patterns of the 3-actor/4-link fixture.',
        'property':'Current observations do not depend on take, release or external ready.',
        'trust':['DSLX/XLS','Yosys/ABC/SAT'],
        'limits':'Combinational dependency cut only; not sequential refinement or network progress.'},indent=2)+'\n')


def area(fixture: Path, stage: Path) -> None:
    """Screen the whole connected fixture against preregistered local XC7 resource caps."""
    script=stage/'map.ys'; netlist=stage/'mapped.json'
    script.write_text(f'read_verilog "{fixture}/network/core.v" "{fixture}/network/protocol_network.sv"\n'
                      f'synth_xilinx -family xc7 -top protocol_network -flatten -nowidelut\nwrite_json "{netlist}"\n')
    run(['yosys','-Q','-T','-s',script],stage,'map')
    cells=json.loads(netlist.read_text())['modules']['protocol_network']['cells'].values()
    types=[c['type'] for c in cells]
    counts={name:sum(t.startswith(prefix) for t in types)
            for name,prefix in [('lut','LUT'),('ff','FD'),('bram','RAMB'),('dsp','DSP')]}
    assert counts['lut']<=12000 and counts['ff']<=6000 and counts['bram']==counts['dsp']==0,counts
    (stage/'area.json').write_text(json.dumps({'xc7_counts':counts,
        'limits':'Local synthesis capacity screen, not native area or routed performance.'},indent=2)+'\n')


def main() -> None:
    """Run public generation/lowering, finite RTL witnesses, controls and unsupported-boundary rejection."""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls',type=lambda p:Path(p).resolve())
    parser.add_argument('stage',type=lambda p:Path(p).resolve())
    args=parser.parse_args(); stage=args.stage; stage.mkdir()
    config=stage/'fixture.config';configuration(config,'topology')
    fixture=stage/'fixture'
    run(['bash','tools/emit_protocol_network.sh',args.xls,config,fixture],stage,'public-build')
    simulate(fixture,stage)
    negative_wiring(args.xls,fixture,stage)
    observation_cut(args.xls,fixture,stage)
    area(fixture,stage)
    base=ROOT/'_build/default'
    os.environ['ERL_AFLAGS']='-pa '+' '.join('"'+str(p)+'"' for p in
        [base/'lib/hls_fabric/ebin',base/'checkouts/erl_hls/ebin'])
    for key in ['ingresses']:
        config=stage/(key+'.config');configuration(config,'unsupported','['+key+']')
        output=stage/key
        with (stage/(key+'.log')).open('x') as log:
            result=subprocess.run(['escript','tools/emit_protocol_network.escript',str(config),str(output)],
                cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,timeout=120)
        assert result.returncode!=0 and 'unsupported_protocol_ingress' in (stage/(key+'.log')).read_text()
        assert not (output/'network').exists()
    config=stage/'isolated.config';configuration(config,'isolated')
    isolated=stage/'isolated'
    run(['escript','tools/emit_protocol_network.escript',config,isolated],stage,'isolated-build')
    compile_network(args.xls,isolated)
    (stage/'result.json').write_text(json.dumps({'passed':True,'complete_incarnations':2,
        'interrupted_incarnations':1,'outputs_per_complete_incarnation':39,'final_sum':60,
        'negative_wiring':2,'unsupported_boundaries':['multiple_ingresses'],
        'zero_incoming_links':'lowered',
        'evidence':'Finite source-driven RTL witness and fixture combinational cut; no network admission or native claim.'},indent=2)+'\n')


if __name__ == '__main__':
    main()
