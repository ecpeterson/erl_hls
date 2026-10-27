"""Shared local/CI case inventory; only enumerated fixture consumers may narrow coverage."""
from __future__ import annotations

import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
from typing import TypedDict


class Case(TypedDict):
    """One runnable feature, optional CI job and exhaustively known local fixture edges."""

    group: str | None
    default_stage: str
    dependencies: list[str]


class Inventory(TypedDict):
    """Named regression metadata shared by the command runner and change planner."""

    version: int
    groups: list[str]
    cases: dict[str, Case]


def load_inventory(root: Path | None = None) -> Inventory:
    """Load checked case metadata; core, tools and unlisted fixture paths always remain broad."""
    root = root or Path(__file__).resolve().parents[1]
    inventory = json.loads((root / 'tools/regression_inventory.json').read_text())
    if (not isinstance(inventory, dict) or set(inventory) != {'version', 'groups', 'cases'}
            or type(inventory['version']) is not int or inventory['version'] != 1):
        raise ValueError('invalid regression inventory version or fields')
    groups = inventory['groups']
    if (not isinstance(groups, list) or not groups
            or any(not isinstance(group, str) or not group.isidentifier() for group in groups)
            or len(set(groups)) != len(groups)):
        raise ValueError('invalid regression groups')
    if not isinstance(inventory['cases'], dict) or not inventory['cases']:
        raise ValueError('empty or invalid regression cases')
    for name, case in inventory['cases'].items():
        if (not re.fullmatch(r'[a-z][a-z0-9_]*', name) or not isinstance(case, dict)
                or set(case) != {'group', 'default_stage', 'dependencies'}):
            raise ValueError(f'invalid regression case: {name}')
        if case['group'] is not None and case['group'] not in groups:
            raise ValueError(f'unknown regression group: {name}')
        if not isinstance(case['default_stage'], str):
            raise ValueError(f'invalid regression stage: {name}')
        stage = PurePosixPath(case['default_stage'])
        if (stage.is_absolute() or '..' in stage.parts or str(stage) != case['default_stage']
                or stage.parts[:1] != ('_build',) or len(stage.parts) < 2):
            raise ValueError(f'invalid regression stage: {name}')
        dependencies = case['dependencies']
        if (not isinstance(dependencies, list) or any(not isinstance(path, str) for path in dependencies)
                or len(set(dependencies)) != len(dependencies)):
            raise ValueError(f'invalid regression dependencies: {name}')
        for path in dependencies:
            file = PurePosixPath(path)
            if (file.is_absolute() or '..' in file.parts or str(file) != path
                    or file.parts[:1] not in [('test',), ('test_data',)]
                    or any(character in path for character in '*?[]') or documentation(path)):
                raise ValueError(f'only exact fixture paths may narrow regressions: {path}')
    return inventory


def documentation(path: str) -> bool:
    """Recognize passive prose/assets; executable Markdown and symlinks are checked in Git."""
    file = PurePosixPath(path)
    return file.suffix == '.md' or (
        file.suffix in {'.png', '.svg', '.pdf', '.jpg', '.jpeg'}
        and (path.startswith(('docs/', 'yap/')) or '/results/' in path)
    )


def select_cases(paths: list[str] | None, inventory: Inventory, *,
                 groups: list[str] | None = None, full: bool = False) -> list[str]:
    """Union exact fixture consumers; shared or unknown changes and missing history select all.

    Dependencies are safe narrowing edges, not a complete build graph. An
    unlisted dependency deliberately selects every case. A group of None in
    the inventory marks an explicit local-only case; an omitted groups filter
    includes those cases as well as routine CI coverage.
    """
    cases = inventory['cases']
    if groups is not None and set(groups) - set(inventory['groups']):
        raise ValueError(f'unknown regression groups: {groups}')
    selected = set(cases) if full or paths is None else set()
    for path in paths or []:
        if documentation(path):
            continue
        matches = {name for name, case in cases.items() if path in case['dependencies']}
        selected.update(matches or cases)
    return sorted(name for name in selected if groups is None or cases[name]['group'] in groups)


def changed_paths(base: str, root: Path) -> list[str] | None:
    """Read committed rename sides and documentation modes; absent history selects all."""
    if not base or set(base) == {'0'}:
        return None
    try:
        result = subprocess.run(
            ['git', 'diff', '--name-only', '--no-renames', '-z', base, 'HEAD', '--'],
            cwd=root, check=True, capture_output=True,
        )
        paths = [os.fsdecode(path) for path in result.stdout.split(b'\0') if path]
        for path in paths:
            if documentation(path):
                for revision in (base, 'HEAD'):
                    entry = subprocess.check_output(['git', 'ls-tree', revision, '--', path], cwd=root)
                    if entry and not entry.startswith(b'100644 '):
                        return None
        return paths
    except subprocess.CalledProcessError:
        return None


def paths_since(base: str, root: Path) -> list[str] | None:
    """Include local index/worktree and untracked inputs so an uncommitted edit cannot skip tests."""
    committed = changed_paths(base, root)
    if committed is None:
        return None
    try:
        working = subprocess.check_output(
            ['git', 'diff', '--name-only', '--no-renames', '-z', 'HEAD', '--'], cwd=root)
        untracked = subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard', '-z'], cwd=root)
        paths = sorted(set(committed) | {os.fsdecode(path) for path in (working + untracked).split(b'\0') if path})
        for path in paths:
            file = root / path
            if documentation(path):
                entry = subprocess.check_output(['git', 'ls-tree', 'HEAD', '--', path], cwd=root)
                if ((entry and not entry.startswith(b'100644 ')) or file.is_symlink()
                        or (file.is_file() and file.stat().st_mode & 0o111)):
                    return None
        return paths
    except subprocess.CalledProcessError:
        return None
