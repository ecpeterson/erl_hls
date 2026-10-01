#!/usr/bin/env python3
"""Check packed packet boundaries and independent wire-credit ledgers on known timelines."""
from pathlib import Path
import tempfile
import json
from unittest.mock import patch
import unittest

from phi_packed_metrics import packets, ledger, source_waits


class PackedAccountingTest(unittest.TestCase):
    """Concurrent outstanding frames must not collapse into a Boolean credit model."""

    def test_roundtrip(self) -> None:
        """Two frames share a lane while another lane waits; each return releases only its own slot."""
        data = [{'start_ns': time, 'lane': lane, 'credit': False}
                for time, lane in [(0, 0), (8, 0), (16, 1)]]
        returned = [{'end_ns': time, 'lane': lane, 'credit': True, 'complete': True}
                    for time, lane in [(40, 0), (56, 1), (64, 0)]]
        result = ledger(data, returned, 2, 2, 0, 80)
        self.assertEqual(result['roundtrip_ns']['mean'], (40+40+56)/3)
        self.assertEqual([lane['max_outstanding'] for lane in result['lanes']], [2, 1])
        self.assertEqual([lane['mean_outstanding'] for lane in result['lanes']], [96/80, 40/80])
        self.assertEqual([lane['tail_outstanding'] for lane in result['lanes']], [0, 0])
        with self.assertRaisesRegex(ValueError, 'reserved window'):
            ledger(data, returned, 2, 1, 0, 80)
        with self.assertRaisesRegex(ValueError, 'without an outstanding'):
            ledger(data, [*returned, returned[-1]], 2, 2, 0, 80)

    def test_captured_frame_wait(self) -> None:
        """Idle wire cycles with staged work stay distinct from a lack of source work."""
        histories = {(0, 20): [{'cycle': 0, 'time_ns': 0, 'value': 3}, {'cycle': 1, 'time_ns': 8, 'value': 0}],
                     (0, 21): [{'cycle': 0, 'time_ns': 0, 'value': 0}, {'cycle': 2, 'time_ns': 16, 'value': 1},
                               {'cycle': 3, 'time_ns': 24, 'value': 3}, {'cycle': 4, 'time_ns': 32, 'value': 0}],
                     (0, 30): [{'cycle': 0, 'time_ns': 0, 'value': 0}, {'cycle': 2, 'time_ns': 16, 'value': 3},
                               {'cycle': 3, 'time_ns': 24, 'value': 0}, {'cycle': 5, 'time_ns': 40, 'value': 3}]}
        resources = [{'kind': 'fifo', 'name': f'fifo__outgoing_0__{i}_', 'pop': 20+i} for i in (0, 1)]
        resources.append({'kind': 'channel', 'name': '_link_0_out', 'id': 30})
        devices = [{'id': 0, 'links': [{'index': 0, 'tx_lanes': 2}]}]
        tx = {(0, 0): [{'start_ns': 16, 'lane': 0, 'credit': False}, {'start_ns': 40, 'lane': 1, 'credit': False}]}
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            (stage/'device0-manifest.json').write_text(json.dumps({'resources': resources}))
            (stage/'profile-inputs.json').write_text(json.dumps({'device_periods_ns': [8]}))
            with patch('phi_packed_metrics.read', return_value=({}, histories)):
                result = source_waits(stage, devices, tx, 0, 48)[0, 0]
                self.assertEqual(result['wire_cycles'], {'idle_with_captured_frame': 4, 'accepted': 2})
                self.assertEqual(result['capture_to_wire_header_ns']['mean'], 16)
                with self.assertRaisesRegex(ValueError, 'without a captured frame'):
                    source_waits(stage, devices, {(0, 0): [*tx[0, 0], tx[0, 0][-1]]}, 0, 48)


    def test_crossing_packets(self) -> None:
        """A final payload, credit and new header can occupy the same wide transfer."""
        words = [0x48500000, 11, 22, 33, (1 << 32) | 44, (1 << 32) | 0x48508001, 0x48500002]
        lines = []
        for index in range(0, len(words), 4):
            raw = sum(((1 << 33) | word) << (34*i) for i, word in enumerate(words[index:index+4]))
            lines.append(f'{index*2} 0 1 {raw:x}')
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'traffic.log'
            path.write_text('\n'.join(lines))
            result = packets(path, {'words': 4, 'credits': 4})[0, 1]
            self.assertEqual([p['words'] for p in result], [words[:5], words[5:6], words[6:]])
            self.assertEqual([p['complete'] for p in result], [True, True, False])
            self.assertEqual([p['start_ns'] for p in result], [0, 8, 8])


if __name__ == '__main__':
    unittest.main()
