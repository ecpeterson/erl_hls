"""Check the compiled Erlang lifecycle kernel, including an eight-input SAT bound."""
import argparse
import json
import os
from pathlib import Path
import shutil

from backend_commands import digest, run
from backend_paths import ROOT


def main() -> None:
    """Use an emitted domain bundle; preserve solver counterexamples and exact inputs."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=lambda value: Path(value).resolve())
    parser.add_argument('bundle', type=lambda value: Path(value).resolve())
    parser.add_argument('stage', type=lambda value: Path(value).resolve())
    parser.add_argument('--yosys', default=os.environ.get('YOSYS', 'yosys'))
    args = parser.parse_args()
    args.stage.mkdir()
    manifest = json.loads((args.bundle / 'source-build.json').read_text())
    unit, = manifest['units']
    for item in manifest['inputs']:
        assert digest(args.bundle / item['file']) == item['sha256']
    imports = [args.bundle / name for name in unit['dslx_path']]
    properties = ROOT / 'test/rtl/domain_lifecycle_properties.x'
    source = args.stage / 'properties.x'
    shutil.copyfile(properties, source)
    yosys = Path(shutil.which(args.yosys) or args.yosys).resolve()
    inputs = {str(path): digest(path) for path in
              [properties, Path(__file__).resolve(), yosys,
               *(args.xls / name for name in ('ir_converter_main', 'opt_main', 'codegen_main')),
               *(args.bundle / item['file'] for item in manifest['inputs'])]}
    rows = []
    for name in ('command_frame_roundtrip', 'admission_consistent', 'stale_request_preserves_state',
                 'invalid_control_preserves_state', 'current_fault_closes_ready',
                 'readiness_requires_completion', 'eight_step_history',
                 'incorrect_nonzero_admission'):
        directory = args.stage / name
        directory.mkdir()
        run([args.xls / 'ir_converter_main', '--warnings_as_errors=false', '--top=' + name,
             '--dslx_path=' + ':'.join(map(str, imports)),
             '--dslx_stdlib_path=' + str(args.xls / 'xls/dslx/stdlib'), source],
            directory, 'convert', directory / 'raw.ir')
        run([args.xls / 'opt_main', directory / 'raw.ir'], directory, 'opt', directory / 'opt.ir')
        run([args.xls / 'codegen_main', '--generator=combinational', '--module_name=contract',
             '--use_system_verilog=false', directory / 'opt.ir'], directory, 'codegen', directory / 'contract.v')
        negative = name == 'incorrect_nonzero_admission'
        script = directory / 'proof.ys'
        quoted = str(directory / 'contract.v').replace('\\', '\\\\').replace('"', '\\"')
        script.write_text(f'read_verilog -sv "{quoted}"\nprep -top contract -flatten\nopt\n'
                          + 'sat ' + ('' if negative else '-verify ')
                          + '-prove out 1 -set-def-inputs -show-inputs\n')
        run([yosys, '-Q', '-T', '-s', script], directory, 'proof', timeout=180)
        verdict = 'model found: FAIL!' if negative else 'no model found: SUCCESS!'
        assert 'SAT proof finished - ' + verdict in (directory / 'proof.log').read_text()
        rows.append({'property': name, 'verdict': 'counterexample' if negative else 'pass',
                     'horizon': 8 if name == 'eight_step_history' else 1,
                     'artifacts': {path.name: digest(path) for path in directory.iterdir() if path.is_file()}})
        print('PASS:', name, verdict, flush=True)
    assert all(digest(Path(path)) == value for path, value in inputs.items())
    (args.stage / 'result.json').write_text(json.dumps({
        'passed': True, 'inputs': inputs, 'checks': rows,
        'domain': 'All defined finite-width input bits; single-step arbitrary states or eight steps from cold zero state.',
        'assumptions': 'Generated service failure latch starts zero. Completion inputs model reported facts, not physical correctness.',
        'trust': 'Erlang lowering, XLS, Yosys and SAT solver; no physical fence, liveness or board claim.'
    }, indent=2) + '\n')


if __name__ == '__main__':
    main()
