"""Exercise two independent compiled source domains through actual Erlang/FIFO clients."""
from pathlib import Path
import argparse
import json
import shlex
import shutil
import subprocess
import time

from backend_commands import digest, run
from backend_paths import ROOT, erlang_paths, erlang_environment
from protocol_test_build import compile_build


def build(xls: Path, stage: Path, bad_initialization: bool, ebin: Path) -> Path:
    """Emit and compile the complete reusable domain boundary; retain every failed stage."""
    stage.mkdir()
    source_options = "[{d, 'DOMAIN_BAD_INITIALIZATION'}]" if bad_initialization else "[]"
    config = ('#{sources=>[{"test/hls_domain_counter.erl",' + source_options + '},'
              '{"test/hls_domain_relay.erl",[]}],'
              'topology=>{hls_domain_counter,topology,[]},actor_limit=>2,control=>rectangle}')
    expression = ('[Output,Header]=init:get_plain_arguments(), _=hls_protocol_domain:write('
                  + config + ',Output), ok=hls_domain_rtl_backend:write_codes('
                  'filename:join(Output,"domain/interface.etf"),Header), halt().')
    bundle = stage / 'source'
    run(['erl', '+S', '2:2', '-pa', ebin, '-noshell', '-eval', expression,
         '-extra', bundle, stage / 'domain_codes.h'],
        stage, 'emit', env=erlang_environment('test'))
    compiled = compile_build(xls, bundle, profile='test')
    run(['verilator', '--cc', '--exe', '--build', '--top-module', 'protocol_domain',
         '--Mdir', stage / 'obj_dir', '-j', '1', '-Wno-fatal',
         '-CFLAGS', '-std=c++17 -I' + shlex.quote(str(stage)),
         '-o', 'simulation', compiled / 'domain/core.v',
         compiled / 'domain/protocol_domain.sv', ROOT / 'test/rtl/domain_sim.cpp'],
        stage, 'verilator')
    return stage / 'obj_dir/simulation'


def witness(binary: Path, ebin: Path, stage: Path, mode: str, interface: Path) -> None:
    """Run real domain owners and actor endpoint processes while RTL controls reset/readiness."""
    stage.mkdir()
    shutil.copyfile(interface, stage / 'interface.etf')
    with (stage / 'simulation.log').open('x') as log:
        simulator = subprocess.Popen([binary, stage], stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 10
            while not (stage / 'domain1_application_rx').exists():
                if simulator.poll() is not None or time.monotonic() > deadline:
                    raise RuntimeError('domain simulator startup failed')
                time.sleep(.02)
            expression = ('[Stage,Mode]=init:get_plain_arguments(), '
                          'ModeAtom=case Mode of \"normal\"->normal; \"bad_initialization\"->bad_initialization end, '
                          'ok=hls_domain_recovery_live:run(Stage,ModeAtom),halt().')
            run(['erl', '+S', '2:2', '-noshell', '-pa', *erlang_paths('test'), ebin,
                 '-eval', expression, '-extra', stage, mode], stage, 'host')
            if simulator.wait(timeout=10) != 0:
                raise RuntimeError((stage / 'simulation.log').read_text())
        finally:
            if simulator.poll() is None:
                simulator.terminate()
                simulator.wait(timeout=5)
    assert 'PASS domain RTL:' in (stage / 'simulation.log').read_text()
    assert json.loads((stage / 'result.json').read_text())['passed']


def main() -> None:
    """Qualify the ordinary and failed-initialization designs serially, without native synthesis."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=lambda p: Path(p).resolve())
    parser.add_argument('stage', type=lambda p: Path(p).resolve())
    args = parser.parse_args()
    args.stage.mkdir()
    ebin = args.stage / 'ebin'
    ebin.mkdir()
    sources = [ROOT / 'test' / name for name in
               ['hls_domain_counter.erl', 'hls_domain_relay.erl',
                'hls_domain_rtl_backend.erl', 'hls_domain_rtl_endpoint.erl',
                'hls_domain_recovery_live.erl', 'hls_test_nodes.erl']]
    run(['erlc', *[v for p in erlang_paths('test') for v in ('-pa', p)],
         '+debug_info', '-Werror', '-o', ebin, *sources], args.stage, 'host-compile')
    tracked = [*sources, ROOT / 'test/rtl/domain_sim.cpp', ROOT / 'test/rtl/framed_fifo_stream.h']
    before = {str(p): digest(p) for p in tracked}
    for mode, bad in [('normal', False), ('bad_initialization', True)]:
        part = args.stage / mode
        binary = build(args.xls, part, bad, ebin)
        witness(binary, ebin, part / 'live', mode, part / 'source/domain/interface.etf')
    assert before == {str(p): digest(p) for p in tracked}
    (args.stage / 'result.json').write_text(json.dumps({
        'passed': True, 'inputs': before,
        'evidence': 'Finite two-domain RTL/FIFO and real Erlang owner/endpoint witnesses.',
        'limits': 'No distributed-board, physical-timing, general liveness or exhaustive equivalence claim.'
    }, indent=2) + '\n')


if __name__ == '__main__':
    main()
