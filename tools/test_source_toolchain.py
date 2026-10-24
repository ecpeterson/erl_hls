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

ROOT = Path(__file__).resolve().parents[1]
DRIVER = ROOT/'priv/tools/compile_source_build.py'
spec = importlib.util.spec_from_file_location('compile_source_build', DRIVER)
driver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(driver)
compile_build = driver.compile_build


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
            (includes/'options.hrl').write_text('-ifndef(CLI_DEFINE).\n-error(missing_cli_define).\n-endif.\n')
            env = {**os.environ, 'PATH': str(forbidden)+os.pathsep+os.environ['PATH'], 'ERL_AFLAGS': ''}
            emitted = stage/'emitted'
            command = [release/'bin/hlsc', 'emit', fixture, '-I', includes, '-D', 'CLI_DEFINE=7',
                       '--output', emitted, '--pipeline-stages', '3']
            result = subprocess.run(command, cwd=stage, env=env, capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            manifest = json.loads((emitted/'source-build.json').read_text())
            self.assertEqual(manifest['metadata'], {'kind': 'actor'})
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
            self.assertIn('source_errors', bad.stderr)
            self.assertFalse((stage/'bad').exists())
            moved = stage/'moved bundle'
            emitted.rename(moved)
            xls = stage/'mock xls'
            xls.mkdir()
            for name in ('ir_converter_main', 'opt_main', 'codegen_main'):
                path = xls/name
                path.write_text('#!/bin/sh\nprintf "mock product\\n"\n')
                path.chmod(0o755)
            detached = stage/'driver.py'
            shutil.copyfile(release/'bin/compile-source-build', detached)
            subprocess.run([sys.executable, detached, xls, moved], cwd=stage, env=env, check=True, timeout=30)
            compiled = json.loads((moved/'compiled.json').read_text())
            self.assertFalse(compiled['native_measured'])
            self.assertEqual((moved/'files.f').read_text(), str(moved/'actor.v')+'\n')
            with self.assertRaises(FileExistsError):
                compile_build(xls, moved)
            original = moved/manifest['inputs'][0]['file']
            original.write_bytes(original.read_bytes()+b'changed')
            with self.assertRaisesRegex(ValueError, 'changed source build input'):
                compile_build(xls, moved)

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
