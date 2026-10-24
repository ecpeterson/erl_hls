"""Exercise profile isolation and helper imports without XLS or hardware builds."""
import ast
import json
import os
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from backend_commands import run, execute
from backend_paths import ROOT, erlang_paths, erlang_environment


class BuildContextTests(unittest.TestCase):
    """Reject implicit profile fallback and preserve subprocess failure semantics."""

    def test_helpers_import_without_compiler_or_global_changes(self) -> None:
        """Hash/report helpers work without locating a compiler or mutating paths/environment."""
        script = '''import os, sys
before_env, before_paths = dict(os.environ), list(sys.path)
import backend_paths, backend_commands, phi_message_trace, phi_transport_metrics
assert dict(os.environ) == before_env
assert sys.path == before_paths
assert not any(n.startswith('test_') for n in sys.modules)
assert 'compiler_paths' not in sys.modules
'''
        subprocess.run([sys.executable, '-c', script], cwd=ROOT/'tools', check=True,
                       env={**os.environ, 'ERL_HLS_ROOT': '/nonexistent-compiler', 'ERL_AFLAGS': 'sentinel'}, timeout=10)

    def test_missing_profile_does_not_fall_back(self) -> None:
        """An existing test build cannot satisfy a request for default, nor vice versa."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root/'_build/test/lib/hls_fabric/ebin').mkdir(parents=True)
            with self.assertRaisesRegex(FileNotFoundError, 'rebar3 compile'):
                erlang_paths('default', root)
            with self.assertRaisesRegex(ValueError, 'invalid rebar profile'):
                erlang_paths('../test', root)

    def test_vm_loads_the_requested_profile_and_checkout(self) -> None:
        """Real VMs choose distinguishable beams even with an inherited stale test path."""
        with tempfile.TemporaryDirectory(prefix='build context ') as temporary:
            root = Path(temporary).resolve()/'space "quote" \\path'
            root.mkdir()
            scripts = root/'tools'
            scripts.mkdir()
            for name in ('backend_env.sh', 'backend_paths.py', 'compiler_paths.py'):
                shutil.copyfile(ROOT/'tools'/name, scripts/name)
            compiler = root/'_checkouts/erl_hls/tools'
            compiler.mkdir(parents=True)
            (compiler/'compile_xls.py').write_text('# source discovery fixture\n')
            script = root/'probe.escript'
            script.write_text('#!/usr/bin/env escript\nmain(_) -> io:format("~p", [{context_probe:value(), compiler_probe:value(), code:which(fixture_probe)}]).\n')
            for profile in ('test', 'default'):
                for app, module, value in (
                    ('lib/hls_fabric/ebin', 'context_probe', profile),
                    ('lib/erl_hls/ebin', 'compiler_probe', 'stale'),
                    ('checkouts/erl_hls/ebin', 'compiler_probe', 'checkout'),
                    ('lib/hls_fabric/test', 'fixture_probe', 'fixture'),
                ):
                    directory = root/'_build'/profile/app
                    directory.mkdir(parents=True, exist_ok=True)
                    source = root/(module+'.erl')
                    source.write_text(f'-module({module}).\n-export([value/0]).\nvalue() -> {value}.\n')
                    subprocess.run(['erlc', '-o', directory, source], check=True, capture_output=True, timeout=15)
            stale = erlang_environment('test', root)['ERL_AFLAGS']
            with patch.dict(os.environ, {'ERL_AFLAGS': stale}):
                for profile in ('default', 'test'):
                    env = erlang_environment(profile, root)
                    self.assertEqual(os.environ['ERL_AFLAGS'], stale)
                    result = subprocess.check_output(['escript', script], env=env, text=True, timeout=15)
                    shell_env = {k: v for k, v in os.environ.items() if k != 'ERL_HLS_ROOT'}
                    shell_result = subprocess.check_output(
                        ['bash', '-c', 'source "$1" "$2" && escript "$3"', 'context',
                         scripts/'backend_env.sh', profile, script], env=shell_env, text=True, timeout=15)
                    self.assertEqual(shell_result, result)
                    self.assertTrue(result.startswith('{'+profile+',checkout,'), result)
                    if profile == 'default':
                        self.assertIn('non_existing', result)
                        self.assertNotIn('_build/test/', env['ERL_AFLAGS'])
                    else:
                        self.assertIn('fixture_probe.beam', result)

    def test_production_emitter_uses_its_fresh_default_build(self) -> None:
        """The repetition emitter passes its selected profile to its actual escript callsite."""
        import emit_protocol_repetition as emitter
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)/'application'
            with patch.object(emitter, 'run') as invoke, patch.object(
                    emitter, 'erlang_environment', return_value={'ERL_AFLAGS': 'chosen-default'}) as select:
                emitter.emit_application(2, directory)
            self.assertEqual(invoke.call_args_list[0].args[0], ['rebar3', 'compile'])
            select.assert_called_once_with('default')
            call = invoke.call_args_list[1]
            self.assertEqual(call.args[0][0:2], ['escript', 'tools/emit_protocol_application.escript'])
            self.assertEqual(call.kwargs['env'], {'ERL_AFLAGS': 'chosen-default'})

    def test_command_logs_outputs_and_failure(self) -> None:
        """Extraction preserves working directories, fresh logs, stdout products and failed commands."""
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            output = directory/'product'
            run([sys.executable, '-c', 'import os; print(os.getcwd()); print(os.environ["CONTEXT"])'],
                directory, 'build', output, env={**os.environ, 'CONTEXT': 'child'})
            self.assertEqual(output.read_text().splitlines(), [str(ROOT), 'child'])
            self.assertEqual(json.loads((directory/'build.command.json').read_text())[0], sys.executable)
            with self.assertRaises(FileExistsError):
                run([sys.executable, '-c', 'raise Exception()'], directory, 'build')
            execute([sys.executable, '-c', 'import os; print(os.getcwd())'], directory, 'report')
            self.assertEqual((directory/'report.log').read_text().strip(), str(directory.resolve()))
            with self.assertRaises(subprocess.CalledProcessError):
                run([sys.executable, '-c', 'print("retained failure"); exit(7)'], directory, 'failure')
            self.assertIn('retained failure', (directory/'failure.log').read_text())

    def test_profiles_are_explicit_at_python_callsites(self) -> None:
        """Keep migrated callers from restoring profile inference or test-owned execution helpers."""
        for path in (ROOT/'tools').glob('*.py'):
            tree = ast.parse(path.read_text())
            for node in ast.walk(tree):
                if isinstance(node, ast.ImportFrom) and node.module in ('test_actor_rtl', 'test_local_protocol'):
                    self.assertFalse({'digest', 'run', 'execute', 'erl_command'} & {n.name for n in node.names}, str(path))
                if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
                    if node.func.id == 'erlang_paths':
                        self.assertTrue(node.args or any(k.arg == 'profile' for k in node.keywords), str(path))
                    if node.func.id == 'erl_command':
                        self.assertTrue(any(k.arg == 'profile' for k in node.keywords), str(path))


if __name__ == '__main__':
    unittest.main()
