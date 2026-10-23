"""Exercise the fresh public source-application build with real framed broker feedback."""
from pathlib import Path
import argparse
import json
import subprocess
import time
from backend_paths import ROOT, erlang_paths
from test_local_protocol import run
from compile_protocol_transport import digest


def witness(build: Path, binary: Path, ebin: Path, stage: Path) -> None:
    """Run bounded FIFO transport and the ordinary BEAM host; require actual accepted-word evidence."""
    stage.mkdir()
    with (stage/'simulation.log').open('x') as log:
        sim=subprocess.Popen([binary,stage],stdout=log,stderr=subprocess.STDOUT)
        try:
            deadline=time.monotonic()+10
            while not (stage/'app_rx').exists():
                if sim.poll() is not None or time.monotonic()>deadline:raise RuntimeError('simulation startup failed')
                time.sleep(.02)
            expression='[B,S]=init:get_plain_arguments(),ok=hls_protocol_application_live:run(B,S),halt().'
            run(['erl','+S','2:2','-noshell','-pa',*erlang_paths(),ebin,
                 '-eval',expression,'-extra',build,stage],stage,'host')
            assert sim.wait(timeout=10)==0
        finally:
            if sim.poll() is None:sim.terminate();sim.wait(timeout=5)
    assert 'PASS live application' in (stage/'simulation.log').read_text()
    assert json.loads((stage/'result.json').read_text())['frames']==24


def reset_witness(build: Path, stage: Path, rtl: list[Path]) -> None:
    """Interrupt public attachment/setup/output and require fresh identity framing after reset."""
    identity=bytes.fromhex(json.loads((build/'application/manifest.json').read_text())['identity'])
    assignments='\n'.join(f"identity[{i}]=32'h{int.from_bytes(identity[4*i:4*i+4],'little'):08x};" for i in range(8))
    bench=stage/'reset.sv'
    bench.write_text((ROOT/'test/rtl/protocol_application_reset_tb.sv').read_text().replace('@@IDENTITY@@',assignments))
    run(['iverilog','-g2012','-s','tb','-o',stage/'reset-sim',bench,*rtl],stage,'reset-compile')
    run(['vvp',stage/'reset-sim'],stage,'reset-simulate')
    assert 'PROTOCOL_APPLICATION_RESET_PASS' in (stage/'reset-simulate.log').read_text()


def main() -> None:
    """Build once, exercise two fresh incarnations, and retain inputs/results outside source control."""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls',type=lambda p:Path(p).resolve());parser.add_argument('stage',type=lambda p:Path(p).resolve())
    args=parser.parse_args();stage=args.stage;stage.mkdir();build=stage/'build';config=stage/'config.erl'
    config.write_text('#{sources=>[{"test/hls_protocol_boundary_fixture.erl",[]}],topology=>'
        '{hls_protocol_boundary_fixture,topology,[]},actor_limit=>4,device=>board,host=>1}.\n')
    run(['bash','tools/emit_protocol_application.sh',args.xls,config,build],stage,'public-build')
    qualify(build,stage)


def simulator_source(build: Path, stage: Path) -> Path:
    """Observe all public source fault pins; the four-source expansion retains the original runner bytes."""
    manifest=json.loads((build/'application/manifest.json').read_text())
    actors=manifest['actors']
    indices=range(actors)
    expression='dut.ingress_fault||'+'||'.join(f'dut.actor_{i}_{field}' for field in ['failure','fault'] for i in indices)
    source=stage/'simulation.cpp'
    text=(ROOT/'test/rtl/protocol_application_sim.cpp.in').read_text().replace('@@SOURCE_FAULTS@@',expression)
    from protocol_inspection_sim import debug_fragments
    for key,value in debug_fragments(manifest.get('inspection','none') != 'none').items():text=text.replace('@@DEBUG_'+key+'@@',value)
    source.write_text(text)
    return source


def qualify(build: Path, stage: Path) -> None:
    """Exercise a compiled public application; retain simulation, host and reset evidence."""
    ebin=stage/'ebin';ebin.mkdir()
    run(['erlc',*[v for path in erlang_paths() for v in ('-pa',path)],'+debug_info','-Werror','-o',ebin,
        ROOT/'test/hls_protocol_boundary_fixture.erl',ROOT/'test/hls_protocol_application_live.erl'],stage,'host-compile')
    rtl=[Path(p) for p in (build/'files.f').read_text().splitlines()]
    source=simulator_source(build,stage)
    tracked=rtl+[source,build/'deployment.etf']
    hashes={str(p):digest(p) for p in tracked}
    run(['verilator','--cc','--exe','--build','--top-module','protocol_application_top',
        '--Mdir',stage/'obj_dir','-j','1','-Wno-fatal','-CFLAGS','-std=c++17','-o','simulation',
        *rtl,source],stage,'verilator')
    for i in [1,2]:witness(build,stage/'obj_dir/simulation',ebin,stage/f'live-{i}')
    reset_witness(build,stage,rtl)
    assert hashes=={str(p):digest(p) for p in tracked}
    (stage/'result.json').write_text(json.dumps({'passed':True,'complete_incarnations':2,'frames_each':24,'reset_interruptions':3,'identity_rejections':1,
        'input_hashes':hashes,'evidence':'Finite ordinary-BEAM/broker/RTL witnesses, not general progress or native timing.'},indent=2)+'\n')


if __name__=='__main__':main()
