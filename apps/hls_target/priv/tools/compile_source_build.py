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
import platform
import re
import shutil
import sys
import tempfile
import time
from types import ModuleType
from typing import Any, TypedDict


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
    tool: str
    arguments: list[str]
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
    metadata: dict[str, object]
    provenance: dict[str, str]
    inputs: list[FileIdentity]
    xls_tools: dict[str, ToolIdentity]
    stdlib: str
    stdlib_inputs: list[FileIdentity]
    units: list[UnitPlan]
    rtl: dict[str, list[str]]
    request: dict[str, object]
    request_sha256: str


class ImplementationRecord(TypedDict):
    """Exact cache-owned release contents for one realized implementation."""
    schema: int
    request_sha256: str
    implementation_sha256: str
    release_id: str
    files: dict[str, str]


class SelectionCrossLink(ValueError):
    """A request selector names a well-shaped store entry owned by another request."""


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


def sha256_identity(value: object) -> bool:
    """Recognize one canonical lowercase SHA-256 identity."""
    return isinstance(value, str) and re.fullmatch(r'[0-9a-f]{64}', value) is not None


def release_hashes(directory: Path) -> dict[str, str]:
    """Hash every ordinary file in a release and reject links or special entries."""
    if directory.is_symlink() or not directory.is_dir():
        raise ValueError('implementation release root is not a real directory: ' + str(directory))
    result = {}
    for path in sorted(directory.rglob('*')):
        if path.is_symlink() or not (path.is_file() or path.is_dir()):
            raise ValueError('invalid implementation release entry: ' + str(path))
        if path.is_file():
            name = str(path.relative_to(directory))
            executor().relative(name)
            result[name] = digest(path)
    if not result:
        raise ValueError('empty implementation release')
    return result


def exact_release(directory: Path, expected: dict[str, str]) -> bool:
    """Accept a materialized release only when its complete file inventory matches."""
    try:
        return release_hashes(directory) == expected
    except (OSError, ValueError, TypeError):
        return False


def quarantine(path: Path) -> None:
    """Move a corrupt cache entry aside without deleting diagnostic evidence."""
    if path.exists() or path.is_symlink():
        path.rename(path.with_name(f'{path.name}.damaged-{time.time_ns()}'))


def owned_directory(path: Path) -> Path:
    """Create or validate one real cache/output namespace without accepting a final symlink."""
    if path.is_symlink():
        raise ValueError('linked owned directory: ' + str(path))
    path.mkdir(parents=True, exist_ok=True)
    if path.is_symlink() or not path.is_dir():
        raise ValueError('invalid owned directory: ' + str(path))
    return path


def checked_provenance(value: object) -> dict[str, str]:
    """Validate exact optional plan correlation without interpreting target policy."""
    if value == {'kind': 'unplanned'}:
        return {'kind': 'unplanned'}
    required = {'kind', 'logical_system_sha256', 'implementation_plan_sha256',
                'target_projection_sha256'}
    if not isinstance(value, dict) or set(value) != required or value.get('kind') != 'implementation_plan':
        raise ValueError('invalid source build provenance')
    result = {key: str(item) for key, item in value.items()}
    if any(not re.fullmatch(r'[0-9a-f]{64}', result[key]) for key in required - {'kind'}):
        raise ValueError('invalid source build provenance identity')
    return result


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
    return [{'stage': label, 'tool': tool, 'arguments': arguments,
             'command': [tools[tool]['path'], *arguments], 'output': output,
             'log': str(stage / (label + '.log'))} for label, tool, arguments, output in rows]


def build_request(source_build_sha256: str, tools: dict[str, ToolIdentity],
                  stdlib_inputs: list[FileIdentity], units: list[UnitPlan],
                  rtl: dict[str, list[str]]) -> dict[str, object]:
    """Describe a relocatable external-tool request without predicting product bytes."""
    return {
        'schema': 1,
        'executor_recipe': executor().RECIPE_VERSION,
        'host': [platform.system(), platform.machine()],
        'source_recipe_sha256': source_build_sha256,
        'tools': {name: tool['sha256'] for name, tool in sorted(tools.items())},
        'stdlib': sorted(stdlib_inputs, key=lambda row: row['file']),
        'units': [{key: unit[key] for key in ('directory', 'role', 'source', 'top', 'module',
                                             'codegen_flags', 'dslx_path')} | {
            'commands': [{key: command[key] for key in ('stage', 'tool', 'arguments', 'output')}
                         for command in unit['commands']]
        } for unit in units],
        'rtl': {role: paths for role, paths in sorted(rtl.items())},
    }


