#!/usr/bin/env python3
"""Check local DSLX refreshes and ensure stale or missing artifacts fail closed."""

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


# Checked source artifacts are the public contract of the refresh command.
ARTIFACTS = {
    "regsvc.x": "src/examples/regsvc/regsvc.erl.x",
    "phi_halo_cell.x": "src/examples/phi_decoder/phi_halo_cell.erl.x",
    "phenom_data_cell.x": "src/examples/phi_decoder/phenom_data_cell.erl.x",
    "phenom_syndrome_cell.x": "src/examples/phi_decoder/phenom_syndrome_cell.erl.x",
    "phi_phenom_topology.x": "src/examples/phi_decoder/phi_phenom_topology.x",
    "phi_torus_topology.x": "src/examples/phi_decoder/phi_torus_topology.x",
    "phi_noise_topology.x": "src/examples/phi_decoder/phi_noise_topology.x",
}


class GoldenTests(unittest.TestCase):
    """Exercise the shell command in an isolated repository without any RTL."""

    def setUp(self) -> None:
        """Create matching staged and checked DSLX, with spaces in their paths."""
        temporary = tempfile.TemporaryDirectory(prefix="dslx goldens ")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.stage = self.root / "staged DSLX"
        self.stage.mkdir()
        (self.root / "tools").mkdir()
        self.script = self.root / "tools/xls_goldens.sh"
        shutil.copyfile(Path(__file__).with_name("xls_goldens.sh"), self.script)
        for generated, checked in ARTIFACTS.items():
            content = f"// {generated}\npub const VALUE = u32:1;\n"
            (self.stage / generated).write_text(content)
            destination = self.root / checked
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(content)

    def run_goldens(self, mode: str) -> subprocess.CompletedProcess[str]:
        """Invoke the command from outside its repository root."""
        return subprocess.run(
            ["bash", str(self.script), mode, str(self.stage)],
            cwd=self.stage, capture_output=True, text=True, timeout=10,
            check=False,
        )

    def test_check_needs_only_dslx(self) -> None:
        """Matching source passes without RTL files or an RTL digest manifest."""
        result = self.run_goldens("check")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_changed_source_fails_without_rewriting(self) -> None:
        """A mismatch names its checked source and leaves that source intact."""
        checked = self.root / ARTIFACTS["regsvc.x"]
        before = checked.read_bytes()
        (self.stage / "regsvc.x").write_text("pub const VALUE = u32:2;\n")
        result = self.run_goldens("check")
        self.assertEqual(result.returncode, 1)
        self.assertIn(ARTIFACTS["regsvc.x"], result.stderr)
        self.assertEqual(checked.read_bytes(), before)

    def test_update_copies_dslx_without_rtl(self) -> None:
        """Refresh changed source locally, then require the check to pass."""
        (self.stage / "regsvc.x").write_text("pub const VALUE = u32:2;\n")
        result = self.run_goldens("update")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.run_goldens("check").returncode, 0)
        for generated, checked in ARTIFACTS.items():
            self.assertEqual(
                (self.stage / generated).read_bytes(),
                (self.root / checked).read_bytes(),
            )
        self.assertFalse((self.root / "test/golden/xls_verilog.sha256").exists())

    def test_missing_input_prevents_partial_update(self) -> None:
        """Validate the complete input set before changing any checked file."""
        checked = self.root / ARTIFACTS["regsvc.x"]
        before = checked.read_bytes()
        (self.stage / "regsvc.x").write_text("pub const VALUE = u32:2;\n")
        (self.stage / "phi_noise_topology.x").unlink()
        result = self.run_goldens("update")
        self.assertEqual(result.returncode, 1)
        self.assertIn("missing generated artifact", result.stderr)
        self.assertEqual(checked.read_bytes(), before)

    def test_missing_checked_source_fails(self) -> None:
        """Checking cannot silently accept a deleted generated source file."""
        (self.root / ARTIFACTS["regsvc.x"]).unlink()
        result = self.run_goldens("check")
        self.assertEqual(result.returncode, 1)
        self.assertIn("missing checked-in artifact", result.stderr)


if __name__ == "__main__":
    unittest.main()
