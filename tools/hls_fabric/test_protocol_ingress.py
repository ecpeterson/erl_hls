"""Qualify source-bound rectangle host input through the ordinary DSLX network."""
from pathlib import Path
import argparse
import json
import subprocess
from types import SimpleNamespace

from backend_paths import ROOT
from compiler_paths import compiler_root
from protocol_test_build import compile_clock
from test_protocol_network import area
from backend_commands import run
from test_local_protocol import prove


def configuration(path: Path) -> None:
    """Use two recipients and a real source relay through the public source build."""
    path.write_text('#{sources => [{"test/hls_protocol_ingress_fixture.erl",[]},'
        '{"test/hls_protocol_startup_peer.erl",[]}],topology => '
        '{hls_protocol_ingress_fixture,topology,[]},actor_limit => 3}.\n')


def simulate(fixture: Path, stage: Path, core: Path | None = None, reject: bool = False) -> None:
    """Score public host handshakes and output streams across selective receive, stalls and reset."""
    manifest=json.loads((fixture/'network/manifest.json').read_text())
    assert manifest['actors']==3 and manifest['additional_state_bits']==132
    assert manifest['ingress']['input_bits']==194 and not manifest['eligible']
    lines=[];connections=['.clk(clk)']
    for port in manifest['inputs']+manifest['outputs']:
        name,width=port['name'],port['width'];connections.append(f'.{name}({name})')
        if name not in ['reset','ingress_valid','ingress_data']:lines.append(f'wire [{width-1}:0] {name};')
    for boundary in manifest['boundaries']:
        name=boundary['name'];i=boundary['source_index']
        lines += [f'assign {name}_ready=ready[{i}];',f'assign valid[{i}]={name}_valid;',f'assign data[{i}]={name}_data;']
    faults=[p['name'] for p in manifest['outputs'] if p['name'].startswith('actor_')]
    lines += ['wire [50:0] faults={'+','.join(faults)+'};','protocol_network dut('+','.join(connections)+');']
    bench=stage/'bench.sv';bench.write_text((ROOT/'test/rtl/protocol_ingress_tb.sv').read_text().replace('@@WIRING@@','\n'.join(lines)))
    run(['iverilog','-g2012','-s','tb','-o',stage/'sim',bench,core or fixture/'network/core.v',
         fixture/'network/protocol_network.sv'],stage,'compile')
    with (stage/'simulate.log').open('x') as log:
        result=subprocess.run(['vvp',str(stage/'sim')],stdout=log,stderr=subprocess.STDOUT,timeout=30)
    diagnostic=(stage/'simulate.log').read_text()
    if reject:
        assert result.returncode!=0 and any(s in diagnostic for s in ['wrong ingress','incomplete ingress','unexpected source/ingress']),diagnostic
    else:
        assert result.returncode==0 and 'PROTOCOL_INGRESS_PASS' in diagnostic,diagnostic


def negative_wiring(xls: Path, fixture: Path, stage: Path) -> None:
    """Reject retirement on reservation and bypass of the immutable accepted frame."""
    original=(fixture/'network/network.x').read_text()
    offset=json.loads((fixture/'actors/receiver_0.x.json').read_text())['inbox']['host']['offset']
    cases=[('early-retire',f'step_0.output.take[{offset}+:u1]',f'step_0.output.accepted[{offset}+:u1]'),
           ('live-packet','host_frame: ingress_offer.frame','host_frame: ingress::decode(io.ingress_data).frame')]
    paths=[fixture/'actors',fixture/'dslx',ROOT/'apps/hls_lowering/priv/xls/lib',ROOT/'apps/hls_lowering/priv/xls/fabric',compiler_root('default')/'priv/xls/lib',compiler_root('default')/'priv/xls/fabric']
    for name,before,after in cases:
        part=stage/name;part.mkdir();source=part/'network.x';assert before in original
        source.write_text(original.replace(before,after))
        # Deliberate corruption bypasses the production source identity check.
        compile_clock(xls,source,part,'network_clock','protocol_network_core',paths)
        simulate(fixture,part,part/'core.v',reject=True)


