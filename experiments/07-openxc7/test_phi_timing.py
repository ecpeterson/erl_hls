#!/usr/bin/env python3
"""Fast report/provenance checks; no FPGA tool installation required."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import phi_timing as timing
# The existing lightweight CI entry point also checks the physical LUT oracle.
from lut_legality.test_check import CheckerTest
from timing_coverage.test_check import CoverageTest
from timing_chains.test_replicate import ReplicationTest
from timing_chains.test_probe import HarnessTest


def path_report(clock, logic, routing):
    return (f"Info: Critical path report for clock '{clock}' (posedge -> posedge):\n"
            "Info: Source register.Q\nInfo: Sink destination.D\n"
            f"Info: {logic} ns logic, {routing} ns routing\n")


class TimingReports(unittest.TestCase):
    """Check profile geometry, retained hardware, report coverage and provenance."""

    @unittest.skipUnless(shutil.which("iverilog") and shutil.which("vvp"), "Icarus is not installed")
    def test_public_event_harness_geometry_and_rejection(self) -> None:
        """Check rectangular masks, omitted planes and rejection of an invalid coordinate."""
        # A small independent source emits correction/status pairs for every
        # coordinate and step. Its accepted-beat index advances only on ready.
        source = """
module event_source #(parameter W=2, H=3, BAD=0)(
    input clock, resetn, ready, output [127:0] frame);
    reg [31:0] index = 0;
    wire [31:0] actor = (index / 2) % (W*H);
    wire [15:0] x = BAD ? W : actor / H;
    wire [15:0] y = actor % H;
    wire [31:0] step = (index / 2) / (W*H);
    wire [31:0] tag = index[0] ? 32'h03000011 : 32'h0300000b;
    assign frame = {tag, 32'd1, y, x, step};
    always @(posedge clock)
        if (!resetn) index <= 0;
        else if (ready) index <= index + 1;
endmodule
module phi_decoder_profile_top(
    input aclk, aresetn, x_decoder_event_ready, z_decoder_event_ready,
    output [127:0] x_decoder_event, z_decoder_event,
    output x_decoder_event_valid, z_decoder_event_valid);
    assign x_decoder_event_valid = X_ACTIVE && aresetn;
    assign z_decoder_event_valid = Z_ACTIVE && aresetn;
    event_source #(.W(WIDTH_VALUE), .H(HEIGHT_VALUE), .BAD(BAD_VALUE)) x(
        aclk, aresetn, x_decoder_event_ready, x_decoder_event);
    event_source #(.W(WIDTH_VALUE), .H(HEIGHT_VALUE), .BAD(BAD_VALUE)) z(
        aclk, aresetn, z_decoder_event_ready, z_decoder_event);
