"""Guard the endpoint audit against silent exclusions and vacuous passes."""

import copy
import json
import subprocess
import sys
import tempfile
from pathlib import Path
import unittest

from timing_coverage.check import check, requirements
from timing_coverage.run import feature_digest, validate_modes


def fixture() -> dict:
    """Provide one independently described FF timing endpoint and clock."""
    return {"schema": 1, "cells": {"example": {"type": "SLICE_FFX", "placed": True, "ports": {
        "Q": {"class": "register_output", "clocks": [{"port": "CK"}]},
        "D": {"class": "register_input", "clocks": [{"port": "CK"}]},
        "CK": {"class": "clock_input", "clocks": []}}}}}


class CoverageTest(unittest.TestCase):
    """Necessary endpoint checks must fail when timing information is absent."""

    def test_complete_endpoints_are_not_signoff(self) -> None:
        """Passing the declared requirements cannot grant a design-wide clock claim."""
        result = check(fixture(), requirements("logic"))
        self.assertTrue(result["endpoint_requirements_met"])
        self.assertFalse(result["design_wide_clock_validated"])

    def test_ignored_wrong_class_and_unplaced_fail(self) -> None:
        """An excluded or unplaced launch point remains a visible failure."""
        for klass, placed in (("ignore", True), ("comb_output", True), ("register_output", False)):
            data = fixture()
            data["cells"]["example"]["ports"]["Q"]["class"] = klass
            data["cells"]["example"]["placed"] = placed
            self.assertFalse(check(data, requirements("logic"))["endpoint_requirements_met"])

    def test_clock_association_must_exist(self) -> None:
        """Register labels alone are insufficient without a recognized connected clock."""
        for variant in ("absent", "unclassified", "empty", "mixed"):
            data = fixture()
            ports = data["cells"]["example"]["ports"]
            if variant == "absent":
                del ports["CK"]
            elif variant == "unclassified":
                ports["CK"]["class"] = "ignore"
            elif variant == "empty":
                ports["Q"]["clocks"] = []
            else:
                ports["Q"]["clocks"].append({"port": "OTHER"})
            self.assertFalse(check(data, requirements("logic"))["endpoint_requirements_met"])

    def test_no_matches_is_not_a_pass(self) -> None:
        """Missing a required hard block or its output ports fails the selector."""
        for mode in ("ram", "ram_registered", "dsp", "dsp_registered", "ram_dsp"):
            result = check(fixture(), requirements(mode))
            self.assertFalse(result["endpoint_requirements_met"])
            self.assertEqual(result["checks"][2]["matched"], 0)

    def test_one_good_endpoint_cannot_mask_an_ignored_sibling(self) -> None:
        """Check all matching ports, not merely the first usable one."""
        data = fixture()
        data["cells"]["bad"] = copy.deepcopy(data["cells"]["example"])
        data["cells"]["bad"]["ports"]["Q"]["class"] = "ignore"
        row = check(data, requirements("logic"))["checks"][0]
        self.assertEqual((row["matched"], row["failed"]), (2, 1))
        self.assertEqual(row["failures"][0]["cell"], "bad")

    def test_invalid_contracts_fail_closed(self) -> None:
        """Reject unknown schemas, empty audits, and unsupported requirements."""
        with self.assertRaises(ValueError):
            check({"schema": 2, "cells": {}}, requirements("logic"))
        with self.assertRaises(ValueError):
            check(fixture(), [])
        with self.assertRaises(ValueError):
            check(fixture(), [{"type": ".*", "port": ".*", "class": "ignore"}])

    def test_fabric_register_is_not_a_bram_output_register(self) -> None:
        """Reject the inferred-RAM variant that silently leaves DOB_REG disabled."""
        primitives = {"hard_blocks": {"memory": {"type": "RAMB36E1", "parameters": {"DOB_REG": "0"}}}}
        with self.assertRaisesRegex(ValueError, "BRAM output-register mode"):
            validate_modes("ram_registered", primitives)
        primitives["hard_blocks"]["memory"]["parameters"]["DOB_REG"] = "1"
        validate_modes("ram_registered", primitives)
        with self.assertRaisesRegex(ValueError, "population"):
            validate_modes("dsp", {"hard_blocks": {}})

    def test_cli_exit_status_is_the_coverage_gate(self) -> None:
        """Publish failed audits for diagnosis while returning failure to callers."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            coverage, required, output = [root / name for name in ("coverage.json", "required.json", "audit.json")]
            coverage.write_text(json.dumps(fixture()))
            tool = Path(__file__).with_name("check.py")
            for mode, code in (("logic", 0), ("ram", 1)):
                required.write_text(json.dumps(requirements(mode)))
                result = subprocess.run([sys.executable, str(tool), str(coverage), str(required),
                                         "--output", str(output)], capture_output=True, text=True)
                self.assertEqual(result.returncode, code, result.stderr)
                self.assertEqual(json.loads(output.read_text())["endpoint_requirements_met"], code == 0)

    def test_fasm_comparison_ignores_only_comments(self) -> None:
        """Version banners may differ; feature values and order must survive comparison."""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "design.fasm"
            path.write_text("# version A\nTILE.FEATURE = 1\n")
            before = feature_digest(path)
            path.write_text("# version B\nTILE.FEATURE = 1\n")
            self.assertEqual(before, feature_digest(path))
            path.write_text("# version B\nTILE.FEATURE = 0\n")
            self.assertNotEqual(before, feature_digest(path))


if __name__ == "__main__":
    unittest.main()
