"""Check offline-builder boundaries and receipts without running native tools."""

import copy
import io
import json
from pathlib import Path
import tarfile
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from gtx import build_offline as builder


def archive(path: Path, files: dict[str, bytes], link: tuple[str, str] | None = None) -> None:
    """Write a tiny source archive, optionally containing a deliberately unsafe symlink."""
    with tarfile.open(path, "w:gz") as bundle:
        for name, contents in files.items():
            entry = tarfile.TarInfo(name)
            entry.size = len(contents)
            bundle.addfile(entry, io.BytesIO(contents))
        if link is not None:
            entry = tarfile.TarInfo(link[0])
            entry.type = tarfile.SYMTYPE
            entry.linkname = link[1]
            bundle.addfile(entry)


def fixture(root: Path) -> tuple[Path, dict]:
    """Supply tiny inputs for the real staging path; only native execution is simulated."""
    recipe = json.loads(builder.PINNED_RECIPE.read_text())
    for entry in recipe["archives"] + recipe["patches"]:
        path = root / entry["name"]
        path.write_bytes(b"fixture patch\n")
        entry["path"] = str(path)
    archive(root / "nextpnr.tar.gz", {
        recipe["source_directory"] + "/" + name: b"fixture source\n"
        for name in recipe["patched_sources"]
    })
    archive(root / "eigen.tar.gz", {"eigen-3.4.0/Eigen/Core": b"fixture header\n"})
    for entry in recipe["archives"] + recipe["patches"]:
        entry["sha256"] = builder.digest(Path(entry["path"]))
    tool = root / "fake-tool"
    tool.write_text("#!/bin/sh\nexit 99\n")
    tool.chmod(0o755)
    boost = root / "boost"
    boost.mkdir()
    recipe["tools"] = {name: str(boost if name == "boost" else tool)
                       for name in recipe["tools"]}
    path = root / "recipe.json"
    path.write_text(json.dumps(recipe))
    return path, recipe


class OfflineBuildTests(unittest.TestCase):
    """Pins, extraction, serialization and failed-build evidence survive orchestration."""

    def test_recipe_pins_paths_and_order(self) -> None:
        """Caller paths may vary; source revisions, hashes and patch order may not."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            path, local = fixture(root)
            recipe = json.loads(builder.PINNED_RECIPE.read_text())
            for key in ("archives", "patches"):
                for entry, supplied in zip(recipe[key], local[key]):
                    entry["path"] = Path(supplied["path"]).name
            recipe["tools"] = local["tools"]
            path.write_text(json.dumps(recipe))
            loaded = builder.load_recipe(path)
            self.assertEqual(loaded["archives"][0]["path"], str(root / "nextpnr.tar.gz"))
            for field, value in (("source_directory", "../escape"), ("upstream_revision", "changed")):
                invalid = copy.deepcopy(recipe)
                invalid[field] = value
                path.write_text(json.dumps(invalid))
                with self.subTest(field=field), self.assertRaises(ValueError):
                    builder.load_recipe(path)
            for mutation in ("order", "hash", "name"):
                invalid = copy.deepcopy(recipe)
                if mutation == "order":
                    invalid["patches"].reverse()
                else:
                    invalid["patches"][0]["sha256" if mutation == "hash" else "name"] = "../escape"
                path.write_text(json.dumps(invalid))
                with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                    builder.load_recipe(path)

    def test_archive_scope_and_basename(self) -> None:
        """Reject traversal, another archive root and links escaping the declared root."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            source = root / "source.tar.gz"
            for name in ("../escape", "/absolute", "other/file", "source/../escape"):
                archive(source, {name: b"bad"})
                with self.subTest(name=name), self.assertRaises(ValueError):
                    builder.extract(source, "source", root / "out")
            archive(source, {"source/file": b"ok"}, ("source/link", "../escape"))
            with self.assertRaises(ValueError):
                builder.extract(source, "source", root / "out")
            for name in ("..", "a/b", "a\\b", ""):
                with self.subTest(name=name), self.assertRaises(ValueError):
                    builder.basename(name)

    def test_serial_receipts_and_no_reuse(self) -> None:
        """Exercise real freezing, extraction and receipts with simulated external commands."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            recipe_path, recipe = fixture(root)
            output = root / "output"
            calls = []

            def command(argv: list[str], **kwargs: object) -> SimpleNamespace:
                """Stand in for patch/CMake, generating only the expected compiled artifact."""
                calls.append(argv)
                environment = kwargs["env"]
                self.assertEqual(environment["CMAKE_BUILD_PARALLEL_LEVEL"], "1")
                self.assertEqual(environment["MAKEFLAGS"], "-j1")
                if "--build" in argv:
                    binary = Path(argv[argv.index("--build") + 1]) / "nextpnr-xilinx"
                    binary.parent.mkdir(parents=True)
                    binary.write_bytes(b"fake native binary\n")
                return SimpleNamespace(returncode=0)

            with patch.object(builder, "load_recipe", return_value=recipe), \
                    patch.object(builder.subprocess, "run", side_effect=command):
                result = builder.build(recipe_path, output)
                with self.assertRaises(FileExistsError):
                    builder.build(recipe_path, output)
            self.assertEqual(len(calls), 9)
            self.assertEqual([Path(call[-1]).name for call in calls[:7]],
                             [entry["name"] for entry in recipe["patches"]])
            self.assertEqual(calls[-1][-4:], ["--target", "nextpnr-xilinx", "--parallel", "1"])
            self.assertTrue(result["success"])
            self.assertFalse(result["tests_run"])
            self.assertFalse(result["hardware_qualified"])
            self.assertEqual(result["recipe_sha256"], builder.digest(output / "recipe.json"))
            self.assertEqual(result["script_sha256"], builder.digest(output / "build-script.py"))
            self.assertEqual(result["binary_sha256"], builder.digest(Path(result["binary"])))
            self.assertEqual(len(result["patched_sources"]), 5)

    def test_failed_command_preserves_evidence(self) -> None:
        """A failed patch retains its inputs, return code and failure instead of a success receipt."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            recipe_path, recipe = fixture(root)
            output = root / "failed"
            with patch.object(builder, "load_recipe", return_value=recipe), \
                    patch.object(builder.subprocess, "run", return_value=SimpleNamespace(returncode=7)):
                with self.assertRaisesRegex(RuntimeError, "exit 7"):
                    builder.build(recipe_path, output)
            self.assertFalse((output / "result.json").exists())
            self.assertTrue((output / "inputs/nextpnr.tar.gz").is_file())
            self.assertEqual(json.loads((output / "patch-1.json").read_text())["returncode"], 7)
            self.assertFalse(json.loads((output / "failure.json").read_text())["success"])


if __name__ == "__main__":
    unittest.main()
