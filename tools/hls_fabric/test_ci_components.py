"""Focused backend mechanisms: small DSLX units, source variations and application-free RTL fixtures."""
import argparse
import json
from pathlib import Path
import shutil
import sys
import time

from backend_commands import run
from backend_paths import ROOT, application_directory, erlang_environment
from compiler_paths import compiler_resource
from test_protocol_boundary import configuration, expected, simulate
from test_protocol_bridge import build, qualify, reset_witness
from test_protocol_inspection_shapes import shapes


def main() -> None:
    """Run bounded functional checks once; omit topology/parameter sweeps, mapping and area measurement."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=lambda p: Path(p).resolve())
    parser.add_argument('stage', type=lambda p: Path(p).resolve())
    args = parser.parse_args()
    args.stage.mkdir()
    compiler = application_directory('erl_hls', 'test')
    library = compiler_resource(compiler, 'hls_compile', 'priv/xls/lib')
    fabric = compiler_resource(compiler, 'hls_fabric', 'priv/xls/fabric')
    imports = [ROOT / 'apps/hls_target/priv/xls/lib', ROOT / 'apps/hls_fabric/priv/xls/fabric', library, fabric]
    options = ['--warnings_as_errors=false', '--dslx_path=' + ':'.join(map(str, imports)),
               '--dslx_stdlib_path=' + str(args.xls / 'xls/dslx/stdlib')]
    times = {}

    def command(name: str, argv: list[str | Path], timeout: int = 180,
                env: dict[str, str] | None = None) -> None:
        """Record wall time for one external test, including its setup, and preserve a failure log."""
        started = time.monotonic()
        run(argv, args.stage, name, timeout=timeout, env=env)
        times[name] = time.monotonic() - started
        (args.stage / 'times.json').write_text(json.dumps(times, indent=2) + '\n')

    # Shared public-port FIFO mechanics need no generated hardware or decoder workload.
    command('clocked-controllers', [sys.executable, 'tools/hls_fabric/test_clocked_controllers.py',
        args.xls, args.stage / 'clocked-controllers'])
    fifo_test = args.stage / 'fifo-stream-test'
    command('fifo-stream-compile', ['c++', '-std=c++17', '-Wall', '-Wextra', '-Werror',
        ROOT / 'apps/hls_fabric/test/rtl/framed_fifo_stream_test.cpp', '-o', fifo_test])
    command('fifo-stream', [fifo_test, args.stage / 'fifo-stream'], timeout=30)
    for name in ['effect_window', 'frame_queue', 'indexed_gather_ram', 'mailbox', 'scheduler', 'scheduler_observation']:
        command(name, [args.xls / 'interpreter_main', '--evaluator=dslx-interpreter', '--compare=none', '--max_ticks=1000', *options,
                       ROOT / 'apps/hls_target/priv/xls/lib' / (name + '.x')])
    command('retained-mux', [args.xls / 'interpreter_main', '--evaluator=dslx-interpreter',
        '--compare=none', '--max_ticks=1000', *options, ROOT / 'apps/hls_fabric/test/xls/retained_mux_test.x'])
    command('transport-envelopes', [args.xls / 'interpreter_main', '--evaluator=dslx-interpreter',
        '--compare=none', *options, ROOT / 'apps/hls_fabric/test/xls/protocol_envelope_test.x'])
    command('bridge-transitions', [args.xls / 'interpreter_main', '--evaluator=dslx-interpreter',
        '--compare=none', *options, ROOT / 'apps/hls_fabric/test/rtl/protocol_bridge_transitions.x'])
    # Ordinary frame capacity is shared by codec bits, serialization and packed lane storage.
    command('frame-codecs', ['bash', 'tools/hls_fabric/test_protocol_codecs.sh', args.xls,
        args.stage / 'frame-codecs', 'layouts'])
    for words in [1, 9]:
        capacity = args.stage / ('frame-words' + str(words))
        capacity.mkdir()
        for source in [library / 'axis.x', ROOT / 'apps/hls_target/priv/xls/hls_packed_link.x']:
            shutil.copyfile(source, capacity / source.name)
        command('frame-config-' + str(words), ['erl', '+S', '2:2', '-noshell', '-eval',
            '[W,P]=init:get_plain_arguments(),L=hls_frame_layout:new(list_to_integer(W)),'
            'ok=file:write_file(P,xls_frame_layout:config(L),[exclusive]),halt().',
            '-extra', str(words), capacity / 'frame_config.x'], env=erlang_environment('test'))
        selected = ['--warnings_as_errors=false', '--max_ticks=1000',
            '--dslx_path=' + ':'.join(map(str, [capacity, *imports])),
            '--dslx_stdlib_path=' + str(args.xls / 'xls/dslx/stdlib')]
        # Word nine catches the former u8 bit-offset wrap; the lane tests exercise both wire formats.
        for module, test_filter in [('axis', 'OrdinaryCapacityRoundTripTest'),
                ('hls_packed_link', 'configured_.*_frame_test')]:
            command(module + '-words' + str(words), [args.xls / 'interpreter_main',
                '--evaluator=ir-jit', '--compare=none', '--test_filter=' + test_filter,
                *selected, capacity / (module + '.x')])
    # Tiny actor rows cover every optional storage feature without another application build.
    rows = args.stage / 'machine-rows'
    command('machine-rows-generate', ['erl', '-noshell', '-eval',
        'ok=xls_machine_layout_tests:write(hd(init:get_plain_arguments())),halt().',
        '-extra', rows], env=erlang_environment('test'))
    for name in ['ordinary', 'events', 'reduction_replies', 'gather', 'gather_external',
                 'projected', 'projected_empty']:
        command('machine-row-' + name, [args.xls / 'interpreter_main', '--evaluator=ir-jit',
            '--compare=none', *options, rows / (name + '.x')])
    command('execution', ['bash', 'tools/hls_fabric/test_local_execution.sh', args.xls, args.stage / 'execution'])
    command('receipt-contracts', [sys.executable, 'tools/hls_fabric/test_local_protocol.py', args.xls, args.stage / 'receipt-contracts', '--case', 'scalar'], timeout=180)
    shapes(args.xls, args.stage / 'inspection-shapes')
    command('trace-probe', [sys.executable, ROOT / 'workloads/hls_phi/tools/test_phi_cycle_trace.py', 'CycleTraceTest.test_capture'])
    command('return-routes', ['bash', 'tools/hls_fabric/test_return_routes.sh'])
    command('async-fifo', [sys.executable, 'tools/hls_fabric/test_async_fifo.py', '--stage', args.stage / 'async-fifo'])
    command('credit-link', [sys.executable, 'tools/hls_fabric/test_credit_link.py', args.xls, '--stage', args.stage / 'credit-link'])
    # One configuration per framing format, retaining isolation/reset/malformed-frame checks.
    for mode in ['full', 'compact']:
        command('packed-' + mode, [sys.executable, 'tools/hls_fabric/test_packed_credit.py', args.xls,
            '--stage', args.stage / ('packed-' + mode), '--configs', '1:4', '--quick',
            *(['--compact'] if mode == 'compact' else [])], timeout=240)
    # Four counters cover shared/singleton/unused egress and independent stalls.
    boundary = args.stage / 'boundary'
    boundary.mkdir()
    config = boundary / 'fixture.config'
    configuration(config)
    command('boundary-build', ['bash', 'tools/hls_fabric/emit_protocol_boundary.sh', args.xls, config, boundary / 'build'])
    simulate((boundary / 'build/compiled').resolve(), boundary, expected(boundary))
    # Three actors cover crossing routes, real relay leases and reset-incarnation retirement.
    framed = args.stage / 'framed'
    framed.mkdir()
    roles = build(args.xls, framed)
    qualify(roles, framed)
    reset_witness(roles[0], framed)
    (args.stage / 'result.json').write_text(json.dumps({'passed': True,
        'application_workloads': [], 'limits': 'Finite functional witnesses; no area, timing or scaling qualification.'}, indent=2) + '\n')


if __name__ == '__main__':
    main()
