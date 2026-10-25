#!/usr/bin/env python3
"""Exercise passive VPI slices across word boundaries and asynchronous clocks."""
import csv
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from backend_paths import ROOT
from phi_cycle_trace import executor_requests, plan


class CycleTraceTest(unittest.TestCase):
    """The probe must see pre-edge state and filter writes for the selected actor slot."""

    def test_selected_internal_channels(self) -> None:
        """Limiting detailed channels retains every board's FIFO and actor observations."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            manifest = {'schema': 5, 'actor_projection': {'banks': [
                {'index': 0, 'slots': 1, 'mailbox': {'kind': 'shared'}}]}, 'resources': [
                {'kind': 'fifo', 'id': 0, 'name': 'fifo__outgoing_0', 'width': 2, 'push': 1, 'pop': 2},
                *[{'kind': 'channel', 'id': i, 'name': f'channel{i}'} for i in (1, 2, 3)],
                {'kind': 'actor', 'id': 4, 'bank': 0, 'slot': 0, 'name': 'actor'}]}
            for d in (0, 1):
                path = stage/f'device{d}/debug'
                path.mkdir(parents=True)
                (path/'manifest.json').write_text(json.dumps(manifest))
            plan(stage, stage, channels=True, all_channels=True, actor_devices={0})
            rows = [line.split()[:3] for line in (stage/'cycle-probes.txt').read_text().splitlines()]
            self.assertIn(['0', 'C', '3'], rows)
            self.assertNotIn(['1', 'C', '3'], rows)
            for d in ('0', '1'):
                for kind, ident in (('F', '0'), ('C', '1'), ('C', '2'), ('S', '4'), ('M', '4')):
                    self.assertIn([d, kind, ident], rows)

    def test_executor_boundary_uses_consumer(self) -> None:
        """Input identity survives queue renaming or a depth-zero handoff with no occupancy probe."""
        resources = [
            {'kind': 'channel', 'id': 0, 'name': 'phi/__SharedRequestStage_0/_request_in'},
            {'kind': 'channel', 'id': 1, 'name': 'phi/__SharedExecutor_0/_request_in'},
            {'kind': 'fifo', 'id': 2, 'name': 'phi/fifo__executor_request_', 'pop': 0, 'capacity': 1},
            {'kind': 'fifo', 'id': 3, 'name': 'phi/fifo__renamed_', 'pop': 1, 'capacity': 1}]
        self.assertEqual(executor_requests(resources, 'phi'),
                         [{'owner': 'phi', 'accept': 1, 'queue': resources[-1]}])
        self.assertEqual(executor_requests(resources[:-1]), [{'owner': 'phi', 'accept': 1, 'queue': None}])
        self.assertEqual(executor_requests(resources, 'other'), [])
        with self.assertRaisesRegex(ValueError, 'ambiguous'):
            executor_requests(resources + [{**resources[-1], 'id': 4}])

    def test_capture(self) -> None:
        """Compare every emitted value with an independent counter-driven RTL fixture."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            for cmd in (["iverilog-vpi", str(ROOT / "test/rtl/phi_service_trace.c")],
                        ["iverilog", "-g2012", "-s", "phi_bridge_tb", "-o", "test.vvp",
                         str(ROOT / "test/rtl/phi_cycle_trace_tb.sv")]):
                subprocess.run(cmd, cwd=stage, check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            plan = "".join(f"{d} {declaration}\n" for d in (0, 1, 17) for declaration in
                ("F 0 0 3 -1 -1 0 0", "C 2 0 2 -1 -1 0 0", "S 1 5 80 0 1 4 2", "M 1 86 24 85 -1 0 0"))
            (stage / "cycle-probes.txt").write_text(plan)
            run = ["vvp", "-M", str(stage), "-m", "phi_service_trace", "test.vvp"]
            subprocess.run(run, cwd=stage, check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            with (stage / "cycle-trace.csv").open() as source:
                records = list(csv.DictReader(source))
            self.assertGreater(len(records), 100)
            self.assertEqual({int(r["device"]) for r in records}, {0, 1, 17})
            self.assertEqual({r["kind"] for r in records}, {"F", "C", "S", "M"})
            for row in records:
                cycle, value = int(row["cycle"]), int(row["value"], 16)
                if row["kind"] == "F":
                    self.assertEqual(value, cycle % 5)
                elif row["kind"] == "C":
                    self.assertEqual(value, (cycle % 5) & 3)
                elif row["kind"] == "S":
                    self.assertEqual(cycle % 2, 0)
                    self.assertEqual(cycle % 3, 2)
                    self.assertEqual(value, 0x123456789abcde000000 | cycle)
                else:
                    self.assertEqual(value, 0x800000 | (cycle % 4))
            # A stale projection must fail rather than read beyond its observation bus.
            (stage / "cycle-probes.txt").write_text("0 F 0 63 3 -1 -1 0 0\n")
            bad = subprocess.run(run, cwd=stage, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            self.assertNotEqual(bad.returncode, 0)
            self.assertIn(b"exceeds observation output", bad.stdout)


if __name__ == "__main__":
    unittest.main()
