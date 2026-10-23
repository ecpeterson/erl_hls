"""Check fresh N2/N3 source applications against ordinary BEAM actors through the real broker."""
from pathlib import Path
import argparse
import json
import subprocess
import time
from backend_paths import ROOT, erlang_paths
from compile_protocol_transport import digest
from emit_protocol_repetition import build_application
from test_local_protocol import run
from test_protocol_application import simulator_source


def compare(actual: dict, expected: dict, width: int) -> None:
    """Compare each logical sender through the common fence and the complete final readout."""
    assert actual['fence']==expected['fence']
    assert actual['replies']==expected['replies']
    assert sorted(actual['corrections'])==sorted(expected['corrections'])
    for x in range(width):
        assert [e for e in actual['events'] if e[0]==x and e[2]<=actual['fence']]==[
            e for e in expected['events'] if e[0]==x and e[2]<=expected['fence']], x
    assert actual['descriptors_closed']


def live(build: Path, stage: Path, width: int, ebin: Path, binary: Path) -> None:
    """Apply finite setup/correction/readout traffic with real broker credits and physical-output stalls."""
    stage.mkdir()
    with (stage/'simulation.log').open('x') as log:
        sim=subprocess.Popen([binary,stage],stdout=log,stderr=subprocess.STDOUT)
        try:
            deadline=time.monotonic()+10
            while not (stage/'app_rx').exists():
                if sim.poll() is not None or time.monotonic()>deadline:raise RuntimeError('simulation startup failed')
                time.sleep(.02)
            expression='[B,S,N]=init:get_plain_arguments(),ok=phi_protocol_repetition_fixture:live(B,S,list_to_integer(N)),halt().'
            run(['erl','+S','2:2','-noshell','-pa',*erlang_paths(),ebin,'-eval',expression,
                 '-extra',build,stage,str(width)],stage,'host')
            assert sim.wait(timeout=10)==0
        finally:
            if sim.poll() is None:sim.terminate();sim.wait(timeout=5)
    assert 'PASS live application' in (stage/'simulation.log').read_text()


def qualify(build: Path, stage: Path, width: int) -> dict:
    """Compile the independent reference fixture and public-port simulation once for this fresh build."""
    ebin=stage/'ebin';ebin.mkdir()
    run(['erlc',*[v for p in erlang_paths() for v in ('-pa',p)],'+debug_info','-Werror',
         '-o',ebin,ROOT/'test/phi_protocol_repetition_fixture.erl'],stage,'compile-host')
    expression='[S,N]=init:get_plain_arguments(),ok=phi_protocol_repetition_fixture:oracle(S,list_to_integer(N)),halt().'
    run(['erl','+S','2:2','-noshell','-pa',*erlang_paths(),ebin,'-eval',expression,'-extra',stage,str(width)],stage,'oracle')
    rtl=[Path(p) for p in (build/'files.f').read_text().splitlines()]
    source=simulator_source(build,stage)
    tracked=rtl+[source,build/'deployment.etf',stage/'oracle.json']
    hashes={str(p):digest(p) for p in tracked}
    run(['verilator','--cc','--exe','--build','--top-module','protocol_application_top',
         '--Mdir',stage/'obj_dir','-j','1','-Wno-fatal','-CFLAGS','-std=c++17','-o','simulation',*rtl,source],stage,'verilator')
    live(build,stage/'live',width,ebin,stage/'obj_dir/simulation')
    actual=json.loads((stage/'live/result.json').read_text())
    expected=json.loads((stage/'oracle.json').read_text())
    compare(actual,expected,width)
    assert hashes=={str(p):digest(p) for p in tracked}
    result={'width':width,'passed':True,'fence':actual['fence'],'corrections':len(actual['corrections']),
        'replies':actual['replies'],'input_hashes':hashes,'evidence':'Finite ordinary-BEAM/broker/RTL witness; no QEC, convergence, general progress, board fit or native timing claim.'}
    (stage/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    return result


def main() -> None:
    """Run selected N2/N3 integration cases serially; keep failed and successful build artifacts."""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls',type=lambda p:Path(p).resolve());parser.add_argument('stage',type=lambda p:Path(p).resolve())
    parser.add_argument('--width',type=int,choices=[2,3],action='append')
    args=parser.parse_args();args.stage.mkdir()
    results=[]
    for width in args.width or [2,3]:
        stage=args.stage/('repetition-'+str(width));stage.mkdir()
        build=build_application(args.xls,width,stage/'application')
        results.append(qualify(build,stage,width))
        (args.stage/'summary.json').write_text(json.dumps({'results':results},indent=2)+'\n')


if __name__=='__main__':main()
