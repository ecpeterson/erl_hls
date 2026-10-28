#!/usr/bin/env python3
"""Replace one explicitly selected SD FAT payload and verify it on media."""

import argparse
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path


FILES = ("BOOT.bin", "boot.scr", "image.ub")
PARTITION = re.compile(r"disk([0-9]+)s[0-9]+")


def digest(path: Path) -> str:
    """Return one file's SHA-256 digest."""
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def checked_bundle(archive: Path, manifest_path: Path, stage: Path) -> tuple[dict, dict]:
    """Extract a flat three-file archive after matching its role manifest."""
    manifest = json.loads(manifest_path.read_text())
    records = manifest.get("files", {})
    with zipfile.ZipFile(archive) as bundle:
        members = [item for item in bundle.infolist() if not item.is_dir()]
        if [item.filename for item in members] != list(FILES):
            raise ValueError("FAT archive must contain BOOT.bin, boot.scr and image.ub at its root")
        for item in members:
            if Path(item.filename).name != item.filename:
                raise ValueError(f"non-flat FAT archive member: {item.filename}")
            target = stage / item.filename
            with bundle.open(item) as source, target.open("wb") as output:
                shutil.copyfileobj(source, output)
    verified = {}
    for name in FILES:
        record = records.get(name)
        path = stage / name
        if not isinstance(record, dict):
            raise ValueError(f"manifest has no record for {name}")
        actual = {"bytes": path.stat().st_size, "sha256": digest(path)}
        if actual != {"bytes": record.get("bytes"), "sha256": record.get("sha256")}:
            raise ValueError(f"source {name} differs from its manifest")
        verified[name] = actual
    return manifest, verified


def disk_info(device: str) -> dict:
    """Read one macOS diskutil record without scraping localized text."""
    target = device if device == "/" else f"/dev/{device}"
    output = subprocess.check_output(["diskutil", "info", "-plist", target])
    return plistlib.loads(output)


def parent_disk(device: str, info: dict) -> str:
    """Resolve and cross-check a partition's whole-disk parent."""
    match = PARTITION.fullmatch(device)
    if not match:
        raise ValueError("partition must look like disk4s1, not a whole disk or mount path")
    expected = "disk" + match.group(1)
    reported = str(info.get("ParentWholeDisk", expected)).removeprefix("/dev/")
    if reported != expected:
        raise ValueError(f"partition parent mismatch: expected {expected}, got {reported}")
    return expected


def require_external_disk(device: str, info: dict, system_disk: str) -> None:
    """Require a non-system whole disk with explicit removable/external evidence."""
    identifier = str(info.get("DeviceIdentifier", device)).removeprefix("/dev/")
    if identifier != device or info.get("Whole") is not True:
        raise ValueError(f"parent /dev/{device} is not a whole disk")
    if device == system_disk:
        raise ValueError(f"refusing system disk /dev/{device}")
    bus = str(info.get("BusProtocol", "")).lower()
    external = (info.get("Internal") is False or info.get("RemovableMedia") is True or
                info.get("Ejectable") is True or
                str(info.get("DeviceLocation", "")).lower() == "external" or
                bus in {"usb", "sd", "secure digital", "thunderbolt"})
    if not external:
        raise ValueError(f"parent /dev/{device} has no external/removable-media marker")


def mounted_fat_partition(device: str) -> tuple[dict, Path, str]:
    """Require a FAT partition on an external parent and return its mount point."""
    info = disk_info(device)
    whole_disk = parent_disk(device, info)
    if info.get("Whole") is not False:
        raise ValueError("selected target is not a partition")
    root = disk_info("/")
    system_disk = str(root.get("ParentWholeDisk") or
                      root.get("DeviceIdentifier", "")).removeprefix("/dev/")
    if not system_disk:
        raise ValueError("could not resolve the macOS system disk")
    require_external_disk(whole_disk, disk_info(whole_disk), system_disk)
    filesystem = " ".join(str(info.get(key, "")) for key in
                          ("FilesystemType", "FilesystemName", "Content")).lower()
    if not any(name in filesystem for name in ("fat", "ms-dos", "msdos")):
        raise ValueError(f"selected partition is not FAT: {filesystem}")
    if not info.get("MountPoint"):
        subprocess.run(["diskutil", "mount", f"/dev/{device}"], check=True)
        info = disk_info(device)
    mount = Path(str(info.get("MountPoint", ""))).resolve()
    volumes = Path("/Volumes").resolve()
    if mount == volumes or volumes not in mount.parents:
        raise ValueError(f"unsafe mount point: {mount}")
    return info, mount, whole_disk


def install(stage: Path, records: dict, mount: Path) -> dict:
    """Replace the three FAT-root files, sync, and verify every copied byte."""
    for name in FILES:
        temporary = mount / f".erl-hls-{name}.new"
        with (stage / name).open("rb") as source, temporary.open("wb") as output:
            shutil.copyfileobj(source, output)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, mount / name)
    subprocess.run(["sync"], check=True)
    verified = {}
    for name in FILES:
        path = mount / name
        actual = {"bytes": path.stat().st_size, "sha256": digest(path)}
        if actual != records[name]:
            raise ValueError(f"on-media verification failed for {path}")
        verified[name] = actual
    return verified


def main() -> None:
    """Verify a flat role archive, then optionally install it on an explicit SD partition."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--partition", help="macOS partition identifier, for example disk4s1")
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--yes", action="store_true", help="skip the typed device confirmation")
    args = parser.parse_args()
    if args.verify_only == bool(args.partition):
        parser.error("choose exactly one of --verify-only or --partition")
    with tempfile.TemporaryDirectory(prefix="erl-hls-fat-") as directory:
        stage = Path(directory)
        manifest, records = checked_bundle(args.archive.resolve(), args.manifest.resolve(), stage)
        print(f"source role={manifest.get('role')} BOOT.bin={records['BOOT.bin']['sha256']}")
        if args.verify_only:
            print("PASS: flat FAT archive matches its manifest")
            return
        info, mount, whole_disk = mounted_fat_partition(args.partition)
        print(f"target=/dev/{args.partition} volume={info.get('VolumeName')} mount={mount}")
        if not args.yes and input(f"Type {args.partition} to replace this FAT payload: ").strip() != args.partition:
            raise RuntimeError("device confirmation did not match")
        verified = install(stage, records, mount)
        print(f"on-media BOOT.bin={verified['BOOT.bin']['sha256']}")
        subprocess.run(["diskutil", "eject", f"/dev/{whole_disk}"], check=True)
        print(f"PASS: verified and ejected /dev/{whole_disk}")


if __name__ == "__main__":
    main()
