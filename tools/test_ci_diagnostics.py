#!/usr/bin/env python3
"""Check storage bounds and preservation of useful failure information."""
from pathlib import Path
import tempfile
import unittest
import zipfile

from ci_diagnostics import FILE_BYTES, FILE_COUNT, TOTAL_BYTES, collect


class DiagnosticsTests(unittest.TestCase):
    """Large compiler outputs cannot crowd out small reports or grow uploads."""

    def test_report_log_tail_and_netlist(self) -> None:
        """Keep complete reports and the final error; omit netlists and huge JSON."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "result.json").write_text('{"passed": false}')
            (root / "compile.log").write_bytes(b"x" * FILE_BYTES + b"final error")
            (root / "large.json").write_bytes(b"x" * (FILE_BYTES + 1))
            (root / "flat.json").write_text("netlist")
            (root / "link.json").symlink_to(root / "result.json")
            bundle = root / "result.zip"
            report = collect(root, ["*.json", "*.log", "result.json"], bundle)
            with zipfile.ZipFile(bundle) as archive:
                self.assertEqual(set(archive.namelist()),
                                 {"result.json", "compile.log", "diagnostics-index.json"})
                self.assertTrue(archive.read("compile.log").endswith(b"final error"))
                self.assertEqual(len(archive.read("compile.log")), FILE_BYTES)
            self.assertEqual(report["matched_files"], 4)

    def test_total_and_file_count_limits(self) -> None:
        """Repeated diagnostics obey both the byte budget and index-entry limit."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for index in range(FILE_COUNT + 1):
                with (root / f"{index:03}.log").open("wb") as stream:
                    stream.truncate(FILE_BYTES)
            bundle = root / "result.zip"
            report = collect(root, ["*.log"], bundle)
            self.assertEqual(report["payload_bytes"], TOTAL_BYTES)
            self.assertEqual(len(report["files"]), FILE_COUNT)
            self.assertEqual(report["unlisted_files"], 1)
            self.assertTrue(any(f.get("omitted") == "bundle limit" for f in report["files"]))

    def test_empty_and_external_paths(self) -> None:
        """Early failures yield an index; globs cannot include external files."""
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory)
            root = parent / "root"
            root.mkdir()
            (parent / "outside.log").write_text("outside")
            report = collect(root, ["../*.log", "missing/**"], root / "empty.zip")
            self.assertEqual(report["matched_files"], 0)

    def test_workflow_upload_policy(self) -> None:
        """Every workflow upload is bounded and gated on failure or explicit opt-in."""
        root = Path(__file__).resolve().parents[1]
        for path in (root / ".github/workflows").glob("*.yml"):
            text = path.read_text()
            self.assertNotIn("uses: actions/upload-artifact@", text, path)
            for prefix in text.split("uses: ./.github/actions/diagnostics")[:-1]:
                self.assertIn("if: failure() || inputs.diagnostics == true", prefix.split("- name:")[-1], path)


if __name__ == "__main__":
    unittest.main()