def plan_build(xls: Path, directory: Path) -> BuildPlan:
    """Verify frozen inputs and resolve commands without writing or running tools.

    All relative paths in commands are interpreted inside a private snapshot.
    Schedules are the emitter's literal flags; this driver offers no override.
    Optional metadata must be an object and is retained without interpreting it.
    """
    xls, directory = xls.resolve(), directory.resolve()
    manifest_path = directory / 'source-build.json'
    manifest = json.loads(manifest_path.read_text())
    if manifest['version'] != 2:
        raise ValueError('unsupported source build version')
    metadata = manifest.get('metadata', {})
    if not isinstance(metadata, dict):
        raise ValueError('source build metadata must be an object')
    provenance = checked_provenance(manifest.get('provenance'))
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
    source_build_sha256 = digest(manifest_path)
    stdlib_inputs = [{'file': name, 'sha256': digest(path)}
                     for name, path in executor().tree_files(stdlib).items()]
    request = build_request(source_build_sha256, tools, stdlib_inputs, units, rtl)
    return {'version': 2, 'directory': str(directory),
            'source_build_sha256': source_build_sha256, 'metadata': metadata,
            'provenance': provenance, 'inputs': manifest['inputs'], 'xls_tools': tools,
            'stdlib': str(stdlib), 'stdlib_inputs': stdlib_inputs, 'units': units, 'rtl': rtl,
            'request': request, 'request_sha256': executor().identity(request)}


def revalidate_plan(plan: BuildPlan) -> None:
    """Re-read the complete source recipe, standard library and tools before reuse."""
    roots = {str(Path(tool['path']).parent) for tool in plan['xls_tools'].values()}
    if len(roots) != 1:
        raise ValueError('source build tools do not share one root')
    current = plan_build(Path(roots.pop()), Path(plan['directory']))
    if current['request_sha256'] != plan['request_sha256'] or current['request'] != plan['request']:
        raise ValueError('source build changed before implementation reuse')


