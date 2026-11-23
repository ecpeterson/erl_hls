"""Exercise the emitted channel wrapper and prove two single-edge ownership properties."""
import argparse
import json
import os
from pathlib import Path
import shutil

from backend_commands import digest, run
from backend_paths import ROOT


# Each property quantifies one complete sampled wrapper edge, not an arbitrary history.
PROPERTIES = (
    ('stale_exclusion', False),
    ('credit_release_exact', False),
    ('wrong_stale_accepts', True),
)


def main() -> None:
    """Use the bundle's actual channel unit and retain finite witnesses, SAT evidence and inputs."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=lambda value: Path(value).resolve())
    parser.add_argument('bundle', type=lambda value: Path(value).resolve())
    parser.add_argument('stage', type=lambda value: Path(value).resolve())
    parser.add_argument('--yosys', default=os.environ.get('YOSYS', 'yosys'))
    args = parser.parse_args()
    args.stage.mkdir()
    manifest_path = args.bundle / 'source-build.json'
    manifest = json.loads(manifest_path.read_text())
    unit, = [item for item in manifest['units'] if item['top'] == 'channel_clock']
    for item in manifest['inputs']:
        assert digest(args.bundle / item['file']) == item['sha256'], item['file']
    imports = [args.bundle / name for name in unit['dslx_path']]
    properties = ROOT / 'apps/hls_fabric/test/domain_channel_semantics.x'
    source = args.stage / 'properties.x'
    shutil.copyfile(properties, source)
    yosys = Path(shutil.which(args.yosys) or args.yosys).resolve()
    inputs = {str(path): digest(path) for path in [
        properties, source, Path(__file__).resolve(), manifest_path, yosys,
        *(args.xls / name for name in ('interpreter_main', 'ir_converter_main', 'opt_main', 'codegen_main')),
        *(args.bundle / item['file'] for item in manifest['inputs'])
    ]}
    common = ['--warnings_as_errors=false',
              '--dslx_path=' + ':'.join(map(str, imports)),
              '--dslx_stdlib_path=' + str(args.xls / 'xls/dslx/stdlib')]
    run([args.xls / 'interpreter_main', '--evaluator=dslx-interpreter', '--compare=none',
         '--max_ticks=1000', *common, source], args.stage, 'witness')
    rows = []
    for name, negative in PROPERTIES:
        directory = args.stage / name
        directory.mkdir()
        run([args.xls / 'ir_converter_main', '--top=' + name, *common, source],
            directory, 'convert', directory / 'raw.ir')
        run([args.xls / 'opt_main', directory / 'raw.ir'], directory, 'opt', directory / 'opt.ir')
        run([args.xls / 'codegen_main', '--generator=combinational', '--module_name=contract',
             '--use_system_verilog=false', directory / 'opt.ir'],
            directory, 'codegen', directory / 'contract.v')
        script = directory / 'proof.ys'
        quoted = str(directory / 'contract.v').replace('\\', '\\\\').replace('"', '\\"')
        script.write_text(f'read_verilog -sv "{quoted}"\nprep -top contract -flatten\nopt\n'
                          + 'sat ' + ('' if negative else '-verify ')
                          + '-prove out 1 -set-def-inputs -show-inputs\n')
        run([yosys, '-Q', '-T', '-s', script], directory, 'proof', timeout=180)
        verdict = 'model found: FAIL!' if negative else 'no model found: SUCCESS!'
        assert 'SAT proof finished - ' + verdict in (directory / 'proof.log').read_text()
        rows.append({'property': name, 'verdict': 'counterexample' if negative else 'pass',
                     'horizon': 1,
                     'artifacts': {path.name: digest(path) for path in directory.iterdir() if path.is_file()}})
        print('PASS:', name, verdict, flush=True)
    assert all(digest(Path(path)) == value for path, value in inputs.items())
    (args.stage / 'result.json').write_text(json.dumps({
        'passed': True, 'kind': 'domain_channel', 'unit': unit['top'], 'inputs': inputs,
        'witness': {'evidence': 'Six finite actual-wrapper schedules for the 20-word frame fixture.',
                    'log': digest(args.stage / 'witness.log')},
        'checks': rows,
        'domain': 'All defined finite-width wrapper state and input bits, including unreachable states; '
                  'each SAT proposition covers one sampled edge. Finite interpreter schedules '
                  'exercise held payload, independent handshakes, stale traffic, retirement and rebind.',
        'assumptions': {
            'stale_exclusion': 'No additional antecedent beyond incoming data_valid and a generation '
                               'mismatch; reset, bind, fence and service-failure states remain quantified.',
            'credit_release_exact': 'The implication concerns an in-flight credit becoming free on an '
                                    'ordinary non-reset/non-control edge, with active exact ready endpoints '
                                    'and no old or new service failure. Release requires an exact incoming '
                                    'credit after old-state receipt and acknowledgement emission.',
            'wrong_stale_accepts': 'The deliberately false control requires a healthy active in-flight '
                                   'published/unreceived packet, exact live endpoint incarnations and '
                                   'matching sequence, but a stale incoming generation. A counterexample '
                                   'is required rather than accepted as a failed qualification.'
        },
        'trust': 'Erlang lowering, XLS, Yosys and SAT solver. Endpoint observations are supplied facts; '
                 'these checks establish neither physical fencing, transport integrity, progress, '
                 'arbitrary-history correctness nor native/RTL equivalence.'
    }, indent=2) + '\n')


if __name__ == '__main__':
    main()
