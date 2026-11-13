#!/usr/bin/env python3
"""Synthetic resource-accounting regressions; no synthesis or board access."""

import sys
import tempfile
import unittest
from pathlib import Path

from map_xc7_resources import group_exists, run_tool, script
from xc7_resources import bounds, counts, mapped, module, placed_luts, report


def netlist(cells: dict) -> dict:
    """Wrap an explicit top; a library definition must not add resource instances."""
    return {"modules": {"top": {"cells": cells},
                        "LUT6": {"cells": {"library_only": {"type": "LUT6"}}}}}


def cell(kind: str, bel: str | None = None, origin: str = "LUT5") -> dict:
    """Provide only the primitive metadata used by the inventory."""
    attrs = {"X_ORIG_TYPE": origin}
    if bel is not None:
        attrs["NEXTPNR_BEL"] = bel
    return {"type": kind, "attributes": attrs}


class ResourceTests(unittest.TestCase):
    """Distinguish logical functions, constrained memory resources and physical packing."""

    def test_complete_primitive_census(self) -> None:
        """SRLs and RAM consume LUT capacity; half BRAMs count against one common pool."""
        result = counts({"LUT6": 2, "LUT6_2": 1, "RAM32M": 2, "RAM64X1D": 1,
                         "SRLC32E": 3, "SRL16E": 2, "FDRE": 7, "FDCE_1": 1,
                         "RAMB18E1": 3, "RAMB36E1": 2, "DSP48E1": 4,
                         "LDCE": 1, "PS7": 1, "GTXE2_CHANNEL": 1, "BUFG": 2,
                         "CARRY4": 2, "MUXF7": 3, "MUXF8": 1, "GND": 1})
        self.assertTrue(result["complete"])
        r = result["resources"]
        self.assertEqual((r["lut_primitive_cells"], r["lut_output_functions"]), (3, 4))
        self.assertEqual((r["distributed_ram_lut_sites"], r["srl_lut_site_upper_bound"]), (10, 5))
        self.assertEqual((r["lut_site_upper_bound"], r["slicem_lut_site_upper_bound"]), (18, 15))
        self.assertEqual((r["ff"], r["bram18_equivalents"], r["dsp"], r["latches"]), (8, 7, 4, 1))
        self.assertEqual(result["hard_primitives"]["PS7"], 1)

    def test_unknown_types_are_incomplete(self) -> None:
        """A new RAM, unmapped process or unflattened submodule is never cost-free."""
        for kind in ("RAM_NEW", "$dff", "child_module", "SLICE_LUTX"):
            with self.subTest(kind=kind):
                result = counts({"LUT1": 1, kind: 2})
                self.assertFalse(result["complete"])
                self.assertEqual(result["unknown_primitives"], {kind: 2})

    def test_yosys_wire_metadata_and_inverters(self) -> None:
        """Aliases cost no gates; unabsorbed inverters still reserve LUT capacity."""
        cells = {"wire": {"type": "$buf", "connections": {"A": [1, 2], "Y": [3, 4]}},
                 "scope": {"type": "$scopeinfo", "connections": {}}, "invert": cell("INV"),
                 "logic": cell("LUT2")}
        result = mapped(netlist(cells), "top")
        self.assertTrue(result["complete"])
        self.assertEqual(result["resources"]["lut_primitive_cells"], 1)
        self.assertEqual(result["resources"]["inverter_lut_site_upper_bound"], 1)
        self.assertEqual(result["resources"]["lut_site_upper_bound"], 2)
        self.assertEqual(result["logical_annotations"], {"$buf": 1, "$scopeinfo": 1})
        with self.assertRaisesRegex(ValueError, "invalid wire buffer"):
            mapped(netlist({"bad": {"type": "$buf", "connections": {"A": [1], "Y": [2, 3]}}}), "top")
        with self.assertRaisesRegex(ValueError, "signal connections"):
            mapped(netlist({"bad": {"type": "$scopeinfo", "connections": {"Y": [1]}}}), "top")

    def test_invalid_counts_rejected(self) -> None:
        """Invalid populations cannot silently subtract resource demand."""
        for value in (-1, 0.5, True):
            with self.assertRaises(ValueError):
                counts({"LUT1": value})

    def test_groups_partition_one_image(self) -> None:
        """Longest prefix owns overlapping groups, with no library-definition double count."""
        result = mapped(netlist({"app.actor.a": cell("LUT6"), "app.debug.tap": cell("RAM32M"),
                                  "shell.clock": cell("BUFG"), "merged": cell("SRLC32E")}),
                        "top", {"application": "app.", "debug": "app.debug.", "shell": "shell."})
        self.assertEqual(result["resources"]["lut_site_upper_bound"], 6)
        for name, count in result["resources"].items():
            self.assertEqual(sum(g["resources"][name] for g in result["groups"].values()), count)
        self.assertEqual(result["groups"]["debug"]["resources"]["distributed_ram_lut_sites"], 4)
        self.assertEqual(result["groups"]["unattributed"]["resources"]["srl_lut_site_upper_bound"], 1)

    def test_group_ambiguity_rejected(self) -> None:
        """Duplicate or catch-all prefixes cannot masquerade as precise attribution."""
        for groups in ({"a": "x", "b": "x"}, {"a": ""}, {"unattributed": "x"}):
            with self.assertRaises(ValueError):
                mapped(netlist({}), "top", groups)

    def test_packed_halves_share_one_physical_lut(self) -> None:
        """A5/O5 and A6/O6 are one physical LUT, not two physical capacity charges."""
        result = placed_luts(netlist({"lo": cell("SLICE_LUTX", "SLICE_X0Y0/A5LUT"),
                                      "hi": cell("SLICE_LUTX", "SLICE_X0Y0/A6LUT"),
                                      "ram": cell("SLICE_LUTX", "SLICE_X1Y0/B6LUT", "RAM64X1S")}), "top")
        self.assertEqual(result["packed_lut_cells"], 3)
        self.assertEqual(result["physical_lut_sites"], 2)
        self.assertEqual(result["memory_lut_sites"], 1)
        self.assertFalse(result["placement_legality_verified"])

    def test_pack_only_has_no_physical_count(self) -> None:
        """Unplaced cells leave physical occupancy unknown, never zero or a partial total."""
        result = placed_luts(netlist({"a": cell("SLICE_LUTX"),
                                      "b": cell("SLICE_LUTX", "SLICE_X1Y0/A6LUT")}), "top")
        self.assertFalse(result["complete"])
        self.assertIsNone(result["physical_lut_sites"])
        self.assertEqual(result["observed_placed_lut_sites"], 1)

    def test_placement_duplicate_and_format_rejected(self) -> None:
        """Inconsistent placement cannot be hidden by deduplication."""
        duplicate = {"a": cell("SLICE_LUTX", "SLICE_X0Y0/A6LUT"),
                     "b": cell("SLICE_LUTX", "SLICE_X0Y0/A6LUT")}
        with self.assertRaisesRegex(ValueError, "multiply occupied"):
            placed_luts(netlist(duplicate), "top")
        with self.assertRaisesRegex(ValueError, "unrecognized"):
            placed_luts(netlist({"a": cell("SLICE_LUTX", "BAD")}), "top")

    def test_bounds_are_only_caller_screen(self) -> None:
        """Latches can be forbidden and unknown ceiling names fail rather than disappear."""
        resources = counts({"LUT6": 3, "LDCE": 1})["resources"]
        self.assertFalse(bounds(resources, {"latches": 0})["passes"])
        checked = bounds(resources, {"lut_site_upper_bound": 3})
        self.assertTrue(checked["passes"])
        self.assertFalse(checked["physical_fit_established"])
        with self.assertRaisesRegex(ValueError, "unknown"):
            bounds(resources, {"misspelled": 3})

    def test_explicit_top_and_report_scope(self) -> None:
        """The report does not infer a top, physical timing or board readiness."""
        with self.assertRaises(ValueError):
            module(netlist({}), "missing")
        result = report(netlist({"a": cell("LUT1")}), "top")
        self.assertIsNone(result["placed_luts"])
        self.assertIsNone(result["bounds"])
        self.assertFalse(result["hardware_qualified"])
        self.assertFalse(result["timing_qualified"])

    def test_tool_timeout_retires_descendant(self) -> None:
        """A timed-out external tool cannot leave its child running outside the driver."""
        code = (
            "import subprocess,sys,time; "
            "child=subprocess.Popen([sys.executable,'-c',"
            "'import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(30)']); "
            "print(child.pid,flush=True); time.sleep(30)"
        )
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = run_tool([sys.executable, "-c", code], root, root / "console.log", 0.5)
            self.assertTrue(result["timed_out"])
            self.assertNotEqual(result["returncode"], 0)
            self.assertTrue(result["owned_group_gone"])
            self.assertFalse(group_exists(result["process_group"]))

    def test_mapping_script_preserves_required_checks(self) -> None:
        """One explicit top uses XC7 mapping and graph checks, never route or tools/build.py."""
        source = Path("/tmp/source file.sv").resolve()
        commands = script([source], "top", Path("/tmp/area"), [], ["DEBUG=0"])
        self.assertIn(f'read_verilog -sv -DDEBUG=0 "{source}"', commands)
        self.assertIn("synth_xilinx -flatten -abc9 -family xc7 -noiopad -noclkbuf -top top", commands)
        self.assertIn("check -assert\nscc -expect 0", commands)
        with self.assertRaises(ValueError):
            script([], "top; extra", Path("/tmp"), [], [])
        with self.assertRaises(ValueError):
            script([], "top", Path("/tmp"), [], ["DEBUG; extra"])


if __name__ == "__main__":
    unittest.main()
