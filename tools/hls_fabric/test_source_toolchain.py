"""Check packaged Erlang emission and the independent external-tool boundary without real XLS."""
from pathlib import Path
import hashlib
import importlib.util
import json
import os
import shutil
import shlex
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


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
            source = (ROOT/'apps/hls_fabric/test/hls_protocol_boundary_fixture.erl').read_text().replace(
                'C#cell{base=N}', 'C#cell{base=hls_fixture_math:adjust(N)}')
            fixture.write_text(source)
            actor_line = next(i for i, line in enumerate(source.splitlines(), 1)
                              if 'hls_fixture_math:adjust(N)' in line)
            helper = stage/'hls_fixture_math.erl'
            helper.write_text('-module(hls_fixture_math).\n-export([adjust/1]).\n'
                              '-spec adjust(hls_nums:u32()) -> hls_nums:u32().\n'
                              'adjust(Value) -> Value bxor 1.\n')
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
            spec = importlib.util.spec_from_file_location('packaged_xls_consumer', stage/'compile_xls.py')
            consumer = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(consumer)
            actor, = moved.glob('actors/actor_*.x')
            generated_helper, = moved.glob('actors/*_helpers/hls_fixture_math.x')

            def location(path: Path, token: str) -> tuple[int, int]:
                """Pick code rather than annotation text; expected origins come from the input fixture."""
                for number, line in enumerate(path.read_text().splitlines(), 1):
                    code = line.split('//', 1)[0]
                    if token in code:
                        return number, code.index(token) + 1
                self.fail(f'missing generated expression {token!r} in {path}')

            wrapper = moved/manifest['units'][0]['source']
            points = [(actor, location(actor, 'adjust('), (fixture.name, actor_line)),
                      (generated_helper, location(generated_helper, '^'), (helper.name, 4)),
                      (wrapper, location(wrapper, 'import '), None)]
            # Origins are descriptive: attribution must not depend on the original project still existing.
            fixture.rename(fixture.with_suffix('.retained'))
            helper.rename(helper.with_suffix('.retained'))
            for generated, (line, column), origin in points:
                self.assertEqual(consumer.mapped_source(generated, line, column), origin)
                raw = f'{generated.relative_to(moved)}:{line}:{column}: TypeInferenceError: injected failure\n'
                (xls/'ir_converter_main').write_text('#!/bin/sh\nprintf %s ' + shlex.quote(raw) + ' >&2\nexit 7\n')
                failed = subprocess.run([sys.executable, detached_driver, xls, moved], cwd=stage, env=env,
                                        capture_output=True, text=True, timeout=30)
                self.assertNotEqual(failed.returncode, 0)
                if origin is None:
                    self.assertNotIn('Erlang source:', failed.stderr)
                else:
                    self.assertIn(f'Erlang source: {origin[0]}:{origin[1]} ', failed.stderr)
                report = json.loads((moved/'compiled.run.json').read_text())
                self.assertEqual(report['status'], 'failed')
                self.assertEqual(report['active_stage'], 'unit0.convert')
                self.assertEqual((Path(report['attempt'])/'stderr.log').read_text(), raw)
                self.assertFalse((moved/'compiled').exists())
            (xls/'ir_converter_main').write_text('#!/bin/sh\nprintf "mock product\\n"\n')
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
            shutil.copyfile(ROOT/'apps/hls_lowering/src/examples/counter/hls_counter_example.erl', source)
            config = stage/'scheduler.config'
            config.write_text((ROOT/'apps/hls_lowering/src/examples/counter/scheduler-ram.config').read_text().replace(
                '"apps/hls_lowering/src/examples/counter/hls_counter_example.erl"', json.dumps(str(source))))
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
            source_config = (ROOT/'apps/hls_lowering/src/examples/counter/source.config').read_text().replace(
                '"apps/hls_lowering/src/examples/counter/hls_counter_example.erl"', '"missing-source.erl"')
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

    def test_relocated_example_release(self) -> None:
        """Examples ship separately and resolve source/includes from their installed application."""
        generic = ROOT / '_build/default/rel/hls/lib'
        self.assertFalse(list(generic.glob('hls_phi-*')))
        self.assertFalse(list(generic.glob('hls_snowflake-*')))
        with tempfile.TemporaryDirectory(prefix='example release ') as temporary:
            stage = Path(temporary).resolve()
            release = stage / 'relocated examples'
            shutil.copytree(ROOT / '_build/default/rel/hls_examples', release)
            environment = {**os.environ, 'ERL_AFLAGS': '', 'ERL_HLS_ROOT': '/not-a-checkout'}
            phi = subprocess.run([release / 'bin/hls-repetition', '--width', '2',
                                  '--output', stage / 'phi'], cwd=stage, env=environment,
                                 capture_output=True, text=True, timeout=90)
            self.assertEqual(phi.returncode, 0, phi.stdout + phi.stderr)
            ebins = sorted((release / 'lib').glob('*/ebin'))
            expression = 'hls_source_build:write(boundary, snowflake_source:config(), "snowflake"), halt().'
            snowflake = subprocess.run(['erl', '+S', '2', '-noshell', '-pa', *map(str, ebins),
                                        '-eval', expression], cwd=stage, env=environment,
                                       capture_output=True, text=True, timeout=90)
            self.assertEqual(snowflake.returncode, 0, snowflake.stdout + snowflake.stderr)
            for application in ('phi', 'snowflake'):
                bundle = stage / application
                manifest = json.loads((bundle / 'source-build.json').read_text())
                self.assertTrue(manifest['units'])
                for item in manifest['inputs']:
                    self.assertFalse(Path(item['file']).is_absolute())
                    self.assertEqual(hashlib.sha256((bundle / item['file']).read_bytes()).hexdigest(),
                                     item['sha256'])

if __name__ == '__main__':
    unittest.main()