def properties(xls: Path, fixture: Path, stage: Path) -> None:
    """Prove finite-state ingress rules and actual generated cuts, retaining a rejecting control."""
    args=SimpleNamespace(xls=xls,yosys='yosys');raw=stage/'properties.ir'
    imports=[fixture/'network',fixture/'actors',fixture/'dslx',ROOT/'apps/hls_lowering/priv/xls/lib',compiler_root('default')/'priv/xls/lib',compiler_root('default')/'priv/xls/fabric']
    converter=[xls/'ir_converter_main','--warnings_as_errors=false','--dslx_path='+':'.join(map(str,imports)),
               '--dslx_stdlib_path='+str(xls/'xls/dslx/stdlib')]
    run([*converter,ROOT/'test/protocol_ingress_properties.x'],stage,'properties-convert',raw)
    results=[prove(args,stage,raw,'protocol_ingress_properties',name,name!='wrong_retirement')
             for name in ['retirement','admission','reset_cancels','malformed','wrong_retirement']]
    cut=stage/'host_cut.x';cut_ir=stage/'host_cut.ir'
    cut.write_text('import network;\n'
        '// All finite state/input patterns: live host data only reaches the shared ingress register.\n'
        'pub fn registered(s: network::State, io: network::Inputs, data: bits[194], valid: bool) -> bool {\n'
        'let a = network::tick(s, io); let b = network::tick(s, network::Inputs { ingress_data: data, ingress_valid: valid, ..io });\n'
        'a.output == b.output && a.state.transport == b.state.transport && '
        'a.state.actor_0 == b.state.actor_0 && a.state.actor_1 == b.state.actor_1 && a.state.actor_2 == b.state.actor_2 }\n')
    run([*converter,cut],stage,'cut-convert',cut_ir)
    results.append(prove(args,stage,cut_ir,'host_cut','registered',True))
    results.append(geometry_property(args,converter,stage))
    (stage/'properties.json').write_text(json.dumps({'results':results,
        'domain':'All finite state/input bit patterns of the three-recipient ingress and generated three-actor fixture, and every 194-bit command for its two-target geometry.',
        'properties':'Full commands only retire consumed recipients; malformed/reset semantics; live host input cannot reach current outputs or next actor/transport state.',
        'trust':['DSLX/XLS','Yosys/ABC/SAT'],
        'limits':'Combinational properties, not an arbitrary-program sequential refinement or network progress proof.'},indent=2)+'\n')


def geometry_property(args: SimpleNamespace, converter: list[str | Path], stage: Path) -> dict:
    """Check every packet against the fixture's independently stated geometry and ordinary ABI."""
    geometry=stage/'host_geometry.x';geometry_ir=stage/'host_geometry.ir'
    geometry.write_text('import ingress;\n'
        '// Independent fixture geometry and wire ABI, quantified over all 194 packet bits.\n'
        'pub fn canonical(packet: bits[194]) -> bool {\n'
        'let d = ingress::decode(packet);\n'
        'let x0 = packet[178+:u16]; let y0 = packet[162+:u16]; '
        'let x1 = packet[146+:u16]; let y1 = packet[130+:u16]; let target = packet[128+:u2];\n'
        'let valid = x0 <= x1 && x1 < u16:3 && y0 <= y1 && y1 < u16:2 && target < u2:2 && '
        'packet[96+:u32] == u32:0x01000004 && packet[32+:bits[64]] == bits[64]:0;\n'
        'let recipients = u1:0 ++ ((target == u2:0 && x1 == u16:2 && y1 == u16:1) as u1) ++ '
        '((x0 == u16:0 && y0 == u16:0) as u1);\n'
        'd.canonical == valid && (!valid || (d.selected == recipients && '
        'd.frame == (bits[64]:0 ++ packet[0+:u32] ++ u32:0x04000001))) }\n')
    run([*converter,geometry],stage,'geometry-convert',geometry_ir)
    return prove(args,stage,geometry_ir,'host_geometry','canonical',True)


def main() -> None:
    """Build once, simulate finite workloads, reject wiring controls and screen local whole-network cost."""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls',type=lambda p:Path(p).resolve())
    parser.add_argument('stage',type=lambda p:Path(p).resolve())
    args=parser.parse_args();stage=args.stage;stage.mkdir();config=stage/'fixture.config';configuration(config)
    fixture=stage/'fixture';run(['bash','tools/emit_protocol_network.sh',args.xls,config,fixture],stage,'public-build')
    fixture=(fixture/'compiled').resolve()
    simulate(fixture,stage);negative_wiring(args.xls,fixture,stage);properties(args.xls,fixture,stage);area(fixture,stage)
    (stage/'result.json').write_text(json.dumps({'passed':True,'complete_incarnations':2,'reset_interruptions':3,
        'commands_per_complete_incarnation':6,'outputs_per_complete_incarnation':13,'malformed_incarnations':8,
        'source_failure_incarnations':2,'negative_wiring':2,
        'evidence':'Finite RTL witnesses plus specified finite-state cuts; no application/native qualification.'},indent=2)+'\n')


if __name__ == '__main__':
    main()
