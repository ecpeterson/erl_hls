"""Exercise immutable releases and archive placement without XLS."""

from __future__ import annotations
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from artifacts import artifact_root, archive_path
from backend_paths import erlang_paths
from backend_commands import digest as sha
import compile_backend
from functools import partial
from compiler_paths import compiler_root, compiler_tool
from optimizer_pipeline import prepare

public = compiler_root("test")
compiler_helpers = compiler_tool(public, "compile_xls")
BuildFixture = compiler_tool(public, "testing").BuildFixture
prepare_optimizer = partial(prepare, public=public, profile="test")


# Minimal accepted XLS completion-ring shape; this exercises legalization, not hardware behavior.
COMPLETION_FIFO_RTL = """module fifo_for_depth_3_width_8(
    input wire clk, input wire reset, input wire push_valid,
    input wire [7:0] push_data, input wire [1:0] head, input wire is_full_bool);
  reg [7:0] buf__1[0:2];
  wire [7:0] buf__1_init[0:2];
  wire [7:0] array_update_42[0:2];
  wire pushed;
  assign pushed = ~is_full_bool & push_valid;
  for (genvar __i0 = 0; __i0 < 3; __i0 = __i0 + 1) begin : update_payload
    assign array_update_42[__i0] = head == __i0 ? push_data : buf__1[__i0];
  end
  always @(posedge clk) begin
    if (reset) begin
      buf__1[0] <= buf__1_init[0];
      buf__1[1] <= buf__1_init[1];
      buf__1[2] <= buf__1_init[2];
    end else begin
      buf__1[0] <= pushed ? array_update_42[0] : buf__1[0];
      buf__1[1] <= pushed ? array_update_42[1] : buf__1[1];
      buf__1[2] <= pushed ? array_update_42[2] : buf__1[2];
    end
  end
endmodule
module example();
  fifo_for_depth_3_width_8 materialized_fifo_fifo__executor_result_();
endmodule
"""


