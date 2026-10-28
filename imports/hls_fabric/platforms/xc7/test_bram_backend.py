#!/usr/bin/env python3
"""Check the native RAMB36 SDP72 FASM audit."""

import importlib.util
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parent / "bram/check_backend.py"
SPEC = importlib.util.spec_from_file_location("check_bram_backend", SCRIPT)
assert SPEC and SPEC.loader
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)

YOSYS_SCRIPT = Path(__file__).resolve().parent / "bram/check_yosys.py"
YOSYS_SPEC = importlib.util.spec_from_file_location("check_bram_yosys", YOSYS_SCRIPT)
assert YOSYS_SPEC and YOSYS_SPEC.loader
YOSYS_CHECK = importlib.util.module_from_spec(YOSYS_SPEC)
YOSYS_SPEC.loader.exec_module(YOSYS_CHECK)


class BramBackendTest(unittest.TestCase):
    """Exercise vendor-matched width-feature acceptance and omission detection."""

    def setUp(self) -> None:
        """Create one routed SDP72 cell and its site-to-tile mapping."""
        self.routed = {"modules": {"top": {"cells": {"memory": {
            "type": "RAMB36E1_RAMB36E1",
            "parameters": {"RAM_MODE": "SDP", "READ_WIDTH_A": f"{72:032b}",
                           "WRITE_WIDTH_B": f"{72:032b}"},
            "attributes": {"NEXTPNR_BEL": "RAMB36_X2Y39/RAMB36E1"}}}}}}
        self.grid = {"BRAM_L_X22Y195": {"sites": {"RAMB36_X2Y39": "RAMB36E1"}}}
        self.features = {
            f"BRAM_L_X22Y195.RAMB18_Y{half}.{feature}"
            for half in (0, 1)
            for feature in (
                "IN_USE", "READ_WIDTH_A_18", "READ_WIDTH_B_18",
                "SDP_READ_WIDTH_36", "SDP_WRITE_WIDTH_36",
                "WRITE_WIDTH_A_18", "WRITE_WIDTH_B_18")}

    def test_vendor_width_profile_passes(self) -> None:
        """Accept both underlying halves when all vendor width markers exist."""
        result = CHECK.audit(self.routed, self.grid, "\n".join(sorted(self.features)))
        self.assertTrue(result["passed"])
        self.assertEqual(result["required_features_per_tile"], 14)

    def test_missing_a_side_write_marker_fails(self) -> None:
        """Reject the historical encoding that loses each A-side parity bit."""
        broken = {feature for feature in self.features
                  if not feature.endswith("WRITE_WIDTH_A_18")}
        with self.assertRaisesRegex(ValueError, "WRITE_WIDTH_A_18"):
            CHECK.audit(self.routed, self.grid, "\n".join(sorted(broken)))


class BramYosysTest(unittest.TestCase):
    """Exercise the SDP72 parity mapping guards."""

    def cell(self, upper: list[int]) -> dict:
        """Return one mapped SDP72 primitive with caller-selected upper parity nets."""
        return {"type": "RAMB36E1",
                "parameters": {"RAM_MODE": "SDP", "READ_WIDTH_A": f"{72:032b}",
                               "WRITE_WIDTH_B": f"{72:032b}"},
                "connections": {"DIPADIP": [1, 2, 3, 4], "DIPBDIP": upper}}

    def test_correct_library_and_distinct_probe_pass(self) -> None:
        """Accept the width-72 selector and four independent upper parity inputs."""
        library = ".DIPBDIP(PORT_W_WIDTH == 72 ? DIP[7:4] : DIP[3:0])"
        netlist = {"modules": {"top": {"cells": {"memory": self.cell([5, 6, 7, 8])}}}}
        self.assertTrue(YOSYS_CHECK.audit_library(library)["passed"])
        self.assertTrue(YOSYS_CHECK.audit_probe_netlist(netlist)["passed"])

    def test_width_71_typo_fails(self) -> None:
        """Reject the released typo that makes a width-72 port select lower parity."""
        library = ".DIPBDIP(PORT_W_WIDTH == 71 ? DIP[7:4] : DIP[3:0])"
        with self.assertRaisesRegex(ValueError, "compares with 71"):
            YOSYS_CHECK.audit_library(library)

    def test_copied_probe_parity_fails(self) -> None:
        """Reject the exact faulty netlist signature seen in the physical probe."""
        netlist = {"modules": {"top": {"cells": {"memory": self.cell([1, 2, 3, 4])}}}}
        with self.assertRaisesRegex(ValueError, "upper parity copies lower parity"):
            YOSYS_CHECK.audit_probe_netlist(netlist)


if __name__ == "__main__":
    unittest.main()
