"""Qualify explicit source-network activation with setup, retained captures and reset."""
from pathlib import Path
import argparse
import json
import subprocess
from types import SimpleNamespace

from backend_paths import ROOT
from compiler_paths import compiler_root
from protocol_test_build import compile_clock
from test_protocol_network import area, configuration as network_config, simulate as network_simulate
from backend_commands import run
from test_local_protocol import prove


def configuration(path: Path) -> None:
    """Build real setup recipients and a source relay through the public entry point."""
    path.write_text('#{sources => [{"test/hls_protocol_activation_fixture.erl",[]},'
        '{"test/hls_protocol_startup_peer.erl",[]}],topology => '
        '{hls_protocol_activation_fixture,topology,[]},actor_limit => 3,activation => explicit_start}.\n')


def simulate(fixture: Path, stage: Path, core: Path | None = None, reject: bool = False) -> None:
    """Score only public pins across setup/start contention, independent stalls and reset."""
    manifest=json.loads((fixture/'network/manifest.json').read_text())
    assert manifest['activation']=='explicit_start' and manifest['additional_state_bits']==133
    assert manifest['actors']==3 and not manifest['eligible']
    lines=[];connections=['.clk(clk)']
    driven={'reset','start_valid','ingress_valid','ingress_data'}
    for port in manifest['inputs']+manifest['outputs']:
        name,width=port['name'],port['width'];connections.append(f'.{name}({name})')
        if name not in driven:lines.append(f'wire [{width-1}:0] {name};')
    for boundary in manifest['boundaries']:
        name=boundary['name'];i=boundary['source_index']
        lines += [f'assign {name}_ready=ready[{i}];',f'assign valid[{i}]={name}_valid;',f'assign data[{i}]={name}_data;']
    faults=[p['name'] for p in manifest['outputs'] if p['name'].startswith('actor_')]
    lines += ['wire [50:0] faults={'+','.join(faults)+'};','protocol_network dut('+','.join(connections)+');']
    bench=stage/'bench.sv';bench.write_text((ROOT/'test/rtl/protocol_activation_tb.sv').read_text().replace('@@WIRING@@','\n'.join(lines)))
    run(['iverilog','-g2012','-s','tb','-o',stage/'sim',bench,core or fixture/'network/core.v',
         fixture/'network/protocol_network.sv'],stage,'compile')
    with (stage/'simulate.log').open('x') as log:
        result=subprocess.run(['vvp',str(stage/'sim')],stdout=log,stderr=subprocess.STDOUT,timeout=30)
    diagnostic=(stage/'simulate.log').read_text()
    if reject:
        assert result.returncode!=0 and any(s in diagnostic for s in
            ['internal traffic before start','premature start readiness','blocked setup incorrectly started']),diagnostic
    else:
        assert result.returncode==0 and 'PROTOCOL_ACTIVATION_PASS' in diagnostic,diagnostic


def negative_wiring(xls: Path, fixture: Path, stage: Path) -> None:
    """Require ungated captures and ignoring setup to fail the same public scoreboard."""
    original=(fixture/'network/network.x').read_text()
    cases=[('ungated','activation::eligible(s.activation, io.reset, ',
            'activation::eligible(activation::State { running: true }, io.reset, '),
           ('premature-start','startup_done, ingress_idle: ingress_offer.ready, ingress_valid: io.ingress_valid',
            'startup_done: true, ingress_idle: true, ingress_valid: false')]
    paths=[fixture/'actors',fixture/'dslx',ROOT/'apps/hls_lowering/priv/xls/lib',ROOT/'apps/hls_lowering/priv/xls/fabric',compiler_root('default')/'priv/xls/lib',compiler_root('default')/'priv/xls/fabric']
    for name,before,after in cases:
        part=stage/name;part.mkdir();source=part/'network.x';assert before in original
        source.write_text(original.replace(before,after))
        # Deliberately corrupt only the test circuit, bypassing production identity checks.
        compile_clock(xls,source,part,'network_clock','protocol_network_core',paths)
        simulate(fixture,part,part/'core.v',reject=True)


