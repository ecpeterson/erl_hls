"""Regression cases for shared LUT slots and conflicting, foreign or absent route evidence."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "priv/tools"))
from openxc7_endpoints import lut_endpoint


class EndpointTests(unittest.TestCase):
    def test_packed_bit_and_unique_physical_slot(self) -> None:
        """Both halves share candidate switches, but each must own the net on its packed port."""
        cells = {
            half: {
                "type": "SLICE_LUTX",
                "attributes": {"NEXTPNR_BEL": f"SLICE_X1Y2/D{half}LUT"},
                "connections": {"A2": [int(half)]},
            }
            for half in ("5", "6")
        }
        top = {"cells": cells, "netnames": {"n": {"bits": [5]}}}
        key, hit = ("SLICE_X1Y2", "D", 2), ("SITEWIRE/SLICE_X1Y2/D3", "tile/10.11")

        def match(cell: str, candidates: dict) -> tuple | None:
            return lut_endpoint(
                top, "n", cell, "A2", "SITEWIRE/SLICE_X1Y2/D2", candidates
            )

        self.assertEqual(match("5", {key: [hit]}), hit)
        self.assertIsNone(match("6", {key: [hit]}))
        self.assertIsNone(match("5", {key: [hit, hit]}))
        self.assertIsNone(match("5", {("SLICE_X0Y0", "D", 2): [hit]}))
        self.assertIsNone(match("5", {}))


if __name__ == "__main__":
    unittest.main()
