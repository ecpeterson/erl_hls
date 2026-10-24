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
from backend_paths import ROOT, erlang_paths, erlang_environment, application_directory, erl_command


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
            self.assertEqual(application_directory('erl_hls', 'default', root),
                             root/'_build/default/checkouts/erl_hls')
            self.assertEqual(application_directory('erl_hls', 'test', root),
                             root/'_build/test/checkouts/erl_hls')
            with self.assertRaisesRegex(FileNotFoundError, 'missing absent'):
                application_directory('absent', 'default', root)
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

    def test_normal_dependency_and_explicit_beam_override(self) -> None:
        """Normal rebar dependencies work without checkouts; test-local beams win when requested."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            compiler = root/'_build/default/lib/erl_hls'
            (root/'_build/default/lib/hls_fabric/ebin').mkdir(parents=True)
            override = root/'fixture'
            for app, value in [(compiler, 'dependency'), (override, 'fixture')]:
                (app/'ebin').mkdir(parents=True)
                source = app/'compiler_probe.erl'
                source.write_text(f'-module(compiler_probe).\n-export([value/0]).\nvalue() -> {value}.\n')
                subprocess.run(['erlc', '-o', app/'ebin', source], check=True, capture_output=True, timeout=15)
            self.assertEqual(application_directory('erl_hls', 'default', root), compiler)
            env = erlang_environment('default', root)
            expression = 'io:format("~p", [compiler_probe:value()]), halt().'
            self.assertEqual(subprocess.check_output(['erl', '-noshell', '-eval', expression],
                                                     env=env, text=True, timeout=15), 'dependency')
            with patch('backend_paths.erlang_paths', return_value=erlang_paths('default', root)):
                command = erl_command(override, expression, profile='default')
            self.assertEqual(subprocess.check_output(command, env=env, text=True, timeout=15), 'fixture')

    def test_production_emitter_uses_native_release(self) -> None:
        """The optional driver delegates source configuration to the packaged Erlang CLI."""
        import emit_protocol_repetition as emitter
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)/'application'
            with patch.object(emitter, 'run') as invoke:
                build = emitter.emit_application(6, directory, split=3)
            self.assertEqual(invoke.call_args_list[0].args[0], ['rebar3', 'release'])
            self.assertEqual(invoke.call_args_list[1].args[0],
                             [ROOT/'_build/default/rel/hls/bin/hls-repetition',
                              '--width', '6', '--output', build, '--split', '3'])
            self.assertFalse((directory/'config.erl').exists())
            with patch.object(emitter, 'emit_application', return_value=build), patch.object(emitter, 'run') as invoke:
                self.assertEqual(emitter.build_application(Path('/xls'), 6, directory, split=3), build)
            # Whole-bundle time must not undercut the compiler driver's per-stage watchdog.
            self.assertEqual(invoke.call_args.args[0],
                             [ROOT/'_build/default/rel/hls/bin/compile-source-build', Path('/xls'), build])
            self.assertIsNone(invoke.call_args.kwargs['timeout'])

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

    def test_command_timeout_and_delegated_watchdog(self) -> None:
        """Enforce caller limits for both log modes while permitting stage-bounded child drivers."""
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for name, output in [('combined', None), ('product', directory/'product')]:
                with self.assertRaises(subprocess.TimeoutExpired):
                    run([sys.executable, '-c', 'import time; time.sleep(10)'], directory, name,
                        output, timeout=0)
            run([sys.executable, '-c', 'print("driver complete")'], directory, 'delegated', timeout=None)
            self.assertEqual((directory/'delegated.log').read_text().strip(), 'driver complete')

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
