"""Exercise a relocated compiler release and detached XLS consumer. Mock tools test orchestration only."""
from pathlib import Path
import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
DRIVER = ROOT/'priv/tools/compile_source_build.py'
spec = importlib.util.spec_from_file_location('compile_source_build', DRIVER)
driver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(driver)
compile_build = driver.compile_build


def snapshot(directory: Path) -> dict[str, tuple[bytes, int]]:
    """Capture bytes and modification times to detect writes even when contents are unchanged."""
    return {str(path.relative_to(directory)): (path.read_bytes(), path.stat().st_mtime_ns)
            for path in directory.rglob('*') if path.is_file()}


class SourceToolchainTests(unittest.TestCase):
    """Check actual Erlang lowering, portable artifacts and controlled external failures."""

    def test_moved_compiler_and_bundle(self) -> None:
        """The installed compiler needs no checkout, Python or rebar; the emitted bundle needs no Erlang."""
        with tempfile.TemporaryDirectory(prefix='compiler toolchain ') as temporary:
            stage = Path(temporary).resolve()
            release = stage/'compiler release'
            shutil.copytree(ROOT/'_build/default/rel/erl_hls', release)
            forbidden = stage/'forbidden'
            forbidden.mkdir()
            for name in ('python3', 'rebar3'):
                path = forbidden/name
                path.write_text('#!/bin/sh\nexit 99\n')
                path.chmod(0o755)
            fixture = stage/'actor.erl'
            fixture.write_text((ROOT/'test/xls_names_gs_fixture.erl').read_text().replace(
                '-module(xls_names_gs_fixture).', '-module(xls_names_gs_fixture).\n-include("options.hrl").'))
            includes = stage/'includes'
            includes.mkdir()
            (includes/'options.hrl').write_text('-ifndef(CLI_DEFINE).\n-error(missing_cli_define).\n-endif.\n'
                '-if(?CLI_DEFINE =/= 7 orelse ?BARE =/= true orelse ?FROM_FILE =/= 9).\n'
                '-error(wrong_macro_precedence).\n-endif.\n')
            defaults = stage/'options.erl'
            defaults.write_text("[{d, 'CLI_DEFINE', 1}, {d, 'BARE', 0}, {d, 'FROM_FILE', 9}].\n")
            env = {**os.environ, 'PATH': str(forbidden)+os.pathsep+os.environ['PATH'], 'ERL_AFLAGS': ''}
            emitted = stage/'emitted'
            command = [release/'bin/hlsc', 'emit', fixture, '--output', stage/'superseded',
                       '--pipeline-stages', 'invalid', '--source-options', stage/'absent.erl',
                       '-I', includes, '-D', 'CLI_DEFINE', '-D', 'CLI_DEFINE=7', '-D', 'BARE=2', '-D', 'BARE',
                       '--source-options', defaults, '--output', emitted, '--pipeline-stages', '3']
            result = subprocess.run(command, cwd=stage, env=env, capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            manifest = json.loads((emitted/'source-build.json').read_text())
            self.assertEqual(manifest['metadata'], {'kind': 'actor'})
            self.assertFalse((stage/'superseded').exists())
            self.assertIn('--pipeline_stages=3', manifest['units'][0]['codegen_flags'])
            self.assertIn('proc Top {', (emitted/'actor.x').read_text())
            for row in manifest['inputs']:
                self.assertEqual(hashlib.sha256((emitted/row['file']).read_bytes()).hexdigest(), row['sha256'])
                self.assertFalse(Path(row['file']).is_absolute())
            repeated = subprocess.run(command, cwd=stage, env=env, capture_output=True, timeout=60)
            self.assertNotEqual(repeated.returncode, 0)
            self.assertEqual(json.loads((emitted/'source-build.json').read_text()), manifest)
            # Missing macros surface preprocessing errors through the installed command.
            bad = subprocess.run([release/'bin/hlsc', 'emit', fixture, '-I', includes,
                                  '--output', stage/'bad'], cwd=stage, env=env, capture_output=True, text=True, timeout=60)
            self.assertNotEqual(bad.returncode, 0)
            self.assertIn('source/source_errors', bad.stderr)
            bad_json = subprocess.run([release/'bin/hlsc', 'emit', fixture, '-I', includes,
                                       '--output', stage/'bad', '--diagnostics', 'json'],
                                      cwd=stage, env=env, capture_output=True, text=True, timeout=60)
            error_rows = json.loads(bad_json.stderr)['context']['errors']
            self.assertTrue(any(row['source'] == str(includes/'options.hrl') and row['location'] == 2
                                and row['module'] == 'epp' and row['message'] for row in error_rows))
            self.assertFalse((stage/'bad').exists())
            moved = stage/'moved bundle'
            emitted.rename(moved)
            xls = stage/'mock xls'
            xls.mkdir()
            (xls/'xls/dslx/stdlib').mkdir(parents=True)
            for name in ('ir_converter_main', 'opt_main', 'codegen_main'):
                path = xls/name
                path.write_text('#!/bin/sh\nprintf "mock product\\n"\n')
                path.chmod(0o755)
            detached = stage/'driver.py'
            shutil.copyfile(release/'bin/compile-source-build', detached)
            preview_command = [sys.executable, detached, '--dry-run', xls, moved]
            before = snapshot(moved)
            preview = subprocess.run(preview_command, cwd=stage, env=env, check=True,
                                     capture_output=True, text=True, timeout=30)
            plan = json.loads(preview.stdout)
            self.assertEqual(snapshot(moved), before)
            self.assertEqual(plan['units'][0]['codegen_flags'], manifest['units'][0]['codegen_flags'])
            subprocess.run([sys.executable, detached, xls, moved], cwd=stage, env=env, check=True, timeout=30)
            compiled = json.loads((moved/'compiled.json').read_text())
            self.assertFalse(compiled['native_measured'])
            self.assertEqual([row['command'] for row in plan['units'][0]['commands']],
                             [row['command'] for row in compiled['units'][0]['commands']])
            after = snapshot(moved)
            repeated_preview = subprocess.run(preview_command, cwd=stage, env=env, check=True,
                                              capture_output=True, text=True, timeout=30)
            self.assertEqual(json.loads(repeated_preview.stdout), plan)
            self.assertEqual(snapshot(moved), after)
            self.assertEqual((moved/'files.f').read_text(), str(moved/'actor.v')+'\n')
            with self.assertRaises(FileExistsError):
                compile_build(xls, moved)
            original = moved/manifest['inputs'][0]['file']
            original.write_bytes(original.read_bytes()+b'changed')
            with self.assertRaisesRegex(ValueError, 'changed source build input'):
                compile_build(xls, moved)

    def test_cli_diagnostic_formats(self) -> None:
        """The installed CLI gives owned errors structured output and exposes unowned exception stacks."""
        release = ROOT/'_build/default/rel/erl_hls'
        env = {**os.environ, 'ERL_AFLAGS': '', 'HLS_DEBUG': '0'}
        with tempfile.TemporaryDirectory() as temporary:
            stage = Path(temporary)
            source = stage/'wide.erl'
            source.write_text('-module(wide).\n-behaviour(hls_gs).\n-hls_data(cell).\n-hls_tags([message]).\n'
                              '-record(cell, {value = hls_type:zero() :: hls_nums:u32()}).\n'
                              '-record(message, {value = hls_type:zero() :: hls_bits:bits(128)}).\n'
                              'init([]) -> #cell{}.\nhandle_call(#message{}, State) -> {reply, #message{}, State}.\n')
            command = [release/'bin/hlsc', 'emit', source, '--output', stage/'unused']
            human = subprocess.run([*command, '--diagnostics', 'json', '--diagnostics', 'text'],
                                   env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(human.returncode, 1)
            self.assertIn('actor_source/message_too_wide', human.stderr)
            self.assertIn(str(source), human.stderr)
            machine = subprocess.run([*command, '--diagnostics', 'invalid', '--diagnostics', 'text',
                                      '--diagnostics', 'json'], env=env,
                                     capture_output=True, text=True, timeout=30)
            report = json.loads(machine.stderr)
            self.assertEqual(report['code'], 'message_too_wide')
            self.assertEqual(report['context']['source'], str(source))
            self.assertEqual(report['context']['location'], 6)
            self.assertEqual(report['context']['width'], 128)
            self.assertFalse((stage/'unused').exists())
            invalid = subprocess.run([*command, '--diagnostics', 'json', '--diagnostics', 'invalid'],
                                     env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(invalid.returncode, 1)
            self.assertIn('arguments/invalid_diagnostics', invalid.stderr)
            for flags in (['--diagnostics', 'json', '--diagnostics'],
                          ['--diagnostics', '--help', '--diagnostics', 'text']):
                with self.subTest(flags=flags):
                    missing_mode = subprocess.run([*command, *flags], env=env,
                                                  capture_output=True, text=True, timeout=30)
                    self.assertEqual(missing_mode.returncode, 1)
                    self.assertIn('arguments/missing_option_value', missing_mode.stderr)
            debug = subprocess.run([*command, '--diagnostics', 'json'], env={**env, 'HLS_DEBUG': '1'},
                                   capture_output=True, text=True, timeout=30)
            self.assertTrue(json.loads(debug.stderr)['stack'])
            missing = subprocess.run([release/'bin/hlsc', 'emit', source, '--diagnostics', 'json'],
                                     env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(json.loads(missing.stderr)['code'], 'missing_option')
            ebin, = release.glob('lib/erl_hls-*/ebin')
            injected = ['erl', '+S', '1:1', '-noshell', '-pa', str(ebin), '-eval',
                        'hls_cli:main("fixture", fun(_) -> error(unexpected_fixture) end).']
            unowned = subprocess.run(injected, env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(unowned.returncode, 1)
            self.assertIn('error:unexpected_fixture', unowned.stderr)
            self.assertIn('hls_cli', unowned.stderr)
            machine_unowned = subprocess.run([*injected, '-extra', '--diagnostics', 'json'],
                                             env=env, capture_output=True, text=True, timeout=30)
            exception = json.loads(machine_unowned.stderr)
            self.assertEqual(exception['exception'], 'error')
            self.assertEqual(exception['reason'], 'unexpected_fixture')
            self.assertTrue(exception['stack'])
            self.assertNotIn('code', exception)

    def test_dry_run_preflight_is_read_only(self) -> None:
        """All units share execution command assembly, and drift fails before any tool or write."""
        with tempfile.TemporaryDirectory(prefix='preview inputs ') as temporary:
            root = Path(temporary).resolve()
            xls = root/'tool bundle'
            (xls/'xls/dslx/stdlib').mkdir(parents=True)
            (xls/'xls/dslx/stdlib/std.x').write_text('pub const VALUE = u32:1;')
            for name in ('ir_converter_main', 'opt_main', 'codegen_main'):
                path = xls/name
                path.write_text('#!/bin/sh\nexit 99\n')
                path.chmod(0o755)
            units, inputs = [], []
            for index, flags in enumerate((['--pipeline_stages=1', '--flop_outputs=false'],
                                           ['--pipeline_stages=3', '--flop_outputs=true'])):
                role = 'role' + str(index)
                (root/role).mkdir()
                source = root/role/'source.x'
                source.write_text('pub fn main() -> u1 { u1:0 }')
                inputs.append({'file': f'{role}/source.x', 'sha256': driver.digest(source)})
                units.append({'directory': role, 'role': role, 'source': f'{role}/source.x',
                              'output': f'{role}/top.v', 'top': 'main', 'module': role,
                              'codegen_flags': flags, 'dslx_path': [role], 'rtl': [f'{role}/top.v']})
            manifest = {'version': 1, 'inputs': inputs, 'units': units,
                        'rtl': {row['role']: row['rtl'] for row in units}}
            (root/'source-build.json').write_text(json.dumps(manifest))
            before = snapshot(root)
            with patch.object(driver.subprocess, 'run', side_effect=AssertionError('preview executed a tool')):
                plan = driver.plan_build(xls, root)
            self.assertEqual(snapshot(root), before)
            self.assertEqual([unit['codegen_flags'] for unit in plan['units']], [unit['codegen_flags'] for unit in units])
            self.assertEqual(plan['xls_tools']['codegen_main'],
                             {'path': str(xls/'codegen_main'), 'sha256': driver.digest(xls/'codegen_main')})
            self.assertEqual(plan['stdlib_inputs'], [{'file': 'std.x', 'sha256': driver.digest(xls/'xls/dslx/stdlib/std.x')}])
            # Any existing product is tolerated by preview, including a partial failed output.
            (root/'role0/raw.ir').write_text('retained failure')
            self.assertEqual(driver.plan_build(xls, root), plan)
            (root/inputs[0]['file']).write_text('changed')
            changed = snapshot(root)
            with self.assertRaisesRegex(ValueError, 'changed source build input'):
                driver.plan_build(xls, root)
            self.assertEqual(snapshot(root), changed)

    def test_failed_tool_retains_diagnostics(self) -> None:
        """A failed external tool leaves its output and exact command and stops later stages."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root/'source.x').write_text('pub fn main() -> u1 { u1:0 }')
            unit = {'role': '.', 'directory': '.', 'source': 'source.x', 'top': 'main', 'module': 'fixture',
                    'output': 'fixture.v', 'dslx_path': ['.'], 'codegen_flags': [], 'rtl': ['fixture.v']}
            (root/'source-build.json').write_text(json.dumps({'version': 1, 'units': [unit],
                'inputs': [{'file': 'source.x', 'sha256': hashlib.sha256((root/'source.x').read_bytes()).hexdigest()}],
                'rtl': {'.': ['fixture.v']}}))
            xls = root/'xls'
            xls.mkdir()
            (xls/'xls/dslx/stdlib').mkdir(parents=True)
            for name in ('ir_converter_main', 'opt_main', 'codegen_main'):
                path = xls/name
                path.write_text('#!/bin/sh\necho failed-fixture >&2\nexit 7\n')
                path.chmod(0o755)
            with self.assertRaisesRegex(RuntimeError, 'failed-fixture'):
                compile_build(xls, root)
            self.assertEqual(json.loads((root/'commands.json').read_text())[0]['exit'], 7)
            self.assertFalse((root/'optimized.ir').exists())
            self.assertFalse((root/'compiled.json').exists())


if __name__ == '__main__':
    unittest.main()
