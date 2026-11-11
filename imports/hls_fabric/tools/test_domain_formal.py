"""Check emitted Erlang domain or supervisor lifecycle kernels with finite SAT properties."""
import argparse
import json
import os
from pathlib import Path
import shutil

from backend_commands import digest, run
from backend_paths import ROOT


# Property horizons count composed source transitions, not physical clock edges.
DOMAIN_PROPERTIES = (
    ('command_frame_roundtrip', 1), ('admission_consistent', 1),
    ('stale_request_preserves_state', 1), ('invalid_control_preserves_state', 1),
    ('current_fault_closes_ready', 1), ('readiness_requires_completion', 1),
    ('stopped_requires_explicit_replacement', 1), ('eight_step_history', 8),
    ('incorrect_nonzero_admission', 1),
)
SUPERVISOR_PROPERTIES = (
    ('command_frame_roundtrip', 1), ('stale_stop_preserves_state', 1),
    ('exact_start_replay_preserves_state', 1), ('terminal_emits_no_child_command', 1),
    ('initial_allocation_consumes_one', 2), ('pending_retry_preserves_allocation', 1),
    ('incorrect_start_is_running', 1),
)


def main() -> None:
    """Select an emitted control unit; preserve exact inputs, assumptions and counterexamples."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=lambda value: Path(value).resolve())
    parser.add_argument('bundle', type=lambda value: Path(value).resolve())
    parser.add_argument('stage', type=lambda value: Path(value).resolve())
    parser.add_argument('--yosys', default=os.environ.get('YOSYS', 'yosys'))
    parser.add_argument('--supervisor', action='store_true',
                        help='Check the supervisor control unit in a static-supervisor bundle.')
    args = parser.parse_args()
    args.stage.mkdir()
    manifest = json.loads((args.bundle / 'source-build.json').read_text())
    if args.supervisor:
        unit, = [item for item in manifest['units'] if item['top'] == 'supervisor_clock']
    else:
        unit, = manifest['units']
    for item in manifest['inputs']:
        assert digest(args.bundle / item['file']) == item['sha256']
    imports = [args.bundle / name for name in unit['dslx_path']]
    kind = 'supervisor' if args.supervisor else 'domain'
    properties = ROOT / f'test/rtl/{kind}_lifecycle_properties.x'
    source = args.stage / 'properties.x'
    shutil.copyfile(properties, source)
    yosys = Path(shutil.which(args.yosys) or args.yosys).resolve()
    inputs = {str(path): digest(path) for path in
              [properties, Path(__file__).resolve(), yosys,
               *(args.xls / name for name in ('ir_converter_main', 'opt_main', 'codegen_main')),
               *(args.bundle / item['file'] for item in manifest['inputs'])]}
    rows = []
    selected = SUPERVISOR_PROPERTIES if args.supervisor else DOMAIN_PROPERTIES
    for name, horizon in selected:
        directory = args.stage / name
        directory.mkdir()
        run([args.xls / 'ir_converter_main', '--warnings_as_errors=false', '--top=' + name,
             '--dslx_path=' + ':'.join(map(str, imports)),
             '--dslx_stdlib_path=' + str(args.xls / 'xls/dslx/stdlib'), source],
            directory, 'convert', directory / 'raw.ir')
        run([args.xls / 'opt_main', directory / 'raw.ir'], directory, 'opt', directory / 'opt.ir')
        run([args.xls / 'codegen_main', '--generator=combinational', '--module_name=contract',
             '--use_system_verilog=false', directory / 'opt.ir'], directory, 'codegen', directory / 'contract.v')
        negative = name.startswith('incorrect_')
        script = directory / 'proof.ys'
        quoted = str(directory / 'contract.v').replace('\\', '\\\\').replace('"', '\\"')
        script.write_text(f'read_verilog -sv "{quoted}"\nprep -top contract -flatten\nopt\n'
                          + 'sat ' + ('' if negative else '-verify ')
                          + '-prove out 1 -set-def-inputs -show-inputs\n')
        run([yosys, '-Q', '-T', '-s', script], directory, 'proof', timeout=180)
        verdict = 'model found: FAIL!' if negative else 'no model found: SUCCESS!'
        assert 'SAT proof finished - ' + verdict in (directory / 'proof.log').read_text()
        rows.append({'property': name, 'verdict': 'counterexample' if negative else 'pass',
                     'horizon': horizon,
                     'artifacts': {path.name: digest(path) for path in directory.iterdir() if path.is_file()}})
        print('PASS:', name, verdict, flush=True)
    assert all(digest(Path(path)) == value for path, value in inputs.items())
    (args.stage / 'result.json').write_text(json.dumps({
        'passed': True, 'kind': kind, 'inputs': inputs, 'checks': rows,
        'domain': ('Defined finite-width inputs to six combinational propositions: arbitrary '
                   'states for rejection/replay/terminal rules; valid grants from cold state and '
                   'a constructed outstanding restart for allocation/retry. No arbitrary-history '
                   'or exhaustive native/RTL equivalence claim.' if args.supervisor else
                   'All defined finite-width input bits; single-step arbitrary states or eight '
                   'steps from cold zero state.'),
        'assumptions': ('Generated service failure latch starts zero. Property-local legal grant '
                        'bounds and outstanding-command state are explicit in the retained source; '
                        'the sole authority supplies ordered child observations. No physical '
                        'completion or progress follows from these propositions.' if args.supervisor else
                        'Generated service failure latch starts zero. Completion inputs model '
                        'reported facts, not physical correctness.'),
        'trust': 'Erlang lowering, XLS, Yosys and SAT solver; no physical fence, liveness or board claim.'
    }, indent=2) + '\n')


if __name__ == '__main__':
    main()
