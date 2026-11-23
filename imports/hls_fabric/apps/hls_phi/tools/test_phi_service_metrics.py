#!/usr/bin/env python3
"""Check cycle accounting at asynchronous status-window boundaries."""
import phi_tool_paths  # Resolve shared tooling for this application.
import json
from pathlib import Path
import tempfile
import unittest

from phi_service_metrics import cycles, summarize
from phi_service_analysis import traffic, occupancy, idle_returns
from unittest.mock import patch


class ServiceMetricsTest(unittest.TestCase):
    """Status windows need not align with either device's rising edges."""

    def test_edges(self) -> None:
        """Include the starting edge, exclude the stopping edge, and clip each state episode."""
        self.assertEqual(cycles(10, 30, 10, 40, 6), 4)
        self.assertEqual(cycles(11, 28, 10, 40, 6), 2)
        self.assertEqual(cycles(0, 100, 10, 22, 6), 2)
        self.assertEqual(cycles(40, 50, 10, 22, 6), 0)

    def test_ports(self) -> None:
        """Account independent port states without attributing idle-but-unready cycles to blockage."""
        with tempfile.TemporaryDirectory() as folder:
            stage = Path(folder)
            progress = {"complete_rounds": [{"time_ns": 10}, {"time_ns": 40}], "intervals_ns": [30]}
            (stage / "progress.json").write_text(json.dumps(progress))
            # Device 0 edges: 12, 18 accepted; 24, 30, 36 blocked at link out.
            # Device 1 edges: 14, 28 idle and unready at every port.
            (stage / "activity.log").write_text("0 0 0 ff\n0 1 0 00\n24 0 4 80\n")
            report = summarize(stage, [6, 14])
            left, right = report["devices"]
            self.assertEqual(left["ports"]["link_out"]["accepted"], 2)
            self.assertEqual(left["ports"]["link_out"]["blocked"], 3)
            self.assertEqual(left["ports"]["app_in"]["idle_unready"], 3)
            self.assertEqual(right["ports"]["link_out"]["idle_unready"], 2)
            self.assertEqual(right["ports"]["link_out"]["blocked"], 0)

    def test_packets_crossing_window(self) -> None:
        """Keep word accounting exact when the window cuts through a fixed-length frame."""
        with tempfile.TemporaryDirectory() as folder:
            stage = Path(folder)
            catalog = [{'device': d, 'lane': 0, 'schemas': [{'name': 'query', 'tag': 8, 'bits': 64}]} for d in (0, 1)]
            (stage / 'lane-catalog.json').write_text(json.dumps(catalog))
            lines = '0 0 048500000\n6 0 008000002\n12 0 000000003\n18 0 000000007\n24 0 100000000\n30 0 148508000\n'
            (stage / 'traffic.log').write_text(lines)
            result = traffic(stage, 6, 31)[0]
            self.assertEqual(result['words'], {'frame_header': 1, 'payload': 2, 'padding': 1, 'credit': 1})
            self.assertEqual(result['frames'], {'query': 1})
            (stage / 'traffic.log').write_text(lines.replace('100000000', '100000001'))
            with self.assertRaisesRegex(ValueError, 'padding'):
                traffic(stage, 6, 31)

    def test_occupancy_weighting(self) -> None:
        """Repeated publications must not bias the time-weighted queue depth."""
        resource = {'kind': 'fifo', 'name': 'queue', 'capacity': 2}
        history = [{'time_ns': t, 'occupancy': depth} for t, depth in [(0, 0), (12, 2), (18, 2), (24, 1)]]
        with tempfile.TemporaryDirectory() as folder, patch('phi_service_analysis.read', return_value=({(0, 0): resource}, {(0, 0): history})):
            stage = Path(folder)
            (stage / 'profile-inputs.json').write_text('{"device_periods_ns": [6, 14]}')
            result, = occupancy(stage, 10, 31)
            self.assertEqual(result['mean_depth'], 1.5)
            self.assertEqual(result['full_fraction'], 0.5)
            self.assertEqual(result['max_depth'], 2)

    def test_idle_returns(self) -> None:
        """Queued returns count only on ready-but-idle edges, with each clock aligned independently."""
        resources = {(d, 0): {'kind': 'fifo', 'name': 'fifo__link_returned__0_'} for d in (0, 1)}
        histories = {(0, 0): [{'time_ns': t, 'occupancy': n} for t, n in [(0, 0), (12, 1), (18, 0)]],
                     (1, 0): [{'time_ns': 0, 'occupancy': 1}]}
        with tempfile.TemporaryDirectory() as folder, patch('phi_service_analysis.read', return_value=(resources, histories)):
            stage = Path(folder)
            (stage / 'profile-inputs.json').write_text('{"device_periods_ns": [6, 14]}')
            (stage / 'activity.log').write_text('0 0 0 40\n0 1 0 40\n24 0 4 c0\n28 1 2 80\n')
            left, right = idle_returns(stage, 11, 31)
            self.assertEqual(left['idle_ready_cycles'], 2)
            self.assertEqual(left['pending_return_cycles'], 1)
            self.assertEqual(left['pending_fraction'], 0.5)
            self.assertEqual(right['idle_ready_cycles'], 1)
            self.assertEqual(right['pending_return_cycles'], 1)


if __name__ == "__main__":
    unittest.main()
