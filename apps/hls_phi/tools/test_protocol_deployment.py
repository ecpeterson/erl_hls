"""Exercise periodic N6 source repetition on two independent 3+3 RTL roles through real brokers."""
import phi_tool_paths  # Resolve shared tooling for this application.
from pathlib import Path
import argparse
import json
import subprocess
import time
from backend_paths import ROOT, erlang_paths
from emit_protocol_repetition import build_application
from test_protocol_bridge import pair
from test_protocol_repetition import compare
from backend_commands import digest, run


def live(build: Path, binary: Path, ebin: Path, stage: Path, incarnation: int) -> dict:
    """Run one reset-owned incarnation, independent physical stalls, and collective transport closure."""
    stage.mkdir()
    with (stage/'simulation.log').open('x') as log:
        sim=subprocess.Popen([binary,stage,'--cancel-chatter'],stdout=log,stderr=subprocess.STDOUT)
        try:
            deadline=time.monotonic()+10
            while not (stage/'role1_rx').exists():
                if sim.poll() is not None or time.monotonic()>deadline:raise RuntimeError('simulation startup')
                time.sleep(.02)
            expression='[B,S,I]=init:get_plain_arguments(),ok=phi_protocol_deployment_live:run(B,S,6,list_to_integer(I)),halt().'
            run(['erl','+S','2:2','-noshell','-pa',*erlang_paths("default"),ebin,'-eval',expression,
                 '-extra',build,stage,str(incarnation)],stage,'host')
            assert sim.wait(timeout=10)==0,(stage/'simulation.log').read_text()
        finally:
            if sim.poll() is None:sim.terminate();sim.wait(timeout=5)
    log=(stage/'simulation.log').read_text()
    assert 'PASS framed pair' in log and 'RETIRED pending_input_bytes=' in log
    return json.loads((stage/'result.json').read_text())


def qualify(build: Path, stage: Path) -> tuple[Path,list[Path]]:
    """Compare every logical sender and final readout with independently executed ordinary BEAM actors."""
    ebin=stage/'ebin';ebin.mkdir()
    run(['erlc',*[v for p in erlang_paths("default") for v in ('-pa',p)],'+debug_info','-Werror','-o',ebin,
         ROOT/'apps/hls_phi/test/phi_protocol_repetition_fixture.erl',ROOT/'apps/hls_phi/test/phi_protocol_deployment_live.erl'],stage,'host-compile')
    expression='[S]=init:get_plain_arguments(),ok=phi_protocol_repetition_fixture:oracle(S,6),halt().'
    run(['erl','+S','2:2','-noshell','-pa',*erlang_paths("default"),ebin,'-eval',expression,'-extra',stage],stage,'oracle')
    roles=[build/'role0',build/'role1']
    wrapper,rtl=pair(roles,stage)
    source=ROOT/'test/rtl/protocol_bridge_sim.cpp'
    tracked=[*rtl,wrapper,source,source.with_name('framed_fifo_stream.h'),build/'deployment.etf',stage/'oracle.json']
    hashes={str(p):digest(p) for p in tracked}
    run(['verilator','--cc','--exe','--build','--top-module','protocol_bridge_pair',
        '--Mdir',stage/'obj_dir','-j','1','-Wno-fatal','-CFLAGS','-std=c++17','-o','simulation',
        wrapper,*rtl,source],stage,'verilator')
    expected=json.loads((stage/'oracle.json').read_text());results=[]
    for incarnation in [701,702]:
        actual=live(build,stage/'obj_dir/simulation',ebin,stage/f'live-{incarnation}',incarnation)
        compare(actual,expected,6);results.append(actual)
    assert hashes=={str(p):digest(p) for p in tracked}
    (stage/'result.json').write_text(json.dumps({'passed':True,'width':6,'split':3,
        'fence':expected['fence'],'corrections':len(expected['corrections']),'replies':expected['replies'],
        'incarnations':[r['stream_at_retirement'] for r in results],
        'input_hashes':hashes,
        'evidence':'Finite BEAM/broker/two-role RTL witness; not global quiescence, QEC validation, sustained throughput, native timing or device admission.'},indent=2)+'\n')
    return wrapper,rtl


def area(wrapper: Path, rtl: list[Path], stage: Path) -> None:
    """Screen complete connected logic against the preregistered N6 budget; never infer native fit."""
    script=stage/'map.ys';netlist=stage/'mapped.json'
    script.write_text('read_verilog -sv '+' '.join('"'+str(p)+'"' for p in [wrapper,*rtl])+'\n'
        'synth_xilinx -family xc7 -top protocol_bridge_pair -flatten -nowidelut\nwrite_json "'+str(netlist)+'"\n')
    run(['yosys','-Q','-T','-s',script],stage,'map')
    types=[c['type'] for c in json.loads(netlist.read_text())['modules']['protocol_bridge_pair']['cells'].values()]
    counts={k:sum(t.startswith(v) for t in types) for k,v in [('lut','LUT'),('ff','FD'),('bram','RAMB'),('dsp','DSP')]}
    limits={'lut':60000,'ff':36000,'bram':0,'dsp':0}
    passed=all(counts[k]<=limits[k] for k in counts)
    (stage/'area.json').write_text(json.dumps({'counts':counts,'limits':limits,'within_budget':passed,
        'evidence':'Local complete XC7 diagnostic; not routed timing or Zynq-7030 admission.'},indent=2)+'\n')
    assert passed,counts


def main() -> None:
    """Build once and run two fresh incarnations; retain all failures. Mapping is an explicit diagnostic."""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls',type=lambda p:Path(p).resolve());parser.add_argument('stage',type=lambda p:Path(p).resolve())
    parser.add_argument('--area',action='store_true')
    args=parser.parse_args();args.stage.mkdir()
    build=build_application(args.xls,6,args.stage/'application',split=3)
    wrapper,rtl=qualify(build,args.stage)
    if args.area:area(wrapper,rtl,args.stage)


if __name__=='__main__':main()
