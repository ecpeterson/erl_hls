#!/usr/bin/env python3
"""Reject false optimization evidence without executing XLS or HDL tools."""
import unittest
from check_source_helper_optimization import check


def function(body: str) -> str:
    """Build the minimal scalar IR envelope consumed by the focused evidence check."""
    return "package test\n\ntop fn probe(x: bits[32], y: bits[32], keep_left: bits[1]) -> bits[32] {\n" + body + "}\n"


RAW = function("  ret invoke.1: bits[32] = invoke(keep_left, x, y, to_apply=__xls_remote_selector__choose, id=1)\n")
CONSTANT = function("  ret x: bits[32] = param(name=x, id=1)\n")
DYNAMIC = function("  ret sel.1: bits[32] = sel(keep_left, cases=[y, x], id=1)\n")


class OptimizationEvidenceTests(unittest.TestCase):
    """Require both an actual module call and its distinct constant/dynamic optimized forms."""

    def test_accepts_constant_and_dynamic_forms(self) -> None:
        """The expected optimized pair produces concrete per-top operation counts."""
        result = check(RAW, CONSTANT, RAW, DYNAMIC)
        self.assertEqual("x", result["constant"]["result"])
        self.assertEqual({"sel": 1}, result["dynamic"]["operations"])

    def test_rejects_missing_source_module_call(self) -> None:
        """An already trivial handwritten probe does not demonstrate inter-module optimization."""
        with self.assertRaisesRegex(ValueError, "did not invoke"):
            check(CONSTANT, CONSTANT, RAW, DYNAMIC)

    def test_rejects_constant_selector(self) -> None:
        """A surviving mux does not count as folding the constant parameter."""
        with self.assertRaisesRegex(ValueError, "retained selection"):
            check(RAW, DYNAMIC, RAW, DYNAMIC)

    def test_rejects_wrong_constant_result(self) -> None:
        """Eliminating selection is insufficient if the surviving input is wrong."""
        wrong = function("  ret y: bits[32] = param(name=y, id=2)\n")
        with self.assertRaisesRegex(ValueError, "simplify to input x"):
            check(RAW, wrong, RAW, DYNAMIC)

    def test_rejects_disappearing_dynamic_selection(self) -> None:
        """The control case must still expose a genuine choice after optimization."""
        with self.assertRaisesRegex(ValueError, "lost its selector"):
            check(RAW, CONSTANT, RAW, CONSTANT)

    def test_rejects_degenerate_dynamic_selection(self) -> None:
        """A select that always picks the same data input is not the dynamic control case."""
        degenerate = DYNAMIC.replace("cases=[y, x]", "cases=[x, x]")
        with self.assertRaisesRegex(ValueError, "both data inputs"):
            check(RAW, CONSTANT, RAW, degenerate)


if __name__ == "__main__":
    unittest.main()
