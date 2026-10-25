#!/usr/bin/env python3
"""Inspect or compile a frozen source bundle with the shared external XLS executor.

The manifest owns entry points, imports and schedules. Execution snapshots those
inputs and publishes every unit together; it never writes compiler products into
the source bundle. The two adjacent Python scripts need only the standard library.
"""
from functools import cache
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys
from types import ModuleType
from typing import TypedDict


class FileIdentity(TypedDict):
    """One exact input or product, identified independently of modification time."""
    file: str
    sha256: str


class ToolIdentity(TypedDict):
    """An executable's resolved filename and contents."""
    path: str
    sha256: str


class Command(TypedDict):
    """Snapshot-relative arguments and output paths, executed in the private snapshot."""
    stage: str
    command: list[str]
    output: str
    log: str


class UnitPlan(TypedDict):
    """One emitter-owned entry point and its exact external schedule and commands."""
    directory: str
    role: str
    source: str
    top: str
    module: str
    codegen_flags: list[str]
    dslx_path: list[str]
    commands: list[Command]


class BuildPlan(TypedDict):
    """A checked, read-only recipe; relative command paths refer to the future snapshot."""
    version: int
    directory: str
    source_build_sha256: str
    inputs: list[FileIdentity]
    xls_tools: dict[str, ToolIdentity]
    stdlib: str
    stdlib_inputs: list[FileIdentity]
    units: list[UnitPlan]
    rtl: dict[str, list[str]]


@cache
def executor() -> ModuleType:
    """Load the adjacent standalone executor without selecting a checkout or changing search paths."""
    path = Path(__file__).resolve().with_name('compile_xls.py')
    name = '_source_build_executor_' + hashlib.sha256(str(path).encode()).hexdigest()
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f'cannot load XLS executor: {path}')
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    try:
        spec.loader.exec_module(module)
    except BaseException:
        del sys.modules[name]
        raise
    return module


def digest(path: Path) -> str:
    """Identify exact external inputs and products."""
    return executor().sha(path)


def relative(value: str) -> str:
    """Require a bundle-relative path without parent traversal or the reserved standard-library root."""
    path = Path(value)
    if not value or path.is_absolute() or '..' in path.parts or (path.parts and path.parts[0] == '_stdlib'):
        raise ValueError('invalid source-build path: ' + value)
    return str(path)


def unit_commands(unit: dict, tools: dict[str, ToolIdentity]) -> list[Command]:
    """Keep command construction shared by preview and execution, including literal schedule flags."""
    stage = Path(unit['directory'])
    raw, optimized = str(stage / 'raw.ir'), str(stage / 'optimized.ir')
    rows = [
        ('convert', 'ir_converter_main',
         ['--warnings_as_errors=false', '--top=' + unit['top'],
          '--dslx_path=' + ':'.join(unit['dslx_path']), '--dslx_stdlib_path=_stdlib', unit['source']], raw),
        ('opt', 'opt_main', [raw], optimized),
        ('codegen', 'codegen_main', [*unit['codegen_flags'], '--module_name=' + unit['module'], optimized],
         unit['output']),
    ]
    return [{'stage': label, 'command': [tools[tool]['path'], *arguments], 'output': output,
             'log': str(stage / (label + '.log'))} for label, tool, arguments, output in rows]