endmodule
"""
        for width, height, planes, bad in ((2, 1, ["x", "z"], 0),
                                           (2, 5, ["z"], 0), (2, 5, ["z"], 1)):
            with self.subTest(width=width, height=height, planes=planes, bad=bad):
                with tempfile.TemporaryDirectory() as directory:
                    stage = Path(directory)
                    rtl = source
                    for token, value in {"WIDTH_VALUE": width, "HEIGHT_VALUE": height,
                                         "X_ACTIVE": int("x" in planes), "Z_ACTIVE": int("z" in planes),
                                         "BAD_VALUE": bad}.items():
                        rtl = rtl.replace(token, str(value))
                    (stage / "phi_decoder_profile_top.v").write_text(rtl)
                    for name in ("phi_decoder_profile.v", "hls_1r1w_ram.v"):
                        (stage / name).write_text("// No additional modules in this fixture.\n")
                    profile = {"profile": {"width": width, "height": height, "planes": planes}}
                    with patch.object(timing, "load_profile", return_value=profile):
                        if bad:
                            with self.assertRaises(subprocess.CalledProcessError):
                                timing.simulate(SimpleNamespace(stage=stage, rtl=stage))
                            self.assertIn("out-of-range coordinate", (stage / "simulate.console").read_text())
                        else:
                            timing.simulate(SimpleNamespace(stage=stage, rtl=stage))
                            self.assertIn("PASS:", (stage / "simulate.console").read_text())

    def test_package_constraints_and_device_cache(self) -> None:
        """Use exact-package pins and cache paths without changing historical XDC."""
        board = SimpleNamespace(part="xc7z030sbg485-1", device_root=Path("cache"))
        self.assertEqual(timing.chipdb_path(board), Path("cache/chipdb/xc7z030sbg485.bin"))
        xdc = timing.timing_xdc(board.part, 25)
        self.assertIn("PACKAGE_PIN Y14 IOSTANDARD LVCMOS33", xdc)
        self.assertIn("PACKAGE_PIN V13", xdc)
        self.assertIn("create_clock -period 40.000000000", xdc)
        self.assertEqual(timing.timing_xdc(timing.PART, 100),
            "# Compile-harness pins, not a board assignment.\n"
            "set_property -dict {PACKAGE_PIN F5 IOSTANDARD LVCMOS18} [get_ports clock]\n"
            "set_property -dict {PACKAGE_PIN A2 IOSTANDARD LVCMOS18} [get_ports activity]\n"
            "create_clock -period 10.000000000 [get_ports clock]\n")
        with self.assertRaises(ValueError):
            timing.timing_xdc("wrong-package", 100)

    def test_rectangular_and_single_plane_simulation_parameters(self) -> None:
        """Preserve D3 defaults while checking configurable geometry and planes."""
        with patch.object(timing, "load_profile") as load:
            load.return_value = {"profile": {"width": 2, "height": 1, "planes": ["x", "z"]}}
            self.assertEqual(timing.profile_parameters(Path("rtl")),
                             {"WIDTH": 2, "HEIGHT": 1, "X_ENABLED": 1, "Z_ENABLED": 1})
            load.return_value["profile"]["planes"] = ["z"]
            self.assertEqual(timing.profile_parameters(Path("rtl"))["X_ENABLED"], 0)
            for field, value in (("width", 0), ("height", True), ("planes", []),
                                 ("planes", ["x", "x"]), ("planes", ["q"])):
                load.return_value = {"profile": {"width": 2, "height": 1, "planes": ["x"], field: value}}
                with self.assertRaises(ValueError):
                    timing.profile_parameters(Path("rtl"))

    @unittest.skipUnless(os.environ.get("YOSYS") or shutil.which("yosys"), "Yosys is not installed")
    def test_two_stage_mapping_with_real_yosys(self):
        binary = Path(os.environ.get("YOSYS") or shutil.which("yosys")).resolve()
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            rtl = stage / "rtl"
            rtl.mkdir()
            (rtl / "phi_decoder_profile_top.v").write_text("""
module phi_decoder_profile_top(
    input aclk, aresetn, x_decoder_event_ready, z_decoder_event_ready,
    output [127:0] x_decoder_event, z_decoder_event,
    output x_decoder_event_valid, z_decoder_event_valid);
    reg [31:0] count = 0;
    always @(posedge aclk)
        if (!aresetn) count <= 0;
        else if (x_decoder_event_ready || z_decoder_event_ready) count <= count + 1;
    assign x_decoder_event = {4{count}};
    assign z_decoder_event = ~{4{count}};
    assign x_decoder_event_valid = aresetn;
    assign z_decoder_event_valid = aresetn;
