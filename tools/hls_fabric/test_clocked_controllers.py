"""Compile every sampled lifecycle controller through the merged actor backend, without full application builds."""
import argparse
from pathlib import Path
import json

from backend_commands import digest, run
from backend_paths import ROOT, application_directory, erlang_environment
from compiler_paths import compiler_resource


def main() -> None:
    """Check the actual clock_step API used by domain/endpoint wrappers; retain failures and exact inputs."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=lambda s: Path(s).resolve())
    parser.add_argument('stage', type=lambda s: Path(s).resolve())
    args = parser.parse_args()
    args.stage.mkdir()
    run(['erl', '+S', '1:1', '-noshell', '-eval',
         '[P]=init:get_plain_arguments(),ok=xls_clocked_controller_tests:write(P),halt().',
         '-extra', args.stage], args.stage, 'emit', env=erlang_environment('test'))
    compiler = application_directory('erl_hls', 'test')
    shared = [compiler_resource(compiler, 'hls_compile', 'priv/xls/lib'),
              compiler_resource(compiler, 'hls_fabric', 'priv/xls/fabric'),
              ROOT / 'apps/hls_target/priv/xls/lib']
    evidence = []
    for unit in sorted(p for p in args.stage.iterdir() if p.is_dir()):
        inputs = {str(p): digest(p) for p in unit.glob('*.x')}
        run([args.xls / 'ir_converter_main', '--top=clock_step', '--warnings_as_errors=false',
             '--dslx_path=' + ':'.join(map(str, [unit, *shared])),
             '--dslx_stdlib_path=' + str(args.xls / 'xls/dslx/stdlib'), unit / 'controller.x'],
            unit, 'convert', unit / 'controller.ir')
        evidence.append({'unit': unit.name, 'inputs': inputs, 'ir_sha256': digest(unit / 'controller.ir')})
    (args.stage / 'result.json').write_text(json.dumps({'passed': True, 'units': evidence,
        'scope': 'Compiler/type checking of shipped control adapters; no equivalence proof.'}, indent=2) + '\n')


if __name__ == '__main__':
    main()
