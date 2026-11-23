#!/usr/bin/env python3
"""Check mesh accounting against a synthetic capture with known per-link payload and credit totals."""
import phi_tool_paths  # Resolve shared tooling for this application.
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from phi_mesh_metrics import analyze, layout, transfer_words


class MeshAccountingTest(unittest.TestCase):
    """Repeated lane IDs must retain their physical link identity throughout reporting."""

    def test_packed_prefix(self) -> None:
        """A beat may end one packet and start another; invalid tails carry no words."""
        words = [(1 << 32) | 42, 0x48500001, 0x03000003]
        raw = sum(((1 << 33) | word) << (34*i) for i, word in enumerate(words))
        self.assertEqual(transfer_words(raw, {"words": 4, "credits": 4}), words)
        for bad in (0, 1 << 67, (1 << 33) | (1 << 101), 1 << 136):
            with self.assertRaises(ValueError):
                transfer_words(bad, {"words": 4, "credits": 4})


    def test_all_directions(self) -> None:
        """Each of 72 directed streams transfers one five-word frame and one credit in twelve clocks."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            devices, directions, catalog, traffic, activity = [], [], [], [], []
            for d in range(18):
                x, y = d % 3, d // 3
                neighbors = {"east": y*3+(x+1) % 3, "west": y*3+(x-1) % 3,
                             "north": ((y-1) % 6)*3+x, "south": ((y+1) % 6)*3+x}
                links = [{"index": i, "peer": peer, "tx_lanes": 1, "rx_lanes": 1}
                         for i, peer in enumerate(sorted(neighbors.values()))]
                devices.append({"id": d, "links": links})
                directions += [{"device": d, "peer": peer, "direction": name, "local": False}
                               for name, peer in neighbors.items()]
                phase = d % 8
                activity += [f"{phase} {d} 0 55555", f"{phase+8} {d} 1 555ff", f"{phase+56} {d} 7 55555"]
                for link in links:
                    i, peer = link["index"], link["peer"]
                    catalog.append({"device": d, "peer": peer, "lane": 0,
                                    "schemas": [{"name": "phi", "tag": 2, "bits": 32}]})
                    words = [0x48500000, 0x02000001, 42, 0, 1 << 32, (1 << 32) | 0x48508000]
                    traffic += [f"{phase+8*(n+1)} {d} {i} {word:09x}" for n, word in enumerate(words)]
            files = {"bridge.json": {"devices": devices}, "geometry.json": [{"distance": 6, "directions": directions}],
                     "lane-catalog.json": catalog, "profile-inputs.json": {"device_periods_ns": [8]*18},
                     "progress.json": {"intervals_ns": [48, 48], "complete_rounds": [
                         {"step": 8, "time_ns": 8}, {"step": 9, "time_ns": 56}, {"step": 10, "time_ns": 104}]}}
            for name, data in files.items():
                (stage / name).write_text(json.dumps(data))
            (stage / "traffic.log").write_text("\n".join(traffic)+"\n")
            (stage / "activity.log").write_text("\n".join(activity)+"\n")
            self.assertEqual(len(layout(stage)["port_labels"]), 18)
            with patch("phi_mesh_metrics.occupancy", return_value=[]):
                report = analyze(stage)
                self.assertEqual(len(report["links"]), 72)
                for link in report["links"]:
                    self.assertEqual(link["words"], {"lane_header": 1, "frame_header": 1, "payload": 1, "padding": 2, "credit": 1})
                    self.assertEqual(link["frames"], {"phi": 1})
                    self.assertEqual(link["pressure"]["accepted"], 6)
                    self.assertEqual(link["pressure"]["accepted_fraction"], 0.5)
                # A changed capture must be rejected before it can become a throughput claim.
                (stage / "traffic.log").write_text("\n".join(traffic[:-1])+"\n")
                with self.assertRaisesRegex(ValueError, "wire/handshake accounting differs"):
                    analyze(stage)


if __name__ == "__main__":
    unittest.main()
