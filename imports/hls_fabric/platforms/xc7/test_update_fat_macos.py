#!/usr/bin/env python3
"""Regression checks for the guarded macOS FAT updater."""

import importlib.util
import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock
import zipfile


SCRIPT = Path(__file__).with_name("update_fat_macos.py")
SPEC = importlib.util.spec_from_file_location("update_fat_macos", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
UPDATER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(UPDATER)


class FatTargetTests(unittest.TestCase):
    """Exercise partition-parent validation without touching real media."""

    def test_external_classification_uses_parent_record(self) -> None:
        """Accept a partition whose own Internal field is misleading."""
        partition = {
            "DeviceIdentifier": "disk4s1",
            "ParentWholeDisk": "disk4",
            "Whole": False,
            "Internal": True,
            "FilesystemType": "msdos",
            "MountPoint": "/Volumes/SD_BOOT",
            "VolumeName": "SD_BOOT",
        }
        parent = {"DeviceIdentifier": "disk4", "Whole": True, "Internal": False}
        root = {"ParentWholeDisk": "disk3"}
        with mock.patch.object(UPDATER, "disk_info", side_effect=[partition, root, parent]):
            info, mount, whole = UPDATER.mounted_fat_partition("disk4s1")
        self.assertIs(info, partition)
        self.assertEqual(Path("/Volumes/SD_BOOT"), mount)
        self.assertEqual("disk4", whole)

    def test_internal_parent_is_rejected(self) -> None:
        """Reject an internal whole disk even if its partition says external."""
        partition = {
            "ParentWholeDisk": "disk4",
            "Whole": False,
            "Internal": False,
            "FilesystemType": "msdos",
            "MountPoint": "/Volumes/SD_BOOT",
        }
        parent = {"DeviceIdentifier": "disk4", "Whole": True, "Internal": True}
        root = {"ParentWholeDisk": "disk3"}
        with mock.patch.object(UPDATER, "disk_info", side_effect=[partition, root, parent]):
            with self.assertRaisesRegex(ValueError, "no external/removable-media marker"):
                UPDATER.mounted_fat_partition("disk4s1")

    def test_usb_reader_overrides_unreliable_internal_flag(self) -> None:
        """Accept a removable USB reader even when diskutil labels it internal."""
        partition = {"ParentWholeDisk": "disk4", "Whole": False,
                     "FilesystemType": "msdos", "MountPoint": "/Volumes/SD_BOOT"}
        parent = {"DeviceIdentifier": "disk4", "Whole": True, "Internal": True,
                  "RemovableMedia": True, "Ejectable": True, "BusProtocol": "USB"}
        root = {"ParentWholeDisk": "disk3"}
        with mock.patch.object(UPDATER, "disk_info", side_effect=[partition, root, parent]):
            _, mount, whole = UPDATER.mounted_fat_partition("disk4s1")
        self.assertEqual(Path("/Volumes/SD_BOOT"), mount)
        self.assertEqual("disk4", whole)

    def test_system_parent_is_always_rejected(self) -> None:
        """Refuse the root filesystem's parent even if other fields look external."""
        partition = {"ParentWholeDisk": "disk4", "Whole": False,
                     "FilesystemType": "msdos", "MountPoint": "/Volumes/SD_BOOT"}
        parent = {"DeviceIdentifier": "disk4", "Whole": True, "Internal": False,
                  "RemovableMedia": True}
        root = {"ParentWholeDisk": "disk4"}
        with mock.patch.object(UPDATER, "disk_info", side_effect=[partition, root, parent]):
            with self.assertRaisesRegex(ValueError, "refusing system disk"):
                UPDATER.mounted_fat_partition("disk4s1")

    def test_reported_parent_must_match_identifier(self) -> None:
        """Reject a contradictory diskutil partition relationship."""
        with self.assertRaisesRegex(ValueError, "partition parent mismatch"):
            UPDATER.parent_disk("disk4s1", {"ParentWholeDisk": "disk5"})


class FatBundleTests(unittest.TestCase):
    """Exercise flat archive validation and byte-for-byte installation."""

    def make_bundle(self, root: Path, names: tuple[str, ...] = UPDATER.FILES) -> tuple[Path, Path]:
        """Create one synthetic archive and matching role manifest."""
        archive = root / "role-fat.zip"
        payloads = {name: f"payload:{name}".encode() for name in UPDATER.FILES}
        with zipfile.ZipFile(archive, "w") as bundle:
            for name in names:
                bundle.writestr(name, payloads[Path(name).name])
        manifest = root / "role-manifest.json"
        manifest.write_text(json.dumps({"role": "a", "files": {
            name: {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
            for name, data in payloads.items()}}))
        return archive, manifest

    def test_flat_bundle_installs_and_verifies(self) -> None:
        """Accept only root files, then reproduce their hashes at the selected mount."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive, manifest_path = self.make_bundle(root)
            stage, mount = root / "stage", root / "mount"
            stage.mkdir()
            mount.mkdir()
            _, records = UPDATER.checked_bundle(archive, manifest_path, stage)
            with mock.patch.object(UPDATER.subprocess, "run") as run:
                self.assertEqual(records, UPDATER.install(stage, records, mount))
            run.assert_called_once_with(["sync"], check=True)
            self.assertEqual(records["BOOT.bin"]["sha256"],
                             UPDATER.digest(mount / "BOOT.bin"))

    def test_nested_bundle_is_rejected(self) -> None:
        """Reject archives that would create an enclosing directory on the FAT volume."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive, manifest = self.make_bundle(
                root, tuple(f"role-a/{name}" for name in UPDATER.FILES))
            stage = root / "stage"
            stage.mkdir()
            with self.assertRaisesRegex(ValueError, "archive must contain"):
                UPDATER.checked_bundle(archive, manifest, stage)


if __name__ == "__main__":
    unittest.main()
