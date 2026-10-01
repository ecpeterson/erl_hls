#!/usr/bin/env python3
"""Exercise selection and qualification invalidation against real Git histories."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from ci_plan import changed_paths, main, plan, source_fingerprint

CONFIG = json.loads((Path(__file__).with_name('ci_groups.json')).read_text())


class SelectionTests(unittest.TestCase):
    """Only passive documentation or previously qualified content can omit tests."""

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
            self.assertIn('Affected groups:', (root/'summary').read_text())


if __name__ == '__main__':
    unittest.main()
