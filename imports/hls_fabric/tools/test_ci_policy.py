"""Keep the agreed CI budget boundary explicit while automatic Actions remain suspended."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PolicyTests(unittest.TestCase):
    """Prevent accidentally restoring the former grids or automatic duplicate runs."""

    def test_manual_single_workflow(self) -> None:
        """No automatic trigger or unreviewed workflow bypasses the local qualification period."""
        workflows = list((ROOT / '.github/workflows').glob('*.yml'))
        self.assertEqual([p.name for p in workflows], ['ci.yml'])
        workflow = workflows[0].read_text()
        self.assertIn('  workflow_dispatch:', workflow)
        for trigger in ('  pull_request:', '  push:', '  schedule:'):
            self.assertNotIn(trigger, workflow)
        self.assertNotIn('matrix:', workflow)

    def test_local_entrypoint_and_unit_inventory(self) -> None:
        """The local entry point parses in bash and names real, unique tooling test modules."""
        subprocess.run(['bash', '-n', ROOT / 'tools/ci.sh'], check=True)
        names = [line for line in (ROOT / 'tools/ci_unit_tests.txt').read_text().splitlines()
                 if line and not line.startswith('#')]
        self.assertEqual(len(names), len(set(names)))
        for name in names:
            self.assertTrue((ROOT / 'tools' / (name.split('.')[0] + '.py')).is_file(), name)
        self.assertFalse(any('ci_plan' in name for name in names))


if __name__ == '__main__':
    unittest.main()
