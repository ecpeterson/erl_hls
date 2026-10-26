"""Check the cache boundary between constant bindings and compiled behavior."""
import argparse
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from backend_build_profile import emit
from phi_tiles import bind, check_sources, identity, outputs, prepare


class TileCacheTest(unittest.TestCase):
    """A changed wrapper value reuses logic; changed source or tool never does."""

    def test_cache_identity(self) -> None:
        """Include library/compiler/settings changes but exclude per-board values."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, xls = root/'source', root/'xls'
            source.mkdir()
            (xls/'xls/dslx/stdlib').mkdir(parents=True)
            for name in ('ir_converter_main', 'opt_main', 'codegen_main'):
                (xls/name).write_text(name)
            (xls/'xls/dslx/stdlib/std.x').write_text('stdlib')
            helper = root/'rams.sh'
            helper.write_text('RAM ABI')
            for name in ('phi_tile.x', 'tile_graph.x', 'actor.x'):
                (source/name).write_text(name)
            build_profile = source/'build-profile.json'
            emit(build_profile, profile='test', initiation_interval=None)
            original = identity(source, xls, helper, 4, build_profile)
            (source/'phi_device_3_config.json').write_text('new seed')
            (source/'phi_device_3_ram.v').write_text('new constant connections')
            self.assertEqual(original, identity(source, xls, helper, 4, build_profile))
            self.assertNotEqual(original, identity(source, xls, helper, 5, build_profile))
            table = root/'model.tsv'
            table.write_text('add 8 2 100 200\n')
            measured_profile = source/'measured-profile.json'
            emit(measured_profile, profile='test', initiation_interval=None, delay_model='xc7_7030')
            measured = identity(source, xls, helper, 4, measured_profile, table)
            self.assertNotEqual(original, measured)
            self.assertIn('--delay_model=xc7_7030', measured['flags'])
            table.write_text('add 8 2 100 300\n')
            self.assertNotEqual(measured, identity(source, xls, helper, 4, measured_profile, table))
            for policy, calibration in [(measured_profile, None), (build_profile, table)]:
                with self.assertRaisesRegex(ValueError, 'delay table'):
                    identity(source, xls, helper, 4, policy, calibration)
            policy_bytes = build_profile.read_bytes()
            changed = json.loads(policy_bytes)
            changed['profile']['postprocess']['completion_storage'] = 'lutram'
            build_profile.write_text(json.dumps(changed))
            with self.assertRaisesRegex(ValueError, 'completion storage'):
                identity(source, xls, helper, 4, build_profile)
            build_profile.write_bytes(policy_bytes)
            for path in (source/'actor.x', helper, xls/'opt_main', xls/'xls/dslx/stdlib/std.x'):
                previous = path.read_text()
                path.write_text(previous+' changed')
                self.assertNotEqual(original, identity(source, xls, helper, 4, build_profile))
                path.write_text(previous)

    def test_unsupported_storage_rejected_before_cache(self) -> None:
        """A tile cannot claim LUTRAM legalization that this adapter does not perform."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            source = stage / "source"
            source.mkdir()
            for name, text in [("tile_graph.x", "graph"), ("phi_tile.x", "top"),
                               ("device_0_graph.x", "graph"), ("phi_device_0.x", "top")]:
                (source / name).write_text(text)
            args = argparse.Namespace(stage=stage, xls=stage / "xls", tile_cache=stage / "cache")
            policy = {"profile": {"postprocess": {"completion_storage": "lutram"}}}
            with patch("phi_tiles.read_profile", return_value=policy), \
                    patch("phi_tiles.execute") as execute:
                with self.assertRaisesRegex(ValueError, "completion storage"):
                    prepare(args, [{"id": 0, "tile": True, "scheduler_count": 4}])
            execute.assert_not_called()
            self.assertFalse(args.tile_cache.exists())
            self.assertFalse((stage / "tile.json").exists())

    def test_modified_compiler_product(self) -> None:
        """A valid cache hit performs no compilation, and a modified RTL file is rejected."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, xls, public = root/'source', root/'xls', root/'public'
            source.mkdir()
            (xls/'xls/dslx/stdlib').mkdir(parents=True)
            (public/'tools').mkdir(parents=True)
            helper = public/'tools/phi_scheduler_rams.sh'
            helper.write_text('RAM ABI')
            for name in ('ir_converter_main', 'opt_main', 'codegen_main'):
                (xls/name).write_text('not executable: cache hits must not invoke this')
            for name, text in [('phi_tile.x', 'top'), ('tile_graph.x', 'graph'),
                               ('phi_device_0.x', 'top'), ('device_0_graph.x', 'graph')]:
                (source/name).write_text(text)
            build_profile = source/'build-profile.json'
            emit(build_profile, profile='test', initiation_interval=None)
            inputs = identity(source, xls, helper, 4, build_profile)
            key = hashlib.sha256(json.dumps(inputs, sort_keys=True).encode()).hexdigest()
            cache = root/'cache'/key
            cache.mkdir(parents=True)
            for name in ('phi_tile.ir', 'phi_tile.opt.ir', 'phi_tile.v'):
                (cache/name).write_text(name)
            (cache/'build-profile.json').write_bytes(build_profile.read_bytes())
            (cache/'complete.json').write_text(json.dumps({'inputs': inputs,
                'outputs': outputs(cache), 'seconds': {}}))
            args = argparse.Namespace(stage=root, xls=xls, erl_hls=public, tile_cache=root/'cache')
            devices = [{'id': 0, 'tile': True, 'scheduler_count': 4}]
            override = patch('phi_tiles.RAM_HELPER', helper)
            override.start()
            self.addCleanup(override.stop)
            self.assertEqual(prepare(args, devices), cache/'phi_tile.v')
            self.assertTrue(json.loads((root/'tile.json').read_text())['reused'])
            for name in ('phi_tile.v', 'build-profile.json'):
                with self.subTest(artifact=name):
                    path = cache/name
                    previous = path.read_bytes()
                    path.write_text('changed artifact')
                    with self.assertRaisesRegex(ValueError, 'tile cache changed'):
                        prepare(args, devices)
                    path.write_bytes(previous)

    def test_codegen_uses_selected_policy(self) -> None:
        """Only tile name and RAM wiring are appended to the authoritative scheduler flags."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, xls = root/'source', root/'xls'
            source.mkdir()
            (xls/'xls/dslx/stdlib').mkdir(parents=True)
            for name in ('ir_converter_main', 'opt_main', 'codegen_main'):
                (xls/name).write_text('compiler fixture')
            for name, text in [('phi_tile.x', 'top'), ('tile_graph.x', 'graph'),
                               ('phi_device_0.x', 'top'), ('device_0_graph.x', 'graph')]:
                (source/name).write_text(text)
            profile = emit(source/'build-profile.json', profile='test', stages=4,
                           initiation_interval=3, executor_result_delay=7)
            helper = root/'rams.sh'
            helper.write_text('RAM ABI')
            args = argparse.Namespace(stage=root, xls=xls, tile_cache=root/'cache')
            devices = [{'id': 0, 'tile': True, 'scheduler_count': 4}]

            def compile_fixture(command: list[str], stage: Path, name: str,
                                *, timeout: int, output: Path) -> None:
                """Supply deterministic artifacts while preserving the recorded command boundary."""
                output.write_text(name)

            with patch('phi_tiles.RAM_HELPER', helper), patch('phi_tiles.execute', compile_fixture), \
                    patch('phi_tiles.subprocess.check_output', return_value='fixture:1RW:1'), \
                    patch('phi_tiles.specialize'):
                rtl = prepare(args, devices)
            record = json.loads((rtl.parent/'complete.json').read_text())
            self.assertEqual(record['inputs']['build_profile'], profile)
            self.assertEqual(record['commands'][-1], [str(xls/'codegen_main'), *profile['codegen_flags'],
                '--module_name=phi_tile', '--ram_configurations=fixture:1RW:1', str(rtl.with_suffix('.opt.ir'))])
            self.assertEqual((rtl.parent/'build-profile.json').read_bytes(),
                             (source/'build-profile.json').read_bytes())

    def test_binding_uses_retained_policy_and_rejects_changes(self) -> None:
        """Bind the compiled policy only while both its cache and source bytes remain frozen."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            source, cache = stage / "source", stage / "cache"
            source.mkdir()
            cache.mkdir()
            source_profile = source / "build-profile.json"
            profile = emit(source_profile, profile="test", initiation_interval=None)
            policy_bytes = source_profile.read_bytes()
            profile_sha256 = hashlib.sha256(policy_bytes).hexdigest()
            retained_profile = cache / "build-profile.json"
            retained_profile.write_bytes(policy_bytes)
            (cache / "complete.json").write_text(json.dumps({
                "inputs": {"build_profile_sha256": profile_sha256}}))
            rtl = cache / "phi_tile.v"
            rtl.write_text("module phi_tile(); endmodule\n")
            (source / "phi_device_0_config.json").write_text("{}\n")
            (source / "phi_device_0_ram.v").write_text("module ram(); endmodule\n")
            args = argparse.Namespace(stage=stage)
            for path in (source_profile, retained_profile):
                with self.subTest(changed=path.parent.name):
                    path.write_bytes(policy_bytes + b"\n")
                    with self.assertRaisesRegex(ValueError, "build profile changed"):
                        bind(args, {"id": 0}, rtl)
                    self.assertFalse((stage / "device0").exists())
                    path.write_bytes(policy_bytes)
            bind(args, {"id": 0}, rtl)
            receipt = json.loads((stage / "device0/build.json").read_text())
            self.assertEqual(receipt["build_profile"], profile)
            self.assertEqual(receipt["build_profile_sha256"], profile_sha256)
            self.assertEqual((stage / "device0/phi_device_0.v").read_bytes(), rtl.read_bytes())

    def test_complete_source_congruence(self) -> None:
        """A different route or startup-table shape cannot silently share a tile."""
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            for name, text in [('tile_graph.x', 'graph'), ('phi_tile.x', 'top'),
                               ('device_0_graph.x', 'graph'), ('phi_device_0.x', 'top')]:
                (source/name).write_text(text)
            devices = [{'id': 0, 'tile': True}]
            check_sources(source, devices)
            (source/'device_0_graph.x').write_text('different route')
            with self.assertRaisesRegex(ValueError, 'different tile graph'):
                check_sources(source, devices)
            (source/'device_0_graph.x').write_text('graph')
            (source/'phi_device_0.x').write_text('different port')
            with self.assertRaisesRegex(ValueError, 'different tile wrapper'):
                check_sources(source, devices)


if __name__ == '__main__':
    unittest.main()
