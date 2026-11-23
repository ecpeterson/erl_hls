#!/usr/bin/env python3
"""Routine bridge probes retain boundary cases without repeating the performance grid."""
import unittest

from test_packed_credit import service_cases


class SweepTests(unittest.TestCase):
    """The fast selection must still exercise every supported load and latency level."""

    def test_regression_covers_boundaries_and_levels(self) -> None:
        """Keep sparse/saturated and zero/long-delay corners plus both interior levels."""
        cases = service_cases(regression=True)
        self.assertEqual(len(cases), 6)
        self.assertEqual({active for active, _ in cases}, {1, 2, 4, 8})
        self.assertEqual({delay for _, delay in cases}, {0, 2, 16, 64})
        self.assertTrue({(1, 0), (1, 64), (8, 0), (8, 64)}.issubset(cases))
        self.assertTrue(set(cases).issubset(service_cases()))

    def test_full_and_quick_remain_distinct(self) -> None:
        """Explicit performance runs retain the whole grid; quick probes remain minimal."""
        self.assertEqual(len(set(service_cases())), 16)
        self.assertEqual(service_cases(quick=True), [(8, 2)])


if __name__ == '__main__':
    unittest.main()
