#!/usr/bin/env python3
"""Inspect or compile an emitted source-build.json with an independently supplied XLS bundle.

Only Python's standard library and the emitted directory are needed. The manifest
is a trusted local build record; no Erlang checkout, rebar, or Python bootstrap is used.
"""
from pathlib import Path
from typing import TypedDict
import argparse
import hashlib
import json
import os
import subprocess


class FileIdentity(TypedDict):
    """One exact input or product, identified independently of modification time."""
    file: str
    sha256: str


class ToolIdentity(TypedDict):
    """An executable's resolved filename and contents."""
    path: str
    sha256: str


class Command(TypedDict):
    """A direct argument vector and the paths used for its output and diagnostics."""
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
    """A checked, read-only preview consumed unchanged by the executor."""
    version: int
    directory: str
    source_build_sha256: str
    inputs: list[FileIdentity]
    xls_tools: dict[str, ToolIdentity]
    stdlib: str
    stdlib_inputs: list[FileIdentity]
    units: list[UnitPlan]
    rtl: dict[str, list[str]]


def digest(path: Path) -> str:
    """Identify exact external inputs and products."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def plan_build(xls: Path, directory: Path) -> BuildPlan:
    """Verify source/tool inputs and resolve exact commands without writing or executing.

    Existing products are allowed so a completed bundle remains inspectable.
    Schedules are the emitter's literal flags; this function does not choose them.
    """
    xls, directory = xls.resolve(), directory.resolve()
    manifest_path = directory / 'source-build.json'
    manifest = json.loads(manifest_path.read_text())
    if manifest['version'] != 1:
        raise ValueError('unsupported source build version')
    for row in manifest['inputs']:
        if digest(directory / row['file']) != row['sha256']:
            raise ValueError('changed source build input: ' + row['file'])
    tools = {}
    for name in ('ir_converter_main', 'opt_main', 'codegen_main'):
        path = (xls / name).resolve()
        if not path.is_file() or not os.access(path, os.X_OK):
            raise ValueError('missing or non-executable XLS tool: ' + str(path))
        tools[name] = {'path': str(path), 'sha256': digest(path)}
    stdlib = (xls / 'xls/dslx/stdlib').resolve()
    if not stdlib.is_dir():
        raise ValueError('missing XLS standard library: ' + str(stdlib))
    units = []
    for unit in manifest['units']:
        stage = directory / unit['directory']
        source = directory / unit['source']
        imports = [str(directory / path) for path in unit['dslx_path']]
        if not source.is_file():
            raise ValueError('missing unit source: ' + str(source))
        for path in [stage, *(Path(path) for path in imports)]:
            if not path.is_dir():
                raise ValueError('missing unit directory: ' + str(path))
        commands = [
            ('convert', [tools['ir_converter_main']['path'], '--warnings_as_errors=false', '--top=' + unit['top'],
                         '--dslx_path=' + ':'.join(imports), '--dslx_stdlib_path=' + str(stdlib), str(source)], stage / 'raw.ir'),
            ('opt', [tools['opt_main']['path'], str(stage / 'raw.ir')], stage / 'optimized.ir'),
            ('codegen', [tools['codegen_main']['path'], *unit['codegen_flags'], '--module_name=' + unit['module'],
                         str(stage / 'optimized.ir')], directory / unit['output']),
        ]
        units.append({'directory': unit['directory'], 'role': unit['role'], 'source': str(source),
                      'top': unit['top'], 'module': unit['module'], 'codegen_flags': unit['codegen_flags'],
                      'dslx_path': imports, 'commands': [
                          {'stage': label, 'command': command, 'output': str(output), 'log': str(stage / (label + '.log'))}
                          for label, command, output in commands]})
    return {'version': 1, 'directory': str(directory), 'source_build_sha256': digest(manifest_path),
            'inputs': manifest['inputs'], 'xls_tools': tools, 'stdlib': str(stdlib),
            'stdlib_inputs': [{'file': str(path.relative_to(stdlib)), 'sha256': digest(path)}
                              for path in sorted(stdlib.rglob('*.x'))],
            'units': units, 'rtl': {role: [str(directory / path) for path in files]
                                  for role, files in manifest['rtl'].items()}}


def compile_build(xls: Path, directory: Path) -> None:
    """Execute the same checked commands exposed by plan_build and retain provenance.

    Failures preserve partial output; existing compilation products are rejected.
    Each XLS stage has a 300-second deadline. Emission does not grant admission.
    """
    plan = plan_build(xls, directory)
    directory = Path(plan['directory'])
    # Reject retries before executing even the first external stage.
    for unit in plan['units']:
        paths = [Path(command[key]) for command in unit['commands'] for key in ('output', 'log')]
        paths.append(directory / unit['directory'] / 'commands.json')
        for path in paths:
            if path.exists():
                raise FileExistsError(path)
    for role in plan['rtl']:
        if (directory / role / 'files.f').exists():
            raise FileExistsError(directory / role / 'files.f')
    records = []
    for unit in plan['units']:
        stages = []
        for command in unit['commands']:
            output, log_path = Path(command['output']), Path(command['log'])
            with log_path.open('x') as log, output.open('x') as target:
                try:
                    result = subprocess.run(command['command'], stdout=target, stderr=log, timeout=300)
                    record = {'stage': command['stage'], 'command': command['command'], 'exit': result.returncode}
                except subprocess.TimeoutExpired:
                    record = {'stage': command['stage'], 'command': command['command'], 'exit': None, 'timeout_seconds': 300}
            record.update(output=str(output), sha256=digest(output))
            stages.append(record)
            (directory / unit['directory'] / 'commands.json').write_text(json.dumps(stages, indent=2) + '\n')
            if record['exit'] != 0:
                raise RuntimeError(f"{unit['directory']}/{command['stage']} failed: " + log_path.read_text()[-4000:])
        records.append({'directory': unit['directory'], 'commands': stages})
    rtl = {}
    for role, paths in plan['rtl'].items():
        with (directory / role / 'files.f').open('x') as listing:
            listing.write(''.join(path + '\n' for path in paths))
        rtl[role] = [{'file': path, 'sha256': digest(Path(path))} for path in paths]
    (directory / 'compiled.json').write_text(json.dumps({
        'source_build_sha256': plan['source_build_sha256'],
        'xls_tools': {name: tool['sha256'] for name, tool in plan['xls_tools'].items()},
        'units': records, 'rtl': rtl, 'eligible': False, 'native_measured': False,
    }, indent=2) + '\n')


def main() -> None:
    """Compile a source bundle or print its checked commands as JSON without executing them."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run', action='store_true', help='verify inputs and print JSON commands without writing or running tools')
    parser.add_argument('xls', type=Path)
    parser.add_argument('directory', type=Path)
    args = parser.parse_args()
    if args.dry_run:
        print(json.dumps(plan_build(args.xls, args.directory), indent=2))
    else:
        compile_build(args.xls, args.directory)


if __name__ == '__main__':
    main()
