"""Check packaged Erlang emission and the independent external-tool boundary without real XLS."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class SourceToolchainTests(unittest.TestCase):
    """Exercise real source emission and controlled external tools in moved directories."""

    def test_moved_toolchain_and_emitted_bundle(self) -> None:
        """A packaged CLI needs neither rebar/Python nor its checkout; XLS needs only its emitted bundle."""
        with tempfile.TemporaryDirectory(prefix='source toolchain ') as temporary:
            stage = Path(temporary).resolve()
            release = stage/'tool chain'
            shutil.copytree(ROOT/'_build/default/rel/hls', release)
            forbidden = stage/'forbidden'
            forbidden.mkdir()
            for name in ('python3', 'rebar3'):
                path = forbidden/name
                path.write_text('#!/bin/sh\necho forbidden-build-tool >&2\nexit 99\n')
                path.chmod(0o755)
            fixture = stage/'fixture.erl'
            shutil.copyfile(ROOT/'test/hls_protocol_boundary_fixture.erl', fixture)
            config = stage/'config.erl'
            # JSON string escaping is valid for this fixture's ordinary Erlang filename.
            config.write_text('#{sources=>[{' + json.dumps(str(fixture)) + ',[]}],topology=>'
                              '{hls_protocol_boundary_fixture,topology,[]},actor_limit=>4,device=>board,host=>1}.\n')
            env = {**os.environ, 'PATH': str(forbidden)+os.pathsep+os.environ['PATH'],
                   'ERL_HLS_ROOT': '/not-a-compiler', 'PYTHONPATH': '/not-python-tools', 'ERL_AFLAGS': ''}
            emitted = stage/'emitted'
            command = [release/'bin/hls-fabric', 'emit', '--config', config, '--output', emitted]
            result = subprocess.run(command, cwd=stage, env=env, capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            manifest = json.loads((emitted/'source-build.json').read_text())
            self.assertEqual([u['module'] for u in manifest['units']], ['protocol_boundary_core', 'application_gateway'])
            for row in manifest['inputs']:
                self.assertFalse(Path(row['file']).is_absolute())
                self.assertEqual(hashlib.sha256((emitted/row['file']).read_bytes()).hexdigest(), row['sha256'])
            for unit in manifest['units']:
                self.assertTrue(all((emitted/p).is_dir() for p in unit['dslx_path']))
            self.assertFalse(any((emitted/name).exists() for name in ('files.f', 'compiled.json')))
            repeated = subprocess.run(command, cwd=stage, env=env, capture_output=True, timeout=60)
            self.assertNotEqual(repeated.returncode, 0)
            self.assertEqual(json.loads((emitted/'source-build.json').read_text()), manifest)
            moved = stage/'moved source bundle'
            emitted.rename(moved)
            # Mock tools validate invocation/provenance mechanics, not XLS semantics or RTL.
            xls = stage/'mock xls'
            xls.mkdir()
            for name in ('ir_converter_main', 'opt_main', 'codegen_main'):
                path = xls/name
                path.write_text('#!/bin/sh\nprintf "mock product\\n"\n')
                path.chmod(0o755)
            detached_driver = stage/'compile_source_build.py'
            shutil.copyfile(next(release.glob('lib/erl_hls-*/priv/tools/compile_source_build.py')), detached_driver)
            subprocess.run([sys.executable, detached_driver, xls, moved], cwd=stage, env=env, check=True, timeout=30)
            compiled = json.loads((moved/'compiled.json').read_text())
            self.assertFalse(compiled['native_measured'])
            boundary, gateway = compiled['units']
            self.assertIn('--pipeline_stages=1', boundary['commands'][2]['command'])
            self.assertIn('--flop_outputs=false', boundary['commands'][2]['command'])
            self.assertIn('--pipeline_stages=2', gateway['commands'][2]['command'])
            self.assertIn('--flop_outputs=true', gateway['commands'][2]['command'])
            for unit in compiled['units']:
                imports = next(a for a in unit['commands'][0]['command'] if a.startswith('--dslx_path='))
                self.assertNotIn(str(ROOT), imports)
                self.assertNotIn(str(emitted), imports)
            self.assertTrue(all(Path(p).is_file() for p in (moved/'files.f').read_text().splitlines()))

if __name__ == '__main__':
    unittest.main()
