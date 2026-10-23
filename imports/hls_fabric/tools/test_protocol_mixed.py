"""Compare actual BEAM data actors and a framed native syndrome/Phi partition to ordinary BEAM."""
from pathlib import Path
import argparse
import json
import subprocess
import time
from backend_paths import ROOT, erlang_paths
from emit_protocol_repetition import build_application
from test_protocol_repetition import compare
from compile_protocol_transport import digest
from test_local_protocol import run


def live(build: Path, binary: Path, ebin: Path, stage: Path, session: int) -> dict:
    """Exercise one fresh mixed incarnation, physical stalls and definite descriptor closure."""
    stage.mkdir()
    with (stage/'simulation.log').open('x') as log:
        sim=subprocess.Popen([binary,stage],stdout=log,stderr=subprocess.STDOUT)
        try:
            deadline=time.monotonic()+10
            while not (stage/'app_rx').exists():
                if sim.poll() is not None or time.monotonic()>deadline:raise RuntimeError('simulation startup')
                time.sleep(.02)
            expression='[B,S,I]=init:get_plain_arguments(),ok=hls_protocol_mixed_live:run(B,S,3,list_to_integer(I)),halt().'
            run(['erl','+S','2:2','-noshell','-pa',*erlang_paths(),ebin,'-eval',expression,
                 '-extra',build,stage,str(session)],stage,'host')
            assert sim.wait(timeout=10)==0,(stage/'simulation.log').read_text()
        finally:
            if sim.poll() is None:sim.terminate();sim.wait(timeout=5)
    log=(stage/'simulation.log').read_text()
    assert 'PASS live application' in log and 'RETIRED pending_input_bytes=' in log
    return json.loads((stage/'result.json').read_text())


def qualify(build: Path, stage: Path) -> list[Path]:
    """Compile once, then compare per-sender events and readout over two reset-owned incarnations."""
    ebin=stage/'ebin';ebin.mkdir()
    fixtures=['phi_protocol_repetition_fixture','hls_protocol_mixed_live','hls_actor_broker_fixture',
              'hls_test_nodes','hls_protocol_mixed_queue_tests']
    run(['erlc',*[v for p in erlang_paths() for v in ('-pa',p)],'+debug_info','-Werror','-o',ebin,
         *[ROOT/'test'/(f+'.erl') for f in fixtures]],stage,'host-compile')
    expression='[S,B]=init:get_plain_arguments(),ok=phi_protocol_repetition_fixture:oracle(S,3),{ok,D}=file:read_file(filename:join(B,"mixed.etf")),#{mixed:=M}=binary_to_term(D),P=filename:join(S,"cut.etf"),ok=file:write_file(P,term_to_binary(M)),ok=hls_protocol_mixed_queue_tests:run(P),halt().'
    run(['erl','+S','2:2','-noshell','-pa',*erlang_paths(),ebin,'-eval',expression,'-extra',stage,build],stage,'oracle-and-queue')
    rtl=[Path(p) for p in (build/'files.f').read_text().splitlines()]
    source=ROOT/'test/rtl/protocol_mixed_sim.cpp'
    tracked=[*rtl,source,build/'mixed.etf',stage/'oracle.json'];hashes={str(p):digest(p) for p in tracked}
    run(['verilator','--cc','--exe','--build','--top-module','protocol_bridge_top','--Mdir',stage/'obj_dir',
         '-j','1','-Wno-fatal','-CFLAGS','-std=c++17','-o','simulation',*rtl,source],stage,'verilator')
    expected=json.loads((stage/'oracle.json').read_text());results=[]
    for session in [801,802]:
        actual=live(build,stage/'obj_dir/simulation',ebin,stage/f'live-{session}',session)
        compare(actual,expected,3);results.append(json.loads((stage/f'live-{session}/stream.json').read_text()))
    assert hashes=={str(p):digest(p) for p in tracked}
    (stage/'result.json').write_text(json.dumps({'passed':True,'width':3,'beam':'data','native':['syndrome','phi'],
        'fence':expected['fence'],'corrections':len(expected['corrections']),'replies':expected['replies'],
        'incarnations':results,'input_hashes':hashes,
        'evidence':'Finite actual BEAM/distribution/broker/RTL witness; no QEC, unrestricted progress, routed timing or device admission.'},indent=2)+'\n')
    return rtl


def area(rtl: list[Path], stage: Path) -> None:
    """Screen complete native logic against preregistered N3 bounds; never infer routed device fit."""
    script=stage/'map.ys';netlist=stage/'mapped.json'
    script.write_text('read_verilog -sv '+' '.join('"'+str(p)+'"' for p in rtl)+'\n'
        'synth_xilinx -family xc7 -top protocol_bridge_top -flatten -nowidelut\nwrite_json "'+str(netlist)+'"\n')
    run(['yosys','-Q','-T','-s',script],stage,'map')
    types=[c['type'] for c in json.loads(netlist.read_text())['modules']['protocol_bridge_top']['cells'].values()]
    counts={k:sum(t.startswith(v) for t in types) for k,v in [('lut','LUT'),('ff','FD'),('bram','RAMB'),('dsp','DSP')]}
    limits={'lut':36000,'ff':24000,'bram':0,'dsp':0};passed=all(counts[k]<=limits[k] for k in counts)
    (stage/'area.json').write_text(json.dumps({'counts':counts,'limits':limits,'within_budget':passed,
        'evidence':'Local complete XC7 diagnostic; not routed timing or Zynq-7030 admission.'},indent=2)+'\n')
    assert passed,counts


def main() -> None:
    """Build N3 once and qualify the mixed application; mapping remains an optional local diagnostic."""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls',type=lambda p:Path(p).resolve());parser.add_argument('stage',type=lambda p:Path(p).resolve())
    parser.add_argument('--area',action='store_true');args=parser.parse_args();args.stage.mkdir()
    build=build_application(args.xls,3,args.stage/'application',mixed=True)
    rtl=qualify(build,args.stage)
    if args.area:area(rtl,args.stage)


if __name__=='__main__':main()
