"""Compile an emitted ordinary or sender-local inbox actor owner into sampled-clock RTL."""
from pathlib import Path
import argparse
import hashlib
import json

from backend_paths import ROOT
from compiler_paths import compiler_root, compiler_tool


def digest(path: Path) -> str:
    """Identify retained inputs and outputs by exact bytes."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compile_owner(xls: Path, source: Path, output: Path, imports: list[Path] | None = None,
                  *, public: Path | None = None, profile: str = "default") -> None:
    """Publish checked sampled-clock RTL with cached stages and retained failure diagnostics.

    The selected manifest clock_proc is the ordinary or source-bound inbox owner.
    The resulting local_actor module has packed _commands/_observations ports;
    tie _commands_vld and _observations_rdy high on every clock. This scheduling
    contract makes source-level output_ready independent of XLS channel stalls.
    """
    public = compiler_root(profile, public)
    compiler = compiler_tool(public, "compile_xls")
    source, xls = source.resolve(), xls.resolve()
    manifest_file = Path(str(source) + '.json')
    manifest = json.loads(manifest_file.read_text())
    if (manifest['dslx_sha256'] != digest(source)
            or manifest['frame_config_sha256'] != digest(source.parent/'frame_config.x')
            or manifest['clock_proc'] not in ['local_owner_clock', 'local_inbox_clock']):
        raise ValueError('changed or unsupported actor source/configuration')
    flags = manifest['codegen_flags']
    hardware_profile = manifest['build_profile']
    schedule = hardware_profile['schedules']['sampled_clock']
    roots = [ROOT/'apps/hls_lowering/priv/xls/lib', ROOT/'apps/hls_lowering/priv/xls/fabric', public/'priv/xls/lib',
             public/'priv/xls/fabric', *(imports or [])]
    directories = ['_stdlib', *[f'_imports/{index}' for index in range(len(roots))]]
    files = {path.name: path for path in sorted(source.parent.glob('*.x'))}
    files[manifest_file.name] = manifest_file
    for prefix, path in zip(directories[1:], roots):
        if path.is_dir():
            files.update(compiler.tree_files(path, prefix))
    stdlib = xls/'xls/dslx/stdlib'
    if not (stdlib/'std.x').is_file():
        raise ValueError(f'missing XLS standard library: {stdlib}')
    files.update(compiler.tree_files(stdlib, '_stdlib'))
    search = ':'.join(['.', *directories[1:]])
    products = [('convert', 'raw.ir'), ('opt', 'optimized.ir'), ('codegen', 'actor.v')]
    tools = {name: xls/name for name in ['ir_converter_main', 'opt_main', 'codegen_main']}

    def prepare(snapshot: Path) -> list[dict]:
        """Check the retained actor manifest before compiling only its frozen source tree."""
        retained = json.loads((snapshot/manifest_file.name).read_text())
        if (retained != manifest or retained['dslx_sha256'] != digest(snapshot/source.name)
                or retained['frame_config_sha256'] != digest(snapshot/'frame_config.x')):
            raise ValueError('changed actor source, configuration or manifest during snapshot')
        return [
            {'id': 'convert', 'cache': 'owner_ir', 'tool': 'ir_converter_main',
             'arguments': ['--warnings_as_errors=false', '--top='+retained['clock_proc'],
                           '--dslx_path='+search, '--dslx_stdlib_path=_stdlib', source.name],
             'output': 'raw.ir', 'inputs': {name: name for name in files if name.endswith('.x')}},
            {'id': 'opt', 'cache': 'owner_opt', 'tool': 'opt_main',
             'arguments': ['raw.ir'], 'output': 'optimized.ir', 'inputs': {'ir': 'raw.ir'}},
            {'id': 'codegen', 'cache': 'owner_codegen', 'tool': 'codegen_main',
             'arguments': [*flags, '--module_name=local_actor', 'optimized.ir'],
             'output': 'actor.v', 'inputs': {'ir': 'optimized.ir'}},
        ]

    def finalize(snapshot: Path, runs: dict) -> dict:
        """Retain the owner contract and actual stage commands with the executor's verified products."""
        records = [{key: runs[name][key] for key in ['command', 'exit', 'output', 'sha256']}
                   for name, _ in products]
        (snapshot/'commands.json').write_text(json.dumps(records, indent=2)+'\n')
        report = {'actor': manifest, 'build_profile': hardware_profile, 'module': 'local_actor', 'source': str(source),
                  'rtl_sha256': digest(snapshot/'actor.v'),
                  'dslx_path': ':'.join(map(str, roots)),
                  'inputs': {name: digest(snapshot/name) for name in files},
                  'xls_tools': {name: digest(path) for name, path in tools.items()},
                  'schedule': {**{key: schedule[key] for key in ('pipeline_stages', 'flop_inputs', 'flop_outputs')},
                               'commands_valid': True, 'observations_ready': True},
                  'network_admitted': False, 'native_measured': False}
        retained = {filename: filename for _, filename in products}
        retained['commands.json'] = 'commands.json'
        retained.update({'sources/'+name: name for name in files})
        return {'manifest_name': 'owner.json', 'manifest': report, 'files': retained}

    compiler.execute(files, tools, output, prepare=prepare, finalize=finalize,
                     name='local_actor', directories=directories, timeout=300)


def main() -> None:
    """Compile the selected current artifact using an explicit XLS distribution."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--erl-hls', type=Path)
    parser.add_argument('--profile', default='default')
    parser.add_argument('xls', type=Path)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--dslx-path', type=Path, action='append', default=[])
    args = parser.parse_args()
    compile_owner(args.xls.resolve(), args.source.resolve(), args.output.absolute(),
                  [path.resolve() for path in args.dslx_path], public=args.erl_hls, profile=args.profile)


if __name__ == '__main__':
    main()