def plan_build(xls: Path, directory: Path) -> BuildPlan:
    """Verify frozen inputs and resolve commands without writing or running tools.

    All relative paths in commands are interpreted inside a private snapshot.
    Schedules are the emitter's literal flags; this driver offers no override.
    """
    xls, directory = xls.resolve(), directory.resolve()
    manifest_path = directory / 'source-build.json'
    manifest = json.loads(manifest_path.read_text())
    if manifest['version'] != 1:
        raise ValueError('unsupported source build version')
    bound = {}
    for row in manifest['inputs']:
        name = relative(row['file'])
        if name in bound:
            raise ValueError('duplicate source build input: ' + name)
        if digest(directory / name) != row['sha256']:
            raise ValueError('changed source build input: ' + name)
        bound[name] = row['sha256']
    tools = {}
    for name in ('ir_converter_main', 'opt_main', 'codegen_main'):
        path = (xls / name).resolve()
        if not path.is_file() or not os.access(path, os.X_OK):
            raise ValueError('missing or non-executable XLS tool: ' + str(path))
        tools[name] = {'path': str(path), 'sha256': digest(path)}
    stdlib = (xls / 'xls/dslx/stdlib').resolve()
    if not stdlib.is_dir():
        raise ValueError('missing XLS standard library: ' + str(stdlib))
    units, products, directories = [], set(), set()
    for supplied in manifest['units']:
        unit = {**supplied, **{key: relative(supplied[key]) for key in ('directory', 'role', 'source', 'output')},
                'dslx_path': [relative(path) for path in supplied['dslx_path']]}
        if unit['source'] not in bound:
            raise ValueError('unbound unit source: ' + unit['source'])
        if unit['directory'] in directories:
            raise ValueError('duplicate unit directory: ' + unit['directory'])
        directories.add(unit['directory'])
        for name in [unit['directory'], unit['role'], *unit['dslx_path']]:
            if not (directory / name).is_dir():
                raise ValueError('missing unit directory: ' + str(directory / name))
        # Added modules must be frozen too: they can shadow imports even if they were not used before.
        for name in unit['dslx_path']:
            for path in (directory / name).rglob('*.x'):
                # Hidden executor attempts/releases cannot name DSLX modules.
                if any(part.startswith('.') for part in path.relative_to(directory / name).parts):
                    continue
                if str(path.relative_to(directory)) not in bound:
                    raise ValueError('unbound DSLX input: ' + str(path.relative_to(directory)))
        commands = unit_commands(unit, tools)
        names = [command[key] for command in commands for key in ('output', 'log')]
        names.append(str(Path(unit['directory']) / 'commands.json'))
        if len(set(names)) != len(names) or set(names) & (bound.keys() | products):
            raise ValueError('compilation products overlap inputs or another unit')
        products.update(names)
        units.append({key: unit[key] for key in ('directory', 'role', 'source', 'top', 'module',
                                                'codegen_flags', 'dslx_path')} | {'commands': commands})
    rtl = {relative(role): [relative(path) for path in paths] for role, paths in manifest['rtl'].items()}
    for role, paths in rtl.items():
        for path in paths:
            if path not in bound and path not in products:
                raise ValueError('unbound RTL input: ' + path)
        listing = str(Path(role) / 'files.f')
        if listing in bound or listing in products:
            raise ValueError('RTL listing overlaps a source or product')
    if 'compiled.json' in bound or 'source-build.json' in bound:
        raise ValueError('reserved source build input')
    return {'version': 1, 'directory': str(directory), 'source_build_sha256': digest(manifest_path),
            'inputs': manifest['inputs'], 'xls_tools': tools, 'stdlib': str(stdlib),
            'stdlib_inputs': [{'file': name, 'sha256': digest(path)}
                              for name, path in executor().tree_files(stdlib).items()],
            'units': units, 'rtl': rtl}


