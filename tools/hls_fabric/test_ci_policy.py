"""Keep the agreed automatic software gate and manual hardware tiers explicit."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PolicyTests(unittest.TestCase):
    """Prevent accidentally restoring the former grids or duplicate merge runs."""

    def test_pull_request_software_gate_and_manual_tiers(self) -> None:
        """Pull requests select software while hardware tiers remain explicit manual choices."""
        workflow = (ROOT / '.github/workflows/fabric-ci.yml').read_text()
        self.assertIn('  workflow_dispatch:', workflow)
        self.assertIn('  pull_request:', workflow)
        for trigger in ('  push:', '  schedule:'):
            self.assertNotIn(trigger, workflow)
        self.assertNotIn('matrix:', workflow)
        self.assertIn("github.event_name == 'pull_request' && 'software'", workflow)
        self.assertEqual(workflow.count("if: env.SUITE != 'software'"), 3)
        self.assertIn('bash tools/hls_fabric/ci.sh', workflow)

    def test_local_entrypoint_and_unit_inventory(self) -> None:
        """The local entry point parses in bash and names real, unique tooling test modules."""
        entrypoint = ROOT / 'tools/hls_fabric/ci.sh'
        subprocess.run(['bash', '-n', entrypoint], check=True)
        script = entrypoint.read_text()
        spacetime = 'rebar3 as spacetime compile'
        boundaries = ('python3 tools/hls_fabric/check_application_boundaries.py \\\n'
                      '        --profile default --profile spacetime')
        self.assertIn(spacetime, script)
        self.assertIn(boundaries, script)
        self.assertIn('bash tools/test_umbrella_eunit.sh boundaries', script)
        runtime_release = 'bash tools/hls_fabric/test_runtime_release.sh'
        external_consumers = 'python3 tools/test_external_consumers.py'
        self.assertIn(runtime_release, script)
        self.assertIn(external_consumers, script)
        self.assertLess(script.index(spacetime), script.index(boundaries))
        self.assertLess(script.index(runtime_release), script.index(external_consumers))
        local_distribution = (ROOT / 'tools/hls_fabric/test_local_dist.sh').read_text()
        self.assertIn('/../.." && pwd)', local_distribution)
        names = [line for line in (ROOT / 'tools/hls_fabric/ci_unit_tests.txt').read_text().splitlines()
                 if line and not line.startswith('#')]
        self.assertEqual(len(names), len(set(names)))
        for name in names:
            self.assertTrue(any((directory / (name.split('.')[0] + '.py')).is_file()
                for directory in [ROOT / 'tools/hls_fabric', ROOT / 'workloads/hls_phi/tools']), name)
        self.assertFalse(any('ci_plan' in name for name in names))
        xls_action = (ROOT / '.github/actions/xls-tools/action.yml').read_text()
        self.assertIn("hashFiles('tools/hls_fabric/xls_ram_codegen/manifest.json')", xls_action)
        self.assertIn('python3 tools/hls_fabric/xls_ram_codegen/install.py', xls_action)


if __name__ == '__main__':
    unittest.main()
