#!/usr/bin/env python3
"""Structural discovery checks and query-service RTL regression (no XLS needed)."""
import copy
from pathlib import Path
import subprocess
import tempfile
import unittest

import topology_debug as topology

ROOT = Path(__file__).resolve().parents[1]


class DiscoveryTests(unittest.TestCase):
    def test_channel_contract(self):
        module = {"ports": {"msg_valid": {"direction": "output", "bits": [1]},
                            "msg_ready": {"direction": "input", "bits": [2]}}}
        self.assertEqual(list(topology.channel_ports(module)), [("msg", "msg_valid", "msg_ready", "output")])
        bad = copy.deepcopy(module)
        del bad["ports"]["msg_ready"]
        with self.assertRaisesRegex(ValueError, "missing ready"):
            list(topology.channel_ports(bad))
        bad = copy.deepcopy(module)
        bad["ports"]["msg_ready"]["bits"] = [2, 3]
        with self.assertRaisesRegex(ValueError, "one bit"):
            list(topology.channel_ports(bad))
        bad["ports"]["msg_ready"] = {"direction": "output", "bits": [2]}
        with self.assertRaisesRegex(ValueError, "directions"):
            list(topology.channel_ports(bad))

    def test_deepest_alias(self):
        endpoints = [{"path": p} for p in ([], ["grid"], ["grid", "fifo"], ["peer"])]
        self.assertEqual(topology.deepest(endpoints), endpoints[2:])

    def test_only_output_alias_changes(self):
        module = {"ports": {"clk": {"direction": "input", "bits": [2]}},
                  "netnames": {}, "cells": {"state": {"type": "$dff"}}, "memories": {"ram": {"size": 16}}}
        original = copy.deepcopy(module)
        exported = topology.export_probes({"modules": {"top": module}}, "top",
            [{"bits": [4, 5], "width": 2}], "instrumented")["modules"]["instrumented"]
        self.assertEqual(exported["ports"].pop("hls_probe_values")["bits"], [4, 5] + ["0"]*30)
        exported["netnames"].pop("hls_probe_values")
        self.assertEqual(exported, original)

    def test_fifo_shape_fails_closed(self):
        name = "fifo_for_depth_2_ty_bits_32__with_bypass_register_push"
        ports = {n: {"bits": [i], "direction": "input"} for i, n in enumerate(
            ["clk", "push_valid", "push_ready", "pop_valid", "pop_ready"], 1)}
        fifo = {"ports": ports, "netnames": {"slots": {"bits": [7, 8]}, "is_full_bool": {"bits": [9]}},
                "cells": {"count": {"type": "$dff", "parameters": {"CLK_POLARITY": "1"},
                    "connections": {"CLK": [1], "Q": [7, 8]}}, "full": {"type": "$eq",
                    "connections": {"A": [7, 8], "B": ["0", "1"], "Y": [9]}}}}
        hierarchy = {"modules": {"top": {"cells": {"fifo": {"type": name}}}, name: fifo}}
        nets = {"fifo."+n: {"bits": p["bits"]} for n, p in ports.items()}
        nets["fifo.slots"] = {"bits": [7, 8]}
        flat = {"modules": {"top": {"netnames": nets}}}
        probes = [{"id": 0, "valid_bit": 2, "ready_bit": 3}, {"id": 1, "valid_bit": 4, "ready_bit": 5}]
        queues, unsupported = topology.fifo_resources(hierarchy, flat, "top", probes)
        self.assertEqual(queues[0]["capacity"], 2)
        self.assertEqual(unsupported, [])
        fifo["cells"]["full"]["connections"]["B"] = ["1", "1"]
        with self.assertRaisesRegex(ValueError, "unrecognized XLS FIFO occupancy"):
            topology.fifo_resources(hierarchy, flat, "top", probes)

    def test_clock_domain_rejected(self):
        ports = {"clk": {"bits": [1], "direction": "input"},
                 "x_valid": {"bits": [2], "direction": "output"},
                 "x_ready": {"bits": [3], "direction": "input"}}
        child = {"ports": ports}
        root = {"ports": ports, "cells": {"child": {"type": "child"}}}
        nets = {name: {"bits": p["bits"]} for name, p in ports.items()}
        nets.update({"child."+name: {"bits": p["bits"]} for name, p in ports.items()})
        nets["child.clk"] = {"bits": [99]}
        with self.assertRaisesRegex(ValueError, "clock domain"):
            topology.discover({"modules": {"top": root, "child": child}},
                {"modules": {"top": {"netnames": nets}}}, "top", "clk")

    def test_rtl_protocol(self):
        with tempfile.TemporaryDirectory() as stage:
            exe = str(Path(stage) / "test.vvp")
            subprocess.run(["iverilog", "-g2012", "-s", "hls_topology_debug_tb", "-o", exe,
                str(ROOT / "test/rtl/debug/hls_topology_debug_tb.sv"),
                *[str(ROOT / "priv/rtl/debug" / name) for name in
                  ["hls_debug_frame_rx.v", "hls_debug_route.v", "hls_topology_debug.v"]]], check=True)
            result = subprocess.run(["vvp", exe], capture_output=True, text=True, check=True, timeout=30)
            self.assertIn("PASS: routed topology queries", result.stdout)


if __name__ == "__main__":
    unittest.main()
