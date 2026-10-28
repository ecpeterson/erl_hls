"""Qualify declared external endpoints with source traffic, held selection and scoped finite properties."""
from pathlib import Path
import argparse
import json
import subprocess
from types import SimpleNamespace

from backend_paths import ROOT, erlang_environment
from compiler_paths import compiler_root
from protocol_test_build import compile_clock
from backend_commands import run
from test_local_protocol import prove


def configuration(path: Path) -> None:
    """Bind four ordinary identified producers to shared, singleton and unused endpoints."""
    path.write_text('#{sources => [{"test/hls_protocol_boundary_fixture.erl",[]}],topology => '
        '{hls_protocol_boundary_fixture,topology,[]},actor_limit => 4,activation => explicit_start}.\n')


def imports(fixture: Path) -> list[Path]:
    """Resolve this exact fresh network and its source-derived components."""
    return [fixture/'network',fixture/'actors',fixture/'dslx',ROOT/'apps/hls_lowering/priv/xls/lib',
            ROOT/'apps/hls_lowering/priv/xls/fabric',compiler_root('default')/'priv/xls/lib',compiler_root('default')/'priv/xls/fabric']


def expected(stage: Path) -> list[list[str]]:
    """Use the fixture's ordinary BEAM codec, independently of emitted DSLX/RTL."""
    output=stage/'expected.json'
    env=erlang_environment('default')
    expression='{ok,M,B}=compile:file("test/hls_protocol_boundary_fixture.erl",[binary,debug_info,report,warnings_as_errors]),' \
        '{module,M}=code:load_binary(M,"fixture",B),ok=file:write_file('+json.dumps(str(output))+ \
        ',json:encode(M:expected())),halt().'
    with (stage/'oracle.log').open('x') as log:
        subprocess.run(['erl','-noshell','-eval',expression],cwd=ROOT,env=env,stdout=log,
                       stderr=subprocess.STDOUT,check=True,timeout=30)
    return json.loads(output.read_text())


def simulate(fixture: Path, stage: Path, frames: list[list[str]],
             core: Path | None = None, reject: bool = False) -> None:
    """Check public endpoint frames, producer order, independent stalls, host/start and reset."""
    manifest=json.loads((fixture/'boundary/manifest.json').read_text())
    assert manifest['actors']==4 and manifest['arbitration_state_bits']==5 and not manifest['eligible']
    assert [(e['id'],len(e['members']),e['state_bits']) for e in manifest['externals']]==[
        ('shared',3,5),('single',1,0),('unused',0,0)]
    lines=[];connections=['.clk(clk)'];driven={'reset','start_valid','ingress_valid','ingress_data'}
    for port in manifest['inputs']+manifest['outputs']:
        name,width=port['name'],port['width'];connections.append(f'.{name}({name})')
        if name not in driven:lines.append(f'wire [{width-1}:0] {name};')
    for e in manifest['externals']:
        i=e['index'];lines += [f'assign external_{i}_ready=ready[{i}];',
            f'assign valid[{i}]=external_{i}_valid;',f'assign data[{i}]=external_{i}_data;']
    faults=[p['name'] for p in manifest['outputs'] if p['name'].startswith('actor_')]
    lines += ['wire [67:0] faults={'+','.join(faults)+'};','protocol_boundary dut('+','.join(connections)+');']
    oracle=['function [127:0] expected(input integer producer,position);','case(producer*6+position)']
    oracle += [f"{6*i+j}:expected=128'h{frame};" for i,fs in enumerate(frames) for j,frame in enumerate(fs)]
    oracle += ["default:expected=128'bx;",'endcase','endfunction']
    bench=stage/'bench.sv';bench.write_text((ROOT/'test/rtl/protocol_boundary_tb.sv').read_text()
        .replace('@@WIRING@@','\n'.join(lines)).replace('@@EXPECTED@@','\n'.join(oracle)))
    run(['iverilog','-g2012','-s','tb','-o',stage/'sim',bench,core or fixture/'boundary/core.v',
         fixture/'boundary/protocol_boundary.sv'],stage,'compile')
    with (stage/'simulate.log').open('x') as log:
        result=subprocess.run(['vvp',str(stage/'sim')],stdout=log,stderr=subprocess.STDOUT,timeout=30)
    diagnostic=(stage/'simulate.log').read_text()
    if reject:
        assert result.returncode!=0 and any(s in diagnostic for s in
            ['changed stalled boundary frame','wrong boundary frame/order','incomplete boundary witness',
             'independent endpoint was stalled']),diagnostic
    else:assert result.returncode==0 and 'PROTOCOL_BOUNDARY_PASS' in diagnostic,diagnostic