class PackagingTests(BuildFixture):
    """Reject stale sources and failed publication before they affect a selected build."""

    def test_backend_release_and_failed_transform(self) -> None:
        """Retain a prior release on transform failure and repair tampering from verified stage caches."""
        args = dict(name="example", assets=[], executor_result_delay=6, public=public, profile="test")
        with compiler_helpers.locked(self.root / ".published.lock"):
            with self.assertRaisesRegex(ValueError, "build already active"):
                compile_backend.compile_topology(self.source, self.xls, self.output, **args)
        self.assertFalse(self.calls.exists())
        release = compile_backend.compile_topology(self.source, self.xls, self.output, **args)
        manifest = json.loads((release / "example.build.json").read_text())
        self.assertIn("--additional_channel_delay_ps=_result_out:send=6", manifest["options"]["codegen"])
        self.assertEqual(manifest["backend"]["completion_storage"], "registers")
        self.assertEqual(self.output.resolve(), release)
        calls = self.calls.read_text()
        with patch.object(compile_backend, "transform", side_effect=ValueError("unknown FIFO")):
            with self.assertRaisesRegex(ValueError, "unknown FIFO"):
                compile_backend.compile_topology(
                    self.source, self.xls, self.output, completion_storage="lutram", **args)
        self.assertEqual(self.output.resolve(), release)
        self.assertEqual(self.calls.read_text(), calls)
        report = json.loads(self.output.with_suffix('.run.json').read_text())
        self.assertEqual(report["status"], "failed")
        self.assertTrue(Path(report["attempt"]).is_dir())
        (release / "example.v").write_text("tampered\n")
        repaired = compile_backend.compile_topology(self.source, self.xls, self.output, **args)
        self.assertEqual(repaired, release)
        self.assertEqual(sha(repaired / "example.v"), manifest["rtl"]["example.v"])
        self.assertEqual(self.calls.read_text(), calls)
        self.assertTrue(list(release.parent.glob(release.name + ".damaged-*")))

    def test_completion_transform_precedes_final_hashes(self) -> None:
        """The real completion pass changes published RTL without changing the cached codegen product."""
        codegen = self.xls / "codegen_main"
        codegen.write_text("#!/usr/bin/env python3\nprint(" + repr(COMPLETION_FIFO_RTL) + ")\n")
        args = dict(name="example", assets=[], public=public, profile="test")
        original = compile_backend.compile_topology(self.source, self.xls, self.output, **args)
        original_rtl = (original / "example.v").read_text()
        transformed = compile_backend.compile_topology(
            self.source, self.xls, self.output, completion_storage="lutram", **args)
        manifest = json.loads((transformed / "example.build.json").read_text())
        self.assertIn('ram_style = "distributed"', (transformed / "example.v").read_text())
        self.assertEqual(manifest["rtl"]["example.v"], sha(transformed / "example.v"))
        self.assertEqual(manifest["artifacts"]["example.v"], sha(transformed / "example.v"))
        self.assertEqual(set(manifest["backend"]["completion_fifo"]["modules"]),
                         {"fifo_for_depth_3_width_8"})
        self.assertEqual((original / "example.v").read_text(), original_rtl)
        self.assertTrue(all(self.statuses().values()))
        self.assertEqual(compile_backend.compile_topology(self.source, self.xls, self.output, **args), original)

    def test_checkout_beams_override_stale_dependency(self) -> None:
        """A previous rebar dependency cannot shadow the selected compiler checkout."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in (
                "lib/hls_fabric/ebin",
                "lib/hls_fabric/test",
                "lib/erl_hls/ebin",
                "checkouts/erl_hls/ebin",
            ):
                (root / "_build/test" / name).mkdir(parents=True)
            selected = erlang_paths("test", root)
            self.assertIn(root / "_build/test/checkouts/erl_hls/ebin", selected)
            self.assertNotIn(root / "_build/test/lib/erl_hls/ebin", selected)
            self.assertIn(root / "_build/test/lib/hls_fabric/test", selected)

    def test_external_archive_override(self) -> None:
        """Archive lookup is portable and cannot silently accept a source-local output root."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "source"
            root.mkdir()
            with patch.dict(os.environ, {"HLS_ARTIFACT_ROOT": str(root / "results")}):
                with self.assertRaisesRegex(ValueError, "outside"):
                    artifact_root(root)
            with patch.dict(os.environ, {"HLS_ARTIFACT_ROOT": str(Path(temporary) / "evidence")}):
                self.assertEqual(artifact_root(root).name, "evidence")
                self.assertTrue(str(archive_path("old/report.json")).endswith("/old/report.json"))
                with self.assertRaises(ValueError):
                    archive_path("../escape")


def optimizer_bundle(root: Path) -> Path:
    """Create executable argument-reporting tools and a minimal standard-library tree."""
    xls = root / "source tools"
    xls.mkdir()
    for name in ("opt_main", "ir_converter_main", "codegen_main"):
        path = xls / name
        path.write_text("#!/usr/bin/env python3\nimport json,sys\nprint(json.dumps(sys.argv[1:]))\n")
        path.chmod(0o755)
    (xls / "xls/dslx/stdlib").mkdir(parents=True)
    return xls


