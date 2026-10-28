"""Check artifact integrity for both Phi harness ownership modes without invoking hardware tools."""
import phi_tool_paths  # Resolve shared tooling for this application.
import json
from pathlib import Path
import tempfile
import unittest
from phi_build_artifacts import bridge_outputs, read_bridge_build


class BuildArtifactsTests(unittest.TestCase):
    """An omitted harness must not excuse missing or changed device artifacts."""

    def test_device_only_checks_actual_device_files(self) -> None:
        """Profiling can supply its own harness while all emitted device bytes remain bound."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'device0').mkdir()
            rtl = root / 'device0/core.v'
            rtl.write_text('module fixture; endmodule\n')
            (root / 'phi_devices.vh').write_text('// ports\n')
            record = {'inputs': {'config': {'devices_only': True}},
                      'outputs': bridge_outputs(root, devices_only=True)}
            (root / 'provenance.json').write_text(json.dumps(record))
            self.assertEqual(read_bridge_build(root), record)
            rtl.write_text('module changed; endmodule\n')
            with self.assertRaisesRegex(ValueError, 'artifacts|instrumentation'):
                read_bridge_build(root)

    def test_existing_mode_still_requires_harness(self) -> None:
        """Records without the optional mode flag retain their original required-adapter contract."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'phi_devices.vh').write_text('// ports\n')
            harness = root / 'phi_bridge.vvp'
            harness.write_text('simulation\n')
            record = {'inputs': {'config': {}}, 'outputs': bridge_outputs(root)}
            (root / 'provenance.json').write_text(json.dumps(record))
            self.assertEqual(read_bridge_build(root), record)
            harness.unlink()
            with self.assertRaises(FileNotFoundError):
                read_bridge_build(root)


if __name__ == '__main__':
    unittest.main()