def negative_wiring(xls: Path, fixture: Path, stage: Path, frames: list[list[str]]) -> None:
    """The same scoreboard must reject discarded locks and accepting unselected producers."""
    original=(fixture/'boundary/boundary.x').read_text()
    unlocked=original.replace('egress::tick(s.external_0,',
        'egress::tick(egress::State<2> { held: false, ..s.external_0 },')
    all_ready=original
    for k in range(3):all_ready=all_ready.replace(f'merge_0.output.ready[{k}+:u1]','io.external_0_ready')
    for name,text in [('unlocked',unlocked),('all-ready',all_ready)]:
        assert text!=original
        part=stage/name;part.mkdir();source=part/'boundary.x';source.write_text(text)
        # Intentionally corrupt test circuits bypass the production identity check.
        compile_clock(xls,source,part,'boundary_clock','protocol_boundary_core',imports(fixture))
        simulate(fixture,part,frames,part/'core.v',reject=True)


def properties(xls: Path, stage: Path) -> None:
    """Quantify all legal finite component states/inputs at 1/3/8/36 producers, plus finite service witnesses."""
    args=SimpleNamespace(xls=xls,yosys='yosys');results=[]
    common=['--warnings_as_errors=false','--dslx_path='+':'.join(map(str,[ROOT/'apps/hls_lowering/priv/xls/lib',compiler_root('default')/'priv/xls/lib'])),
            '--dslx_stdlib_path='+str(xls/'xls/dslx/stdlib')]
    for n in [1,3,8,36]:
        c=max(1,(n-1).bit_length());part=stage/f'properties-{n}';part.mkdir()
        source=part/'properties.x';raw=part/'properties.ir'
        source.write_text((ROOT/'test/protocol_egress_properties.x.in').read_text()
                          .replace('@@N@@',str(n)).replace('@@C@@',str(c)))
        run([xls/'ir_converter_main',*common,source],part,'convert',raw)
        for name in ['contract','availability','retained']+(['wrong_acceptance'] if n==3 else []):
            results.append(dict(fanin=n,**prove(args,part,raw,'properties',name,name!='wrong_acceptance')))
        run([xls/'interpreter_main','--evaluator=ir-jit','--compare=none',*common,source],part,'service-witness')
    (stage/'properties.json').write_text(json.dumps({'results':results,
        'domain':'All legal cursor/owner states, frame/request bits and controls at N=1/3/8/36; retention preserves only selected valid/frame. Finite service witness at every initial cursor for N accepted persistent-request grants with interleaved stalls.',
        'trust':['DSLX/XLS','Yosys/ABC/SAT','XLS JIT'],
        'limits':'Specified combinational properties and finite service witnesses, not general application progress.'},indent=2)+'\n')


def observation_cut(xls: Path, fixture: Path, stage: Path) -> None:
    """Check every actual generated network output against arbitrary independent producer readiness."""
    manifest=json.loads((fixture/'network/manifest.json').read_text())
    assignments=', '.join(b['name']+'_ready: other.'+b['name']+'_ready' for b in manifest['boundaries'])
    source=stage/'preview_cut.x';raw=stage/'preview_cut.ir'
    source.write_text('import network;\n// All finite fixture state/input bits; only live producer ready differs.\n'
        'pub fn independent(s: network::State, io: network::Inputs, other: network::Inputs) -> bool {\n'
        'network::tick(s, io).output == network::tick(s, network::Inputs {'+assignments+', ..io}).output }\n')
    run([xls/'ir_converter_main','--warnings_as_errors=false','--dslx_path='+':'.join(map(str,imports(fixture))),
         '--dslx_stdlib_path='+str(xls/'xls/dslx/stdlib'),source],stage,'cut-convert',raw)
    result=prove(SimpleNamespace(xls=xls,yosys='yosys'),stage,raw,'preview_cut','independent',True)
    (stage/'cut.json').write_text(json.dumps({'result':result,'actors':manifest['actors'],'links':manifest['links'],
        'domain':'All finite state and independent input bits of this exact generated source network.',
        'trust':['Source extraction','DSLX/XLS','Yosys/ABC/SAT'],
        'limits':'Observation dependency cut only; no sequential refinement or application progress.'},indent=2)+'\n')


