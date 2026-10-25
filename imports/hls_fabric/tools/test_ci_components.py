"""Focused backend mechanisms: small DSLX units, source variations and application-free RTL fixtures."""
import argparse
import json
from pathlib import Path
import sys
import time

from backend_commands import run
from backend_paths import ROOT, application_directory
from test_protocol_boundary import configuration, expected, simulate
from test_protocol_bridge import build, qualify, reset_witness
from test_protocol_inspection import shapes


def main() -> None:
    """Run bounded functional checks once; omit topology/parameter sweeps, mapping and area measurement."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=lambda p: Path(p).resolve())
    parser.add_argument('stage', type=lambda p: Path(p).resolve())
    args = parser.parse_args()
    args.stage.mkdir()
    compiler = application_directory('erl_hls', 'test')
    imports = [ROOT / 'priv/xls/lib', ROOT / 'priv/xls/fabric', compiler / 'priv/xls/lib', compiler / 'priv/xls/fabric']
    options = ['--warnings_as_errors=false', '--dslx_path=' + ':'.join(map(str, imports)),
               '--dslx_stdlib_path=' + str(args.xls / 'xls/dslx/stdlib')]
    times = {}

    def command(name: str, argv: list[str | Path], timeout: int = 180) -> None:
        """Record wall time for one external test, including its setup, and preserve a failure log."""
        started = time.monotonic()
        run(argv, args.stage, name, timeout=timeout)
        times[name] = time.monotonic() - started
        (args.stage / 'times.json').write_text(json.dumps(times, indent=2) + '\n')

    for name in ['effect_window', 'frame_queue', 'indexed_gather_ram', 'mailbox', 'scheduler', 'scheduler_observation']:
        command(name, [args.xls / 'interpreter_main', '--evaluator=dslx-interpreter', '--compare=none', '--max_ticks=1000', *options,
                       ROOT / 'priv/xls/lib' / (name + '.x')])
    command('retained-mux', [args.xls / 'interpreter_main', '--evaluator=dslx-interpreter',
        '--compare=none', '--max_ticks=1000', *options, ROOT / 'test/xls/retained_mux_test.x'])
    command('bridge-transitions', [args.xls / 'interpreter_main', '--evaluator=dslx-interpreter',
        '--compare=none', *options, ROOT / 'test/rtl/protocol_bridge_transitions.x'])
    command('execution', ['bash', 'tools/test_local_execution.sh', args.xls, args.stage / 'execution'])
    command('receipt-contracts', [sys.executable, 'tools/test_local_protocol.py', args.xls, args.stage / 'receipt-contracts', '--case', 'scalar'], timeout=180)
    shapes(args.xls, args.stage / 'inspection-shapes')
    command('trace-probe', [sys.executable, ROOT / 'tools/test_phi_cycle_trace.py', 'CycleTraceTest.test_capture'])
    command('return-routes', ['bash', 'tools/test_return_routes.sh'])
    command('async-fifo', [sys.executable, 'tools/test_async_fifo.py', '--stage', args.stage / 'async-fifo'])
    command('credit-link', [sys.executable, 'tools/test_credit_link.py', args.xls, '--stage', args.stage / 'credit-link'])
    # One configuration per framing format, retaining isolation/reset/malformed-frame checks.
    for mode in ['full', 'compact']:
        command('packed-' + mode, [sys.executable, 'tools/test_packed_credit.py', args.xls,
            '--stage', args.stage / ('packed-' + mode), '--configs', '1:4', '--quick',
            *(['--compact'] if mode == 'compact' else [])], timeout=240)
    # Four counters cover shared/singleton/unused egress and independent stalls.
    boundary = args.stage / 'boundary'
    boundary.mkdir()
    config = boundary / 'fixture.config'
    configuration(config)
    command('boundary-build', ['bash', 'tools/emit_protocol_boundary.sh', args.xls, config, boundary / 'build'])
    simulate(boundary / 'build', boundary, expected(boundary))
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
