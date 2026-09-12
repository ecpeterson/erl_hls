#!/usr/bin/env python3
"""Fast report/provenance checks; no FPGA tool installation required."""
import os
from pathlib import Path
import shutil
import tempfile
from types import SimpleNamespace
import unittest

import phi_timing as timing


def path_report(clock, logic, routing):
    return (f"Info: Critical path report for clock '{clock}' (posedge -> posedge):\n"
            "Info: Source register.Q\nInfo: Sink destination.D\n"
            f"Info: {logic} ns logic, {routing} ns routing\n")


class TimingReports(unittest.TestCase):
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
