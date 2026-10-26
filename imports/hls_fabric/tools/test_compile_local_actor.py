"""Exercise the sampled-clock owner adapter through the shared executor using isolated tool stubs."""
import json
from pathlib import Path
import unittest
from unittest.mock import patch

import compile_local_actor
from compiler_paths import compiler_root, compiler_tool

public = compiler_root('test')
BuildFixture = compiler_tool(public, 'testing').BuildFixture


class LocalActorCompilationTests(BuildFixture):
    """Keep owner admission and scheduling intact across caching, changes and failures."""

    def setUp(self) -> None:
        """Create a source-bound owner and a nested import whose bytes affect stub conversion."""
        super().setUp()
        self.manifest = Path(str(self.source) + '.json')
        self.frame_config = self.source.parent / 'frame_config.x'
        self.frame_config.write_bytes((public / 'priv/xls/lib/frame_config.x').read_bytes())
        self.bind_source()
        self.imports = self.root / 'import with spaces'
        self.library = self.imports / 'nested/helper.x'
        self.library.parent.mkdir(parents=True)
        self.library.write_text('pub const VALUE = u32:7;\n')
        converter = self.xls / 'ir_converter_main'
        converter.write_text(converter.read_text().replace(
            "['*.x', '_stdlib/**/*.x']", "['*.x', '_stdlib/**/*.x', '_imports/**/*.x']"))

    def bind_source(self, clock: str = 'local_owner_clock') -> None:
        """Write the source identity and clock proc selected by the owning Erlang emitter."""
        self.manifest.write_text(json.dumps({'clock_proc': clock,
                                            'build_profile': {'backend': 'source_protocol', 'placement': {'kind': 'local_owner'},
                                                'schedules': {'sampled_clock': {'pipeline_stages': 1,
                                                    'flop_inputs': False, 'flop_outputs': False}}},
                                            'codegen_flags': ['--pipeline_stages=1', '--delay_model=unit',
                                                '--flop_inputs=false', '--flop_outputs=false',
                                                '--use_system_verilog=false', '--reset=reset'],
                                            'dslx_sha256': compile_local_actor.digest(self.source),
                                            'frame_config_sha256': compile_local_actor.digest(self.frame_config)}))

    def compile(self) -> Path:
        """Run only stub XLS tools with the same public adapter used by RTL witnesses."""
        compile_local_actor.compile_owner(self.xls, self.source, self.output, [self.imports],
                                          public=public, profile='test')
        return self.output.resolve()

    def test_fixed_schedule_and_cached_dependency_snapshot(self) -> None:
        """Cache exact owner flags and retain nested import bytes in the selected release."""
        release = self.compile()
        owner = json.loads((release / 'owner.json').read_text())
        self.assertEqual(owner['schedule'], {'pipeline_stages': 1, 'flop_inputs': False,
                         'flop_outputs': False, 'commands_valid': True, 'observations_ready': True})
        commands = json.loads((release / 'commands.json').read_text())
        self.assertIn('--top=local_owner_clock', commands[0]['command'])
        self.assertIn('--module_name=local_actor', commands[2]['command'])
        self.assertIn('--pipeline_stages=1', commands[2]['command'])
        self.assertIn('--flop_outputs=false', commands[2]['command'])
        self.assertFalse(owner['network_admitted'])
        self.assertFalse(owner['native_measured'])
        self.assertEqual(owner['rtl_sha256'], compile_local_actor.digest(release / 'actor.v'))
        retained = release / 'sources/_imports/4/nested/helper.x'
        self.assertEqual(retained.read_bytes(), self.library.read_bytes())
        calls = self.calls.read_text()
        self.assertEqual(self.compile(), release)
        self.assertEqual(self.calls.read_text(), calls)
        self.assertTrue(all(self.statuses().values()))
        self.library.write_text('pub const VALUE = u32:8;\n')
        changed = self.compile()
        self.assertNotEqual(changed, release)
        self.assertTrue(all(not reused for reused in self.statuses().values()))
        self.assertIn('u32:7', retained.read_text())

    def test_invalid_source_rejects_before_tools(self) -> None:
        """A changed source or unsupported clock cannot replace the selected release."""
        release = self.compile()
        calls = self.calls.read_text()
        self.source.write_text(self.source.read_text() + '// unbound edit\n')
        with self.assertRaisesRegex(ValueError, 'changed or unsupported'):
            self.compile()
        self.bind_source('unsupported_clock')
        with self.assertRaisesRegex(ValueError, 'changed or unsupported'):
            self.compile()
        self.assertEqual(self.calls.read_text(), calls)
        self.assertEqual(self.output.resolve(), release)

    def test_frame_configuration_rejects_before_tools_and_after_snapshot(self) -> None:
        """An unbound frame configuration cannot change either a live source or its retained snapshot."""
        release = self.compile()
        calls = self.calls.read_text()
        original = self.frame_config.read_bytes()
        changed = original + b'// unbound configuration edit\n'
        self.frame_config.write_bytes(changed)
        with self.assertRaisesRegex(ValueError, 'changed or unsupported'):
            self.compile()
        self.frame_config.write_bytes(original)
        compiler = compiler_tool(public, 'compile_xls')
        execute = compiler.execute

        def alter_before_snapshot(*args, **kwargs):
            """Change the dependency after admission, before the shared executor freezes input bytes."""
            self.frame_config.write_bytes(changed)
            return execute(*args, **kwargs)

        with patch.object(compile_local_actor, 'compiler_tool', return_value=compiler), patch.object(
                compiler, 'execute', side_effect=alter_before_snapshot):
            with self.assertRaisesRegex(ValueError, 'configuration or manifest during snapshot'):
                self.compile()
        self.assertEqual(self.calls.read_text(), calls)
        self.assertEqual(self.output.resolve(), release)

    def test_failed_stage_retains_release_and_retry_reuses_predecessors(self) -> None:
        """Retry an interrupted owner compilation without repeating its completed conversion."""
        release = self.compile()
        self.source.write_text(self.source.read_text() + '// new owner\n')
        self.bind_source('local_inbox_clock')
        with patch.dict('os.environ', {'XLS_TEST_FAIL': 'opt'}):
            with self.assertRaisesRegex(RuntimeError, 'compiler exited 7'):
                self.compile()
        self.assertEqual(self.output.resolve(), release)
        failure = json.loads(self.output.with_suffix('.run.json').read_text())
        self.assertEqual(failure['status'], 'failed')
        self.assertTrue(Path(failure['attempt']).is_dir())
        changed = self.compile()
        self.assertNotEqual(changed, release)
        self.assertEqual(self.statuses(), {'convert': True, 'opt': False, 'codegen': False})
        commands = json.loads((changed / 'commands.json').read_text())
        self.assertIn('--top=local_inbox_clock', commands[0]['command'])


if __name__ == '__main__':
    unittest.main()
