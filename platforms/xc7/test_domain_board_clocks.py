"""Focused clock-binding negatives; no native tools or full-image parsing."""

import copy
from pathlib import Path
import unittest

from application import domain_board_clocks as clocks


def projection(stage: str = "mapped") -> dict:
    """Build only the five scalar names and two stage-specific MMCM observations."""
    cells = {}
    for name, bel in clocks.MMCMS.items():
        attributes = {} if stage == "mapped" else {
            "BEL" if stage == "packed" else "NEXTPNR_BEL": bel}
        cells[name] = {"type": "MMCME2_BASE" if stage == "mapped" else "MMCME2_ADV_MMCME2_ADV",
                       "attributes": attributes}
    return {"clock_nets": {name: {"bits": [index + 2]} for index, name in enumerate(clocks.CLOCKS)},
            "mmcms": cells}


def report() -> dict:
    """Construct a complete synthetic target report with positive margin on every clock."""
    return {"fmax": {name: {"constraint": frequency, "achieved": frequency + 1}
                     for name, frequency in clocks.CLOCKS.items()}}


class BoardClockTests(unittest.TestCase):
    """Names, frequencies and MMCM sites must bind before timing can be assessed."""

    def test_render_preserves_pins_sites_and_periods(self) -> None:
        """Only the five stale net selectors change in the established XDC."""
        original = (Path(__file__).parent / "ethernet/te0715_ethernet.xdc").read_text()
        rendered = clocks.render(projection(), original)
        for name, frequency in clocks.CLOCKS.items():
            self.assertIn(f"create_clock -period {1000 / frequency:.3f} [get_nets {name}]", rendered)
        unchanged = lambda text: [line for line in text.splitlines() if "[get_nets " not in line]
        self.assertEqual(unchanged(original), unchanged(rendered))
        self.assertNotIn("set_false_path", rendered)

    def test_render_rejects_missing_scalar_or_aliased_names(self) -> None:
        """A missing name, vector, constant or shared clock net cannot produce constraints."""
        original = (Path(__file__).parent / "ethernet/te0715_ethernet.xdc").read_text()
        variants = []
        missing = projection(); del missing["clock_nets"]["application.clk"]; variants.append(missing)
        for bits in ([2, 3], ["0"], []):
            changed = projection(); changed["clock_nets"]["application.clk"]["bits"] = bits
            variants.append(changed)
        aliased = projection(); aliased["clock_nets"]["application.clk"]["bits"] = [3]
        variants.append(aliased)
        for projected in variants:
            with self.subTest(projected=projected), self.assertRaises(ValueError):
                clocks.render(projected, original)

    def test_render_rejects_changed_original_contract(self) -> None:
        """Unexpected pins, periods, extra exceptions and repeated commands fail closed."""
        original = (Path(__file__).parent / "ethernet/te0715_ethernet.xdc").read_text()
        for changed in (original.replace("PACKAGE_PIN U5", "PACKAGE_PIN U6"),
                        original.replace("40.000", "80.000"),
                        original + "set_false_path -from [get_clocks *]\n",
                        original + "create_clock -period 8.000 [get_ports ref_p]\n"):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                clocks.render(projection(), changed)

    def test_project_omits_large_routes_and_unrelated_cells(self) -> None:
        """Projection retains only required name/bit/type/placement evidence."""
        expected = projection("routed")
        module = {"netnames": copy.deepcopy(expected["clock_nets"]),
                  "cells": copy.deepcopy(expected["mmcms"])}
        for row in module["netnames"].values():
            row["attributes"] = {"ROUTING": "large route omitted"}
        module["cells"]["unrelated"] = {"type": "FDRE", "attributes": {}}
        self.assertEqual(clocks.project(module), expected)

    def test_pack_checks_targets_without_claiming_timing(self) -> None:
        """The known selector warning is tolerable only with actual required MMCM attributes."""
        data = report()
        for row in data["fmax"].values():
            row["achieved"] = 0
        result = clocks.validate_pack(projection("packed"),
            "Warning: set_property: target get_cells not supported (on line 10)\n", data)
        self.assertTrue(result["clock_coverage_complete"])
        self.assertIsNone(result["modeled_targets_met"])
        self.assertFalse(result["timing_qualified"])

    def test_rejects_dropped_constraints(self) -> None:
        """No-op parser outcomes cannot be mistaken for a successfully applied default."""
        for log in ("Warning: create_clock: target [get_nets clock] matched nothing",
                    "Warning: net 'clock' does not exist in design, ignoring clock constraint",
                    "Info: get_nets: no net named clock - this target is ignored",
                    "ERROR: failed to parse target"):
            with self.subTest(log=log), self.assertRaises(ValueError):
                clocks.validate_pack(projection("packed"), log, report())

    def test_rejects_missing_extra_and_wrong_clock_targets(self) -> None:
        """Empty/subset reports and default 125-MHz targets cannot certify this design."""
        variants = [{}, {"fmax": {}}]
        missing = report(); del missing["fmax"]["clocks.rx_half_clock"]; variants.append(missing)
        extra = report(); extra["fmax"]["clock"] = {"constraint": 25}; variants.append(extra)
        for value in (125.0, 25.01, None, True, float("nan")):
            changed = report(); changed["fmax"]["application.clk"]["constraint"] = value
            variants.append(changed)
        for data in variants:
            with self.subTest(data=data), self.assertRaises(ValueError):
                clocks.validate_pack(projection("packed"), "", data)

    def test_rejects_wrong_or_missing_mmcm_placement(self) -> None:
        """Packed BEL and routed actual BEL are both required at their respective stages."""
        for stage, validate in (("packed", clocks.validate_pack), ("routed", clocks.validate_routed)):
            for attributes in ({}, {"BEL": "wrong", "NEXTPNR_BEL": "wrong"}):
                data = projection(stage); data["mmcms"]["clocks.tx.generator"]["attributes"] = attributes
                with self.subTest(stage=stage, attributes=attributes), self.assertRaises(ValueError):
                    validate(data, "", report())

    def test_routed_timing_miss_is_separate_from_coverage(self) -> None:
        """A correctly constrained slow clock keeps complete coverage and fails its target."""
        data = report()
        self.assertTrue(clocks.validate_routed(projection("routed"), "", data)["modeled_targets_met"])
        data["fmax"]["application.clk"]["achieved"] = 24.9
        result = clocks.validate_routed(projection("routed"), "", data)
        self.assertTrue(result["clock_coverage_complete"])
        self.assertFalse(result["modeled_targets_met"])
        for value in (None, float("inf"), float("nan"), 0, -1, True):
            data["fmax"]["application.clk"]["achieved"] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                clocks.validate_routed(projection("routed"), "", data)


if __name__ == "__main__":
    unittest.main()
