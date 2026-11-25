"""Regression witnesses for startup configuration, scoped nets and four-state primitive sampling."""

import json
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from flow import ROW, arrivals, native, route_geometry, vivado
from placed_flow import placed_rows
from routed_flow import route_result, trace
from openxc7_tree import RouteTree
from unittest.mock import Mock, patch
from init_bits import configured
from packed_buffers import append_buffers, input_sources
from pack import asset
from pin_activity import native_pins, read_asset, replay_pins, transitions
from scopes import links
import vivado_lane

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from capture import check_mapping_log


def packed(kind: str, inputs: dict, outputs: dict) -> dict:
    """Build a scalar packed cell with distinct bit and direction records."""
    return dict(
        type=kind,
        attributes={},
        connections={p: [b] for p, b in (inputs | outputs).items()},
        port_directions={
            **dict.fromkeys(inputs, "input"),
            **dict.fromkeys(outputs, "output"),
        },
    )


def delay(tag: str, a: str, b: str, n: int) -> str:
    """Emit one nextpnr delay record with equal rise and fall values in ps."""
    return f"({tag} {a} {b} ({n}:{n}:{n}) ({n}:{n}:{n}))"


class WorkloadTest(unittest.TestCase):
    """Run small witnesses independently of the archived decoder and device databases."""

    def test_per_output_clock_and_unknown_boundaries(self) -> None:
        """A known change on one output must not light its steady or unknown sibling."""
        with tempfile.TemporaryDirectory() as tmp:
            samples = Path(tmp) / "pins.txt"
            samples.write_text("00\n01\nx1\n10\nz0\n")
            self.assertEqual(transitions(samples, 2, 5), bytes([0, 1, 0, 1, 0]))

    def test_packed_identity_replay(self) -> None:
        """A shared physical input cannot replace I0. Chained buffers copy one exact carry bit."""
        cells = {
            "carry": packed("CARRY4", {}, {"O2": 2}),
            "zero": packed("PSEUDO_GND", {}, {"Y": 1}),
            "buf": packed("SLICE_LUTX", {"A2": 2, "A4": 1}, {"O5": 3}),
            "next": packed("SLICE_LUTX", {"A2": 3}, {"O5": 4}),
            "ground": packed("SLICE_LUTX", {"A2": 1}, {"O5": 5}),
        }
        cells["carry"]["attributes"] = {
            "X_ORIG_TYPE": "CARRY4",
            "X_ORIG_PORT_O2": "O[2]",
        }
        for name in ("buf", "next", "ground"):
            cells[name].update(
                parameters={"INIT": "0010"},
                attributes={
                    "X_ORIG_TYPE": "LUT1",
                    "X_ORIG_PORT_O5": "O",
                    "X_ORIG_PORT_A2": "I0",
                    "NEXTPNR_BEL": "SLICE_X1Y2/C5LUT",
                },
            )
        self.assertEqual(
            input_sources(cells, ["carry"]),
            {
                "buf": (0, "O2"),
                "next": (0, "O2"),
                "ground": None,
            },
        )
        with tempfile.TemporaryDirectory() as tmp:
            g = Path(tmp)
            b = dict(
                cells=1,
                mapped=1,
                kinds=["CARRY4"],
                placementOnly={"LUT1": 3},
                names=asset(g, "names", b"carry"),
                catalogue=asset(g, "cat", struct.pack("<iBh", 2, 0, -1)),
                chunks=[asset(g, "chunk", bytes([0, 1, 1, 0, 0, 1]))],
                changed=[0, 1, 0],
                unknown=[1, 0, 1],
            )
            replay = dict(cycles=3, chunk=3, backends={"openxc7": b})
            trace = g / "pins.txt"
            trace.write_text("0\n1\nx\n")
            pins = native_pins(["carry"], cells)
            keep, changes = replay_pins(g, replay, "openxc7", pins, trace, {(0, "O2")})
            self.assertEqual(changes, bytes([0, 1, 0]))
            grid = Mock(owners={"SLICE_X1Y2": 7})
            self.assertEqual(
                append_buffers(g, replay, cells, grid, keep),
                ["carry", "buf", "next", "ground"],
            )
            self.assertEqual(read_asset(g, b["chunks"][0]), bytes([0, 15, 7, 0, 0, 7]))
            self.assertEqual(read_asset(g, b["entire"]), bytes([7, 7]))
        cells["buf"]["parameters"]["INIT"] = "01"
        self.assertEqual(input_sources(cells, ["carry"]), {"ground": None})

    def test_split_ram_and_srl_launches(self) -> None:
        """Launch only from the connected SDF clock half and keep SRL data on the preceding edge."""
        cells = {
            "clk": packed("BUFGCTRL", {}, {"O": 1}),
            "ram": packed(
                "RAMB36E1_RAMB36E1", {"CLKARDCLKU": 1, "CLKARDCLKL": 2}, {"DOADO0": 3}
            ),
            "srl": packed("SLICE_LUTX", {"CLK": 1, "DI2": 3}, {"O6": 2}),
        }
        cells["srl"]["attributes"] = {"X_LUT_AS_SRL": "1", "X_ORIG_PORT_O6": "Q"}
        with tempfile.TemporaryDirectory() as tmp:
            sdf = Path(tmp) / "placed.sdf"
            for connected in (False, True):
                cells["ram"]["connections"]["CLKARDCLKL"] = [1 if connected else 2]
                rows = [
                    "(TIMESCALE 1ps)",
                    '(CELLTYPE "top")',
                    "(INSTANCE )",
                    delay("INTERCONNECT", "clk/O", "ram/CLKARDCLKU", 400),
                    delay(
                        "INTERCONNECT",
                        "clk/O" if connected else "srl/O6",
                        "ram/CLKARDCLKL",
                        110,
                    ),
                    delay("INTERCONNECT", "clk/O", "srl/CLK", 400),
                    delay("INTERCONNECT", "ram/DOADO0", "srl/DI2", 175),
                    '(CELLTYPE "BUFGCTRL")',
                    "(INSTANCE clk)",
                    '(CELLTYPE "RAMB36E1_RAMB36E1")',
                    "(INSTANCE ram)",
                    delay("IOPATH", "CLKARDCLKL", "DOADO0", 2080),
                    '(CELLTYPE "SLICE_LUTX")',
                    "(INSTANCE srl)",
                    delay("IOPATH", "CLK", "O6", 1102),
                    delay("IOPATH", "DI2", "O6", 124),
                ]
                if connected:
                    # Keep the SRL output consumed while its RAM clock sink moves to BUFG.
                    cells["ram"]["connections"]["ADDR0"] = [2]
                    cells["ram"]["port_directions"]["ADDR0"] = "input"
                    rows.insert(7, delay("INTERCONNECT", "srl/O6", "ram/ADDR0", 90))
                sdf.write_text("\n".join(rows))
                data, ports, pins, _ = placed_rows(
                    dict(cells=cells, netnames={}), sdf, list(cells)
                )
                timed = {
                    ports[i]: (start, end)
                    for (i,), (_, _, start, end) in zip(
                        struct.iter_unpack("<H", pins), ROW.iter_unpack(data)
                    )
                }
                self.assertNotIn(("DI2", "O6"), timed)
                self.assertAlmostEqual(timed["CLK", "O6"][1], 1.102, places=5)
                if connected:
                    self.assertAlmostEqual(timed["DOADO0", "DI2"][0], 2.080, places=5)
                else:
                    self.assertNotIn(("DOADO0", "DI2"), timed)

    def test_registered_state_lane(self) -> None:
        """Check reset priority, disabled captures and known adjacent pin changes across the register."""
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.object(vivado_lane, "CYCLES", 4),
        ):
            root = Path(directory)
            vendor = root / "vivado-sim-guard"
            native = root / "rtl-sim-guard"
            vendor.mkdir()
            native.mkdir()
            log = vendor / "console.log"
            states = "STATE 0 x 1 1 1 0 0\nSTATE 1 0 1 1 0 1 1\nSTATE 2 1 0 0 0 1 1\nSTATE 3 0 1 1 1 0 0\n"
            log.write_text(states)
            (native / "console.log").write_text(
                "LANE 0 x\nLANE 1 0\nLANE 2 1\nLANE 3 0\n"
            )
            observed = vivado_lane.changes(root, root)
            self.assertEqual(observed["knownRamClocks"], 3)
            self.assertEqual(
                observed["transitions"], {"ram": [2, 3], "q": [1, 3], "dsp": [1, 3]}
            )
            log.write_text(states.replace("STATE 2 1 0 0 0 1", "STATE 2 1 0 0 0 0"))
            with self.assertRaisesRegex(ValueError, "FDRE capture at C2"):
                vivado_lane.changes(root, root)

    def test_clock_to_pin_flow(self) -> None:
        """Use the launch pin as time zero and propagate only connected scalar bus lanes."""
        with tempfile.TemporaryDirectory() as directory:
            sdf = Path(directory) / "flow.sdf"
            sdf.write_text(
                "(INSTANCE ff)\n(IOPATH C Q[1:0] (8:9:10) (8:9:20))\n"
                "(INSTANCE lut)\n(IOPATH I0 O (9:10:30) (9:10:15))\n"
                "(INSTANCE )\n"
                "(INTERCONNECT clock_IBUF_BUFG_inst/O ff/C (900:900:900) (900:900:900))\n"
                "(INTERCONNECT ff/Q[1] lut/I0 (40:50:80) (40:50:70))\n"
                "(INTERCONNECT lut/O ff/D (20:30:40) (20:30:35))\n"
            )
            nets, local, counts = vivado(sdf, ["clock_IBUF_BUFG_inst", "ff", "lut"])
            self.assertEqual(counts["timedConnections"], 2)
            self.assertEqual(len(local), 2)
            self.assertEqual(nets[0][:2], ((1, "Q[1]"), (2, "I0")))
            self.assertAlmostEqual(nets[0][2], 0.02)
            self.assertAlmostEqual(nets[1][3], 0.17)
        with self.assertRaisesRegex(ValueError, "cycle"):
            arrivals([(1, 2, 1), (2, 1, 1)], {1: 0})

    def test_placed_flow(self) -> None:
        """Keep per-pin delay on a reconvergent sink and reject a missing or incorrectly joined branch."""

        cells = {
            "clock": packed("BUFGCTRL", {}, {"O": 1}),
            "ff": packed("SLICE_FFX", {"CK": 1, "D": 5}, {"Q": 2}),
            "slow": packed("SLICE_LUTX", {"A": 2}, {"O": 3}),
            "join": packed("SLICE_LUTX", {"A": 2, "B": 3}, {"O": 5}),
        }
        signals = [
            ("clock/O", "ff/CK", 5000),
            ("ff/Q", "join/A", 80),
            ("ff/Q", "slow/A", 200),
            ("slow/O", "join/B", 200),
            ("join/O", "ff/D", 50),
        ]
        gates = {
            "clock": [],
            "ff": [("CK", "Q", 100)],
            "slow": [("A", "O", 1000)],
            "join": [("A", "O", 50), ("B", "O", 80)],
        }

        text = "\n".join(
            [
                "(TIMESCALE 1ps)",
                '(CELLTYPE "top")',
                "(INSTANCE )",
                *(delay("INTERCONNECT", *v) for v in signals),
            ]
        )
        for name, stages in gates.items():
            text += f'\n(CELLTYPE "{cells[name]["type"]}")\n(INSTANCE {name})\n'
            text += "\n".join(delay("IOPATH", *v) for v in stages)
        with tempfile.TemporaryDirectory() as tmp:
            sdf = Path(tmp) / "placed.sdf"
            sdf.write_text(text)
            design = dict(cells=cells, netnames={})
            data, ports, _, stats = placed_rows(design, sdf, list(cells))
            nets = list(ROW.iter_unpack(data))[: stats["timedConnections"]]
            self.assertEqual(len(nets), 4)
            self.assertAlmostEqual(nets[0][3], 0.18)
            self.assertAlmostEqual(nets[-1][3], 1.63)
            self.assertIn(("Q", "A"), ports)
            for bad in (
                text.replace("ff/Q join/A", "slow/O join/A"),
                text.replace(delay("INTERCONNECT", *signals[1]), ""),
            ):
                sdf.write_text(bad)
                with self.assertRaises(ValueError):
                    placed_rows(design, sdf, list(cells))

    def test_registered_dsp_depth(self) -> None:
        """The cell-depth view cuts feedback at P and rejects mixed registered and bypass outputs."""
        cells = {
            "dsp": packed("DSP48E1", {"CLK": 1, "A": 2}, {"P": 3}),
            "lut": packed("LUT1", {"I": 3}, {"O": 2}),
        }
        cells["dsp"]["parameters"] = {"PREG": "1"}
        design = {"modules": {"phi_timing_harness": {"cells": cells}}}
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "synth.json"
            path.write_text(json.dumps(design))
            self.assertEqual(native(path, list(cells))[0], [(0, 1, 0, 1), (1, 0, 1, 2)])
            cells["dsp"]["connections"]["ACOUT"] = [4]
            cells["dsp"]["port_directions"]["ACOUT"] = "output"
            path.write_text(json.dumps(design))
            with self.assertRaisesRegex(ValueError, "additional outputs"):
                native(path, list(cells))

    def test_registered_dsp_launch(self) -> None:
        """Keep the multiplier cycle boundary even when the input arrives later than P launches."""
        cells = {
            "clk": packed("BUFGCTRL", {}, {"O": 1}),
            "ff": packed("SLICE_FFX", {"CK": 1, "D": 3}, {"Q": 2}),
            "mul": packed("DSP48E1_DSP48E1", {"CLK": 1, "A0": 2}, {"P0": 3}),
        }
        cells["mul"]["parameters"] = {"MREG": "1", "PREG": "1"}
        base = "\n".join([
            "(TIMESCALE 1ps)", '(CELLTYPE "top")', "(INSTANCE )",
            delay("INTERCONNECT", "clk/O", "ff/CK", 500),
            delay("INTERCONNECT", "clk/O", "mul/CLK", 500),
            delay("INTERCONNECT", "ff/Q", "mul/A0", 500),
            delay("INTERCONNECT", "mul/P0", "ff/D", 500),
            '(CELLTYPE "BUFGCTRL")', "(INSTANCE clk)",
            '(CELLTYPE "SLICE_FFX")', "(INSTANCE ff)", delay("IOPATH", "CK", "Q", 500),
            '(CELLTYPE "DSP48E1_DSP48E1")', "(INSTANCE mul)",
        ])
        with tempfile.TemporaryDirectory() as tmp:
            sdf = Path(tmp) / "design.sdf"
            for qualified in (False, True):
                sdf.write_text(base + ("\n" + delay("IOPATH", "CLK", "P0", 383) if qualified else ""))
                data, ports, ids, stats = placed_rows(dict(cells=cells, netnames={}), sdf, list(cells))
                rows = {
                    ports[pid]: (a, b, start, end)
                    for (pid,), (a, b, start, end) in zip(struct.iter_unpack("<H", ids), ROW.iter_unpack(data))
                }
                self.assertAlmostEqual(rows["Q", "A0"][3], 1)
                self.assertNotIn(("A0", "P0"), rows)
                if qualified:
                    self.assertEqual(stats["registeredProducts"], [2])
                    self.assertAlmostEqual(rows["P0", "D"][2], 0.383)
                    self.assertAlmostEqual(rows["CLK", "P0"][2], 0)
                else:
                    self.assertNotIn(("P0", "D"), rows)
                    self.assertNotIn("registeredProducts", stats)

    def test_partial_route(self) -> None:
        """Reject truncated or debug-accepted routes even when a checkpoint was emitted."""
        log = (
            "Info:     iter=7 wires=105 overused=0 overuse=0 archfail=0\n"
            "Info: Router2 time 0.01s\nInfo: Wrote 113 fixed-route pips across 12 nets to 'fixed.txt'\n"
        )
        self.assertEqual(route_result(log)["fixedPips"], 113)
        for bad in (
            log.replace("archfail=0", "archfail=1"),
            log + "Warning: SKIP_FAILED_ARCS",
            log.replace("Wrote 113", "Skipped 113"),
        ):
            with self.assertRaisesRegex(ValueError, "incomplete native route"):
                route_result(bad)

    def test_vivado_physical_sinks(self) -> None:
        """Keep separate RAM pin routes under one timing row and reject duplicate terminal bindings."""
        from types import SimpleNamespace

        grid = SimpleNamespace(owners={"SRC": 2, "LOW": 3, "HIGH": 5})
        route = "+RAM/L\t\tSRC LOW\tRAM/U\tRAM/ENABLE_MUX\tSRC HIGH"
        kind, primary, paths = route_geometry(route, grid)
        self.assertEqual((kind, primary), ("pipBranches", [2, 3]))
        self.assertEqual(
            paths,
            [
                {"sink": "RAM/L"},
                {"sink": "RAM/U", "via": "RAM/ENABLE_MUX", "tiles": [2, 5]},
            ],
        )
        with self.assertRaisesRegex(ValueError, "physical sink"):
            route_geometry(route.replace("RAM/U", "RAM/L"), grid)
        with self.assertRaisesRegex(ValueError, "incomplete"):
            route_geometry("+RAM/L\t", grid)

    def test_routed_pin_branches(self) -> None:
        """Require a unique switch to the physical input even when the net also owns its sibling."""
        top = {
            "cells": {
                "src": {
                    "connections": {"Q": [7]},
                    "port_directions": {"Q": "output"},
                    "attributes": {"NEXTPNR_BEL": "X/Q"},
                },
                "sink": {
                    "type": "SLICE_LUTX",
                    "connections": {"A2": [7]},
                    "port_directions": {"A2": "input"},
                    "attributes": {"NEXTPNR_BEL": "SLICE_X0Y0/A6LUT"},
                },
            },
            "netnames": {"net": {"bits": [7]}},
        }
        physical = "SITEWIRE/SLICE_X0Y0/A2"
        permuted = "SITEWIRE/SLICE_X0Y0/A1"
        source = "driver"
        names = Mock()
        names.bel_wire.side_effect = (
            lambda bel, port: source if port == "Q" else physical
        )
        tree = RouteTree.__new__(RouteTree)
        tree.bound = {source: "", permuted: "pip"}
        tree.parent = {permuted: (source, "switch", "pip", 0)}
        tree.candidates = {("SLICE_X0Y0", "A", 2): [(permuted, "switch")]}
        tree.permutation_inputs = {permuted: physical}
        query = (top, names, tree, "net", ("src", "Q"), ("sink", "A2"))
        self.assertEqual(trace(*query), ("permuted", [permuted]))
        tree.candidates.clear()
        self.assertEqual(trace(*query), ("unresolved", None))
        tree.bound[physical] = "exact"
        tree.parent[physical] = (source, "switch2", "exact", 1)
        self.assertEqual(trace(*query), ("routed", [physical]))
        tree.permutation_inputs[physical] = permuted
        self.assertEqual(trace(*query), ("unresolved", None))
        tree.candidates[("SLICE_X0Y0", "A", 2)] = [(permuted, "switch")]
        self.assertEqual(trace(*query), ("permuted", [permuted]))
        top["cells"]["sink"]["connections"]["A2"] = [8]
        with self.assertRaisesRegex(ValueError, "wrong packed pin"):
            trace(*query)

    def test_effective_map(self) -> None:
        """Reject a run whose executable opened a different installation's technology map."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            library = root / "qualified/share/brams_xc6v_map.v"
            log = root / "map.log"
            log.write_text(
                "1.2. Executing Verilog-2005 frontend: " + str(library) + "\n"
            )
            check_mapping_log(log, library)
            with self.assertRaises(ValueError):
                check_mapping_log(log, root / "stock/share/brams_xc6v_map.v")

    def test_configuration(self) -> None:
        """Keep defined startup bits and reject a new class of unqualified unknowns."""
        cells = {
            "ff": {"type": "FDRE", "parameters": {"INIT": "x"}},
            "mem": {
                "type": "RAMB18E1",
                "parameters": {"INIT_01": "10xz", "WRITE_MODE_A": "READ_FIRST"},
            },
        }
        with tempfile.TemporaryDirectory() as directory:
            d = Path(directory)
            s = d / "source.json"

            def write() -> None:
                """Write the current set of test primitives as a fresh input."""
                s.write_text(
                    json.dumps({"modules": {"phi_timing_harness": {"cells": cells}}})
                )

            write()
            configured(s, d / "view", d / "receipt")
            found = json.loads((d / "view").read_text())["modules"][
                "phi_timing_harness"
            ]["cells"]
            self.assertEqual(
                found["mem"]["parameters"],
                {"INIT_01": "1000", "WRITE_MODE_A": "READ_FIRST"},
            )
            self.assertEqual(found["ff"]["parameters"]["INIT"], "0")
            self.assertEqual(
                json.loads((d / "receipt").read_text())["RAMB18E1.INIT_nn"], 2
            )
            cells["mem"]["parameters"]["INIT_A"] = "1x"
            write()
            with self.assertRaisesRegex(ValueError, "nonzero BRAM"):
                configured(s, d / "bad", d / "receipt")
            del cells["mem"]["parameters"]["INIT_A"]
            cells["ff"]["type"] = "LUT1"
            write()
            with self.assertRaisesRegex(ValueError, "unqualified"):
                configured(s, d / "bad", d / "receipt")

    def test_scopes(self) -> None:
        """Use exact hierarchy or named output bits, leaving shared and unnamed nets unassigned."""
        units = [{"path": "decoder.a"}, {"path": "decoder.b"}]
        cell = lambda bit: {
            "connections": {"O": [bit]},
            "port_directions": {"O": "output"},
        }
        module = {
            "netnames": {"decoder.a.q": {"bits": [4, 5]}, "decoder.b.q": {"bits": [5]}},
            "cells": {
                "direct": cell(4),
                "shared": cell(5),
                "unnamed": cell(6),
                r"$flatten\decoder.\a.$mul": cell(6),
            },
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "native").mkdir()
            (root / "native/synth.json").write_text(
                json.dumps({"modules": {"phi_timing_harness": module}})
            )
            self.assertEqual(
                links("openxc7", root, units, []),
                {"direct": 0, r"$flatten\decoder.\a.$mul": 0},
            )
            self.assertEqual(
                links(
                    "vivado",
                    root,
                    units,
                    [("decoder/b/gate", "LUT"), ("decoder/bb/gate", "LUT")],
                ),
                {"decoder/b/gate": 1},
            )

    @unittest.skipUnless(
        all(shutil.which(t) for t in ("iverilog", "iverilog-vpi", "vvp")),
        "Icarus VPI toolchain",
    )
    def test_transition_masks(self) -> None:
        """Check a known toggle alongside an unknown bit, a stable edge and a 33-bit output."""
        bench = """`timescale 1ns/1ps
module FDRE(output Q); assign Q=1'b1; endmodule
module primitive_model(output reg [32:0] q);
initial begin q=33'b0; #14; q[32]=1; q[2]=1'bx; #15; q[2]=1; end
endmodule
module holder; wire [32:0] q; wire qb; primitive_model m(q); FDRE z(qb); endmodule
module functional_tb; reg clock=0; holder dut(); initial begin repeat(5) begin #5;clock=1;#5;clock=0;end #1;$finish;end endmodule
"""
        with tempfile.TemporaryDirectory() as directory:
            d = Path(directory)
            (d / "cells.v").write_text(bench)
            (d / "primitive-types.txt").write_text("FDRE\nprimitive_model\n")
            for cmd in (
                ["iverilog-vpi", HERE / "transitions.cpp"],
                ["iverilog", "-o", "design", "cells.v"],
                ["vvp", "-M.", "-mtransitions", "design"],
            ):
                subprocess.run(cmd, cwd=d, check=True, capture_output=True)
            self.assertEqual(
                (d / "cells.tsv").read_text(), "m\tprimitive_model\nz\tFDRE\n"
            )
            self.assertEqual((d / "initial-q.txt").read_text(), "-1")
            self.assertEqual(
                (d / "changes.bin").read_bytes(), bytes([0, 3, 1, 1, 0, 1, 0, 0, 0, 0])
            )


if __name__ == "__main__":
    unittest.main()