def checked_compiled_release(release: Path, plan: BuildPlan,
                             expected_implementation: str | None = None) -> str:
    """Validate exact request, product and implementation identities in one release."""
    manifest = json.loads((release / 'compiled.json').read_text())
    required = {'version', 'source_build_sha256', 'metadata', 'provenance', 'build_request',
                'products', 'implementation', 'xls_tools', 'units', 'rtl', 'eligible',
                'native_measured'}
    if not isinstance(manifest, dict) or set(manifest) != required or manifest['version'] != 2:
        raise ValueError('invalid compiled implementation manifest')
    request = {'schema': 1, 'sha256': plan['request_sha256'], 'descriptor': plan['request']}
    if manifest['build_request'] != request or manifest['source_build_sha256'] != plan['source_build_sha256']:
        raise ValueError('compiled implementation request mismatch')
    if manifest['provenance'] != plan['provenance'] or manifest['metadata'] != plan['metadata']:
        raise ValueError('compiled implementation source metadata mismatch')
    tool_hashes = {name: tool['sha256'] for name, tool in plan['xls_tools'].items()}
    if manifest['xls_tools'] != tool_hashes:
        raise ValueError('compiled implementation tool mismatch')
    products = manifest['products']
    if not isinstance(products, dict) or set(products) != {'schema', 'files', 'sha256'} \
            or products['schema'] != 1 or not isinstance(products['files'], list):
        raise ValueError('invalid compiled product record')
    rows = products['files']
    if rows != sorted(rows, key=lambda row: row.get('file', '') if isinstance(row, dict) else ''):
        raise ValueError('noncanonical compiled product record')
    names = []
    for row in rows:
        if not isinstance(row, dict) or set(row) != {'file', 'sha256'} \
                or not sha256_identity(row['sha256']):
            raise ValueError('invalid compiled product file')
        name = relative(row['file'])
        names.append(name)
        if digest(release / name) != row['sha256']:
            raise ValueError('changed compiled product: ' + name)
    if len(names) != len(set(names)):
        raise ValueError('duplicate compiled product')
    expected_products = sorted(
        command['output'] for unit in plan['units'] for command in unit['commands']
    )
    if names != expected_products:
        raise ValueError('compiled product inventory mismatch')
    product_descriptor = {'schema': 1, 'files': rows}
    if products['sha256'] != executor().identity(product_descriptor):
        raise ValueError('compiled product identity mismatch')
    implementation = manifest['implementation']
    implementation_keys = {'schema', 'request_sha256', 'product_sha256', 'provenance', 'sha256'}
    if not isinstance(implementation, dict) or set(implementation) != implementation_keys:
        raise ValueError('invalid implementation identity record')
    realization = {key: implementation[key]
                   for key in ('schema', 'request_sha256', 'product_sha256', 'provenance')}
    actual = implementation['sha256']
    if (realization != {'schema': 1, 'request_sha256': plan['request_sha256'],
                       'product_sha256': products['sha256'], 'provenance': plan['provenance']}
            or not sha256_identity(actual) or actual != executor().identity(realization)):
        raise ValueError('implementation identity mismatch')
    if expected_implementation is not None and actual != expected_implementation:
        raise ValueError('selected implementation identity mismatch')
    rtl = manifest['rtl']
    if not isinstance(rtl, dict) or set(rtl) != set(plan['rtl']):
        raise ValueError('compiled RTL role inventory mismatch')
    for role, expected_names in plan['rtl'].items():
        role_rows = rtl[role]
        if not isinstance(role_rows, list):
            raise ValueError('invalid compiled RTL inventory')
        actual_names = []
        for row in role_rows:
            if not isinstance(row, dict) or set(row) != {'file', 'sha256'} \
                    or not sha256_identity(row['sha256']):
                raise ValueError('invalid compiled RTL file')
            name = relative(row['file'])
            actual_names.append(name)
            if digest(release / name) != row['sha256']:
                raise ValueError('changed compiled RTL: ' + name)
        if actual_names != expected_names:
            raise ValueError('compiled RTL inventory mismatch')
    return actual


def selection_path(cache: Path, request_sha256: str) -> Path:
    """Locate one request selection under the cache-owned source-build namespace."""
    return cache / 'source-build' / 'requests' / f'{request_sha256}.json'


def checked_selection(path: Path, plan: BuildPlan) -> str | None:
    """Return the selected implementation only for an exact current request record."""
    try:
        if path.is_symlink():
            raise ValueError('linked source build selection')
        value = json.loads(path.read_text())
        required = {'schema', 'request_sha256', 'request', 'implementation_sha256'}
        if (not isinstance(value, dict) or set(value) != required or value['schema'] != 1
                or value['request_sha256'] != plan['request_sha256']
                or value['request'] != plan['request']
                or not sha256_identity(value['implementation_sha256'])):
            raise ValueError('invalid source build selection')
        return value['implementation_sha256']
    except FileNotFoundError:
        return None
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError):
        quarantine(path)
        return None


def implementation_path(cache: Path, implementation_sha256: str) -> Path:
    """Locate one content-checked implementation entry by realized identity."""
    return cache / 'source-build' / 'implementations' / implementation_sha256


