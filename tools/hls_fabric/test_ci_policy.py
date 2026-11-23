"""Keep the agreed CI budget boundary explicit while automatic Actions remain suspended."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PolicyTests(unittest.TestCase):
    """Prevent accidentally restoring the former grids or automatic duplicate runs."""

    def test_manual_single_workflow(self) -> None:
        """The Fabric tier stays manual while unrelated umbrella checks retain their policy."""
        workflow = (ROOT / '.github/workflows/fabric-ci.yml').read_text()
        self.assertIn('  workflow_dispatch:', workflow)
        for trigger in ('  pull_request:', '  push:', '  schedule:'):
            self.assertNotIn(trigger, workflow)
        self.assertNotIn('matrix:', workflow)
        self.assertIn('bash tools/hls_fabric/ci.sh', workflow)

    def test_local_entrypoint_and_unit_inventory(self) -> None:
        """The local entry point parses in bash and names real, unique tooling test modules."""
        subprocess.run(['bash', '-n', ROOT / 'tools/hls_fabric/ci.sh'], check=True)
        names = [line for line in (ROOT / 'tools/hls_fabric/ci_unit_tests.txt').read_text().splitlines()
                 if line and not line.startswith('#')]
        self.assertEqual(len(names), len(set(names)))
        for name in names:
            self.assertTrue(any((directory / (name.split('.')[0] + '.py')).is_file()
                for directory in [ROOT / 'tools/hls_fabric', ROOT / 'apps/hls_phi/tools']), name)
        self.assertFalse(any('ci_plan' in name for name in names))
        xls_action = (ROOT / '.github/actions/xls-tools/action.yml').read_text()
        self.assertIn("hashFiles('tools/hls_fabric/xls_ram_codegen/manifest.json')", xls_action)
        self.assertIn('python3 tools/hls_fabric/xls_ram_codegen/install.py', xls_action)


if __name__ == '__main__':
    unittest.main()
