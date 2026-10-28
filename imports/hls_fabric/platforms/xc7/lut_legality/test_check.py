"""Mutation regressions for placement and FASM checks; no FPGA tools required."""

import copy
import json
import tempfile
import unittest
from pathlib import Path
from typing import Any

if __package__:
    from .check import check
else:
    from check import check


class CheckerTest(unittest.TestCase):
    """Exercise reachable truth rows, pin constraints and corrupt exports."""

    def setUp(self) -> None:
        """Build a five-input function with independently permuted physical pins."""
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        # I0 & !I1 | I2 ^ (I3 & I4) distinguishes each logical input.
        table = sum((((a & 1) & (1 ^ ((a >> 1) & 1))) |
                     (((a >> 2) & 1) ^ (((a >> 3) & 1) & ((a >> 4) & 1)))) << a
                    for a in range(32))
        attrs = {f"X_ORIG_PORT_A{i+1}": f"I{i}" for i in range(5)}
        attrs.update(X_ORIG_TYPE="LUT5", X_ORIG_PORT_O6="O")
        cell = {"type": "SLICE_LUTX", "parameters": {"INIT": f"{table:032b}"},
                "attributes": attrs, "connections": {**{f"A{i+1}": [i+2] for i in range(5)}, "O6": [8]},
                "port_directions": {**{f"A{i+1}": "input" for i in range(5)}, "O6": "output"}}
        self.before = {"cells": {"lut": cell}, "netnames": {f"n{i}": {"bits": [i]} for i in range(2, 9)}}
        self.after = copy.deepcopy(self.before)
        self.cell = self.after["cells"]["lut"]
        self.cell["attributes"].update(NEXTPNR_BEL="SLICE_X0Y0/A5LUT", X_ORIG_PORT_O5="O")
        del self.cell["attributes"]["X_ORIG_PORT_O6"]
        self.cell["connections"]["O5"] = self.cell["connections"].pop("O6")
        self.cell["port_directions"]["O5"] = self.cell["port_directions"].pop("O6")
        permutation = [2, 0, 4, 3, 1]
        for physical, logical in enumerate(permutation, 1):
            self.cell["attributes"][f"X_ORIG_PORT_A{physical}"] = f"I{logical}"
            self.cell["connections"][f"A{physical}"] = [logical + 2]
        self.programmed = sum(((table >> sum(((a >> p) & 1) << i for p, i in enumerate(permutation))) & 1) << a
                              for a in range(32))
        (self.root / "tilegrid.json").write_text(json.dumps({"CLBLL_L_X0Y0": {"sites": {"SLICE_X0Y0": "SLICEL"}}}))

    def validate(self) -> dict[str, Any]:
        """Check the current mutable exports and programmed INIT."""
        for name, module in (("packed", self.before), ("routed", self.after)):
            (self.root / f"{name}.json").write_text(json.dumps({"modules": {"top": module}}))
        (self.root / "design.fasm").write_text(f"CLBLL_L_X0Y0.SLICEL_X0.ALUT.INIT[63:0] = 64'b{self.programmed:064b}\n")
        return check(self.root / "packed.json", self.root / "routed.json", self.root / "design.fasm", self.root / "tilegrid.json")

    def test_permuted_function(self) -> None:
        """All 32 reachable O5 rows retain the original asymmetric function."""
        self.assertEqual(self.validate()["truth_table_rows"], 32)

    def test_shared_a6_does_not_hide_o5_rows(self) -> None:
        """Unattributed shared A6=VCC must not make O5 validation vacuous."""
        self.cell["connections"]["A6"] = ["1"]
        self.assertEqual(self.validate()["truth_table_rows"], 32)
        self.programmed ^= 1
        with self.assertRaisesRegex(ValueError, "wrong programmed truth table"):
            self.validate()

    def test_wrong_init(self) -> None:
        """A single changed reachable FASM bit fails validation."""
        self.programmed ^= 1 << 7
        with self.assertRaisesRegex(ValueError, "wrong programmed truth table"):
            self.validate()

    def test_rewired_input(self) -> None:
        """Changing a signal fails even if the INIT is untouched."""
        self.cell["connections"]["A1"] = [2]
        with self.assertRaisesRegex(ValueError, "connectivity changed"):
            self.validate()

    def test_consistent_metadata_cannot_mask_wrong_function(self) -> None:
        """Truth expectations come from original nets, not final pin annotations."""
        for field, prefix in (("connections", ""), ("attributes", "X_ORIG_PORT_")):
            values = self.cell[field]
            a, b = prefix + "A1", prefix + "A2"
            values[a], values[b] = values[b], values[a]
        with self.assertRaisesRegex(ValueError, "wrong programmed truth table"):
            self.validate()

    def test_elided_constant_origin(self) -> None:
        """Accept missing constant metadata only with the value and function intact."""
        self.before["cells"]["lut"]["connections"]["A2"] = ["0"]
        self.cell["connections"]["A5"] = ["0"]
        del self.cell["attributes"]["X_ORIG_PORT_A5"]
        result = self.validate()
        self.assertEqual(result["elided_logic_constant_origins"], 1)
        self.assertEqual(result["truth_table_rows"], 16)
        self.programmed ^= 1
        with self.assertRaisesRegex(ValueError, "wrong programmed truth table"):
            self.validate()

    def test_wrong_output_pin(self) -> None:
        """The provisional O6 name must be gone from a routed O5 cell."""
        self.cell["connections"]["O6"] = [8]
        with self.assertRaisesRegex(ValueError, "O6 on a five-input site"):
            self.validate()

    def test_nonconstant_shared_a6(self) -> None:
        """Only the shared high-half select may appear as unattributed A6."""
        self.cell["connections"]["A6"] = [2]
        with self.assertRaisesRegex(ValueError, "nonconstant shared A6"):
            self.validate()

    def test_fixed_location(self) -> None:
        """Imported BEL constraints must survive routing exactly."""
        self.before["cells"]["lut"]["attributes"]["BEL"] = "SLICE_X0Y0/B5LUT"
        with self.assertRaisesRegex(ValueError, "fixed placement moved"):
            self.validate()

    def test_wrong_memory_slice(self) -> None:
        """RAM and SRL cells cannot use ordinary logic-only slices."""
        for design in (self.before, self.after):
            design["cells"]["lut"]["attributes"]["X_ORIG_TYPE"] = "RAM32M"
        with self.assertRaisesRegex(ValueError, "memory in a non-memory slice"):
            self.validate()


if __name__ == "__main__":
    unittest.main()
