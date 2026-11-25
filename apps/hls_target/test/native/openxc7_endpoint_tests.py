"""Regression cases for shared LUT slots and conflicting, foreign or absent route evidence."""

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "priv/tools"))
from openxc7_endpoints import lut_endpoint
from openxc7_tree import RouteTree


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

    def test_disconnected_tie_requires_observed_cut(self) -> None:
        """Follow the sink up to its actual tie and reject incompatible rails and absent endpoints."""
        source, sink = "$PACKER_GND_DRV/Y", "lut/A1"
        start, end, local = "NULL/PSEUDO_GND_WIRE_GLBL", "SITEWIRE/S/A1", "INT/GND_WIRE"
        net = "$PACKER_GND_NET"
        wires = [start, end, local]
        grid = SimpleNamespace(owners={"INT": 0}, wire_key=lambda tile, index: index)
        names = SimpleNamespace(grid=grid, name=wires.__getitem__)
        decoder = SimpleNamespace(identify=lambda *args: ())
        tree = RouteTree(
            names, decoder, f"{start};;1;{end};{local}->{end};1", ["INT/2.1"]
        )
        top = {
            "cells": {
                "$PACKER_GND_DRV": {"connections": {"Y": [1]}},
                "lut": {"connections": {"A1": [1]}},
            },
            "netnames": {net: {"bits": [1]}},
        }
        timing = {
            "$PACKER_GND_DRV": {
                "ports": {"Y": {"net": net, "wire": start, "direction": "OUT"}}
            },
            "lut": {
                "ports": {
                    "A1": {"net": net, "wire": end, "direction": "IN", "bel_pin": "A1"}
                }
            },
        }
        self.assertEqual(
            tree.branch(top, timing, net, source, sink),
            ("disconnected_constant", None, [], None, local),
        )
        tree.parent[end] = ("INT/VCC_WIRE", "INT/2.1", "other", 0)
        self.assertEqual(tree.branch(top, timing, net, source, sink)[0], "unavailable")
        timing["lut"]["ports"]["A1"]["net"] = "foreign"
        self.assertEqual(
            tree.branch(top, timing, net, source, sink)[0], "missing_endpoint"
        )
        with self.assertRaisesRegex(ValueError, "unaccounted PIPs"):
            RouteTree(names, decoder, f"{end};{local}->{end};1", [])


if __name__ == "__main__":
    unittest.main()
