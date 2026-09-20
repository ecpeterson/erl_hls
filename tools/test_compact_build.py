#!/usr/bin/env python3
"""Exercise compaction selection and preservation guards without macOS tools."""

import os
import shutil
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

import compact_build as compact


class CompactionTests(unittest.TestCase):
    """Ensure that cleanup cannot replace mismatched or concurrently changed data."""

    def setUp(self) -> None:
        """Create a private build tree with one old generated artifact."""
        self.stage = tempfile.TemporaryDirectory()
        self.addCleanup(self.stage.cleanup)
        self.root = Path(self.stage.name) / "_build"
        self.root.mkdir()
        self.source = self.make("experiment/netlist.json")

    def make(self, name: str) -> Path:
        """Create an allocated, old file under the test build tree."""
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"generated artifact\n" * 200)
        os.utime(path, (1, 1))
        return path

    def plan(self) -> list[Path]:
        """Select old files with a small threshold suitable for these fixtures."""
        return [p for p, _ in compact.candidates(self.root, time.time() - 3600, 1)]

    def copy(self) -> Path:
        """Make an ordinary metadata-preserving candidate for verification tests."""
        result = self.root / "copy.json"
        shutil.copy2(self.source, result)
        return result

    def test_selection(self) -> None:
        """Protect active/rebar/tool caches, symlinks, hard links and hidden files."""
        for name in ["default/large.json", "test/artifact.vvp", "prod/data.json",
                     ".hidden/large.log", "experiment/chipdb.bin", "experiment/table.plt",
                     "experiment/.hidden.json"]:
            self.make(name)
        fresh = self.make("fresh.json")
        os.utime(fresh, None)
        linked = self.make("linked.vvp")
        os.link(linked, self.root / "hardlink.vvp")
        (self.root / "link.json").symlink_to(self.source)
        (self.root / "alias").symlink_to(self.source.parent, target_is_directory=True)
        self.assertEqual(self.plan(), [self.source])

    def test_root_guard(self) -> None:
        """A wrong root or a symlink must not broaden the selected tree."""
        with self.assertRaisesRegex(ValueError, "real directory"):
            compact.candidates(self.root.parent, time.time(), 1)
        alias = self.root.parent / "alias"
        alias.mkdir()
        (alias / "_build").symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "real directory"):
            compact.candidates(alias / "_build", time.time(), 1)

    def test_matching_copy(self) -> None:
        """A byte-identical copy with preserved permissions/mtime is accepted."""
        before = self.source.lstat()
        self.assertEqual(compact.verify_copy(self.source, self.copy(), before), compact.sha256(self.source))

    def test_corrupt_copy(self) -> None:
        """A same-length corrupted candidate cannot replace cached build work."""
        before = self.source.lstat()
        copied = self.copy()
        data = copied.read_bytes()
        copied.write_bytes(b"X" + data[1:])
        shutil.copystat(self.source, copied)
        with self.assertRaisesRegex(ValueError, "content mismatch"):
            compact.verify_copy(self.source, copied, before)
        self.assertEqual(self.source.read_bytes(), data)

    def test_truncated_copy(self) -> None:
        """Catch a sandbox-stripped compression flag exposing an empty data fork."""
        before = self.source.lstat()
        copied = self.copy()
        copied.write_bytes(b"")
        shutil.copystat(self.source, copied)
        with self.assertRaisesRegex(ValueError, "size or metadata mismatch"):
            compact.verify_copy(self.source, copied, before)

    def test_permissions(self) -> None:
        """Changing executable or permission bits invalidates a copy."""
        copied = self.copy()
        copied.chmod(0o700)
        with self.assertRaisesRegex(ValueError, "metadata mismatch"):
            compact.verify_copy(self.source, copied, self.source.lstat())

    def test_changed_source(self) -> None:
        """A source touched after selection is rejected before copying."""
        before = self.source.lstat()
        os.utime(self.source, None)
        with self.assertRaisesRegex(ValueError, "source changed"):
            compact.compact_one(self.source, before)

    def test_change_during_verification(self) -> None:
        """Check source identity again after reading both hashes."""
        before = self.source.lstat()
        copied = self.copy()
        original_hash = compact.sha256

        def changing_hash(path: Path) -> str:
            """Simulate a build touching the source during candidate verification."""
            value = original_hash(path)
            if path == copied:
                os.utime(self.source, None)
            return value

        with patch.object(compact, "sha256", side_effect=changing_hash):
            with self.assertRaisesRegex(ValueError, "during verification"):
                compact.verify_copy(self.source, copied, before)

    def test_missing_compression_flag(self) -> None:
        """Never replace the original with a copy missing native compression state."""
        before = self.source.lstat()
        content = self.source.read_bytes()

        def uncompressed_copy(command: list[str], **kwargs: object) -> None:
            """Stand in for a copy operation that cannot enable compression."""
            shutil.copy2(command[-2], command[-1])

        with patch.object(compact.subprocess, "run", side_effect=uncompressed_copy):
            with self.assertRaisesRegex(ValueError, "compression was not enabled"):
                compact.compact_one(self.source, before)
        self.assertEqual(self.source.read_bytes(), content)
        self.assertEqual(compact.signature(self.source.lstat()), compact.signature(before))
        self.assertFalse(list(self.source.parent.glob(".compact-*")))

    def test_failed_compressor(self) -> None:
        """A backend failure removes only its temporary files."""
        before = self.source.lstat()
        content = self.source.read_bytes()
        with patch.object(compact.subprocess, "run", side_effect=OSError("failed")):
            with self.assertRaisesRegex(OSError, "failed"):
                compact.compact_one(self.source, before)
        self.assertEqual(self.source.read_bytes(), content)
        self.assertFalse(list(self.source.parent.glob(".compact-*")))


if __name__ == "__main__":
    unittest.main()
