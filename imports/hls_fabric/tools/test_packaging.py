"""Exercise dependency preparation, immutable releases and archive placement without XLS."""

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
from prepare_compiler import prepare, sha
import compile_backend


class PackagingTests(unittest.TestCase):
    """Reject stale sources and failed publication before they affect a selected build."""

    def test_compiler_reconstruction_and_local_edits(self) -> None:
        """Fetch the pinned commit, ignore checkout edits and rebuild after cache deletion."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "backend"
            source = Path(temporary) / "compiler"
            root.mkdir()
            source.mkdir()

            def git(*arguments: str) -> str:
                """Run fixture-local Git operations without changing user configuration."""
                return subprocess.check_output(["git", "-C", str(source), *arguments], text=True).strip()

            git("init", "--quiet")
            (source / "api.txt").write_text("base\n")
            git("add", "api.txt")
            git(
                "-c",
                "user.name=Fixture",
                "-c",
                "user.email=fixture@example.invalid",
                "commit",
                "--quiet",
                "-m",
                "base",
            )
            base = git("rev-parse", "HEAD")
            (source / "api.txt").write_text("extension\n")
            git("add", "api.txt")
            git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                "commit", "--quiet", "-m", "extension")
            revision = git("rev-parse", "HEAD")
            (source / "api.txt").write_text("unrelated developer edit\n")
            directory = root / "tools/compiler"
            directory.mkdir(parents=True)
            manifest = {"revision": revision, "url": str(source)}
            (directory / "manifest.json").write_text(json.dumps(manifest))
            result = prepare(root, source)
            self.assertEqual((result / "api.txt").read_text(), "extension\n")
            self.assertEqual((source / "api.txt").read_text(), "unrelated developer edit\n")
            self.assertEqual(prepare(root, source), result)
            (result / "api.txt").write_text("cache edit\n")
            with self.assertRaisesRegex(ValueError, "cache changed"):
                prepare(root, source)
            shutil.rmtree(root / "_build")
            self.assertEqual((prepare(root, source) / "api.txt").read_text(), "extension\n")
            checkout = root / "_checkouts/erl_hls"
            checkout.unlink()
            checkout.symlink_to(source)
            with self.assertRaisesRegex(ValueError, "already selected"):
                prepare(root, source)
            self.assertEqual(checkout.resolve(), source.resolve())
            checkout.unlink()
            # Exercise the fetch path as well as the explicit offline source.
            shutil.rmtree(root / "_build")
            self.assertEqual((prepare(root) / "api.txt").read_text(), "extension\n")
            manifest["revision"] = base
            (directory / "manifest.json").write_text(json.dumps(manifest))
            self.assertEqual((prepare(root, source) / "api.txt").read_text(), "base\n")
            self.assertEqual((source / "api.txt").read_text(), "unrelated developer edit\n")

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
            with patch.object(compile_backend, "build", return_value=raw) as build:
                args = dict(name="example", assets=[], executor_result_delay=6)
                with compile_backend.locked(root / ".compiled.lock"):
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
            selected = erlang_paths(root)
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


if __name__ == "__main__":
    unittest.main()