endmodule
""")
            for name in ("phi_decoder_profile.v", "hls_1r1w_ram.v"):
                (rtl / name).write_text("// No additional modules in this small mapping fixture.\n")
            result = timing.map_design(SimpleNamespace(stage=stage, rtl=rtl), {"yosys": binary})
            self.assertGreater(result["retained_decoder_cells"], 32)
            self.assertEqual(result["assembled_cells"]["BUFG"], 1)

    def test_final_routed_path_and_single_clock_alias(self):
        data = {"fmax": {"(internal) clock": {"achieved": 40, "constraint": 100}}, "utilization": {}}
        log = path_report("clock_buf", 2, 10) + path_report("clock_buf", 3, 22)
        result = timing.timed_path(data, log)
        self.assertEqual(result["critical_path"]["routing_ns"], 22)
        self.assertEqual(result["critical_path_clock"], "clock_buf")
        self.assertEqual(result["clock"], "(internal) clock")
        with self.assertRaises(ValueError):
            timing.timed_path(data, log + path_report("other_clock", 1, 1))
        with self.assertRaises(ValueError):
            timing.timed_path(data, "no routed path")
        with self.assertRaises(ValueError):
            timing.timed_path({**data, "fmax": {}}, log)

    def test_warning_summary_preserves_counts_and_other_warnings(self):
        warnings = timing.warning_summary("\n".join([
            "Warning: Port PCOUT0 connected to net a on cell dsp has no connections",
            "Warning: Port PCOUT1 connected to net b on cell dsp has no connections",
            "Warning: Missing timing for example",
            "Info: a normal message"]))
        self.assertEqual(warnings["Unconnected port PCOUT"]["count"], 2)
        self.assertEqual(warnings["Missing timing for example"]["count"], 1)

    def test_distribution_includes_all_seeds(self):
        result = timing.summarize([{"achieved_mhz": f} for f in (20, 30, 40)])
        self.assertEqual(result["mean_mhz"], 30)
        self.assertAlmostEqual(result["variance_mhz_squared"], 200/3)
        self.assertEqual((result["best_mhz"], result["worst_mhz"], result["samples"]), (40, 20, 3))
        for bad in ([], [{"achieved_mhz": 0}], [{"achieved_mhz": float("nan")}]):
            with self.assertRaises(ValueError):
                timing.summarize(bad)

    def test_ignored_ram_and_registered_dsp_are_disclosed(self):
        coverage = timing.timing_coverage([
            {"type": "RAMB36E1"}, {"type": "RAM32M"}, {"type": "SRL16E"},
            {"type": "DSP48E1", "parameters": {"PREG": "0"}},
            {"type": "DSP48E1", "parameters": {"AREG": "10"}}])
        self.assertFalse(coverage["design_wide_clock_validated"])
        self.assertEqual(coverage["combinational_dsps_with_coarse_delay"], 1)
        self.assertEqual(coverage["omitted_sequential_primitives"],
                         {"RAMB36E1": 1, "RAM32M": 1, "SRL16E": 1, "registered_DSP48E1": 1})

    def test_incomplete_stale_and_modified_runs_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            run = Path(directory)
            expected = {"netlist": "one-build", "seed": 3}
            self.assertFalse(timing.completion_valid(run, expected))
            for name in ("nextpnr.json", "nextpnr.log"):
                (run / name).write_text("valid output")
            timing.save(run / "completed.json", {"inputs": expected,
                "outputs": {p.name: timing.sha(p) for p in run.iterdir()}})
            self.assertTrue(timing.completion_valid(run, expected))
            self.assertFalse(timing.completion_valid(run, {**expected, "netlist": "another-build"}))
            (run / "nextpnr.log").write_text("partial rerun")
            self.assertFalse(timing.completion_valid(run, expected))


    def test_wrong_workload_and_changed_rtl_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            rtl = Path(directory)
            names = ("phi_decoder_profile.v", "phi_decoder_profile_top.v", "hls_1r1w_ram.v")
            for name in names:
                (rtl / name).write_text("compiled RTL")
            build = {"schema": 1, "profile": {
                "width": 3, "height": 3, "shards_per_plane": 3, "pipeline_stages": 2,
                "initiation_interval": 1, "delay_model": "unit", "flop_inputs": False, "flop_outputs": True},
                "rtl": {name: timing.sha(rtl / name) for name in names}}
            manifest = rtl / "phi_decoder_profile.build.json"
            timing.save(manifest, build)
            self.assertEqual(timing.load_profile(rtl), build)
            build["profile"]["shards_per_plane"] = 1
            timing.save(manifest, build)
            with self.assertRaisesRegex(ValueError, "three-shard"):
                timing.load_profile(rtl)
            build["profile"]["shards_per_plane"] = 3
            timing.save(manifest, build)
            (rtl / names[0]).write_text("new RTL")
            with self.assertRaisesRegex(ValueError, "RTL changed"):
                timing.load_profile(rtl)

    def test_core_retention_and_global_clock(self):
        register = {"type": "FDRE", "parameters": {"INIT": "0"}, "connections": {"C": [1]}}
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            timing.save(stage / "core.json", {"modules": {timing.CORE: {"cells": {"q": register}}}})
            cells = {"decoder.q": register,
                     "clock_buffer": {"type": "BUFG", "parameters": {}, "connections": {"O": [1]}}}

            def check():
                timing.save(stage / "mapped.json", {"modules": {timing.TOP: {"cells": cells}}})
                return timing.check_assembly(stage)

            self.assertEqual(check()["retained_decoder_cells"], 1)
            register["connections"]["C"] = [2]
            with self.assertRaisesRegex(ValueError, "bypasses BUFG"):
                check()
            register["connections"]["C"] = [1]
            register["parameters"]["INIT"] = "1"
            with self.assertRaisesRegex(ValueError, "decoder cells changed"):
                check()
            del cells["decoder.q"]
            with self.assertRaisesRegex(ValueError, "decoder cells changed"):
                check()


if __name__ == "__main__":
    unittest.main()
