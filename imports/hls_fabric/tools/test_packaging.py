"""Exercise immutable releases and archive placement without XLS."""

from __future__ import annotations
import json
import os
from pathlib import Path
import shutil
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
prepare_optimizer = partial(prepare, public=public, profile="test")


class PackagingTests(unittest.TestCase):
    """Reject stale sources and failed publication before they affect a selected build."""

    def test_backend_release_and_failed_transform(self) -> None:
        """Retain a previous release on pass failure and reject edits to a cached release."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            raw = root / "raw"
            raw.mkdir()
            output = root / "compiled"
            (raw / "example.v").write_text("module example(); endmodule\n")
            (raw / "placement.json").write_text("{}\n")
            manifest = {
                "rtl": {"example.v": sha(raw / "example.v")},
                "artifacts": {"example.v": sha(raw / "example.v")},
                "assets": {"placement.json": sha(raw / "placement.json")},
            }
            (raw / "example.build.json").write_text(json.dumps(manifest))
            with patch.object(compiler_helpers, "build", return_value=raw) as build:
                args = dict(name="example", assets=[], executor_result_delay=6, public=public, profile="test")
                with compiler_helpers.locked(root / ".compiled.lock"):
                    with self.assertRaisesRegex(ValueError, "build already active"):
                        compile_backend.compile_topology(root / "source.x", root / "xls", output, **args)
                build.assert_not_called()
                release = compile_backend.compile_topology(root / "source.x", root / "xls", output, **args)
                self.assertEqual(build.call_args.kwargs["channel_delays"], {"_result_out:send": 6})
                self.assertEqual(output.resolve(), release)
                with patch.object(compile_backend, "transform", side_effect=ValueError("unknown FIFO")):
                    with self.assertRaisesRegex(ValueError, "unknown FIFO"):
                        compile_backend.compile_topology(
                            root / "source.x", root / "xls", output, completion_storage="lutram", **args
                        )
                self.assertEqual(output.resolve(), release)
                (release / "example.v").write_text("tampered\n")
                with self.assertRaisesRegex(ValueError, "release changed"):
                    compile_backend.compile_topology(root / "source.x", root / "xls", output, **args)

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


class OptimizerPipelineTests(unittest.TestCase):
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
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            xls = optimizer_bundle(root)
            selected = root / "selection.txtpb"
            selected.write_text('default_pipeline: ["dce"]\n')
            raw = root / "raw"
            raw.mkdir()
            (raw / "example.v").write_text("module example(); endmodule\n")
            manifest = {"rtl": {"example.v": sha(raw / "example.v")},
                        "artifacts": {"example.v": sha(raw / "example.v")},
                        "assets": {"optimizer_pipeline.txtpb": sha(selected)}}
            (raw / "optimizer_pipeline.txtpb").write_bytes(selected.read_bytes())
            (raw / "example.build.json").write_text(json.dumps(manifest))
            with patch.object(compiler_helpers, "build", return_value=raw) as compiler:
                release = compile_backend.compile_topology(
                    root / "source.x", xls, root / "compiled", name="example", assets=[],
                    optimizer_pipeline=selected, public=public, profile="test")
                passed = compiler.call_args
                self.assertNotEqual(passed.args[1], xls)
                frozen = passed.kwargs["assets"][0]
                self.assertEqual(frozen.name, "optimizer_pipeline.txtpb")
                self.assertEqual(frozen.read_bytes(), selected.read_bytes())
                recorded = json.loads((release / "example.build.json").read_text())
                self.assertEqual(recorded["backend"]["optimizer_pipeline_sha256"], sha(selected))
                self.assertEqual(recorded["backend"]["optimizer_executable_sha256"], sha(xls / "opt_main"))
                selected.write_text('default_pipeline: ["cse"]\n')
                self.assertEqual(sha(release / frozen.name), manifest["assets"][frozen.name])
                self.assertEqual((release / frozen.name).read_bytes(), frozen.read_bytes())
                with self.assertRaisesRegex(ValueError, "reserved optimizer pipeline"):
                    compile_backend.compile_topology(
                        root / "source.x", xls, root / "other", name="example", assets=[frozen],
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
