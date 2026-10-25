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
            planned = subprocess.run([release/'bin/hls-fabric', 'plan', '--config', stage/'absent.erl',
                                      '--backend', 'channel_scheduler', '--backend', 'source_protocol',
                                      '--kind', 'unknown', '--stage', 'invalid', '--format', 'invalid',
                                      '--config', config, '--kind', 'application',
                                      '--stage', 'schedule', '--format', 'json'],
                                     cwd=stage, env=env, capture_output=True, text=True, timeout=60)
            self.assertEqual(planned.returncode, 0, planned.stdout+planned.stderr)
            schedule = json.loads(planned.stdout)['data']
            self.assertFalse(emitted.exists())
            invalid = stage/'invalid.erl'
            invalid.write_text('#{}.\n')
            rejected = subprocess.run([release/'bin/hls-fabric', 'plan', '--config', invalid,
                                       '--diagnostics', 'json'], cwd=stage, env=env,
                                      capture_output=True, text=True, timeout=30)
            self.assertEqual(rejected.returncode, 1)
            error = json.loads(rejected.stderr)
            self.assertEqual(error['code'], 'missing_config_field')
            self.assertEqual(error['context']['field'], ['sources'])
            self.assertEqual(error['context']['config_file'], str(invalid))
            self.assertEqual(rejected.stdout, '')
            command = [release/'bin/hls-fabric', 'emit', '--output', stage/'superseded',
                       '--config', stage/'absent.erl', '--config', config, '--output', emitted]
            result = subprocess.run(command, cwd=stage, env=env, capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            manifest = json.loads((emitted/'source-build.json').read_text())
            self.assertEqual(schedule, manifest['units'])
            self.assertFalse((stage/'superseded').exists())
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
            (xls/'xls/dslx/stdlib').mkdir(parents=True)
            for name in ('ir_converter_main', 'opt_main', 'codegen_main'):
                path = xls/name
                path.write_text('#!/bin/sh\nprintf "mock product\\n"\n')
                path.chmod(0o755)
            detached_driver = stage/'compile_source_build.py'
            compiler_tools = next(release.glob('lib/erl_hls-*/priv/tools'))
            for name in ('compile_source_build.py', 'compile_xls.py'):
                shutil.copyfile(compiler_tools/name, stage/name)
            subprocess.run([sys.executable, detached_driver, xls, moved], cwd=stage, env=env, check=True, timeout=30)
            published = (moved/'compiled').resolve()
            compiled = json.loads((published/'compiled.json').read_text())
            self.assertFalse(compiled['native_measured'])
            self.assertEqual(compiled['metadata'], manifest['metadata'])
            boundary, gateway = compiled['units']
            self.assertIn('--pipeline_stages=1', boundary['commands'][2]['command'])
            self.assertIn('--flop_outputs=false', boundary['commands'][2]['command'])
            self.assertIn('--pipeline_stages=2', gateway['commands'][2]['command'])
            self.assertIn('--flop_outputs=true', gateway['commands'][2]['command'])
            for unit in compiled['units']:
                imports = next(a for a in unit['commands'][0]['command'] if a.startswith('--dslx_path='))
                self.assertNotIn(str(ROOT), imports)
                self.assertNotIn(str(emitted), imports)
            files = (published/'files.f').read_text().splitlines()
            self.assertTrue(all(not Path(p).is_absolute() and (published/p).is_file() for p in files))
            self.assertEqual(json.loads((published/'source-build.json').read_text()), manifest)
            self.assertFalse((moved/'compiled.json').exists())
            relocated = stage/'moved compiled release'
            shutil.copytree(published, relocated)
            self.assertTrue(all((relocated/p).is_file() for p in files))
            for row in manifest['inputs']:
                self.assertEqual(hashlib.sha256((moved/row['file']).read_bytes()).hexdigest(), row['sha256'])
                self.assertEqual((relocated/row['file']).read_bytes(), (moved/row['file']).read_bytes())


    def test_scheduler_profile_and_backend_constraints(self) -> None:
        """The public backend selector retains one RAM-placement profile across planning, moves and compilation."""
        with tempfile.TemporaryDirectory(prefix='scheduler toolchain ') as temporary:
            stage = Path(temporary).resolve()
            release = stage/'relocated toolchain'
            shutil.copytree(ROOT/'_build/default/rel/hls', release)
            source = stage/'hls_counter_example.erl'
            shutil.copyfile(ROOT/'src/examples/counter/hls_counter_example.erl', source)
            config = stage/'scheduler.config'
            config.write_text((ROOT/'src/examples/counter/scheduler-ram.config').read_text().replace(
                '"src/examples/counter/hls_counter_example.erl"', json.dumps(str(source))))
            environment = {**os.environ, 'ERL_AFLAGS': '', 'ERL_HLS_ROOT': '/not-a-compiler'}
            cli = release/'bin/hls-fabric'

            def invoke(*arguments: object) -> subprocess.CompletedProcess[str]:
                """Run the moved packaged frontend, never a checkout-local executable."""
                return subprocess.run([str(cli), *map(str, arguments)], cwd=stage, env=environment,
                                      capture_output=True, text=True, timeout=60)

            def plan(view: str) -> dict:
                """Earlier backend directives may be superseded before validation or source loading."""
                result = invoke('plan', '--backend', 'unknown', '--backend', 'source_protocol',
                                '--backend', 'channel_scheduler', '--config', config,
                                '--stage', view, '--format', 'json')
                self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
                return json.loads(result.stdout)['data']

            profile, schedule = plan('profile'), plan('schedule')
            self.assertEqual(profile['backend'], 'channel_scheduler')
            self.assertEqual(profile['schedules']['channel']['pipeline_stages'], 2)
            self.assertEqual(profile['placement']['scheduler_groups']['counters']['state_storage'], 'block_ram')
            unit, = schedule
            self.assertTrue(any(flag.startswith('--ram_configurations=') for flag in unit['codegen_flags']))
            self.assertIn('support/compiler/rtl/hls_1r1w_ram.v', unit['rtl'])
            rejected = invoke('emit', '--backend', 'channel_scheduler', '--kind', 'application',
                              '--config', stage/'absent.erl', '--output', stage/'rejected-kind',
                              '--diagnostics', 'json')
            self.assertEqual(rejected.returncode, 1)
            self.assertEqual(json.loads(rejected.stderr)['code'], 'incompatible_build_kind')
            self.assertEqual(rejected.stdout, '')
            self.assertFalse((stage/'rejected-kind').exists())
            override = stage/'source-override.config'
            source_config = (ROOT/'src/examples/counter/source.config').read_text().replace(
                '"src/examples/counter/hls_counter_example.erl"', '"missing-source.erl"')
            prefix, separator, suffix = source_config.rpartition('}.')
            self.assertEqual(separator, '}.')
            override.write_text(prefix + ', schedule => #{pipeline_stages => 2}}.' + suffix)
            rejected = invoke('emit', '--backend', 'source_protocol', '--kind', 'application',
                              '--config', override, '--output', stage/'rejected-schedule',
                              '--diagnostics', 'json')
            self.assertEqual(rejected.returncode, 1)
            diagnostic = json.loads(rejected.stderr)
            self.assertEqual(diagnostic['code'], 'unknown_config_fields')
            self.assertEqual(diagnostic['context']['value'], ['schedule'])
            self.assertFalse((stage/'rejected-schedule').exists())
            emitted = stage/'emitted scheduler'
            result = invoke('emit', '--backend', 'source_protocol', '--backend', 'channel_scheduler',
                            '--config', config, '--output', emitted)
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            manifest = json.loads((emitted/'source-build.json').read_text())
            self.assertEqual(manifest['metadata'], {'backend': 'channel_scheduler', 'profile': profile})
            self.assertEqual(manifest['units'], schedule)
            self.assertEqual(json.loads((emitted/'profile.json').read_text()), profile)
            self.assertEqual(len(json.loads((emitted/'ram/bindings.json').read_text())), 1)
            source.rename(source.with_suffix('.retained'))
            moved = stage/'relocated scheduler bundle'
            emitted.rename(moved)
            # Stubs test the packaged contract and provenance, never hardware functionality.
            xls = stage/'stub xls'
            (xls/'xls/dslx/stdlib').mkdir(parents=True)
            for name in ('ir_converter_main', 'opt_main', 'codegen_main'):
                executable = xls/name
                executable.write_text('#!/bin/sh\nprintf "stub product\\n"\n')
                executable.chmod(0o755)
            compiler_tools = next(release.glob('lib/erl_hls-*/priv/tools'))
            for name in ('compile_source_build.py', 'compile_xls.py'):
                shutil.copyfile(compiler_tools/name, stage/name)
            subprocess.run([sys.executable, stage/'compile_source_build.py', xls, moved],
                           cwd=stage, env=environment, check=True, timeout=30)
            published = (moved/'compiled').resolve()
            compiled = json.loads((published/'compiled.json').read_text())
            self.assertEqual(compiled['metadata'], manifest['metadata'])
            self.assertEqual(json.loads((published/'source-build.json').read_text()), manifest)
            self.assertFalse(compiled['native_measured'])
            compiled_unit, = compiled['units']
            command = compiled_unit['commands'][2]['command']
            self.assertTrue(all(flag in command for flag in unit['codegen_flags']))
            self.assertIn('--module_name=counter_topology', command)
            self.assertEqual(set(compiled['xls_tools']), {'ir_converter_main', 'opt_main', 'codegen_main'})
            for row in manifest['inputs']:
                self.assertEqual(hashlib.sha256((published/row['file']).read_bytes()).hexdigest(), row['sha256'])
                self.assertEqual((published/row['file']).read_bytes(), (moved/row['file']).read_bytes())
            rtl = (published/'files.f').read_text().splitlines()
            self.assertTrue(all(not Path(path).is_absolute() and (published/path).is_file() for path in rtl))

if __name__ == '__main__':
    unittest.main()
