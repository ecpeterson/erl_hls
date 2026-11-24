#!/usr/bin/env python3
"""Check the portable host-source closure and its fresh staging contract."""
from pathlib import Path
import subprocess
import tempfile
import unittest

from portable_host_sources import ADDITIONAL_SOURCES, HOST_SOURCE_ROOTS, ROOT, source_paths


class PortableHostSourceTests(unittest.TestCase):
    """Keep the bridge payload complete across application moves and additions."""

    def test_inventory_covers_every_owned_source(self) -> None:
        """Core and selected runtime roots are exhaustive rather than a module allowlist."""
        expected = set(ADDITIONAL_SOURCES)
        for relative in HOST_SOURCE_ROOTS:
            expected.update(path.relative_to(ROOT) for path in (ROOT / relative).rglob("*.erl"))
        actual = source_paths()
        self.assertEqual(set(actual), expected)
        self.assertEqual(actual, sorted(actual))
        self.assertIn(Path("apps/hls_core/src/api/hls_type.erl"), actual)

    def test_fresh_payload_compiles_in_an_empty_beam_directory(self) -> None:
        """The staged core/runtime closure compiles without a stale source or BEAM cache."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory) / "stage"
            subprocess.run(["bash", "tools/stage_host_sources.sh", stage], cwd=ROOT, check=True)
            host_sources = stage / "portable_host_sources"
            test_sources = stage / "portable_test_sources"
            beam = stage / "beam"
            beam.mkdir()
            subprocess.run(["erlc", "-o", beam, host_sources / "hls_type.erl"], check=True)
            subprocess.run(["erlc", "-pa", beam, "-o", beam,
                            *sorted(host_sources.glob("*.erl"))], check=True)
            subprocess.run(["erlc", "-pa", beam, "-o", beam,
                            test_sources / "regsvc_cpu_tests.erl"], check=True)
            self.assertEqual(len(list(beam.glob("*.beam"))), len(source_paths()) + 1)
            stale = subprocess.run(
                ["bash", "tools/stage_host_sources.sh", stage],
                cwd=ROOT, text=True, capture_output=True, check=False,
            )
            self.assertNotEqual(stale.returncode, 0)
            self.assertIn("source payload already exists", stale.stderr)

    def test_payload_names_are_role_based_in_every_transfer_script(self) -> None:
        """Ordinary, Fabric and Phi producers and consumers share both payload names."""
        scripts = [
            "tools/stage_host_sources.sh", "tools/prepare_xls_sim.sh",
            "tools/remote_xls_sim.sh", "tools/run_xls_sim.sh",
            "tools/hls_fabric/prepare_xls_sim.sh", "tools/hls_fabric/remote_xls_sim.sh",
            "tools/hls_fabric/run_xls_sim.sh", "workloads/hls_phi/tools/remote_phi_memory_demo.sh",
            "workloads/hls_phi/tools/run_phi_memory_demo.sh",
        ]
        for relative in scripts:
            with self.subTest(script=relative):
                text = (ROOT / relative).read_text()
                self.assertNotIn("erl_src", text)
                self.assertNotIn("test_src", text)
                self.assertNotIn("host_runtime_src", text)
                self.assertNotIn("host_test_src", text)
                if relative == "tools/prepare_xls_sim.sh":
                    self.assertIn("stage_host_sources.sh", text)
                else:
                    self.assertIn("portable_host_sources", text)
                    self.assertIn("portable_test_sources", text)


if __name__ == "__main__":
    unittest.main()
