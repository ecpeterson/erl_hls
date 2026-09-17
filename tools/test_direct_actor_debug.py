#!/usr/bin/env python3
"""Validate compiler-owned direct actor probes without building XLS."""
import copy
from pathlib import Path
import subprocess
import tempfile
import unittest

import topology_debug as topology

ROOT = Path(__file__).resolve().parents[1]


def direct_fixture():
    port = "_actor_worker_debug_out"
    direct = {
        "index": 0, "slots": 1, "width": 25, "port": port,
        "fields": {"phase": {"offset": 0, "width": 8},
                   "enter_pending": {"offset": 8, "width": 1},
                   "failure": {"offset": 9, "width": 16}},
        "module": "worker", "phases": ["boot", "active"],
        "failures": {"16": {"kind": "case_clause", "file": "worker.erl", "line": 20}},
        "actors": [{"slot": 0, "key": "a" * 64, "name": "worker"}],
    }
    connections = {"clk": [1], port: list(range(100, 125)),
                   port + "_vld": [200], port + "_rdy": ["1"]}
    application = {
        "ports": {name: {"bits": bits, "direction": "input" if
                  name in ("clk", port + "_rdy") else "output"}
                  for name, bits in connections.items()}}
    hierarchy = {"modules": {
        "top": {"cells": {"shell": {"type": "shell"}}},
        "shell": {"cells": {"application": {"type": "application", "connections": connections}}},
        "application": application}}
    flat = {"ports": {"clk": {"direction": "input", "bits": [1]}},
            "netnames": {"shell.application." + name: {"bits": bits}
                         for name, bits in connections.items()},
            "cells": {"state": {"type": "$dff", "connections": {"CLK": [1], "Q": [500]}}},
            "memories": {"unrelated": {"size": 8, "width": 32}}}
    return {"schema": 3, "banks": [], "direct": [direct]}, hierarchy, flat


def add_shared_bank(projection, hierarchy, flat):
    bank = {"index": 0, "ram": "scheduler_0_state", "slots": 2, "width": 65,
            "fields": {"phase": {"offset": 0, "width": 8},
                       "enter_pending": {"offset": 48, "width": 1},
                       "failure": {"offset": 49, "width": 16}},
            "failures": {}, "module": "shared", "phases": ["idle", "busy"],
            "actors": [{"slot": i, "key": str(i) * 64, "name": str(i)} for i in range(2)]}
    projection["banks"].append(bank)
    projection["direct"][0]["index"] = 1
    ports = {name: {"direction": "input", "bits": bits} for name, bits in
             {"clk": [1], "wr_en": [2], "wr_addr": [3], "wr_data": list(range(10, 75))}.items()}
    hierarchy["modules"]["shell"]["cells"]["scheduler_0_state"] = {"type": "ram"}
    hierarchy["modules"]["ram"] = {
        "ports": ports, "attributes": {"hdlname": "hls_1r1w_ram"},
        "memories": {"memory": {"width": 65, "size": 2, "start_offset": 0}},
        "cells": {
            "write": {"type": "$memwr_v2", "parameters": {
                "CLK_ENABLE": "1", "CLK_POLARITY": "1", "MEMID": "memory"},
                "connections": {"CLK": [1], "ADDR": [3], "DATA": list(range(10, 75)), "EN": [90] * 65}},
            "enable": {"type": "$mux", "connections": {
                "S": [2], "Y": [90] * 65, "A": ["0"] * 65, "B": ["1"] * 65}}}}
    flat["netnames"].update({"shell.scheduler_0_state." + name: {"bits": port["bits"]}
                            for name, port in ports.items()})


def discover(projection, hierarchy, flat):
    return topology.actors.discover(projection, ["shell"], hierarchy, flat, "top", 1)


