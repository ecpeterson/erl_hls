"""Compile an emitted source actor's DSLX owner into a sampled-clock RTL module."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

from backend_paths import ROOT, PUBLIC


def digest(path: Path) -> str:
    """Identify retained inputs and outputs by exact bytes."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compile_owner(xls: Path, source: Path, output: Path, imports: list[Path] | None = None) -> None:
    """Require the emitted source identity, create fresh products, and retain failed tool diagnostics.

    The resulting local_actor module has packed _commands/_observations ports;
    tie _commands_vld and _observations_rdy high on every clock. This scheduling
    contract makes source-level output_ready independent of XLS channel stalls.
    """
    manifest = json.loads(Path(str(source) + '.json').read_text())
    if manifest['dslx_sha256'] != digest(source) or manifest['clock_proc'] != 'local_owner_clock':
        raise ValueError('changed or unsupported actor source')
    output.mkdir()
    paths = ':'.join(map(str, [ROOT/'priv/xls/lib', ROOT/'priv/xls/fabric',
                              PUBLIC/'priv/xls/lib', PUBLIC/'priv/xls/fabric', *(imports or [])]))
    commands = [
        ('convert', [xls/'ir_converter_main', '--warnings_as_errors=false', '--top=local_owner_clock',
                     '--dslx_path='+paths, '--dslx_stdlib_path='+str(xls/'xls/dslx/stdlib'), source], 'raw.ir'),
        ('opt', [xls/'opt_main', output/'raw.ir'], 'optimized.ir'),
        ('codegen', [xls/'codegen_main', '--pipeline_stages=1', '--delay_model=unit',
                     '--flop_inputs=false', '--flop_outputs=false', '--use_system_verilog=false',
                     '--reset=reset', '--module_name=local_actor', output/'optimized.ir'], 'actor.v'),
    ]
    records = []
    for name, command, filename in commands:
        target = output/filename
        with target.open('x') as product, (output/(name+'.log')).open('x') as log:
            result = subprocess.run(list(map(str, command)), stdout=product, stderr=log, timeout=300)
        records.append({'command':list(map(str, command)), 'exit':result.returncode,
                        'output':filename, 'sha256':digest(target)})
        (output/'commands.json').write_text(json.dumps(records, indent=2)+'\n')
        if result.returncode:
            raise RuntimeError(f'{name} failed: ' + (output/(name+'.log')).read_text()[-4000:])
    report = {'actor':manifest, 'module':'local_actor', 'source':str(source),
              'rtl_sha256':digest(output/'actor.v'),
              'dslx_path':paths,
              'xls_tools':{name:digest(xls/name) for name in ['ir_converter_main', 'opt_main', 'codegen_main']},
              'schedule':{'pipeline_stages':1, 'flop_inputs':False, 'flop_outputs':False,
                          'commands_valid':True, 'observations_ready':True},
              'network_admitted':False, 'native_measured':False}
    (output/'owner.json').write_text(json.dumps(report, indent=2)+'\n')


def main() -> None:
    """Compile the selected current artifact using an explicit XLS distribution."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=Path)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--dslx-path', type=Path, action='append', default=[])
    args = parser.parse_args()
    compile_owner(args.xls.resolve(), args.source.resolve(), args.output.resolve(),
                  [path.resolve() for path in args.dslx_path])


if __name__ == '__main__':
    main()
