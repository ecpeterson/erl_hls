#!/usr/bin/env python3
"""Check runtime archive handling and optionally revalidate a completed SD image."""

import argparse
import gzip
import io
import json
import shutil
import stat
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from prepare_te0715_boot import digest
from prepare_te0715_runtime import cpio_entries, guest, tar_entries, validate_candidate
from test_te0715_qemu import cpio


class RuntimeImageTests(unittest.TestCase):
    """Reject mixed boot inputs and malformed archives before target-side assembly."""

    def test_newc_preserves_module_links_and_permissions(self) -> None:
        """Kernel modules and their symlinks survive the vendor archive conversion."""
        entries = [("lib/modules", b"", stat.S_IFDIR | 0o755),
                   ("lib/modules/test.ko", b"\x7fELF\0payload", stat.S_IFREG | 0o644),
                   ("lib/modules/link", b"test.ko", stat.S_IFLNK | 0o777)]
        self.assertEqual(entries, cpio_entries(cpio(entries)))

    def test_newc_rejects_truncation_and_escape(self) -> None:
        """A truncated vendor module archive cannot quietly become an incomplete image."""
        data = cpio([("lib/modules/test.ko", b"payload", stat.S_IFREG | 0o644)])
        for damaged in (data[:15], data[:125], data[:-120], b"bad", cpio([("../escape", b"", 0)])):
            with self.subTest(data=damaged[:20]), self.assertRaises(ValueError):
                cpio_entries(damaged)

    def test_tar_preserves_absolute_target_symlinks(self) -> None:
        """Target symlinks remain archive entries, never host filesystem operations."""
        with tempfile.TemporaryDirectory() as name:
            archive = Path(name) / "root.tar"
            with tarfile.open(archive, "w") as output:
                link = tarfile.TarInfo("sbin/init")
                link.type, link.linkname, link.mode = tarfile.SYMTYPE, "/bin/busybox", 0o777
                output.addfile(link)
            self.assertEqual([("sbin/init", b"/bin/busybox", stat.S_IFLNK | 0o777)], tar_entries(archive))

    def test_tar_rejects_escaping_names(self) -> None:
        """Absolute or parent-relative archive members never enter the generated initramfs."""
        for entry in ("/etc/escape", "../escape", "lib/../../escape"):
            with self.subTest(entry=entry), tempfile.TemporaryDirectory() as name:
                archive = Path(name) / "root.tar"
                with tarfile.open(archive, "w") as output:
                    output.addfile(tarfile.TarInfo(entry), io.BytesIO())
                with self.assertRaises(ValueError):
                    tar_entries(archive)

    def test_boot_manifest_mismatch(self) -> None:
        """A modified kernel is rejected even when its length still matches the manifest."""
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            kernel = root / "zImage"
            kernel.write_bytes(b"kernel")
            manifest = {"module": "TE0715-05-71C33-A", "part": "xc7z030sbg485-1", "carrier": "TEF1002-03-A",
                        "files": {"zImage": {"bytes": 6, "sha256": digest(kernel)}}}
            (root / "manifest.json").write_text(json.dumps(manifest))
            kernel.write_bytes(b"broken")
            with patch("prepare_te0715_runtime.check_directory") as check:
                with self.assertRaisesRegex(ValueError, "zImage"):
                    validate_candidate(root)
                check.assert_not_called()


def check_image(candidate: Path, timeout: int) -> None:
    """Verify artifact hashes and reboot a disposable snapshot of the actual SD root."""
    manifest = json.loads((candidate / "manifest.json").read_text())
    for name, expected in manifest["files"].items():
        path = candidate / name
        if path.stat().st_size != expected["bytes"] or digest(path) != expected["sha256"]:
            raise ValueError(f"runtime artifact mismatch: {name}")
    with tempfile.TemporaryDirectory(prefix="runtime-check-", dir=candidate.parent) as name:
        image = Path(name) / "rootfs.ext4"
        with gzip.open(candidate / "rootfs.ext4.gz", "rb") as source, image.open("wb") as output:
            shutil.copyfileobj(source, output)
        expected = manifest["rootfs_uncompressed"]
        if image.stat().st_size != expected["bytes"] or digest(image) != expected["sha256"]:
            raise ValueError("uncompressed root filesystem mismatch")
        guest(candidate, image, candidate.parent / "recheck-uart.log", timeout, None)
        if digest(image) != expected["sha256"]:
            raise ValueError("QEMU snapshot test altered the filesystem")
    print("PASS: runtime artifact hashes and SD-root QEMU boot")


def main() -> None:
    """Run portable regressions, then the optional candidate boot check."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", type=Path)
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args()
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(RuntimeImageTests))
    if not result.wasSuccessful():
        raise SystemExit(1)
    if args.candidate:
        check_image(args.candidate.resolve(), args.timeout)


if __name__ == "__main__":
    main()
