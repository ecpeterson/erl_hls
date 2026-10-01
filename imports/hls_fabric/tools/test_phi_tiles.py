"""Check the cache boundary between constant bindings and compiled behavior."""
import argparse
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from phi_tiles import check_sources, identity, outputs, prepare


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
            original = identity(source, xls, helper, 4)
            (source/'phi_device_3_config.json').write_text('new seed')
            (source/'phi_device_3_ram.v').write_text('new constant connections')
            self.assertEqual(original, identity(source, xls, helper, 4))
            self.assertNotEqual(original, identity(source, xls, helper, 5))
            table = root/'model.tsv'
            table.write_text('add 8 2 100 200\n')
            measured = identity(source, xls, helper, 4, 'xc7_7030', table)
            self.assertNotEqual(original, measured)
            self.assertIn('--delay_model=xc7_7030', measured['flags'])
            table.write_text('add 8 2 100 300\n')
            self.assertNotEqual(measured, identity(source, xls, helper, 4, 'xc7_7030', table))
            for model, calibration in [('xc7_7030', None), ('unit', table)]:
                with self.assertRaisesRegex(ValueError, 'delay table'):
                    identity(source, xls, helper, 4, model, calibration)
            for path in (source/'actor.x', helper, xls/'opt_main', xls/'xls/dslx/stdlib/std.x'):
                previous = path.read_text()
                path.write_text(previous+' changed')
                self.assertNotEqual(original, identity(source, xls, helper, 4))
                path.write_text(previous)

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
            inputs = identity(source, xls, helper, 4)
            key = hashlib.sha256(json.dumps(inputs, sort_keys=True).encode()).hexdigest()
            cache = root/'cache'/key
            cache.mkdir(parents=True)
            for name in ('phi_tile.ir', 'phi_tile.opt.ir', 'phi_tile.v'):
                (cache/name).write_text(name)
            (cache/'complete.json').write_text(json.dumps({'inputs': inputs,
                'outputs': outputs(cache), 'seconds': {}}))
            args = argparse.Namespace(stage=root, xls=xls, erl_hls=public, tile_cache=root/'cache')
            devices = [{'id': 0, 'tile': True, 'scheduler_count': 4}]
            override = patch('phi_tiles.RAM_HELPER', helper)
            override.start()
            self.addCleanup(override.stop)
            self.assertEqual(prepare(args, devices), cache/'phi_tile.v')
            self.assertTrue(json.loads((root/'tile.json').read_text())['reused'])
            (cache/'phi_tile.v').write_text('changed RTL')
            with self.assertRaisesRegex(ValueError, 'tile cache changed'):
                prepare(args, devices)

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
