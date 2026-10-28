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
from compiler_paths import compiler_root, compiler_tool


class BuildContextTests(unittest.TestCase):
    """Reject implicit profile fallback and preserve subprocess failure semantics."""

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
            for profile in ('default', 'test'):
                compiler_fixture(root/'_build'/profile/'checkouts/erl_hls', profile)
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
                (app/'_build/default/lib/hls_runtime/ebin').mkdir(parents=True)
                source = app/'compiler_probe.erl'
                source.write_text(f'-module(compiler_probe).\n-export([value/0]).\nvalue() -> {value}.\n')
                subprocess.run(['erlc', '-o', app/'ebin', source], check=True, capture_output=True, timeout=15)
            self.assertEqual(application_directory('erl_hls', 'default', root), compiler)
            env = erlang_environment('default', root)
            expression = 'io:format("~p", [compiler_probe:value()]), halt().'
            self.assertEqual(subprocess.check_output(['erl', '-noshell', '-eval', expression],
                                                     env=env, text=True, timeout=15), 'dependency')
            with patch('backend_paths.erlang_paths',
                       side_effect=lambda profile, **options: erlang_paths(profile, root, **options)):
                command = erl_command(override, expression, profile='default')
            self.assertEqual(subprocess.check_output(command, env=env, text=True, timeout=15), 'fixture')

    def test_git_subdir_runtime_and_checkout_precedence(self) -> None:
        """A nested Git application is visible; an explicit runtime checkout wins by app identity."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            base = root/'_build/test'
            for name in ['lib/hls_fabric/ebin', 'lib/hls_lowering/ebin',
                         'lib/hls_runtime/apps/hls_runtime/ebin']:
                (base/name).mkdir(parents=True)
            self.assertEqual(application_directory('hls_runtime', 'test', root),
                             base/'lib/hls_runtime/apps/hls_runtime')
            (base/'checkouts/hls_runtime/ebin').mkdir(parents=True)
            selected = erlang_paths('test', root)
            self.assertIn(base/'checkouts/hls_runtime/ebin', selected)
            self.assertNotIn(base/'lib/hls_runtime/apps/hls_runtime/ebin', selected)
            self.assertIn(base/'lib/hls_lowering/ebin', selected)

    def test_production_emitter_uses_native_release(self) -> None:
        """The optional driver delegates source configuration to the packaged Erlang CLI."""
        import emit_protocol_repetition as emitter
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)/'application'
            with patch.object(emitter, 'run') as invoke:
                build = emitter.emit_application(6, directory, split=3)
            self.assertEqual(invoke.call_args_list[0].args[0], ['rebar3', 'release', '-n', 'hls'])
            self.assertEqual(invoke.call_args_list[1].args[0],
                             [ROOT/'_build/default/rel/hls/bin/hls-repetition',
                              '--width', '6', '--output', build, '--split', '3'])
            self.assertFalse((directory/'config.erl').exists())
            build.mkdir()
            published = directory/'immutable-release'
            published.mkdir()
            (build/'compiled').symlink_to(published, target_is_directory=True)
            with patch.object(emitter, 'emit_application', return_value=build), patch.object(emitter, 'run') as invoke:
                self.assertEqual(emitter.build_application(Path('/xls'), 6, directory, split=3), published.resolve())
            # Whole-bundle time must not undercut the compiler driver's per-stage watchdog.
            self.assertEqual(invoke.call_args.args[0],
                             [ROOT/'_build/default/rel/hls/bin/compile-source-build', Path('/xls'), build])
            self.assertIsNone(invoke.call_args.kwargs['timeout'])

    def test_source_helper_returns_resolved_release(self) -> None:
        """Positive fixtures read the published snapshot while compile diagnostics stay beside the input."""
        import protocol_test_build as builder
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)/'source'
            directory.mkdir()
            published = Path(temporary)/'release'
            published.mkdir()
            (directory/'compiled').symlink_to(published, target_is_directory=True)
            compiler = Path(temporary)/'compiler'
            with patch.object(builder, 'application_directory', return_value=compiler) as select, \
                    patch.object(builder, 'run') as invoke:
                self.assertEqual(builder.compile_build(Path('/xls'), directory, profile='test'), published.resolve())
            select.assert_called_once_with('erl_hls', 'test')
            self.assertEqual(invoke.call_args.args[0],
                             [sys.executable, compiler/'priv/tools/compile_source_build.py', Path('/xls'), directory])
            self.assertEqual(invoke.call_args.args[1], directory)
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


def compiler_fixture(public: Path, label: str) -> Path:
    """Create a compiler package with distinguishable direct and transitive helpers."""
    package = public/'tools/erl_hls_tools'
    package.mkdir(parents=True)
    for profile in ('default', 'test'):
        (public/'_build'/profile/'lib/hls_runtime/ebin').mkdir(parents=True, exist_ok=True)
    (package/'__init__.py').write_text('"""Inert compiler fixture package."""\n')
    (package/'sibling.py').write_text(f'VALUE = {label!r}\n')
    (package/'compile_xls.py').write_text('from .sibling import VALUE\n')
    return public.resolve()


def production_sources() -> list[Path]:
    """List tool and experiment Python sources, excluding test entrypoints."""
    roots = [ROOT/'tools', ROOT/'experiments']
    return sorted(path for root in roots for path in root.rglob('*.py')
                  if not path.name.startswith('test_') and not path.stem.endswith('_test')
                  and '__pycache__' not in path.parts
                  # Third-party FPGA IP includes legacy Python 2 generators.
                  and 'ip_lib' not in path.parts)


class CompilerContextTests(unittest.TestCase):
    """Resolve compiler sources explicitly and keep production imports independent of tests."""

    def test_profile_selection_ignores_stale_sources(self) -> None:
        """Other profiles, source checkouts and inherited overrides cannot satisfy this request."""
        with tempfile.TemporaryDirectory(prefix='compiler context ') as temporary:
            root = Path(temporary)
            test = compiler_fixture(root/'_build/test/lib/erl_hls', 'test')
            (root/'_build/test/lib/hls_fabric/ebin').mkdir(parents=True)
            (test/'ebin').mkdir()
            compiler_fixture(root/'_checkouts/erl_hls', 'unbuilt')
            with patch.dict(os.environ, {'ERL_HLS_ROOT': str(test)}):
                with self.assertRaises(FileNotFoundError):
                    compiler_root('default', root=root)
                self.assertEqual(compiler_root('test', root=root), test)
                default = compiler_fixture(root/'_build/default/lib/erl_hls', 'default')
                (root/'_build/default/lib/hls_fabric/ebin').mkdir(parents=True)
                (default/'ebin').mkdir()
                self.assertEqual(compiler_root('default', root=root), default)
                # Both profiles remain present, but only the requested checkout wins.
                checkout = compiler_fixture(root/'_build/default/checkouts/erl_hls', 'checkout')
                (checkout/'ebin').mkdir()
                self.assertEqual(compiler_root('default', root=root), checkout)
                self.assertEqual(compiler_root('test', root=root), test)
                with self.assertRaises(ValueError):
                    compiler_root('../test', root=root)

    def test_umbrella_projection_keeps_matching_beams_and_resolves_tool_sources(self) -> None:
        """A built app's src link selects helpers without substituting standalone or stale beams."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = compiler_fixture(root/'source compiler', 'selected')
            (source/'src').mkdir()
            selected = root/'_build/test/checkouts/erl_hls'
            (selected/'ebin').mkdir(parents=True)
            (selected/'src').symlink_to(source/'src', target_is_directory=True)
            (root/'_build/test/checkouts/hls_runtime/ebin').mkdir(parents=True)
            (root/'_build/test/lib/hls_fabric/ebin').mkdir(parents=True)
            compiler_fixture(root/'_checkouts/erl_hls', 'unrelated')
            self.assertEqual(compiler_root('test', root=root), source)
            self.assertEqual(compiler_tool(source, 'compile_xls').VALUE, 'selected')
            paths = erlang_paths('test', root, compiler=source)
            self.assertIn(selected/'ebin', paths)
            self.assertIn(root/'_build/test/checkouts/hls_runtime/ebin', paths)
            self.assertNotIn(source/'_build/test/lib/erl_hls/ebin', paths)

    def test_override_is_explicit_and_never_falls_back(self) -> None:
        """Explicit sources need no build tree; incomplete overrides cannot select another compiler."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            selected = compiler_fixture(root/'selected compiler', 'override')
            before_env, before_paths = dict(os.environ), list(sys.path)
            self.assertEqual(compiler_root('default', override=selected, root=root), selected)
            self.assertEqual(dict(os.environ), before_env)
            self.assertEqual(sys.path, before_paths)
            stale = compiler_fixture(root/'_build/default/lib/erl_hls', 'stale')
            (root/'_build/default/lib/hls_fabric/ebin').mkdir(parents=True)
            (stale/'ebin').mkdir()
            legacy = root/'legacy'
            (legacy/'tools').mkdir(parents=True)
            (legacy/'tools/compile_xls.py').write_text('# Old flat tools are insufficient.\n')
            for absent in (root/'missing', legacy):
                with self.assertRaises(FileNotFoundError):
                    compiler_root('default', override=absent, root=root)

    def test_two_compilers_keep_transitive_imports_separate(self) -> None:
        """A→B→A selection cannot reuse another root's identically named sibling module."""
        with tempfile.TemporaryDirectory(prefix='compiler packages ') as temporary:
            root = Path(temporary)
            first = compiler_fixture(root/'first', 'first')
            second = compiler_fixture(root/'second', 'second')
            before_env, before_paths = dict(os.environ), list(sys.path)
            a = compiler_tool(first, 'compile_xls')
            b = compiler_tool(second, 'compile_xls')
            again = compiler_tool(first, 'compile_xls')
            self.assertEqual((a.VALUE, b.VALUE, again.VALUE), ('first', 'second', 'first'))
            self.assertIs(a, again)
            self.assertIsNot(a, b)
            self.assertEqual(Path(a.__file__).resolve(), first/'tools/erl_hls_tools/compile_xls.py')
            self.assertEqual(Path(b.__file__).resolve(), second/'tools/erl_hls_tools/compile_xls.py')
            self.assertEqual(dict(os.environ), before_env)
            self.assertEqual(sys.path, before_paths)

    def test_production_imports_are_inert(self) -> None:
        """Import every production tool without compiler lookup, test imports or child execution."""
        modules = [path.stem for path in sorted((ROOT/'tools').glob('*.py'))
                   if not path.name.startswith('test_')]
        script = import_probe() + '''
for name in sys.argv[1:]:
    importlib.import_module(name)
    assert dict(os.environ) == before_env, name
    assert sys.path == before_paths, name
    assert Path.cwd() == before_cwd, name
assert not any(part.startswith('test_') for name in sys.modules for part in name.split('.'))
'''
        self.run_probe(script, modules)

    def test_production_help_needs_no_compiler_or_test_modules(self) -> None:
        """CLI help is available before selecting a compiler and cannot launch build tools."""
        names = ('compile_backend', 'compile_local_actor', 'compile_phi_decoder_profile',
                 'build_phi_debug', 'measure_actor_ingress', 'measure_phi_memory',
                 'profile_phi_memory', 'measure_phi_mesh', 'phi_profile_timeline',
                 'run_repetition_profile')
        script = import_probe() + '''
import runpy
filename = sys.argv[1]
sys.argv = [filename, '--help']
try:
    runpy.run_path(filename, run_name='__main__')
except SystemExit as result:
    assert result.code == 0, result.code
else:
    raise AssertionError('CLI did not parse --help')
assert dict(os.environ) == before_env
assert sys.path == before_paths
assert Path.cwd() == before_cwd
'''
        for name in names:
            with self.subTest(name=name):
                result = self.run_probe(script, [str(ROOT/'tools'/f'{name}.py')])
                self.assertIn('usage:', result.stdout.lower())

    def test_production_has_no_test_import_edges(self) -> None:
        """Cover lazy and direct imports across all owned tools and experiment drivers."""
        failures = []
        for path in production_sources():
            for node in ast.walk(ast.parse(path.read_text(), filename=str(path))):
                names = []
                if isinstance(node, ast.Import):
                    names = [entry.name for entry in node.names]
                elif isinstance(node, ast.ImportFrom):
                    names = [node.module] if node.module else []
                    names.extend(entry.name for entry in node.names)
                elif isinstance(node, ast.Call) and node.args:
                    function = node.func
                    operation = function.id if isinstance(function, ast.Name) else (
                        function.attr if isinstance(function, ast.Attribute) else '')
                    if operation in ('import_module', '__import__') and isinstance(node.args[0], ast.Constant):
                        name = node.args[0].value
                        names = [name] if isinstance(name, str) else []
                for name in names:
                    if any(part.startswith('test_') or part.endswith('_test') for part in name.split('.')):
                        failures.append(f'{path.relative_to(ROOT)}:{node.lineno}: {name}')
        self.assertEqual(failures, [])

    def run_probe(self, script: str, arguments: list[str]) -> subprocess.CompletedProcess[str]:
        """Give each import/CLI probe a fresh interpreter, directory and deterministic search path."""
        with tempfile.TemporaryDirectory(prefix='inert tool imports ') as temporary:
            result = subprocess.run([sys.executable, '-B', '-c', script, *arguments],
                cwd=temporary, capture_output=True, text=True, timeout=15,
                env={**os.environ, 'PYTHONPATH': str(ROOT/'tools'),
                     'ERL_HLS_ROOT': '/nonexistent-compiler', 'ERL_AFLAGS': 'sentinel'})
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            self.assertEqual(list(Path(temporary).iterdir()), [])
            return result


def import_probe() -> str:
    """Block test imports, compiler resolution and subprocesses before loading production code."""
    return '''import importlib, importlib.abc, os, subprocess, sys
from pathlib import Path

class RejectTests(importlib.abc.MetaPathFinder):
    def find_spec(self, fullname, path=None, target=None):
        if any(part.startswith('test_') or part.endswith('_test') for part in fullname.split('.')):
            raise AssertionError('test import rejected: ' + fullname)

sys.meta_path.insert(0, RejectTests())
try:
    importlib.import_module('test_context_positive_control')
except AssertionError as error:
    assert str(error) == 'test import rejected: test_context_positive_control'
else:
    raise AssertionError('test import guard was inactive')

before_env, before_paths, before_cwd = dict(os.environ), list(sys.path), Path.cwd()
import compiler_paths
assert dict(os.environ) == before_env
assert sys.path == before_paths

def forbidden(*args, **kwargs):
    raise AssertionError('import/help attempted compiler discovery or external execution')

compiler_paths.compiler_root = forbidden
compiler_paths.compiler_tool = forbidden
subprocess.Popen = forbidden
'''


if __name__ == '__main__':
    unittest.main()
