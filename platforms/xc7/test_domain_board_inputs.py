#!/usr/bin/env python3
"""Small offline image-input/gate regressions; no compiler, mapper or board runs."""

import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

from application import domain_board
from gtx.prepare import fetch
from xc7_resources import digest


def compiled_fixture(root: Path) -> dict:
    """Write one minimal ordinary release whose selected RTL is hash-bound."""
    rtl = root / "unit.v"
    rtl.write_text("module unit; endmodule\n")
    source = root / "source-build.json"
    source.write_text(json.dumps({"inputs": [], "units": [{"module": "unit", "rtl": ["unit.v"],
        "role": ".", "directory": ".", "output": "unit.v"}]}))
    compiled = root / "compiled.json"
    compiled.write_text(json.dumps({"source_build_sha256": digest(source),
        "rtl": {"unit": [{"file": "unit.v", "sha256": digest(rtl)}]},
        "units": [{"role": ".", "directory": ".", "commands": [
            {"stage": "codegen", "exit": 0, "output": "unit.v", "sha256": digest(rtl)}]}]}))
    return {"root": str(root), "source_build_sha256": digest(source),
            "compiled_sha256": digest(compiled), "modules": ["unit"]}


class DomainBoardInputsTests(unittest.TestCase):
    """Missing identity or failed predecessor evidence cannot dispatch physical tools."""

    def test_cleanup_error_preserves_original_log_guard(self) -> None:
        """A denied terminal group probe cannot hide the guard or invent group absence."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            (root / "oversized.log").write_text("xx")
            process = Mock(pid=123, returncode=-15)
            process.poll.return_value = None
            process.wait.return_value = -15
            with patch.object(domain_board.subprocess, "Popen", return_value=process), \
                    patch.object(domain_board, "LOG_LIMIT", 1), \
                    patch.object(domain_board, "stop_group", side_effect=PermissionError("probe denied")), \
                    patch.object(domain_board, "snapshot_group", return_value={"owned_group_gone": None}):
                with self.assertRaisesRegex(ValueError, "external phase failed"):
                    domain_board.command(["not-executed"], root, root, 10)
            record = json.loads((root / "execution.json").read_text())
            self.assertEqual(record["guard"], "log_size")
            self.assertIn("PermissionError", record["cleanup_error"])
            self.assertIsNone(record["owned_group_gone"])
            process.wait.assert_called_once_with(timeout=5)

    def test_group_snapshot_requires_complete_absence(self) -> None:
        """Complete snapshots distinguish absent/live owned groups; malformed output is unknown."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            for content, expected in (("1 1\n2 2\n", True), ("1 1\n124 123\n", False),
                                      ("1 1\ntruncated\n", None), ("", None)):
                def observed(*args, **kwargs):
                    kwargs["stdout"].write(content)
                    return Mock(returncode=0)
                with self.subTest(content=content), patch.object(domain_board.subprocess, "run", side_effect=observed):
                    result = domain_board.snapshot_group(123, root)
                    self.assertIs(result["owned_group_gone"], expected)

    def test_mapping_checkpoint_precedes_quiet_normalization(self) -> None:
        """The same synthesis is preserved before normalizing connection buffers quietly."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            frozen = {"sources": [], "role": 1, "yosys": "not-executed", "cwd": str(root)}
            with patch.object(domain_board, "command", side_effect=ValueError("stop before execution")):
                with self.assertRaisesRegex(ValueError, "stop before execution"):
                    domain_board.map_image(frozen, root)
            script = (root / "map.ys").read_text()
            self.assertLess(script.index("synth_xilinx"), script.index("raw-mapped.json"))
            self.assertLess(script.index("raw-mapped.json"), script.index("tee -q bufnorm -conn"))
            self.assertLess(script.index("tee -q bufnorm -conn"), script.index("check -assert"))

    def test_bundle_selection_and_changed_rtl(self) -> None:
        """One declared module is accepted; changing its RTL rejects the same release."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            row = compiled_fixture(root)
            inputs = {}
            _, sources = domain_board.bundle(row, inputs)
            self.assertEqual(sources, [root / "unit.v"])
            self.assertIn(str(root / "unit.v"), inputs)
            (root / "unit.v").write_text("changed\n")
            with self.assertRaisesRegex(ValueError, "changed input"):
                domain_board.bundle(row, {})

    def test_undeclared_or_unknown_rtl_rejected(self) -> None:
        """Extra RTL must be a checked member and selected modules must exist exactly once."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            row = compiled_fixture(root)
            (root / "rogue.v").write_text("module rogue; endmodule\n")
            with self.assertRaisesRegex(ValueError, "checked bundle member"):
                domain_board.bundle(row | {"extra_rtl": ["rogue.v"]}, {})
            with self.assertRaisesRegex(ValueError, "selected compiled unit"):
                domain_board.bundle(row | {"modules": ["missing"]}, {})

    def test_offline_donor_never_fetches(self) -> None:
        """Both missing and modified donors fail before any network operation."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            source = {"sha256": "0" * 64, "url": "https://invalid.example/source"}
            with patch("gtx.prepare.urllib.request.urlopen") as network:
                with self.assertRaisesRegex(ValueError, "missing offline source"):
                    fetch(source, root, offline=True)
                (root / source["sha256"]).write_bytes(b"wrong")
                with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                    fetch(source, root, offline=True)
                network.assert_not_called()

    def test_missing_codegen_receipt_rejected(self) -> None:
        """A file hash alone does not turn an incomplete compiler run into emitted RTL."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            row = compiled_fixture(root)
            path = root / "compiled.json"
            release = json.loads(path.read_text())
            release["units"][0]["commands"][0]["exit"] = 1
            path.write_text(json.dumps(release))
            row["compiled_sha256"] = digest(path)
            with self.assertRaisesRegex(ValueError, "successful compiler receipt"):
                domain_board.bundle(row, {})

    def test_every_readmem_dependency_is_bound(self) -> None:
        """A second unlisted initialization file or dynamic filename cannot evade hashing."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            source = root / "unit.v"
            (root / "first.init").write_text("00\n")
            (root / "second.init").write_text("01\n")
            inputs = {str(root / "first.init"): digest(root / "first.init")}
            source.write_text('$readmemh("first.init", a); $readmemh("second.init", b);\n')
            with self.assertRaisesRegex(ValueError, "not a checked input"):
                domain_board.readmem_inputs([source], root, inputs)
            inputs[str(root / "second.init")] = digest(root / "second.init")
            domain_board.readmem_inputs([source], root, inputs)
            source.write_text('$readmemh(FILE_PARAMETER, a);\n')
            with self.assertRaisesRegex(ValueError, "dynamic or escaping"):
                domain_board.readmem_inputs([source], root, inputs)

    def test_unattributed_luts_cannot_pass_link_screen(self) -> None:
        """FF ownership labels cannot make 9000 global ABC LUTs disappear from link cost."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            cells = {prefix + "owner_ff": {"type": "FDRE"}
                     for prefix in domain_board.GROUPS.values()}
            cells.update({f"$abc$global{i}": {"type": "LUT1"} for i in range(9000)})
            (root / "netlist.json").write_text(json.dumps({"modules": {domain_board.TOP: {"cells": cells}}}))
            frozen = {"sources": [], "role": 1, "yosys": "not-executed", "cwd": str(root)}
            with patch.object(domain_board, "command"), patch.object(domain_board, "inspect",
                    return_value={"debug_observation": []}):
                result = domain_board.map_image(frozen, root)
            self.assertTrue(result["whole_image_passes"])
            self.assertFalse(result["component_screen_passes"])
            self.assertFalse(result["route_admitted"])

    def test_failed_or_changed_mapping_cannot_route(self) -> None:
        """A whole-image pass cannot replace failed link admission or changed input identity."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            (root / "map").mkdir()
            (root / "inputs.json").write_text("{}\n")
            result = {"success": True, "whole_image_passes": True, "route_admitted": False,
                      "input_manifest_sha256": digest(root / "inputs.json")}
            target = root / "map/result.json"
            target.write_text(json.dumps(result))
            with patch.object(domain_board, "command") as execute:
                with self.assertRaisesRegex(ValueError, "component screen blocks"):
                    domain_board.route_image({}, root / "route")
                target.write_text(json.dumps(result | {"input_manifest_sha256": "0" * 64}))
                with self.assertRaisesRegex(ValueError, "another frozen input"):
                    domain_board.route_image({}, root / "route")
                execute.assert_not_called()


if __name__ == "__main__":
    unittest.main()