def compile_build(xls: Path, directory: Path, *, output: Path | None = None,
                  cache: Path | None = None, timeout: float = 300) -> Path:
    """Compile or reuse checked stages and return one complete immutable release.

    The default managed output is SOURCE/compiled. A failed stage leaves the last
    release selected; retry reuses completed stages. Source inputs stay unchanged.
    """
    plan = plan_build(xls, directory)
    source = Path(plan['directory'])
    output = source / 'compiled' if output is None else output
    compiler = executor()
    files = {row['file']: source / row['file'] for row in plan['inputs']}
    files['source-build.json'] = source / 'source-build.json'
    files.update({'_stdlib/' + row['file']: Path(plan['stdlib']) / row['file'] for row in plan['stdlib_inputs']})
    expected = {row['file']: row['sha256'] for row in plan['inputs']}
    expected['source-build.json'] = plan['source_build_sha256']
    expected.update({'_stdlib/' + row['file']: row['sha256'] for row in plan['stdlib_inputs']})
    directories = {unit['directory'] for unit in plan['units']} | {'_stdlib'}
    directories.update(path for unit in plan['units'] for path in unit['dslx_path'])
    directories.update(plan['rtl'])
    specifications = []
    for index, unit in enumerate(plan['units']):
        dependencies = {'sources': {name: name for name in files if name.endswith('.x') and not name.startswith('_stdlib/')},
                        'stdlib': {name: name for name in files if name.startswith('_stdlib/')}}
        for command, tool in zip(unit['commands'], ('ir_converter_main', 'opt_main', 'codegen_main')):
            specifications.append({'id': f'unit{index}.{command["stage"]}',
                                   'cache': 'ir' if command['stage'] == 'convert' else command['stage'],
                                   'tool': tool, 'arguments': command['command'][1:],
                                   'output': command['output'], 'inputs': dependencies})
            dependencies = {command['output']: command['output']}

    def prepare(snapshot: Path) -> list[dict]:
        """Reject changes between preflight and the executor snapshot before any tool runs."""
        for name, value in expected.items():
            if digest(snapshot / name) != value:
                raise ValueError('changed source build input during snapshot: ' + name)
        for tool in plan['xls_tools'].values():
            if digest(Path(tool['path'])) != tool['sha256']:
                raise ValueError('changed XLS tool during snapshot: ' + tool['path'])
        return specifications

    def finalize(snapshot: Path, runs: dict) -> dict:
        """Describe the entire bundle and write portable role lists before common publication."""
        retained = {name: name for name in files}
        records = []
        for index, unit in enumerate(plan['units']):
            stages = []
            for command in unit['commands']:
                stage_id = f'unit{index}.{command["stage"]}'
                result = runs[stage_id]
                row = {key: result[key] for key in ('command', 'output', 'sha256', 'exit',
                                                   'key', 'original_time')}
                row.update(stage=command['stage'], log=command['log'])
                stages.append(row)
                retained[command['output']] = command['output']
                # The common executor retains the original producing stage's stderr alongside its record.
                log_source = stage_id + '.stderr.log'
                retained[command['log']] = log_source
            filename = str(Path(unit['directory']) / 'commands.json')
            (snapshot / filename).write_text(json.dumps(stages, indent=2) + '\n')
            retained[filename] = filename
            records.append({'directory': unit['directory'], 'role': unit['role'], 'commands': stages})
        rtl = {}
        for role, paths in plan['rtl'].items():
            listing = str(Path(role) / 'files.f')
            (snapshot / listing).write_text(''.join(os.path.relpath(path, role) + '\n' for path in paths))
            retained[listing] = listing
            rtl[role] = [{'file': path, 'sha256': digest(snapshot / path)} for path in paths]
        manifest = {'source_build_sha256': plan['source_build_sha256'],
                    'xls_tools': {name: tool['sha256'] for name, tool in plan['xls_tools'].items()},
                    'units': records, 'rtl': rtl, 'eligible': False, 'native_measured': False}
        return {'manifest_name': 'compiled.json', 'manifest': manifest, 'files': retained}

    return compiler.execute(files, {name: Path(tool['path']) for name, tool in plan['xls_tools'].items()},
                            output, prepare=prepare, finalize=finalize, name='source-build',
                            directories=sorted(directories), timeout=timeout, cache=cache)


def main() -> None:
    """Preview a frozen recipe or publish its complete compiled release through the common executor."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run', action='store_true', help='verify and print snapshot-relative commands without executing')
    parser.add_argument('--output', type=Path, help='managed release symlink (default: SOURCE/compiled)')
    parser.add_argument('--cache', type=Path, help='shared checked stage cache')
    parser.add_argument('--timeout', type=executor().duration, default=300, help='per-stage limit, e.g. 300 or 5m')
    parser.add_argument('xls', type=Path)
    parser.add_argument('directory', type=Path)
    args = parser.parse_args()
    if args.dry_run:
        print(json.dumps(plan_build(args.xls, args.directory), indent=2))
    else:
        print(compile_build(args.xls, args.directory, output=args.output, cache=args.cache, timeout=args.timeout))


if __name__ == '__main__':
    main()
