"""Exercise immutable releases and archive placement without XLS."""

from __future__ import annotations
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from artifacts import artifact_root, archive_path
from backend_paths import erlang_paths
from backend_commands import digest as sha
import compile_backend
from compiler_paths import compiler_root, compiler_tool
from backend_build_profile import emit, read

public = compiler_root("test")
compiler_helpers = compiler_tool(public, "compile_xls")
BuildFixture = compiler_tool(public, "testing").BuildFixture


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


class PolicyFixture(BuildFixture):
    """Resolve actual Erlang policy once per distinct selection, with mocked external XLS tools."""

    def policy(self, storage: str = "registers") -> Path:
        """Emit a fresh profile and retain it for repeated immutable-build checks."""
        path = self.root / (storage + "-profile.json")
        if not path.exists():
            emit(path, profile="test", public=public, initiation_interval=None,
                 executor_result_delay=6, completion_storage=storage)
        return path


class PackagingTests(PolicyFixture):
    """Reject stale sources and failed publication before they affect a selected build."""

    def test_backend_release_and_failed_transform(self) -> None:
        """Retain a prior release on transform failure and repair tampering from verified stage caches."""
        args = dict(name="example", assets=[], public=public, profile="test")
        with compiler_helpers.locked(self.root / ".published.lock"):
            with self.assertRaisesRegex(ValueError, "build already active"):
                compile_backend.compile_topology(self.source, self.xls, self.output, build_profile=self.policy(), **args)
        self.assertFalse(self.calls.exists())
        release = compile_backend.compile_topology(self.source, self.xls, self.output, build_profile=self.policy(), **args)
        manifest = json.loads((release / "example.build.json").read_text())
        self.assertIn("--additional_channel_delay_ps=_result_out:send=6", manifest["options"]["codegen"])
        self.assertEqual(manifest["backend"]["build_profile"]["profile"]["postprocess"]["completion_storage"], "registers")
        self.assertEqual(self.output.resolve(), release)
        calls = self.calls.read_text()
        with patch.object(compile_backend, "transform", side_effect=ValueError("unknown FIFO")):
            with self.assertRaisesRegex(ValueError, "unknown FIFO"):
                compile_backend.compile_topology(
                    self.source, self.xls, self.output, build_profile=self.policy("lutram"), **args)
        self.assertEqual(self.output.resolve(), release)
        self.assertEqual(self.calls.read_text(), calls)
        report = json.loads(self.output.with_suffix('.run.json').read_text())
        self.assertEqual(report["status"], "failed")
        self.assertTrue(Path(report["attempt"]).is_dir())
        (release / "example.v").write_text("tampered\n")
        repaired = compile_backend.compile_topology(self.source, self.xls, self.output, build_profile=self.policy(), **args)
        self.assertEqual(repaired, release)
        self.assertEqual(sha(repaired / "example.v"), manifest["rtl"]["example.v"])
        self.assertEqual(self.calls.read_text(), calls)
        self.assertTrue(list(release.parent.glob(release.name + ".damaged-*")))

    def test_completion_transform_precedes_final_hashes(self) -> None:
        """The real completion pass changes published RTL without changing the cached codegen product."""
        codegen = self.xls / "codegen_main"
        codegen.write_text("#!/usr/bin/env python3\nprint(" + repr(COMPLETION_FIFO_RTL) + ")\n")
        args = dict(name="example", assets=[], public=public, profile="test")
        original = compile_backend.compile_topology(self.source, self.xls, self.output, build_profile=self.policy(), **args)
        original_rtl = (original / "example.v").read_text()
        transformed = compile_backend.compile_topology(
            self.source, self.xls, self.output, build_profile=self.policy("lutram"), **args)
        manifest = json.loads((transformed / "example.build.json").read_text())
        self.assertIn('ram_style = "distributed"', (transformed / "example.v").read_text())
        self.assertEqual(manifest["rtl"]["example.v"], sha(transformed / "example.v"))
        self.assertEqual(manifest["artifacts"]["example.v"], sha(transformed / "example.v"))
        self.assertEqual(set(manifest["backend"]["completion_fifo"]["modules"]),
                         {"fifo_for_depth_3_width_8"})
        self.assertEqual((original / "example.v").read_text(), original_rtl)
        self.assertTrue(all(self.statuses().values()))
        self.assertEqual(compile_backend.compile_topology(self.source, self.xls, self.output, build_profile=self.policy(), **args), original)

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


class OptimizerPipelineTests(PolicyFixture):
    """The real optimizer and immutable pipeline retain separate identities and cache dependencies."""

    def test_backend_retains_configuration_and_original_tool(self) -> None:
        """Direct invocation freezes pipeline bytes and reruns optimization on edits while preserving identical downstream inputs."""
        selected = self.root / "selection.txtpb"
        selected.write_text('default_pipeline: ["dce"]\n')
        expected = selected.read_bytes()
        args = dict(name="example", assets=[], build_profile=self.policy(),
                    optimizer_pipeline=selected, public=public, profile="test")
        release = compile_backend.compile_topology(self.source, self.xls, self.output, **args)
        recorded = json.loads((release / "example.build.json").read_text())
        self.assertEqual(recorded["backend"]["optimizer_pipeline_sha256"], sha(selected))
        self.assertEqual(recorded["tools"]["opt_main"], sha(self.xls / "opt_main"))
        self.assertEqual(recorded["backend"]["optimizer_executable_sha256"], recorded["tools"]["opt_main"])
        command = json.loads((release / "opt.command.json").read_text())
        self.assertEqual(Path(command[0]), (self.xls / "opt_main").resolve())
        self.assertIn("--pipeline_textproto=assets/optimizer_pipeline.txtpb", command)
        self.assertEqual(recorded["backend"]["build_profile"], read(self.policy()))
        selected.write_text('default_pipeline: ["cse"]\n')
        frozen = release / "optimizer_pipeline.txtpb"
        self.assertEqual(sha(frozen), recorded["assets"][frozen.name])
        self.assertEqual(frozen.read_bytes(), expected)
        changed = compile_backend.compile_topology(self.source, self.xls, self.output, **args)
        self.assertNotEqual(changed, release)
        self.assertEqual(self.statuses(), {"ir": True, "opt": False, "codegen": True})
        with self.assertRaisesRegex(ValueError, "reserved optimizer pipeline"):
            compile_backend.compile_topology(
                self.source, self.xls, self.root / "other", name="example", assets=[frozen],
                build_profile=self.policy(), optimizer_pipeline=selected, public=public, profile="test")


if __name__ == "__main__":
    unittest.main()
