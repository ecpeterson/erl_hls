#!/usr/bin/env python3
"""Exercise selection and qualification invalidation against real Git histories."""
import copy
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from ci_plan import changed_paths, main, plan, source_fingerprint

from regression_inventory import load_inventory, paths_since, select_cases

CONFIG = load_inventory()


class SelectionTests(unittest.TestCase):
    """Exact fixture consumers narrow features; unknown inputs retain complete coverage."""

    def test_documentation_and_unknown_changes(self) -> None:
        """Documents skip; sources, fixtures, workflows and unknown files trigger checks."""
        for paths in ([], ['README.md', 'docs/p.png', 'experiments/probe/results/p.svg']):
            self.assertFalse(plan(paths, CONFIG)['qualify'])
        for path in ('src/actor.erl', 'priv/xls/a.x', 'rtl/a.sv', 'docs/example.py',
                     'rebar.lock', '.github/workflows/ci.yml', 'new-file', 'test/fixture.json'):
            with self.subTest(path=path):
                self.assertTrue(plan([path], CONFIG)['qualify'])
        self.assertTrue(all(plan(None, CONFIG)[g] for g in CONFIG['groups']))
        self.assertTrue(all(plan([], CONFIG, manual=True)[g] for g in CONFIG['groups']))

    def test_exact_fixture_selection_is_shared(self) -> None:
        """Local and CI views use the same exact dependencies, including shared testbenches."""
        paths = ['test/rtl/logical_service_tb.sv']
        expected = ['comparisons', 'logical_types', 'serial']
        self.assertEqual(select_cases(paths, CONFIG), expected)
        selected = plan(paths, CONFIG)
        self.assertEqual(selected['test_cases'], expected)
        self.assertTrue(selected['test'])
        self.assertFalse(selected['topology'])
        self.assertEqual(select_cases(paths + ['test/xls_binary_dslx.erl'], CONFIG),
                         ['binary', *expected])
        self.assertEqual(select_cases(['test_data/hls_reduction_failure_semantics.inc.x'], CONFIG),
                         ['reduction_dslx'])

    def test_full_fallback_and_group_filters(self) -> None:
        """Core, tools, unknown fixtures and missing history cannot reduce feature coverage."""
        all_cases = sorted(CONFIG['cases'])
        for paths in (None, ['src/xls_actor.erl'], ['priv/xls/axis.x'],
                      ['tools/test_binary.sh'], ['test/unlisted_fixture.erl'],
                      ['test/xls_binary_dslx.erl', 'test/new_fixture.erl']):
            with self.subTest(paths=paths):
                self.assertEqual(select_cases(paths, CONFIG), all_cases)
                selected = plan(paths, CONFIG)
                self.assertTrue(all(selected[group] for group in CONFIG['groups']))
                for group in CONFIG['groups']:
                    self.assertEqual(selected[f'{group}_cases'],
                                     select_cases(paths, CONFIG, groups=[group]))
        self.assertEqual(select_cases([], CONFIG, full=True), all_cases)
        self.assertEqual(select_cases(['README.md'], CONFIG), [])
        with self.assertRaises(ValueError):
            select_cases([], CONFIG, groups=['missing'])

    def test_topology_and_local_only_keep_base_checks(self) -> None:
        """Specialized feature selection never drops ordinary EUnit and toolchain checks."""
        topology = ['test/hls_mixed_topology_dslx.erl']
        self.assertEqual(select_cases(topology, CONFIG), ['mixed_topology'])
        selected = plan(topology, CONFIG)
        self.assertTrue(selected['test'])
        self.assertTrue(selected['topology'])
        self.assertEqual(selected['test_cases'], [])
        self.assertEqual(selected['topology_cases'], ['mixed_topology'])
        local_only = ['test/xls_phase_values_dslx.erl']
        self.assertEqual(select_cases(local_only, CONFIG), ['phase_values'])
        selected = plan(local_only, CONFIG)
        self.assertTrue(selected['test'])
        self.assertFalse(selected['topology'])
        self.assertEqual(selected['test_cases'], [])
        self.assertEqual(selected['topology_cases'], [])

    def test_inventory_rejects_unsafe_narrowing(self) -> None:
        """Only exact fixture edges are eligible; broad selectors cannot hide shared changes."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'tools').mkdir()
            metadata = root / 'tools/regression_inventory.json'
            for dependency in ('src/xls_actor.erl', 'tools/test_binary.sh', 'test/*.erl',
                               'test/../src/xls_actor.erl', '/test/a.erl', 'test/README.md'):
                with self.subTest(dependency=dependency):
                    invalid = copy.deepcopy(CONFIG)
                    invalid['cases']['binary']['dependencies'] = [dependency]
                    metadata.write_text(json.dumps(invalid))
                    with self.assertRaises(ValueError):
                        load_inventory(root)
            for value in ([], {'version': 1}, {**CONFIG, 'version': True},
                          {**CONFIG, 'groups': [['test']]}):
                with self.subTest(value=value):
                    metadata.write_text(json.dumps(value))
                    with self.assertRaises(ValueError):
                        load_inventory(root)

    def test_local_changes_include_index_worktree_and_untracked(self) -> None:
        """Local selection covers edits not committed to HEAD and preserves both rename sides."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)

            def git(*args: str) -> str:
                """Use a private repository with deterministic author and file-mode handling."""
                return subprocess.check_output([
                    'git', '-c', 'user.name=CI test', '-c', 'user.email=ci@example.invalid',
                    '-c', 'commit.gpgsign=false', *args], cwd=root, text=True).strip()

            git('init', '-q')
            git('config', 'core.filemode', 'true')
            (root / 'test').mkdir()
            binary = root / 'test/xls_binary_dslx.erl'
            helper = root / 'test/xls_helpers_dslx.erl'
            binary.write_text('binary fixture\n')
            helper.write_text('helper fixture\n')
            git('add', '-A')
            git('commit', '-qm', 'base')
            base = git('rev-parse', 'HEAD')
            binary.write_text('staged binary change\n')
            git('add', 'test/xls_binary_dslx.erl')
            helper.write_text('working helper change\n')
            paths = paths_since(base, root)
            self.assertEqual(select_cases(paths, CONFIG), ['binary', 'helpers'])
            self.assertEqual(changed_paths(base, root), [])
            (root / 'README.md').write_text('passive note\n')
            self.assertEqual(select_cases(paths_since(base, root), CONFIG), ['binary', 'helpers'])
            (root / 'test/new_fixture.erl').write_text('unknown dependency\n')
            self.assertEqual(select_cases(paths_since(base, root), CONFIG), sorted(CONFIG['cases']))
            (root / 'test/new_fixture.erl').unlink()
            binary.rename(root / 'test/binary_renamed.erl')
            paths = paths_since(base, root)
            self.assertIn('test/xls_binary_dslx.erl', paths)
            self.assertIn('test/binary_renamed.erl', paths)
            self.assertEqual(select_cases(paths, CONFIG), sorted(CONFIG['cases']))
            for missing in ('', '0' * 40, 'unavailable'):
                self.assertIsNone(paths_since(missing, root))
            (root / 'README.md').chmod(0o755)
            self.assertIsNone(paths_since(base, root))
            (root / 'README.md').unlink()
            (root / 'README.md').symlink_to('test/xls_helpers_dslx.erl')
            self.assertIsNone(paths_since(base, root))

    def test_real_git_history(self) -> None:
        """Content keys survive prose-only updates, but change for every tested input."""
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)

            def git(*args: str) -> str:
                """Commit fixtures independently of user Git identity and signing settings."""
                return subprocess.check_output(['git','-c','user.name=CI test',
                    '-c','user.email=ci@example.invalid','-c','commit.gpgsign=false',*args],
                    cwd=root,text=True).strip()

            def commit(path: str, content: str) -> str:
                """Write an input and record its tracked content."""
                file=root/path
                file.parent.mkdir(parents=True,exist_ok=True)
                file.write_text(content)
                git('add','-A');git('commit','-qm','fixture')
                return git('rev-parse','HEAD')

            git('init','-q')
            base=commit('actor.erl','one\n')
            key=source_fingerprint(root,'ci',False)
            commit('README.md','report\n')
            self.assertEqual(key,source_fingerprint(root,'ci',False))
            self.assertFalse(plan(changed_paths(base,root),CONFIG)['qualify'])
            for path in ('actor.erl','rebar.lock','.github/workflows/ci.yml','test/data.json'):
                previous=source_fingerprint(root,'ci',False)
                commit(path,'new input\n')
                self.assertNotEqual(previous,source_fingerprint(root,'ci',False))
            key=source_fingerprint(root,'ci',False)
            self.assertNotEqual(key,source_fingerprint(root,'backend',False))
            self.assertNotEqual(key,source_fingerprint(root,'ci',True))
            commit('README.md','rewritten prose\n')
            self.assertEqual(key,source_fingerprint(root,'ci',False))
            (root/'README.md').chmod(0o755)
            git('add','-A');git('commit','-qm','executable documentation')
            self.assertNotEqual(key,source_fingerprint(root,'ci',False))
            base=git('rev-parse','HEAD')
            (root/'actor.erl').rename(root/'actor.md')
            for index in range(305):
                (root/f'note {index}\n.md').write_text('prose\n')
            git('add','-A');git('commit','-qm','rename')
            paths=changed_paths(base,root)
            self.assertEqual(len(paths),307)
            self.assertTrue({'actor.erl','actor.md'}.issubset(paths))
            self.assertTrue(plan(paths,CONFIG)['qualify'])
            for missing in ('','0'*40,'unavailable'):
                self.assertIsNone(changed_paths(missing,root))

    def test_actions_outputs(self) -> None:
        """Decisions use native JSON booleans; the cache key contains no path text."""
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            env={'GITHUB_OUTPUT':str(root/'output'),'GITHUB_STEP_SUMMARY':str(root/'summary'),
                 'GITHUB_EVENT_NAME':'workflow_dispatch','CI_EXTENDED':'true'}
            with patch.dict(os.environ,env,clear=True), patch('ci_plan.Path.cwd',return_value=Path(__file__).resolve().parents[1]):
                main()
            actual=dict(line.split('=',1) for line in (root/'output').read_text().splitlines())
            self.assertIs(json.loads(actual['qualify']),True)
            self.assertEqual(len(actual['key']),64)
            for group in CONFIG['groups']:
                self.assertEqual(json.loads(actual[f'{group}_cases']),
                                 select_cases(None, CONFIG, groups=[group]))
            self.assertIn('Affected groups:', (root/'summary').read_text())


if __name__ == '__main__':
    unittest.main()