def checked_implementation(entry: Path, plan: BuildPlan,
                           implementation_sha256: str) -> tuple[Path, ImplementationRecord] | None:
    """Verify the store record, full release inventory and embedded identity relations."""
    try:
        if entry.is_symlink():
            raise ValueError('linked implementation store entry')
        members = {path.name: path for path in entry.iterdir()}
        if (set(members) != {'record.json', 'release'} or members['record.json'].is_symlink()
                or not members['record.json'].is_file() or members['release'].is_symlink()
                or not members['release'].is_dir()):
            raise ValueError('invalid implementation store layout')
        record = json.loads((entry / 'record.json').read_text())
        required = {'schema', 'request_sha256', 'implementation_sha256', 'release_id', 'files'}
        if (not isinstance(record, dict) or set(record) != required or record['schema'] != 1
                or record['implementation_sha256'] != implementation_sha256
                or not sha256_identity(record['release_id']) or not isinstance(record['files'], dict)
                or not record['files']):
            raise ValueError('invalid implementation store record')
        for name, value in record['files'].items():
            executor().relative(name)
            if not sha256_identity(value):
                raise ValueError('invalid implementation store file identity')
        if record['request_sha256'] != plan['request_sha256']:
            raise SelectionCrossLink('implementation belongs to another request')
        release = entry / 'release'
        if not exact_release(release, record['files']):
            raise ValueError('changed implementation store release')
        checked_compiled_release(release, plan, implementation_sha256)
        return release, record
    except FileNotFoundError:
        return None
    except SelectionCrossLink:
        return None
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError):
        quarantine(entry)
        return None


def publish_implementation(cache: Path, release: Path, plan: BuildPlan,
                           implementation_sha256: str) -> tuple[Path, ImplementationRecord]:
    """Atomically retain the first complete checked release for one implementation."""
    root = owned_directory(cache / 'source-build' / 'implementations')
    entry = implementation_path(cache, implementation_sha256)
    lock = root / f'{implementation_sha256}.lock'
    with executor().locked(lock, wait=True):
        existing = checked_implementation(entry, plan, implementation_sha256)
        if existing is not None:
            return existing
        hashes = release_hashes(release)
        if not sha256_identity(release.name):
            raise ValueError('invalid local release identity')
        record: ImplementationRecord = {
            'schema': 1,
            'request_sha256': plan['request_sha256'],
            'implementation_sha256': implementation_sha256,
            'release_id': release.name,
            'files': hashes,
        }
        pending = Path(tempfile.mkdtemp(prefix='.new-', dir=root))
        try:
            shutil.copytree(release, pending / 'release')
            if not exact_release(pending / 'release', hashes):
                raise ValueError('implementation changed during store publication')
            executor().save(pending / 'record.json', record)
            if entry.exists() or entry.is_symlink():
                quarantine(entry)
            pending.rename(entry)
        except BaseException:
            shutil.rmtree(pending, ignore_errors=True)
            raise
    checked = checked_implementation(entry, plan, implementation_sha256)
    if checked is None:
        raise ValueError('published implementation failed validation')
    return checked


def publish_selection(path: Path, plan: BuildPlan, implementation_sha256: str) -> None:
    """Atomically bind one checked request to its first realized implementation."""
    existing = checked_selection(path, plan)
    if existing is not None and existing != implementation_sha256:
        raise ValueError('source build request already selected another implementation')
    if existing is None:
        owned_directory(path.parent)
        executor().save(path, {'schema': 1, 'request_sha256': plan['request_sha256'],
                               'request': plan['request'],
                               'implementation_sha256': implementation_sha256})


def managed_output(output: Path) -> Path:
    """Normalize and validate one executor-compatible managed output path."""
    output = output.absolute()
    output = output.parent.resolve() / output.name
    releases = output.parent / f'.{output.name}-releases'
    if output.is_symlink() and output.resolve().parent != releases:
        raise ValueError('output is not a managed symlink: ' + str(output))
    if output.exists() and not output.is_symlink():
        raise ValueError('output must be absent or a managed symlink: ' + str(output))
    return output


