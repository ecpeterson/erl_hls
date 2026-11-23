#!/usr/bin/env python3
"""Protect the feedback ledger from mistaking display blocks for transfer times."""
import json
from pathlib import Path
import tempfile
import unittest

from numerical_feedback import analyze


class FeedbackTest(unittest.TestCase):
    """Use distinct observed boundaries so a display-origin regression is visible."""

    def test_observed_fold_output(self) -> None:
        """The fold's drawn clock starts one cycle before its accepted output."""
        args = {'actor': 'phi0', 'site': 0, 'key': 7, 'fragment_arrivals': [2, 3, 4, 5],
                'opening_arrival_cycle': 2, 'aggregate_cycle': 6}
        graph = {'metadata': {'clock_period_ns': 8, 'reset_release_ns': 100}, 'events': [
            {'id': 'fold', 'name': 'complete aggregate', 'ts': 140, 'dur': 8, 'args': args},
            {'id': 'capture', 'name': 'scheduler captures aggregate', 'ts': 156, 'dur': 0, 'args': args},
            {'id': 'ram', 'name': 'state RAM read', 'ts': 172, 'dur': 16,
             'args': {**args, 'finisher': 'work'}},
            {'id': 'work', 'name': 'aggregate completion + entry', 'ts': 188, 'dur': 24,
             'args': {'reduction_before': {'key': 7}, 'phase_before': 'gathering', 'result_cycle': 12}},
            {'id': 'effect', 'name': 'effect 0', 'ts': 220, 'dur': 0, 'args': {'producer': 'work'}}]}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'profile.json').write_text(json.dumps(graph))
            (root/'summary.json').write_text(json.dumps({'window_ns': [100, 300]}))
            result = analyze(root/'profile.json', root/'summary.json')
        self.assertEqual(result['cycle_intervals']['inputs_ready_to_aggregate']['mean'], 1)
        self.assertEqual(result['cycle_intervals']['aggregate_to_capture']['mean'], 1)
        self.assertEqual(result['capture_to_publication_cycles']['mean'], 8)
        self.assertEqual(result['round_coverage']['7'], 1)


if __name__ == '__main__':
    unittest.main()
