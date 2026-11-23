"""Exercise clock gates in the actual image driver with small saved-tool fixtures only."""

import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from application import domain_board as board
from application import domain_board_clocks as clocks


def module(stage: str) -> dict:
    """Describe only the clock nets and MMCM evidence consumed by the driver."""
    cells = {}
    for name, bel in clocks.MMCMS.items():
        cells[name] = {"type": "MMCME2_BASE" if stage == "mapped" else "MMCME2_ADV_MMCME2_ADV",
                       "attributes": {} if stage == "mapped" else {
                           "BEL" if stage == "packed" else "NEXTPNR_BEL": bel}}
    return {"netnames": {name: {"bits": [index + 2]} for index, name in enumerate(clocks.CLOCKS)},
            "cells": cells}


def timing() -> dict:
    """Supply the five exact targets with positive synthetic margin."""
    return {"fmax": {name: {"constraint": frequency, "achieved": frequency + 1}
                     for name, frequency in clocks.CLOCKS.items()}}


class DomainBoardRouteTests(unittest.TestCase):
    """Missing coverage stops implementation; altered evidence or timing failure stops assembly."""

    def fixture(self, root: Path) -> dict:
        """Create a previously admitted map and its exact small input identities."""
        mapped = root / "map"
        mapped.mkdir()
        (root / "route").mkdir()
        board.save(root / "inputs.json", {})
        board.save(mapped / "netlist.json", {"modules": {board.TOP: module("mapped")}})
        for name in ("resources.json", "link-screen.json"):
            board.save(mapped / name, {})
        board.save(mapped / "result.json", {
            "success": True, "route_admitted": True,
            "input_manifest_sha256": board.digest(root / "inputs.json"),
            "netlist_sha256": board.digest(mapped / "netlist.json"),
            "resources_sha256": board.digest(mapped / "resources.json"),
            "link_screen_sha256": board.digest(mapped / "link-screen.json")})
        return {"nextpnr": "not-executed", "chipdb": "not-read", "cwd": str(root),
                "database": str(root),
                "constraints": str(Path(__file__).parent / "ethernet/te0715_ethernet.xdc")}

    def route(self, root: Path, frozen: dict, reports: dict, calls: list[str]) -> dict:
        """Replace native execution with deterministic packed/routed files, keeping real clock checks."""
        def execute(argv: list[str], cwd: Path, directory: Path, seconds: int) -> dict:
            """Materialize one selected fake tool result; never spawn a process."""
            stage = "packed" if "--pack-only" in argv else "routed"
            calls.append(stage)
            xdc = Path(argv[argv.index("--xdc") + 1]).read_text()
            for name in clocks.CLOCKS:
                self.assertIn(f"[get_nets {name}]", xdc)
            board.save(Path(argv[argv.index("--write") + 1]), {"modules": {board.TOP: module(stage)}})
            board.save(Path(argv[argv.index("--report") + 1]), reports[stage])
            Path(argv[argv.index("--log") + 1]).write_text("Info: fixture completed\n")
            if stage == "routed":
                Path(argv[argv.index("--fasm") + 1]).write_text("fixture\n")
            return {"owned_group_gone": True}

        with patch.object(board, "command", side_effect=execute), \
                patch.object(board, "check_luts", return_value={"passed": True}), \
                patch.object(board, "audit_database", return_value={}):
            result = board.route_image(frozen, root / "route")
        result.update(success=True, input_manifest_sha256=board.digest(root / "inputs.json"))
        board.save(root / "route/result.json", result)
        return result

    def test_incomplete_pack_coverage_stops_before_implementation(self) -> None:
        """A native pack report missing one clock cannot launch placement/routing."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            frozen, calls = self.fixture(root), []
            packed = timing()
            del packed["fmax"]["clocks.rx_half_clock"]
            with self.assertRaisesRegex(ValueError, "exactly the five"):
                self.route(root, frozen, {"packed": packed, "routed": timing()}, calls)
            self.assertEqual(calls, ["packed"])
            self.assertFalse((root / "route/implementation").exists())

    def test_incomplete_routed_coverage_cannot_publish_a_route(self) -> None:
        """A successful pack cannot substitute for complete routed clock evidence."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            frozen, calls = self.fixture(root), []
            routed = timing()
            del routed["fmax"]["application.clk"]
            with self.assertRaisesRegex(ValueError, "exactly the five"):
                self.route(root, frozen, {"packed": timing(), "routed": routed}, calls)
            self.assertEqual(calls, ["packed", "routed"])
            self.assertFalse((root / "route/result.json").exists())

    def test_complete_coverage_is_bound_before_assembly(self) -> None:
        """Both real validation stages feed assembly; changing retained coverage blocks execution."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            frozen, calls = self.fixture(root), []
            result = self.route(root, frozen, {"packed": timing(), "routed": timing()}, calls)
            self.assertEqual(calls, ["packed", "routed"])
            self.assertTrue(result["modeled_targets_met"])
            coverage_path = root / "route/clock-coverage.json"
            coverage = json.loads(coverage_path.read_text())
            self.assertTrue(coverage["packed"]["clock_coverage_complete"])
            self.assertTrue(coverage["routed"]["clock_coverage_complete"])
            assembled = root / "assemble"
            assembled.mkdir()
            (assembled / "image").mkdir()
            board.save(assembled / "image/result.json", {"hardware_qualified": False})
            with patch.object(board, "command") as execute:
                self.assertFalse(board.assemble_image(frozen, assembled)["hardware_qualified"])
                execute.assert_called_once()
            coverage["routed"]["clock_coverage_complete"] = False
            board.save(coverage_path, coverage)
            with patch.object(board, "command") as execute:
                with self.assertRaisesRegex(ValueError, "changed clock evidence"):
                    board.assemble_image(frozen, assembled)
                execute.assert_not_called()
            result["clock_coverage_sha256"] = board.digest(coverage_path)
            board.save(root / "route/result.json", result)
            with patch.object(board, "command") as execute:
                with self.assertRaisesRegex(ValueError, "incomplete clock coverage"):
                    board.assemble_image(frozen, assembled)
                execute.assert_not_called()

    def test_complete_but_slow_route_still_blocks_assembly(self) -> None:
        """Clock coverage alone cannot admit assembly when a modeled target is missed."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            frozen, calls = self.fixture(root), []
            routed = timing()
            routed["fmax"]["application.clk"]["achieved"] = 24.9
            result = self.route(root, frozen, {"packed": timing(), "routed": routed}, calls)
            self.assertFalse(result["modeled_targets_met"])
            with patch.object(board, "command") as execute:
                with self.assertRaisesRegex(ValueError, "failed modeled timing"):
                    board.assemble_image(frozen, root / "assemble")
                execute.assert_not_called()


if __name__ == "__main__":
    unittest.main()
