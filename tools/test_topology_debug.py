#!/usr/bin/env python3
"""Structural discovery checks and query-service RTL regression (no XLS needed)."""
import copy
from pathlib import Path
import subprocess
import tempfile
import unittest

import topology_debug as topology
from measure_topology_debug import cell_counts

ROOT = Path(__file__).resolve().parents[1]


class DiscoveryTests(unittest.TestCase):
    def test_area_includes_distributed_ram(self):
        counts = cell_counts({'LUT6': 3, 'LUT2': 1, 'RAM32M': 2, 'RAM64X1D': 1,
                              'FDRE': 7, 'RAMB18E1': 1})
        self.assertEqual(counts, {'LUT': 14, 'LUT_logic': 4, 'LUT_RAM': 10, 'FF': 7, 'RAMB18': 1, 'RAMB36': 0})
        with self.assertRaisesRegex(ValueError, 'unaccounted distributed RAM'):
            cell_counts({'RAM_UNKNOWN': 1})

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
        self.assertEqual(exported["ports"].pop("hls_probe_values")["bits"], [4, 5] + ["0"]*62)
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

    def test_actor_projection_binding(self):
        bank = {"index": 0, "ram": "scheduler_0_state", "slots": 2, "width": 65,
                "fields": {"phase": {"offset": 0, "width": 8},
                           "enter_pending": {"offset": 48, "width": 1},
                           "failure": {"offset": 49, "width": 16}},
                "failures": {"16": {"kind": "case_clause", "file": "fixture.erl", "line": 20}},
                "module": "fixture", "phases": ["boot", "active"],
                "actors": [{"slot": i, "key": str(i)*64, "name": str(i)} for i in range(2)]}
        projection = {"schema": 2, "banks": [bank]}
        ports = {"clk": {"bits": [1], "direction": "input"},
                 "wr_en": {"bits": [2], "direction": "input"},
                 "wr_addr": {"bits": [3], "direction": "input"},
                 "wr_data": {"bits": list(range(10, 75)), "direction": "input"}}
        hierarchy = {"modules": {"top": {"cells": {"shell": {"type": "shell"}}},
            "shell": {"cells": {"scheduler_0_state": {"type": "ram"}}},
            "ram": {"ports": ports, "attributes": {"hdlname": "hls_1r1w_ram"}}}}
        hierarchy["modules"]["ram"]["cells"] = {
            "write": {"type": "$memwr_v2", "parameters": {"CLK_ENABLE": "1", "CLK_POLARITY": "1", "MEMID": "memory"},
                      "connections": {"CLK": [1], "ADDR": [3], "DATA": list(range(10,75)), "EN": [90]*65}},
            "enable": {"type": "$mux", "connections": {"S": [2], "Y": [90]*65, "A": ["0"]*65, "B": ["1"]*65}}}
        hierarchy["modules"]["ram"]["memories"] = {"memory": {"width": 65, "size": 2, "start_offset": 0}}
        flat = {"netnames": {"shell.scheduler_0_state."+k: {"bits": p["bits"]} for k,p in ports.items()}}
        def discover(p=projection, f=flat, h=hierarchy):
            return topology.actors.discover(p, ["shell"], h, f, "top", 1)
        banks = discover()
        escaped = copy.deepcopy(hierarchy)
        escaped["modules"]["ram"]["attributes"]["hdlname"] = "\\hls_1r1w_ram"
        self.assertEqual(discover(h=escaped), banks)
        self.assertEqual(banks[0]["taps"], [2, 3, *range(10, 18), *range(58, 75)])
        resources = topology.actors.resources(banks, 5)
        self.assertEqual([r["id"] for r in resources], [5, 6])
        for mutation, message in [
            (lambda b: b.update(width=66), "port mismatch"),
            (lambda b: b["fields"]["failure"].update(offset=65), "invalid actor field"),
            (lambda b: b["fields"]["failure"].update(offset=0), "overlapping"),
            (lambda b: b["actors"][1].update(slot=0), "slots"),
            (lambda b: b["actors"][1].update(key="0"*64), "duplicate"),
            (lambda b: b.update(phases=["boot", "boot"]), "codebook")]:
            bad = copy.deepcopy(projection)
            mutation(bad["banks"][0])
            with self.assertRaisesRegex(ValueError, message):
                discover(bad)
        bad = copy.deepcopy(flat)
        bad["netnames"]["shell.scheduler_0_state.clk"]["bits"] = [99]
        with self.assertRaisesRegex(ValueError, "clock domain"):
            discover(f=bad)
        bad = copy.deepcopy(hierarchy)
        bad["modules"]["ram"]["attributes"]["hdlname"] = "other_ram"
        with self.assertRaisesRegex(ValueError, "unsupported state RAM"):
            discover(h=bad)

        bad = copy.deepcopy(hierarchy)
        bad["modules"]["ram"]["cells"]["enable"]["connections"]["A"] = ["1"]*65
        with self.assertRaisesRegex(ValueError, "accepted-write"):
            discover(h=bad)
        bad = copy.deepcopy(hierarchy)
        bad["modules"]["ram"]["cells"]["write"]["parameters"]["CLK_POLARITY"] = "0"
        with self.assertRaisesRegex(ValueError, "write clock"):
            discover(h=bad)

        # The semantic output belongs to the generator and must be permanently
        # ready. A query cannot own this handshake or stall scheduler progress.
        bank["mailbox"] = {"capacity": 3, "width": 24, "port": "_scheduler_0_mailbox_debug_out"}
        port = bank["mailbox"]["port"]
        connections = {port: list(range(100, 148)), port+"_vld": [148],
                       port+"_rdy": ["1"], "clk": [1]}
        hierarchy["modules"]["shell"]["cells"]["application"] = {"type": "application", "connections": connections}
        hierarchy["modules"]["application"] = {"ports": {
            name: {"bits": bits, "direction": "input" if name in ("clk", port+"_rdy") else "output"}
            for name, bits in connections.items()}}
        flat["netnames"].update({"shell.application."+name: {"bits": bits} for name, bits in connections.items()})
        observed = discover()
        self.assertEqual(observed[0]["taps"][-49:], [148, *range(100, 148)])
        self.assertEqual(topology.actors.resources(observed, 5)[0]["mailbox_capacity"], 3)
        connections[port+"_rdy"] = [55]
        with self.assertRaisesRegex(ValueError, "always be ready"):
            discover()
        connections[port+"_rdy"] = ["1"]
        flat["netnames"]["shell.application.clk"]["bits"] = [99]
        with self.assertRaisesRegex(ValueError, "clock mismatch"):
            discover()

    def test_snapshot_rtl(self):
        with tempfile.TemporaryDirectory() as stage:
            exe = str(Path(stage) / "test.vvp")
            subprocess.run(["iverilog", "-g2012", "-s", "hls_actor_snapshot_tb", "-o", exe,
                str(ROOT / "test/rtl/debug/hls_actor_snapshot_tb.sv"),
                str(ROOT / "priv/rtl/debug/hls_actor_snapshot.v")], check=True)
            result = subprocess.run(["vvp", exe], capture_output=True, text=True, check=True, timeout=30)
            self.assertIn("PASS: committed writes", result.stdout)

    def test_generated_bank_selection(self):
        # Mixed banks cross both physical/actor and low-address wrap boundaries.
        # Distinct data at every global ID detects aliasing and bank overlap.
        banks, offset, resource = [], 0, 5
        setup = ['for(i=0;i<5;i=i+1) begin probe_values[i*64+:64]=i+100; expected[i]=i+100; end']
        for index, slots, mailbox in ((0, 3, True), (1, 9, False), (2, 1, True)):
            aw = max(1, (slots-1).bit_length())
            width = 1 + aw + 25 + (1 + 24*slots if mailbox else 0)
            bank = {'index': index, 'slots': slots, 'address_width': aw, 'taps': [0]*width}
            if mailbox:
                bank['mailbox'] = {}
            banks.append(bank)
            for slot in range(slots):
                state = 1000 + resource + slot
                metadata = 2000 + resource + slot if mailbox else 0
                setup += [f'@(negedge clk); actor_writes=0; actor_writes[{offset}]=1;',
                          f'actor_writes[{offset+1}+:{aw}]={slot}; actor_writes[{offset+1+aw}+:25]={state};',
                          f'expected[{resource+slot}]={{32\'d{metadata}, 32\'d{(1 << 25) + state}}};']
                if mailbox:
                    setup += [f'actor_writes[{offset+1+aw+25}]=1;']
                    setup += [f'actor_writes[{offset+1+aw+26+24*j}+:24]={2000+resource+j};'
                              for j in range(slots)]
                setup += ['@(posedge clk); #1;']
            offset += width
            resource += slots
        bench = ['module selector_tb; reg clk=0,reset=1; always #5 clk=~clk;',
                 'reg [31:0] address; reg [319:0] probe_values;',
                 f'reg [{offset-1}:0] actor_writes=0; reg [63:0] expected[0:{resource-1}]; integer i;',
                 topology.actors.wrapper(banks, 5, 'clk', 'reset', False),
                 'assign probe_address=address;',
                 'initial begin repeat(2) @(negedge clk); reset=0;', *setup,
                 '@(negedge clk); actor_writes=0;',
                 f'for(i=0;i<{resource};i=i+1) begin address=i; #1;',
                 'if(probe_value !== expected[i]) $fatal(1,"wrong resource %0d",i); end',
                 f'address={resource}; #1; if(probe_value !== 0) $fatal(1,"end of catalog");',
                 "address=32'hfffffff9; #1; if(probe_value !== 0) $fatal(1,\"high-ID alias\");",
                 '$display("PASS: generated bank selection"); $finish; end endmodule']
        with tempfile.TemporaryDirectory() as stage:
            source, exe = Path(stage) / 'selector.sv', Path(stage) / 'selector.vvp'
            source.write_text('\n'.join(bench))
            subprocess.run(['iverilog', '-g2012', '-s', 'selector_tb', '-o', str(exe), str(source),
                            str(ROOT / 'priv/rtl/debug/hls_actor_snapshot.v')], check=True)
            result = subprocess.run(['vvp', str(exe)], capture_output=True, text=True, check=True, timeout=30)
            self.assertIn('PASS: generated bank selection', result.stdout)

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