def materialize_implementation(release: Path, record: ImplementationRecord,
                               plan: BuildPlan, output: Path) -> Path:
    """Copy a checked store hit into the output-local release set and select it atomically."""
    output = managed_output(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    report: dict[str, Any] = {'output': str(output), 'stages': {}, 'implementation_reused': True,
                              'request_sha256': plan['request_sha256'],
                              'implementation_sha256': record['implementation_sha256']}
    with executor().locked(output.parent / f'.{output.name}.lock'):
        try:
            managed_output(output)
            releases = owned_directory(output.parent / f'.{output.name}-releases')
            local = releases / record['release_id']
            if not exact_release(local, record['files']):
                pending = Path(tempfile.mkdtemp(prefix='.new-', dir=releases))
                try:
                    shutil.copytree(release, pending / 'release')
                    copied = pending / 'release'
                    if not exact_release(copied, record['files']):
                        raise ValueError('implementation changed during local materialization')
                    revalidate_plan(plan)
                    if local.exists() or local.is_symlink():
                        quarantine(local)
                    copied.rename(local)
                finally:
                    shutil.rmtree(pending, ignore_errors=True)
            else:
                revalidate_plan(plan)
            link = output.parent / f'.{output.name}.publish-{os.getpid()}-{time.time_ns()}'
            try:
                link.symlink_to(os.path.relpath(local, output.parent))
                os.replace(link, output)
            finally:
                link.unlink(missing_ok=True)
            report.update(status='complete', release=str(local))
            return local
        except BaseException as error:
            report.update(status='failed', error=str(error))
            raise
        finally:
            report['elapsed_seconds'] = time.monotonic() - started
            executor().save(output.parent / f'{output.name}.run.json', report)


def compile_build(xls: Path, directory: Path, *, output: Path | None = None,
                  cache: Path | None = None, timeout: float = 300) -> Path:
    """Compile or reuse checked stages and return one complete immutable release.

    The default managed output is SOURCE/compiled. A failed stage leaves the last
    release selected; retry reuses completed stages. Source inputs stay unchanged.
    """
    plan = plan_build(xls, directory)
    source = Path(plan['directory'])
    output = managed_output(source / 'compiled' if output is None else output)
    selected_cache = Path(cache or output.parent / '.xls-cache').absolute()
    cache_root = selected_cache.parent.resolve() / selected_cache.name
    owned_directory(cache_root)
    owned_directory(cache_root / 'source-build')
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
        product_files = []
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
                product_files.append({'file': command['output'], 'sha256': result['sha256']})
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
        products = {'schema': 1, 'files': sorted(product_files, key=lambda row: row['file'])}
        product_sha256 = executor().identity(products)
        realization = {'schema': 1, 'request_sha256': plan['request_sha256'],
                       'product_sha256': product_sha256, 'provenance': plan['provenance']}
        implementation_sha256 = executor().identity(realization)
        manifest = {'version': 2, 'source_build_sha256': plan['source_build_sha256'],
                    'metadata': plan['metadata'], 'provenance': plan['provenance'],
                    'build_request': {'schema': 1, 'sha256': plan['request_sha256'],
                                      'descriptor': plan['request']},
                    'products': products | {'sha256': product_sha256},
                    'implementation': realization | {'sha256': implementation_sha256},
                    'xls_tools': {name: tool['sha256'] for name, tool in plan['xls_tools'].items()},
                    'units': records, 'rtl': rtl, 'eligible': False, 'native_measured': False}
        return {'manifest_name': 'compiled.json', 'manifest': manifest, 'files': retained}

    selection = selection_path(cache_root, plan['request_sha256'])
    owned_directory(selection.parent)
    request_lock = selection.with_suffix('.lock')
    with compiler.locked(request_lock, wait=True):
        revalidate_plan(plan)
        implementation_sha256 = checked_selection(selection, plan)
        if implementation_sha256 is not None:
            stored = checked_implementation(
                implementation_path(cache_root, implementation_sha256),
                plan,
                implementation_sha256,
            )
            if stored is not None:
                release, record = stored
                return materialize_implementation(release, record, plan, output)
            quarantine(selection)
        release = compiler.execute(
            files,
            {name: Path(tool['path']) for name, tool in plan['xls_tools'].items()},
            output,
            prepare=prepare,
            finalize=finalize,
            name='source-build',
            directories=sorted(directories),
            timeout=timeout,
            cache=cache_root,
        )
        implementation_sha256 = checked_compiled_release(release, plan)
        publish_implementation(cache_root, release, plan, implementation_sha256)
        publish_selection(selection, plan, implementation_sha256)
        return release


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
