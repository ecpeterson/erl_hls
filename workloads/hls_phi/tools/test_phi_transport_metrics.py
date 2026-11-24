#!/usr/bin/env python3
"""Check transport attribution and fail-closed behavior with explicit port observations."""
import phi_tool_paths  # Resolve shared tooling for this application.
import unittest

from phi_transport_metrics import dense, inspect_link


def fixture() -> tuple[dict, dict]:
    """Two frames surround a delayed credit and a postponed return-priority turn."""
    plan = {'index': 0, 'peer': 1, 'frames': [0], 'credits': [1], 'returns': [2],
            'outgoing': [3], 'return_queues': [4], 'words': 5, 'wire': 6}
    rows = [[0, 2, 0, 0, 0, 2, 2] for _ in range(20)]
    rows[1][0] = rows[9][0] = 3
    for c in (6, 7, 8): rows[c][0] = 1
    rows[8][1] = rows[16][1] = 3
    rows[7][2], rows[8][2] = 1, 3
    for c in (1, 2, 3, 4, 5, 8, 9, 10, 11, 12, 13):
        rows[c][5], rows[c+1][6] = 3, 3
    histories = {(0, i): [{'cycle': c, 'time_ns': c, 'value': row[i]}
                          for c, row in enumerate(rows)] for i in range(7)}
    return plan, histories


class TransportTest(unittest.TestCase):
    """Cycle accounting must preserve state transitions and reject inconsistent evidence."""

    def test_causes_and_latency(self) -> None:
        """Separate no offered work, credit wait and return arbitration without inspecting state."""
        plan, histories = fixture()
        result = inspect_link(plan, histories, 0, 0, 20, 1)
        counts = result['counts']
        self.assertEqual(counts['data_header'], 2)
        self.assertEqual(counts['payload'], 8)
        self.assertEqual(counts['credit_header'], 1)
        self.assertEqual(counts['credit_idle'], 1)
        self.assertEqual(counts['arbitration_idle'], 1)
        self.assertEqual(counts['wire_accepted'], 11)
        self.assertEqual(result['wire_delay_cycles'], 1)
        self.assertEqual(result['latencies']['frame_wait_cycles']['histogram'], {0: 1, 3: 1})
        self.assertEqual(result['latencies']['credit_roundtrip_cycles']['histogram'], {7: 2})

    def test_duplicate_credit(self) -> None:
        """A credit received before any grant cannot be explained away by the model."""
        plan, histories = fixture()
        histories[0, 1][0]['value'] = 3
        with self.assertRaisesRegex(ValueError, 'duplicate credit'):
            inspect_link(plan, histories, 0, 0, 20, 1)

    def test_wrong_grant(self) -> None:
        """A spurious transfer while the packetizer is busy must invalidate attribution."""
        plan, histories = fixture()
        histories[0, 0][3]['value'] = 3
        with self.assertRaisesRegex(ValueError, 'choice reconstruction differs'):
            inspect_link(plan, histories, 0, 0, 20, 1)

    def test_lost_word(self) -> None:
        """Conservation includes every physical output word, not just frame headers."""
        plan, histories = fixture()
        histories[0, 6][4]['value'] = 2
        with self.assertRaisesRegex(ValueError, 'fixed-delay'):
            inspect_link(plan, histories, 0, 0, 20, 1)

    def test_initial_observation_required(self) -> None:
        """Missing reset-release history cannot be substituted by an assumed empty queue."""
        with self.assertRaisesRegex(ValueError, 'reset release'):
            dense([{'cycle': 1, 'value': 0}], 4)


if __name__ == '__main__':
    unittest.main()
