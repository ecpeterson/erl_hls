#!/usr/bin/env python3
"""Optionally compile an emitted source-build.json using an independently supplied XLS bundle.

Only Python's standard library and the emitted directory are needed. The manifest
is a trusted local build record; no Erlang checkout, rebar, or Python bootstrap is used.
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess


def digest(path: Path) -> str:
    """Identify exact external inputs and products."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compile_build(xls: Path, directory: Path) -> None:
    """Verify frozen source inputs, run each unit once, and retain logs and provenance.

    Failures preserve partial output; existing compilation products are rejected.
    Each XLS stage has a 300-second deadline. Emission does not grant admission.
    """
    xls, directory = xls.resolve(), directory.resolve()
    manifest_path = directory / 'source-build.json'
    manifest = json.loads(manifest_path.read_text())
    if manifest['version'] != 1:
        raise ValueError('unsupported source build version')
    for row in manifest['inputs']:
        if digest(directory / row['file']) != row['sha256']:
            raise ValueError('changed source build input: ' + row['file'])
    # Reject retries before executing even the first external stage.
    for unit in manifest['units']:
        stage = directory / unit['directory']
        for path in [directory / unit['output'], stage / 'raw.ir', stage / 'optimized.ir',
                     stage / 'commands.json', *(stage / (n + '.log') for n in ('convert', 'opt', 'codegen'))]:
            if path.exists():
                raise FileExistsError(path)
    for role in manifest['rtl']:
        if (directory / role / 'files.f').exists():
            raise FileExistsError(directory / role / 'files.f')
    tool_hashes = {name: digest(xls / name) for name in ('ir_converter_main', 'opt_main', 'codegen_main')}
    records = []
    for unit in manifest['units']:
        stage = directory / unit['directory']
        commands = [
            ('convert', [xls / 'ir_converter_main', '--warnings_as_errors=false', '--top=' + unit['top'],
                         '--dslx_path=' + ':'.join(str(directory / p) for p in unit['dslx_path']),
                         '--dslx_stdlib_path=' + str(xls / 'xls/dslx/stdlib'), directory / unit['source']], stage / 'raw.ir'),
            ('opt', [xls / 'opt_main', stage / 'raw.ir'], stage / 'optimized.ir'),
            ('codegen', [xls / 'codegen_main', *unit['codegen_flags'], '--module_name=' + unit['module'],
                         stage / 'optimized.ir'], directory / unit['output']),
        ]
        stages = []
        for label, command, output in commands:
            command = list(map(str, command))
            with (stage / (label + '.log')).open('x') as log, output.open('x') as target:
                try:
                    result = subprocess.run(command, stdout=target, stderr=log, timeout=300)
                    record = {'stage': label, 'command': command, 'exit': result.returncode}
                except subprocess.TimeoutExpired:
                    record = {'stage': label, 'command': command, 'exit': None, 'timeout_seconds': 300}
            record.update(output=str(output), sha256=digest(output))
            stages.append(record)
            (stage / 'commands.json').write_text(json.dumps(stages, indent=2) + '\n')
            if record['exit'] != 0:
                raise RuntimeError(f"{unit['directory']}/{label} failed: " + (stage / (label + '.log')).read_text()[-4000:])
        records.append({'directory': unit['directory'], 'commands': stages})
    rtl = {}
    for role, files in manifest['rtl'].items():
        paths = [directory / path for path in files]
        with (directory / role / 'files.f').open('x') as listing:
            listing.write(''.join(str(path) + '\n' for path in paths))
        rtl[role] = [{'file': str(path), 'sha256': digest(path)} for path in paths]
    (directory / 'compiled.json').write_text(json.dumps({
        'source_build_sha256': digest(manifest_path), 'xls_tools': tool_hashes,
        'units': records, 'rtl': rtl, 'eligible': False, 'native_measured': False,
    }, indent=2) + '\n')


def main() -> None:
    """Compile a source bundle without consulting the source repository or Erlang environment."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=Path)
    parser.add_argument('directory', type=Path)
    args = parser.parse_args()
    compile_build(args.xls, args.directory)


if __name__ == '__main__':
    main()