class DirectActorTests(unittest.TestCase):
    def test_direct_binding_and_alias_only_export(self):
        projection, hierarchy, flat = direct_fixture()
        banks = discover(projection, hierarchy, flat)
        self.assertEqual(len(banks), 1)
        self.assertEqual(banks[0]["taps"], [200, "0", *range(100, 125)])
        self.assertEqual(banks[0]["address_width"], 1)
        resource, = topology.actors.resources(banks, 5)
        self.assertEqual({key: resource[key] for key in ("id", "bank", "slot", "width", "key")},
                         {"id": 5, "bank": 0, "slot": 0, "width": 26, "key": "a" * 64})
        self.assertNotIn("mailbox_capacity", resource)

        original = copy.deepcopy(flat)
        exported = topology.export_probes({"modules": {"top": flat}}, "top",
            [{"bits": [2, 3], "width": 2}], "instrumented", banks)["modules"]["instrumented"]
        self.assertEqual(exported["ports"]["hls_actor_writes"]["bits"], banks[0]["taps"])
        for section in ("ports", "netnames"):
            exported[section].pop("hls_probe_values")
            exported[section].pop("hls_actor_writes")
        self.assertEqual(exported, original)

    def test_direct_contract_fails_closed(self):
        for field, bad_value in (("index", 1), ("slots", 2), ("width", 26),
                                 ("phases", ["active", "active"]), ("phases", [])):
            with self.subTest(field=field, value=bad_value):
                projection, hierarchy, flat = direct_fixture()
                projection["direct"][0][field] = bad_value
                with self.assertRaises(ValueError):
                    discover(projection, hierarchy, flat)
        for mutation in (
            lambda actor: actor["fields"]["failure"].update(offset=25),
            lambda actor: actor["fields"]["failure"].update(offset=8),
            lambda actor: actor["fields"]["phase"].update(width=7),
            lambda actor: actor["actors"][0].update(slot=1),
            lambda actor: actor["actors"][0].update(key="z" * 64),
            lambda actor: actor["actors"].append(copy.deepcopy(actor["actors"][0])),
        ):
            projection, hierarchy, flat = direct_fixture()
            mutation(projection["direct"][0])
            with self.assertRaises(ValueError):
                discover(projection, hierarchy, flat)

    def test_unique_output_with_checked_hierarchy_and_flat_widths(self):
        for suffix, direction in (("", "input"), ("_vld", "input"), ("_rdy", "output")):
            with self.subTest(suffix=suffix, defect="direction"):
                projection, hierarchy, flat = direct_fixture()
                port = projection["direct"][0]["port"] + suffix
                hierarchy["modules"]["application"]["ports"][port]["direction"] = direction
                with self.assertRaises(ValueError):
                    discover(projection, hierarchy, flat)
        for suffix in ("", "_vld", "_rdy"):
            for location in ("module", "cell", "flat"):
                with self.subTest(suffix=suffix, location=location, defect="width"):
                    projection, hierarchy, flat = copy.deepcopy(direct_fixture())
                    port = projection["direct"][0]["port"] + suffix
                    if location == "module":
                        hierarchy["modules"]["application"]["ports"][port]["bits"] = [777, 778]
                    elif location == "cell":
                        hierarchy["modules"]["shell"]["cells"]["application"]["connections"][port] = [777, 778]
                    else:
                        flat["netnames"]["shell.application." + port]["bits"] = [777, 778]
                    with self.assertRaises(ValueError):
                        discover(projection, hierarchy, flat)
        for matches in (0, 2):
            with self.subTest(matches=matches):
                projection, hierarchy, flat = direct_fixture()
                cells = hierarchy["modules"]["shell"]["cells"]
                if matches == 0:
                    cells.clear()
                else:
                    cells["duplicate"] = copy.deepcopy(cells["application"])
                with self.assertRaises(ValueError):
                    discover(projection, hierarchy, flat)

    def test_ready_and_clock_cannot_depend_on_query_or_another_domain(self):
        for signal, value in (("ready", [55]), ("ready", ["0"]), ("clock", [99])):
            # Hierarchical clock numbers are local to that module; only the
            # flattened net identifies the selected application clock.
            for location in (("cell", "flat") if signal == "ready" else ("flat",)):
                with self.subTest(signal=signal, location=location, value=value):
                    projection, hierarchy, flat = direct_fixture()
                    port = projection["direct"][0]["port"] + "_rdy" if signal == "ready" else "clk"
                    if location == "cell":
                        hierarchy["modules"]["shell"]["cells"]["application"]["connections"][port] = value
                    else:
                        flat["netnames"]["shell.application." + port]["bits"] = value
                    with self.assertRaises(ValueError):
                        discover(projection, hierarchy, flat)

    def test_mixed_bank_identity_and_order(self):
        projection, hierarchy, flat = direct_fixture()
        add_shared_bank(projection, hierarchy, flat)
        banks = discover(projection, hierarchy, flat)
        resources = topology.actors.resources(banks, 5)
        self.assertEqual([(r["id"], r["bank"], r["slot"]) for r in resources],
                         [(5, 0, 0), (6, 0, 1), (7, 1, 0)])
        projection["direct"][0]["actors"][0]["key"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "duplicate"):
            discover(projection, hierarchy, flat)

    def test_reduction_projects_metadata_only(self):
        projection, hierarchy, flat = direct_fixture()
        direct = projection["direct"][0]
        direct["width"] = 78
        reduction = {"width": 53, "fields": {}, "sites": [{"id": 0,
            "phase": "active", "name": "sum", "population": {
                "mode": "members", "size": 3, "members": [10, 20, 30]}}]}
        source, observation = 25, 56
        for name, size in (("status", 2), ("site", 1), ("key", 32), ("remaining", 2), ("failure", 16)):
            reduction["fields"][name] = {"offset": source, "width": size, "observation_offset": observation}
            source += size
            observation += size
        direct["reduction"] = reduction
        data = list(range(300, 378))
        port = direct["port"]
        hierarchy["modules"]["application"]["ports"][port]["bits"] = data
        hierarchy["modules"]["shell"]["cells"]["application"]["connections"][port] = data
        flat["netnames"]["shell.application." + port]["bits"] = data
        banks = discover(projection, hierarchy, flat)
        self.assertEqual(banks[0]["taps"], [200, "0", *data])
        resource, = topology.actors.resources(banks, 5)
        self.assertEqual(resource["width"], 109)
        for mutation in (
            lambda r: r["fields"]["status"].update(offset=24),
            lambda r: r["fields"]["site"].update(observation_offset=60),
            lambda r: r["sites"][0]["population"].update(members=[10, 20, 20]),
        ):
            bad = copy.deepcopy(projection)
            mutation(bad["direct"][0]["reduction"])
            with self.assertRaises(ValueError):
                discover(bad, hierarchy, flat)

    def test_generated_mixed_snapshots_retain_only_valid_commits(self):
        projection, hierarchy, flat = direct_fixture()
        add_shared_bank(projection, hierarchy, flat)
        banks = discover(projection, hierarchy, flat)
        # A second direct row puts one-slot collectors at both address parities.
        second = copy.deepcopy(banks[1])
        second["index"] = 2
        second["width"] = 78
        second["actors"][0]["key"] = "b" * 64
        second["reduction"] = {"width": 53}
        second["taps"] += list(range(300, 353))
        banks.append(second)
        width = sum(len(bank["taps"]) for bank in banks)
        setup, offset, resource = [], 0, 5
        for bank in banks:
            for slot in range(bank["slots"]):
                value = (1 << 9) + (slot << 8) + resource
                aw = bank["address_width"]
                reduction_width = bank.get("reduction", {}).get("width", 0)
                reduction = (1 << (reduction_width - 1)) + resource if reduction_width else 0
                packed = value + (reduction << 25)
                expected = (1 << 25) + value + (reduction << 56)
                setup += [f"@(negedge clk); actor_writes=0; actor_writes[{offset}]=1;",
                          f"actor_writes[{offset+1}+:{aw}]={slot};",
                          f"actor_writes[{offset+1+aw}+:{25+reduction_width}]={25+reduction_width}'d{packed};",
                          f"expected[{resource}]=128'd{expected};", "@(posedge clk); #1;"]
                resource += 1
            offset += len(bank["taps"])
        bench = ["module direct_snapshot_tb; reg clk=0,reset=1; always #5 clk=~clk;",
                 "reg [31:0] address; reg [319:0] probe_values=0;",
                 f"reg [{width-1}:0] actor_writes=0; reg [127:0] expected[0:{resource-1}]; integer i;",
                 topology.actors.wrapper(banks, 5, "clk", "reset", False),
                 "assign probe_address=address;",
                 "initial begin repeat(2) @(negedge clk);",
                 f"for(i=5;i<{resource};i=i+1) begin address=i; #1;",
                 "if(probe_value !== 0) $fatal(1,\"snapshot visible before commit\"); end",
                 "reset=0;", *setup,
                 # Invalid observation data must not replace the last commit.
                 "@(negedge clk); actor_writes='1;"]
        offset = 0
        for bank in banks:
            bench += [f"actor_writes[{offset}]=0;"]
            offset += len(bank["taps"])
        bench += ["repeat(3) @(posedge clk); #1;",
                  f"for(i=5;i<{resource};i=i+1) begin address=i; #1;",
                  "if(probe_value !== expected[i]) $fatal(1,\"changed committed actor %0d\",i); end",
                  f"address={resource}; #1; if(probe_value !== 0) $fatal(1,\"end of catalog\");",
                  "address=32'hfffffff7; #1; if(probe_value !== 0) $fatal(1,\"high-ID alias\");",
                  "@(negedge clk); reset=1; @(posedge clk); #1;",
                  f"for(i=5;i<{resource};i=i+1) begin address=i; #1;",
                  "if(probe_value !== 0) $fatal(1,\"reset retained actor validity\"); end",
                  '$display("PASS: direct snapshots retain committed values and reset validity"); $finish; end endmodule']
        with tempfile.TemporaryDirectory() as stage:
            source, exe = Path(stage) / "snapshot.sv", Path(stage) / "snapshot.vvp"
            source.write_text("\n".join(bench))
            subprocess.run(["iverilog", "-g2012", "-s", "direct_snapshot_tb", "-o", str(exe), str(source),
                            str(ROOT / "priv/rtl/debug/hls_actor_snapshot.v")], check=True)
            result = subprocess.run(["vvp", str(exe)], capture_output=True, text=True, check=True, timeout=30)
            self.assertIn("PASS: direct snapshots", result.stdout)


if __name__ == "__main__":
    unittest.main()