def properties(xls: Path, fixture: Path, stage: Path) -> None:
    """Quantify every control bit and all fixture state/input bits for the registered start cut."""
    args=SimpleNamespace(xls=xls,yosys='yosys');raw=stage/'properties.ir'
    imports=[fixture/'network',fixture/'actors',fixture/'dslx',ROOT/'apps/hls_lowering/priv/xls/lib',compiler_root('default')/'priv/xls/lib',compiler_root('default')/'priv/xls/fabric']
    converter=[xls/'ir_converter_main','--warnings_as_errors=false','--dslx_path='+':'.join(map(str,imports)),
               '--dslx_stdlib_path='+str(xls/'xls/dslx/stdlib')]
    run([*converter,ROOT/'test/protocol_activation_properties.x'],stage,'properties-convert',raw)
    results=[prove(args,stage,raw,'protocol_activation_properties',name,name!='wrong_start')
             for name in ['readiness','transition','registered','masks','wrong_start']]
    cut=stage/'start_cut.x';cut_ir=stage/'start_cut.ir'
    cut.write_text('import network;\n'
        '// Every fixture state/input: live start only changes the next activation bit.\n'
        'pub fn registered(s: network::State, io: network::Inputs) -> bool {\n'
        'let a = network::tick(s, network::Inputs { start_valid: false, ..io }); '
        'let b = network::tick(s, network::Inputs { start_valid: true, ..io });\n'
        'a.output == b.output && a.state.transport == b.state.transport && '
        'a.state.ingress == b.state.ingress && a.state.actor_0 == b.state.actor_0 && '
        'a.state.actor_1 == b.state.actor_1 && a.state.actor_2 == b.state.actor_2 }\n'
        '// All fixture bits: a pending command blocks start even on its last-consume edge.\n'
        'pub fn pending(s: network::State, io: network::Inputs) -> bool {\n'
        's.ingress.pending == u3:0 || !network::tick(s, io).output.start_ready }\n')
    run([*converter,cut],stage,'cut-convert',cut_ir)
    results += [prove(args,stage,cut_ir,'start_cut',name,True) for name in ['registered','pending']]
    (stage/'properties.json').write_text(json.dumps({'results':results,
        'domain':'All activation state/control bits; every mask bit at widths 1/3/8/257; every finite generated three-actor fixture state/input bit.',
        'trust':['DSLX/XLS','Yosys/ABC/SAT'],
        'limits':'Combinational properties only; no arbitrary-program refinement or network progress.'},indent=2)+'\n')


def component_area(xls: Path, stage: Path) -> None:
    """Screen activation's next-state/observation logic; its state type contains one bit."""
    source=stage/'activation_cost.x';raw=stage/'activation_cost.ir';optimized=stage/'activation_cost.opt.ir'
    source.write_text('import protocol_activation as activation;\n'
        '// Combinational cone around the one-bit activation register.\n'
        'pub fn logic(s: activation::State, c: activation::Conditions, valid: bool) -> activation::Tick {\n'
        'activation::tick(s, c, valid) }\n')
    run([xls/'ir_converter_main','--warnings_as_errors=false','--top=logic',
         '--dslx_path='+str(ROOT/'apps/hls_lowering/priv/xls/lib'),'--dslx_stdlib_path='+str(xls/'xls/dslx/stdlib'),source],stage,'cost-convert',raw)
    run([xls/'opt_main','--top=__activation_cost__logic',raw],stage,'cost-opt',optimized)
    verilog=stage/'activation_cost.v'
    run([xls/'codegen_main','--generator=combinational','--use_system_verilog=false',
         '--module_name=activation_cost',optimized],stage,'cost-codegen',verilog)
    script=stage/'cost.ys';netlist=stage/'cost.json'
    script.write_text(f'read_verilog "{verilog}"\nsynth_xilinx -family xc7 -top activation_cost -flatten -nowidelut\nwrite_json "{netlist}"\n')
    run(['yosys','-Q','-T','-s',script],stage,'cost-map')
    types=[c['type'] for c in json.loads(netlist.read_text())['modules']['activation_cost']['cells'].values()]
    counts={name:sum(t.startswith(prefix) for t in types)
            for name,prefix in [('lut','LUT'),('ff','FD'),('bram','RAMB'),('dsp','DSP')]}
    assert counts['lut']<=32 and counts['ff']==counts['bram']==counts['dsp']==0,counts
    (stage/'component-area.json').write_text(json.dumps({'combinational_xc7_counts':counts,'state_bits':1,
        'limits':'Combinational cone only; registered/gated integration is covered by the whole-network screen. No native forecast.'},indent=2)+'\n')


def without_host(xls: Path, stage: Path) -> None:
    """Exercise the second production branch: explicit start with no host ingress or startup records."""
    config=stage/'no-host.config';network_config(config,'topology')
    config.write_text(config.read_text().replace('actor_limit => 3','actor_limit => 3,activation => explicit_start'))
    fixture=stage/'no-host';run(['bash','tools/emit_protocol_network.sh',xls,config,fixture],stage,'no-host-build')
    result=stage/'no-host-witness';result.mkdir();network_simulate((fixture/'compiled').resolve(),result)


def main() -> None:
    """Build once, run finite witnesses/controls and prove cuts before a local connected-area screen."""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls',type=lambda p:Path(p).resolve())
    parser.add_argument('stage',type=lambda p:Path(p).resolve())
    args=parser.parse_args();stage=args.stage;stage.mkdir();config=stage/'fixture.config';configuration(config)
    fixture=stage/'fixture';run(['bash','tools/emit_protocol_network.sh',args.xls,config,fixture],stage,'public-build')
    fixture=(fixture/'compiled').resolve()
    simulate(fixture,stage);negative_wiring(args.xls,fixture,stage);properties(args.xls,fixture,stage)
    area(fixture,stage);component_area(args.xls,stage);without_host(args.xls,stage)
    (stage/'result.json').write_text(json.dumps({'passed':True,'complete_incarnations':2,'reset_interruptions':4,
        'commands_per_complete_incarnation':3,'outputs_per_complete_incarnation':9,'starts_per_incarnation':1,
        'blocked_setup_incarnations':6,'negative_wiring':2,'no_host_outputs_per_incarnation':39,
        'evidence':'Finite RTL witnesses and specified combinational properties; no application/native admission.'},indent=2)+'\n')


if __name__ == '__main__':
    main()