class OptimizerPipelineTests(BuildFixture):
    """Configuration identity and frozen bytes must survive cache reuse and later edits."""

    def test_arguments_and_configuration_identity(self) -> None:
        """Reuse identical settings, preserve spaced arguments and isolate configuration changes."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            xls = optimizer_bundle(root)
            original = (xls / "opt_main").read_bytes()
            profile = root / "selection.txtpb"
            profile.write_text('default_pipeline: ["dce"]\n')
            first, frozen, policy = prepare_optimizer(xls, profile, root / "cache")
            self.assertEqual(prepare_optimizer(xls, profile, root / "cache"), (first, frozen, policy))
            result = subprocess.check_output([str(first / "opt_main"), "input with spaces.ir", "--opt_level=3"], text=True)
            self.assertEqual(json.loads(result), ["--pipeline_textproto=" + str(frozen),
                                                "input with spaces.ir", "--opt_level=3"])
            profile.write_text('default_pipeline: ["dce", "cse"]\n')
            second, _, changed = prepare_optimizer(xls, profile, root / "cache")
            self.assertNotEqual(first, second)
            self.assertNotEqual(policy["optimizer_pipeline_sha256"], changed["optimizer_pipeline_sha256"])
            self.assertEqual((xls / "opt_main").read_bytes(), original)
            self.assertEqual(frozen.read_text(), 'default_pipeline: ["dce"]\n')
            with self.assertRaisesRegex(ValueError, "cannot be nested"):
                prepare_optimizer(first, profile, root / "nested")

    def test_backend_retains_configuration_and_original_tool(self) -> None:
        """Publish the pipeline as a checked asset without mutating the caller's tool bundle."""
        selected = self.root / "selection.txtpb"
        selected.write_text('default_pipeline: ["dce"]\n')
        expected = selected.read_bytes()
        release = compile_backend.compile_topology(
            self.source, self.xls, self.output, name="example", assets=[],
            optimizer_pipeline=selected, public=public, profile="test")
        recorded = json.loads((release / "example.build.json").read_text())
        self.assertEqual(recorded["backend"]["optimizer_pipeline_sha256"], sha(selected))
        self.assertEqual(recorded["backend"]["optimizer_executable_sha256"], sha(self.xls / "opt_main"))
        command = json.loads((release / "opt.command.json").read_text())
        self.assertNotEqual(Path(command[0]), self.xls / "opt_main")
        result = json.loads((release / "example.opt.ir").read_text())
        self.assertTrue(result["args"][0].startswith("--pipeline_textproto="))
        selected.write_text('default_pipeline: ["cse"]\n')
        frozen = release / "optimizer_pipeline.txtpb"
        self.assertEqual(sha(frozen), recorded["assets"][frozen.name])
        self.assertEqual(frozen.read_bytes(), expected)
        with self.assertRaisesRegex(ValueError, "reserved optimizer pipeline"):
            compile_backend.compile_topology(
                self.source, self.xls, self.root / "other", name="example", assets=[frozen],
                optimizer_pipeline=selected, public=public, profile="test")

    def test_changed_optimizer_is_rejected_by_old_overlay(self) -> None:
        """An old wrapper cannot silently execute a newly replaced optimizer."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            xls = optimizer_bundle(root)
            profile = root / "policy.txtpb"
            profile.write_text('default_pipeline: ["dce"]\n')
            first, _, policy = prepare_optimizer(xls, profile, root / "cache")
            with (xls / "opt_main").open("a") as stream:
                stream.write("# changed tool\n")
            result = subprocess.run([str(first / "opt_main"), "input.ir"], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("optimizer input changed", result.stderr)
            second, _, changed = prepare_optimizer(xls, profile, root / "cache")
            self.assertNotEqual(first, second)
            self.assertNotEqual(policy["optimizer_executable_sha256"], changed["optimizer_executable_sha256"])

    def test_corrupted_configuration_and_tool_links_are_rejected(self) -> None:
        """Detect edited cache contents both on reuse and when invoking its executable."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            xls = optimizer_bundle(root)
            profile = root / "policy.txtpb"
            profile.write_text('default_pipeline: ["dce"]\n')
            output, frozen, _ = prepare_optimizer(xls, profile, root / "cache")
            frozen.write_text("changed\n")
            result = subprocess.run([str(output / "opt_main")], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            with self.assertRaisesRegex(ValueError, "pipeline changed"):
                prepare_optimizer(xls, profile, root / "cache")
            frozen.write_bytes(profile.read_bytes())
            (output / "codegen_main").unlink()
            (output / "codegen_main").symlink_to(xls / "opt_main")
            with self.assertRaisesRegex(ValueError, "tool links changed"):
                prepare_optimizer(xls, profile, root / "cache")


if __name__ == "__main__":
    unittest.main()
