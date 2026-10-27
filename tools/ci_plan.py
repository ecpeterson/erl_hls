#!/usr/bin/env python3
"""Select affected CI groups and identify identical, previously qualified inputs."""
import hashlib
import json
import os
from pathlib import Path
import subprocess

from regression_inventory import Inventory, changed_paths, documentation, load_inventory, select_cases


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


def plan(paths: list[str] | None, config: Inventory, manual: bool = False) -> dict:
    """Select shared feature cases and retain broad base checks for every executable change."""
    cases = select_cases(paths, config, full=manual)
    selected = {group: any(config['cases'][name]['group'] == group for name in cases)
                for group in config['groups']}
    # Local-only witnesses can change alongside ordinary EUnit fixtures.
    # The base test job still runs even when it has no selected XLS features.
    selected['test'] = selected['test'] or paths is None or manual or any(
        not documentation(path) for path in paths)
    return {**selected, 'qualify': any(selected.values()),
            **{f'{group}_cases': [name for name in cases if config['cases'][name]['group'] == group]
               for group in config['groups']}}


def main() -> None:
    """Emit Actions decisions and a content key for successful-suite reuse."""
    root = Path.cwd()
    manual = os.environ.get('GITHUB_EVENT_NAME') == 'workflow_dispatch'
    extended = manual and os.environ.get('CI_EXTENDED') == 'true'
    config = load_inventory(root)
    paths = changed_paths(os.environ.get('CI_BASE', ''), root)
    selected = plan(paths, config, manual)
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
