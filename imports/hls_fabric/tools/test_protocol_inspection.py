"""Qualify source-process inspection through the public build, typed state and real brokers."""
from pathlib import Path
from types import SimpleNamespace
import argparse
import json
import subprocess
import time
from backend_paths import ROOT, erlang_paths
from compiler_paths import compiler_root
from emit_protocol_repetition import build_application
from backend_commands import digest, run
from test_local_protocol import prove
from test_protocol_application import simulator_source
from test_protocol_repetition import compare


def properties(xls: Path, build: Path, stage: Path) -> None:
    """Check all finite state/input bits: debug selection affects neither transition nor application outputs."""
    stage.mkdir()
    source=stage/'inspection_cut.x';raw=stage/'inspection_cut.ir'
    source.write_text('import network;\n'
        '// Every generated network state, input and alternative query address.\n'
        'pub fn independent(s: network::State, io: network::Inputs, other: u32) -> bool {\n'
        'let a = network::tick(s, io); let b = network::tick(s, network::Inputs { inspect_address: other, ..io });\n'
        'a.state == b.state && network::Outputs { inspect_value: bits[128]:0, ..a.output } == '
        'network::Outputs { inspect_value: bits[128]:0, ..b.output } }\n'
        '// Reset hides every process regardless of its current state or query address.\n'
        'pub fn masked(s: network::State, io: network::Inputs) -> bool { '
        'network::tick(s, network::Inputs { reset: true, ..io }).output.inspect_value == bits[128]:0 }\n'
        '// Deliberately false: distinct process states must be distinguishable by queries.\n'
        'pub fn wrong_same_value(s: network::State, io: network::Inputs) -> bool { '
        'network::tick(s, network::Inputs { inspect_address: u32:0, ..io }).output.inspect_value == '
        'network::tick(s, network::Inputs { inspect_address: u32:1, ..io }).output.inspect_value }\n')
    imports=[build/'network',build/'actors',build/'dslx',ROOT/'priv/xls/lib',compiler_root('default')/'priv/xls/lib',compiler_root('default')/'priv/xls/fabric',compiler_root('default')/'src/examples/phi_decoder']
    run([xls/'ir_converter_main','--warnings_as_errors=false','--dslx_path='+':'.join(map(str,imports)),
         '--dslx_stdlib_path='+str(xls/'xls/dslx/stdlib'),source],stage,'convert',raw)
    args=SimpleNamespace(xls=xls,yosys='yosys')
    results=[prove(args,stage,raw,'inspection_cut',p,p!='wrong_same_value') for p in ['independent','masked','wrong_same_value']]
    (stage/'result.json').write_text(json.dumps({'results':results,'domain':'All generated N3 network state/input bits and every 32-bit query address.',
        'trust':['source layouts','XLS','Yosys/ABC/SAT'],'limits':'Combinational query noninterference; not a network progress or arbitrary-source theorem.'},indent=2)+'\n')


def shapes(xls: Path, stage: Path) -> None:
    """Compare packed projections to ordinary typed machine fields, including active gather/scalar priority."""
    expression='[C,S]=init:get_plain_arguments(),ok=hls_protocol_inspection_shapes:write(C,S),halt().'
    run(['erl','+S','2:2','-noshell','-pa',*erlang_paths("test"),'-eval',expression,'-extra',compiler_root("test"),stage],stage.parent,'shapes-emit')
    for name in ['plain','scalar','gather','gather_sites']:
        shape_case(xls,stage/name)


def shape_case(xls: Path, part: Path) -> None:
    """Check one freshly emitted shape against the ordinary typed machine unpacker."""
    source=part/'shape.x';raw=part/'shape.ir'
    imports=[part,ROOT/'priv/xls/lib',compiler_root('test')/'priv/xls/lib',compiler_root('test')/'priv/xls/fabric']
    run([xls/'ir_converter_main','--warnings_as_errors=false','--dslx_path='+':'.join(map(str,imports)),
         '--dslx_stdlib_path='+str(xls/'xls/dslx/stdlib'),source],part,'shape-convert',raw)
    result=prove(SimpleNamespace(xls=xls,yosys='yosys'),part,raw,'shape','metadata',True)
    (part/'result.json').write_text(json.dumps({'result':result,
        'domain':'All raw machine bits and initialization/reset Booleans for this source fixture.',
        'trust':['source extraction','typed machine unpacker','DSLX/XLS','Yosys/ABC/SAT'],
        'limits':'Combinational projection equivalence; no temporal progress or arbitrary-source claim.'},indent=2)+'\n')