def map_area(source: list[Path], top: str, stage: Path, lut: int, ff: int, require_lut: bool = True) -> dict[str,int]:
    """Record every original capacity limit; optional large-fanin LUT diagnosis is separate from functional qualification."""
    netlist=stage/'mapped.json';script=stage/'map.ys'
    script.write_text('read_verilog '+' '.join('"'+str(p)+'"' for p in source)+
        f'\nsynth_xilinx -family xc7 -top {top} -flatten -nowidelut\nwrite_json "{netlist}"\n')
    run(['yosys','-Q','-T','-s',script],stage,'map')
    types=[c['type'] for c in json.loads(netlist.read_text())['modules'][top]['cells'].values()]
    counts={name:sum(t.startswith(prefix) for t in types)
            for name,prefix in [('lut','LUT'),('ff','FD'),('bram','RAMB'),('dsp','DSP')]}
    (stage/'area.json').write_text(json.dumps({'xc7_counts':counts,'caps':{'lut':lut,'ff':ff,'bram':0,'dsp':0},
        'within_budget':counts['lut']<=lut and counts['ff']<=ff and counts['bram']==counts['dsp']==0,
        'required_for_functional_regression':require_lut,
        'limits':'Local capacity screen, not native area or routed timing.'},indent=2)+'\n')
    assert counts['ff']<=ff and counts['bram']==counts['dsp']==0,counts
    if require_lut:assert counts['lut']<=lut,counts
    elif counts['lut']>lut:print(f'CAPACITY SCREEN FAILED: {top}: {counts["lut"]} LUT > {lut}; no capacity admission',flush=True)
    return counts


def component_area(xls: Path, stage: Path) -> None:
    """Screen mux/arbitration plus only its ownership registers; singleton matches production bypass."""
    for n in [1,3,8,36]:
        c=max(1,(n-1).bit_length());part=stage/f'cost-{n}';part.mkdir();source=part/'cost.x'
        source.write_text((ROOT/'test/protocol_egress_cost.x.in').read_text()
                          .replace('@@N@@',str(n)).replace('@@C@@',str(c)))
        compile_clock(xls,source,part,'cost_clock','cost',[ROOT/'apps/hls_lowering/priv/xls/lib',compiler_root('default')/'priv/xls/lib'])
        adapter=part/'pins.sv'
        adapter.write_text((ROOT/'test/rtl/protocol_egress_cost.sv.in').read_text()
                           .replace('@@N@@',str(n)).replace('@@FRAME_BITS@@',str(128*n)))
        map_area([part/'core.v',adapter],'cost_pins',part,64*n+64,0 if n==1 else 2*c+1,require_lut=n<=8)


def main() -> None:
    """Build once; qualify public traffic, rejecting controls, component cuts/cost and a feedback-network cut."""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls',type=lambda p:Path(p).resolve());parser.add_argument('stage',type=lambda p:Path(p).resolve())
    args=parser.parse_args();stage=args.stage;stage.mkdir();config=stage/'fixture.config';configuration(config)
    fixture=stage/'fixture';run(['bash','tools/emit_protocol_boundary.sh',args.xls,config,fixture],stage,'public-build')
    fixture=(fixture/'compiled').resolve()
    frames=expected(stage);simulate(fixture,stage,frames);negative_wiring(args.xls,fixture,stage,frames)
    properties(args.xls,stage);observation_cut(args.xls,fixture,stage)
    map_area([fixture/'boundary/core.v',fixture/'boundary/protocol_boundary.sv'],'protocol_boundary',stage,16000,8000)
    component_area(args.xls,stage)
    # Internal feedback also needs the actual network preview cut; no old traffic witness is repeated.
    from test_protocol_activation import configuration as feedback_configuration
    feedback_config=stage/'feedback.config';feedback_configuration(feedback_config)
    feedback=stage/'feedback'
    run(['bash','tools/emit_protocol_boundary.sh',args.xls,feedback_config,feedback],stage,'feedback-build')
    observation_cut(args.xls,(feedback/'compiled').resolve(),feedback)
    (stage/'result.json').write_text(json.dumps({'functional_passed':True,
        'all_capacity_screens_passed':all(json.loads((stage/f'cost-{n}/area.json').read_text())['within_budget'] for n in [1,3,8,36]),
        'complete_incarnations':2,'reset_interruptions':4,
        'frames_per_complete_incarnation':24,'host_commands':7,'starts':1,'endpoint_fanin':[3,1,0],
        'negative_wiring':2,'component_fanin':[1,3,8,36],
        'evidence':'Finite RTL/service witnesses and scoped combinational properties; no application admission/native claim.'},indent=2)+'\n')


if __name__=='__main__':main()
