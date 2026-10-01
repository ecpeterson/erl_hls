#!/usr/bin/env python3
"""Select affected CI groups and identify identical, previously qualified inputs."""
import fnmatch
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import subprocess


def documentation(path: str) -> bool:
    """Recognize prose and rendered assets, never executable examples or data fixtures."""
    file = PurePosixPath(path)
    return file.suffix == '.md' or (
        file.suffix in {'.png', '.svg', '.pdf', '.jpg', '.jpeg'}
        and (path.startswith(('docs/', 'yap/')) or '/results/' in path)
    )


def changed_paths(base: str, root: Path) -> list[str] | None:
    """Read both sides of renames; missing history requires all checks."""
    if not base or set(base) == {'0'}:
        return None
    try:
        result = subprocess.run(
            ['git', 'diff', '--name-only', '--no-renames', '-z', base, 'HEAD', '--'],
            cwd=root, check=True, capture_output=True,
        )
    except subprocess.CalledProcessError:
        return None
    return [os.fsdecode(path) for path in result.stdout.split(b'\0') if path]


def source_fingerprint(root: Path, suite: str, extended: bool) -> str:
    """Hash the complete checked-out Git inputs; exclude only ordinary prose/assets."""
    tree = subprocess.check_output(['git', 'ls-tree', '-rz', '--full-tree', 'HEAD'], cwd=root)
    digest = hashlib.sha256(f'ci-v1:{suite}:{extended}\0'.encode())
    for entry in tree.split(b'\0'):
        if not entry:
            continue
        metadata, path = entry.split(b'\t', 1)
        mode = metadata.split(b' ', 1)[0]
        # Executable prose, symlinks and submodules remain qualification inputs.
        if mode == b'100644' and documentation(os.fsdecode(path)):
            continue
        digest.update(entry + b'\0')
    return digest.hexdigest()


def plan(paths: list[str] | None, config: dict, manual: bool = False,
         extended: bool = False) -> dict:
    """Select the union of matching rules; unknown paths fail closed."""
    groups = set(config['groups']) if manual or paths is None else set()
    for path in paths or []:
        if documentation(path):
            continue
        for rule in config['rules']:
            if any(fnmatch.fnmatchcase(path, pattern) for pattern in rule['paths']):
                groups.update(rule['groups'])
                break
        else:
            groups.update(config['groups'])
    selected = {group: group in groups for group in config['groups']}
    outputs = config.get('extended_outputs' if extended else 'outputs', {})
    return {**selected, 'qualify': bool(groups), **outputs}


def main() -> None:
    """Emit Actions decisions and a content key for successful-suite reuse."""
    root = Path.cwd()
    manual = os.environ.get('GITHUB_EVENT_NAME') == 'workflow_dispatch'
    extended = manual and os.environ.get('CI_EXTENDED') == 'true'
    config = json.loads((root/'tools/ci_groups.json').read_text())
    paths = changed_paths(os.environ.get('CI_BASE', ''), root)
    # Do not skip changed executable Markdown or documentation symlinks.
    if paths is not None:
        for path in paths:
            if documentation(path):
                for revision in ('HEAD', os.environ.get('CI_BASE', '')):
                    if not revision:
                        continue
                    entry = subprocess.check_output(['git', 'ls-tree', revision, '--', path], cwd=root)
                    if entry and not entry.startswith(b'100644 '):
                        paths = None
                        break
                if paths is None:
                    break
    selected = plan(paths, config, manual, extended)
    suite_groups = os.environ.get('CI_GROUPS', ','.join(config['groups'])).split(',')
    selected['qualify'] = any(selected[group] for group in suite_groups)
    selected['reusable'] = paths is not None and not manual
    selected['key'] = source_fingerprint(root, os.environ.get('CI_SUITE', 'ci'), extended)
    print(json.dumps(selected, indent=2))
    with Path(os.environ['GITHUB_OUTPUT']).open('a') as output:
        for name, value in selected.items():
            encoded = value if isinstance(value, str) and name == 'key' else json.dumps(value, separators=(',', ':'))
            output.write(f'{name}={encoded}\n')
    with Path(os.environ['GITHUB_STEP_SUMMARY']).open('a') as summary:
        groups = ', '.join(group for group in config['groups'] if selected[group]) or 'none (documentation only)'
        summary.write(f'Affected groups: {groups}.\n\nInput fingerprint: `{selected["key"]}`.\n')


if __name__ == '__main__':
    main()