def live(build: Path, stage: Path, binary: Path) -> None:
    """Run actual broker/client queries and correction feedback; preserve both independent accepted-word logs."""
    stage.mkdir()
    with (stage/'simulation.log').open('x') as log:
        sim=subprocess.Popen([binary,stage],stdout=log,stderr=subprocess.STDOUT)
        try:
            deadline=time.monotonic()+10
            while not (stage/'debug_rx').exists():
                if sim.poll() is not None or time.monotonic()>deadline:raise RuntimeError('simulation startup failed')
                time.sleep(.02)
            expression='[B,S]=init:get_plain_arguments(),ok=hls_protocol_inspection_live:run(B,S,3),halt().'
            run(['erl','+S','2:2','-noshell','-pa',*erlang_paths("test"),'-eval',expression,'-extra',build,stage],stage,'host')
            assert sim.wait(timeout=10)==0
        finally:
            if sim.poll() is None:sim.terminate();sim.wait(timeout=5)
    log=(stage/'simulation.log').read_text()
    assert 'PASS live application' in log and 'PASS passive inspection' in log,log


def reset_witness(build: Path, stage: Path) -> None:
    """Cancel four public debug transactions with common reset, then verify fresh INFO and a process query."""
    stage.mkdir()
    manifest=json.loads((build/'network/inspection.json').read_text());fingerprint=bytes.fromhex(manifest['fingerprint'])
    assignments='\n'.join(f"fingerprint[{i}]=32'h{int.from_bytes(fingerprint[4*i:4*i+4],'little'):08x};" for i in range(8))
    bench=stage/'reset.sv'
    bench.write_text((ROOT/'test/rtl/protocol_inspection_reset_tb.sv').read_text().replace('@@FINGERPRINT@@',assignments))
    rtl=[Path(p) for p in (build/'files.f').read_text().splitlines()]
    run(['iverilog','-g2012','-s','tb','-o',stage/'simulation',bench,*rtl],stage,'compile')
    run(['vvp',stage/'simulation'],stage,'simulate')
    assert 'PROTOCOL_INSPECTION_RESET_PASS' in (stage/'simulate.log').read_text()


def qualify(build: Path, stage: Path) -> None:
    """Compile one public-port twin harness and compare finite runs to independent ordinary BEAM actors."""
    expression='[S]=init:get_plain_arguments(),ok=phi_protocol_repetition_fixture:oracle(S,3),halt().'
    run(['erl','+S','2:2','-noshell','-pa',*erlang_paths("test"),'-eval',expression,'-extra',stage],stage,'oracle')
    rtl=[Path(p) for p in (build/'files.f').read_text().splitlines()];source=simulator_source(build,stage)
    inputs=rtl+[source,build/'deployment.etf',build/'network/inspection.etf',build/'network/inspection.json']
    hashes={str(p):digest(p) for p in inputs}
    run(['verilator','--cc','--exe','--build','--top-module','protocol_application_top',
         '--Mdir',stage/'obj_dir','-j','1','-Wno-fatal','-CFLAGS','-std=c++17','-o','simulation',*rtl,source],stage,'verilator')
    expected=json.loads((stage/'oracle.json').read_text())
    for incarnation in [1,2]:
        part=stage/f'live-{incarnation}';live(build,part,stage/'obj_dir/simulation')
        actual=json.loads((part/'result.json').read_text());compare(actual,expected,3)
        assert actual['samples']==27
    reset_witness(build,stage/'reset')
    assert hashes=={str(p):digest(p) for p in inputs}
    (stage/'result.json').write_text(json.dumps({'passed':True,'incarnations':2,'samples_each':27,'reset_interruptions':4,'input_hashes':hashes,
        'evidence':'Finite ordinary-BEAM/broker/RTL witness and cycle-exact unqueried twin comparison; no native or continuous-history claim.'},indent=2)+'\n')


def main() -> None:
    """Build, prove and exercise the complete opt-in process inspection path serially."""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls',type=lambda p:Path(p).resolve());parser.add_argument('stage',type=lambda p:Path(p).resolve())
    args=parser.parse_args();args.stage.mkdir()
    run(['rebar3','as','test','compile'],args.stage,'compile-fixtures')
    build=build_application(args.xls,3,args.stage/'application',inspect=True)
    shapes(args.xls,args.stage/'shapes');properties(args.xls,build,args.stage/'properties');qualify(build,args.stage)


if __name__=='__main__':main()
