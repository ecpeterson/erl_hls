"""Finite connected transport/source-owner witness for sender order and mailbox retirement."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
from types import SimpleNamespace

from backend_paths import ROOT, erlang_environment
from compiler_paths import compiler_root
from backend_commands import run
from test_local_protocol import prove
from compile_local_actor import compile_owner
from protocol_test_build import compile_build, emit_command


def simulate(xls: Path, fixture: Path, receiver: Path, stage: Path) -> None:
    """Compare actual transport/receiver RTL with independent sender queues and source arithmetic."""
    manifest = json.loads((fixture/'actors/receiver_2.x.json').read_text())
    assert manifest['inbox']['physical_slots'] == 6
    assert manifest['inbox']['additional_state_bits'] == 22
    width = manifest['effect_payload_bits']
    reference = stage/'initial.x'
    reference.write_bytes((fixture/'actors/actor_0.x').read_bytes() + f"""
// Supply the ordinary source's initial evaluated publication, not an invented payload.
pub fn initial_publication() -> bits[{width+8}] {{
  let step = local_step(local_initial(), bits[128]:0, false, true);
  step.effect_layout ++ step.effect_payload
}}
""".encode())
    paths = ':'.join(map(str, [ROOT/'priv/xls/lib', ROOT/'priv/xls/fabric', compiler_root('default')/'priv/xls/lib', compiler_root('default')/'priv/xls/fabric']))
    run([xls/'ir_converter_main', '--top=initial_publication', '--warnings_as_errors=false',
         '--dslx_path='+paths, '--dslx_stdlib_path='+str(xls/'xls/dslx/stdlib'), reference],
        stage, 'initial-convert', stage/'initial.ir')
    run([xls/'opt_main', stage/'initial.ir'], stage, 'initial-opt', stage/'initial.opt.ir')
    run([xls/'codegen_main', '--generator=combinational', '--use_system_verilog=false',
         '--module_name=initial_publication', stage/'initial.opt.ir'], stage, 'initial-codegen', stage/'initial.v')
    ports = json.loads((fixture/'dslx/ports.json').read_text())
    declarations = [f'wire [{width+7}:0] initial_batch;', 'initial_publication initial_source(.out(initial_batch));']
    connections = ['.clk(clk)']
    for field in ports['inputs'] + ports['outputs']:
        name, bits = field['name'], field['width']
        connections.append(f'.{name}({name})')
        if name == 'reset':
            continue
        declarations.append(f'wire [{bits-1}:0] {name};')
        if field not in ports['inputs']:
            continue
        if name.startswith('source_'):
            i = int(name.split('_')[1])
            if name.endswith('_valid'):
                expr = f'(cycle>{3+i*5} && sent{i}<3)' if i<2 else "1'b0"
            elif name.endswith('_layout'): expr = f'initial_batch[{width+7}:{width}]'
            else: expr = f'initial_batch[{width-1}:0]'
        elif name.startswith('link_'):
            i = int(name.split('_')[1]); at=i*3
            if name.endswith('_take'): expr=f'|take[{at}+:3]'
            elif name.endswith('_eligible'): expr=f'eligible[{at}+:3]'
            else: expr=f'released[{at}+:3]'
        else: expr="1'b1"
        declarations.append(f'assign {name}={expr};')
    declarations.append('protocol_fabric transport('+','.join(connections)+');')
    inputs = ','.join(f['name'] for f in manifest['inbox']['inputs'])
    declarations.append('local_actor receiver(.clk(clk),.reset(reset),._commands({'+inputs+'}),'
                        "._commands_vld(1'b1),._commands_rdy(),._observations(observations),"
                        "._observations_vld(),._observations_rdy(1'b1));")
    bench = stage/'bench.sv'
    bench.write_text((ROOT/'test/rtl/protocol_inbox_tb.sv').read_text().replace('@@WIRING@@','\n'.join(declarations)))
    run(['iverilog','-g2012','-s','tb','-o',stage/'sim',bench,receiver/'actor.v',
         fixture/'dslx/core.v',fixture/'dslx/protocol_fabric.sv',stage/'initial.v'],stage,'rtl-compile')
    run(['vvp',stage/'sim'],stage,'rtl-sim')
    assert 'PROTOCOL_INBOX_PASS' in (stage/'rtl-sim.log').read_text()
    reject_miswiring(fixture, receiver, stage, bench)


def reject_miswiring(fixture: Path, receiver: Path, stage: Path, bench: Path) -> None:
    """Require the independent scoreboard to reject early take and same-edge release wiring."""
    original=bench.read_text()
    for name, before, after in [('early-take','_take=|take[','_take=|accepted['),
                                ('early-release','_release_valid=released[','_release_valid=take[')]:
        changed=original.replace(before,after)
        assert changed!=original,name
        source=stage/(name+'.sv'); source.write_text(changed)
        executable=stage/name
        run(['iverilog','-g2012','-s','tb','-o',executable,source,receiver/'actor.v',
             fixture/'dslx/core.v',fixture/'dslx/protocol_fabric.sv',stage/'initial.v'],stage,name+'-compile')
        with (stage/(name+'.log')).open('x') as log:
            result=subprocess.run(['vvp',str(executable)],cwd=ROOT,stdout=log,
                                  stderr=subprocess.STDOUT,timeout=30)
        diagnostic=(stage/(name+'.log')).read_text()
        expected={'early-take':'sender order','early-release':'lease mismatch'}[name]
        assert result.returncode!=0 and expected in diagnostic, (name,diagnostic)


def selection_checks(xls: Path, stage: Path) -> None:
    """Prove finite-width circular priority and screen 1/3/8-input selector circuits."""
    source=ROOT/'test/protocol_inbox_properties.x'
    raw=stage/'selection.ir'
    run([xls/'ir_converter_main','--warnings_as_errors=false',
         '--dslx_path='+str(ROOT/'priv/xls/lib'),
         '--dslx_stdlib_path='+str(xls/'xls/dslx/stdlib'),source],stage,'selection-convert',raw)
    args=SimpleNamespace(xls=xls,yosys='yosys')
    proofs=[prove(args,stage,raw,'protocol_inbox_properties',prop,prop!='wrong_cursor')
            for prop in ['selection1','selection3','selection8','wrong_cursor']]
    counts={}
    for n in [1,3,8]:
        stem='selector'+str(n); optimized=stage/(stem+'.ir'); circuit=stage/(stem+'.v')
        run([xls/'opt_main','--top=__protocol_inbox_properties__'+stem,raw],stage,stem+'-opt',optimized)
        run([xls/'codegen_main','--generator=combinational','--use_system_verilog=false',
             '--module_name=inbox_selector',optimized],stage,stem+'-codegen',circuit)
        script=stage/(stem+'.ys'); netlist=stage/(stem+'.json')
        script.write_text(f'read_verilog "{circuit}"\nsynth_xilinx -family xc7 -top inbox_selector -flatten -nowidelut\nwrite_json "{netlist}"\n')
        run(['yosys','-Q','-T','-s',script],stage,stem+'-map')
        cells=json.loads(netlist.read_text())['modules']['inbox_selector']['cells'].values()
        lut=sum(c['type'].startswith('LUT') for c in cells)
        assert lut<=64*n,(n,lut)
        counts[n]=lut
    (stage/'selection-result.json').write_text(json.dumps({'proofs':proofs,'xc7_logic_lut':counts,
        'domain':'all finite request masks, cursor < N, N in [1,3,8]',
        'trust':['DSLX/XLS lowering','Yosys/ABC/SAT'],
        'limits':'combinational selection only; no sequential owner, network progress or native timing proof'},indent=2)+'\n')


def lower_receivers(xls: Path, directory: Path, stage: Path, seen: set[tuple]) -> int:
    """Check every emitted binding and lower each distinct source/codec/width shape once."""
    report=json.loads((directory/'summary.json').read_text())
    receivers=report['receivers']
    assert len(receivers)==report['actors']
    converted=0
    for receiver in receivers:
        source=directory/receiver['file']; manifest=receiver['manifest']; inbox=manifest['inbox']
        assert json.loads(Path(str(source)+'.json').read_text())==manifest
        assert hashlib.sha256(source.read_bytes()).hexdigest()==manifest['dslx_sha256']
        assert manifest['clock_proc']=='local_inbox_clock'
        startup=inbox['startup']
        assert startup['offset']==inbox['physical_slots'] and startup['count']==len(startup['frames'])
        assert all(0<=frame<2**128 for frame in startup['frames'])
        host=inbox['host']
        assert host['slots'] in (0,1) and host['offset']==inbox['physical_slots']+startup['count']
        assert inbox['mask_bits']==max(1,host['offset']+host['slots'])
        assert inbox['additional_state_bits']==3*inbox['mask_bits']+inbox['cursor_bits']+1+startup['count']
        assert len(inbox['slots'])==inbox['physical_slots']
        # Startup values are individually range-checked fixed-width literals; count changes the circuit shape.
        shape=(receiver['module'],manifest['source_plan']['artifact_sha256'],
               tuple(f['width'] for f in inbox['inputs']),startup['count'],
               tuple((s['slot'],s['width'],s['payload_offset'],s['codec']['value'],
                      tuple(s['codec']['frame_positions'])) for s in inbox['slots']))
        if shape in seen:
            continue
        seen.add(shape); converted+=1
        stem=directory.name+'-receiver-'+str(receiver['index'])
        paths=':'.join(map(str,[directory/'actors',ROOT/'priv/xls/lib',ROOT/'priv/xls/fabric',
            compiler_root('default')/'priv/xls/lib',compiler_root('default')/'priv/xls/fabric',compiler_root('default')/'src/examples/phi_decoder']))
        run([xls/'ir_converter_main','--top=local_inbox_clock','--warnings_as_errors=false',
             '--dslx_path='+paths,'--dslx_stdlib_path='+str(xls/'xls/dslx/stdlib'),source],
            stage,stem,stage/(stem+'.ir'))
    return converted


def main() -> None:
    """Invoke the current application builder and actor compiler, then run connected RTL."""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls',type=lambda p:Path(p).resolve())
    parser.add_argument('stage',type=lambda p:Path(p).resolve())
    args=parser.parse_args(); stage=args.stage; stage.mkdir()
    run(['rebar3','compile'],stage,'build')
    config=stage/'fixture.config'
    config.write_text('#{sources => [{"test/hls_protocol_inbox_fixture.erl",[]}],topology => '
                      '{hls_protocol_inbox_fixture,topology,[]},actor_limit => 3}.\n')
    fixture=stage/'fixture'
    run(emit_command('transport', config, fixture),stage,'emit', env=erlang_environment('default'))
    compile_owner(args.xls,fixture/'actors/receiver_2.x',stage/'receiver', [fixture/'actors'],
                  public=compiler_root('default'), profile='default')
    fixture=compile_build(args.xls,fixture)
    simulate(args.xls,fixture,stage/'receiver',stage)
    selection_checks(args.xls,stage)
    (stage/'result.json').write_text(json.dumps({'passed':True,'complete_incarnations':2,
        'interrupted_incarnations':1,'consumed_per_complete_incarnation':18,'final_sum':48,
        'evidence':'finite connected RTL witness; no general refinement, capacity or progress proof'},indent=2)+'\n')


if __name__ == '__main__':
    main()
