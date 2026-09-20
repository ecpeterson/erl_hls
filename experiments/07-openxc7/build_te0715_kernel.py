#!/usr/bin/env python3
"""Build the Zynq kernel/modules in an offline ARM64 Linux guest on Apple Silicon."""

import argparse
import gzip
import json
import os
import shutil
import stat
import subprocess
import tarfile
import zlib
from pathlib import Path

from prepare_te0715_boot import digest, fetch
from prepare_te0715_runtime import tar_entries, validate_candidate
from test_te0715_qemu import cpio

ROOT = Path(__file__).resolve().parent
BUILD = ROOT / "build/dma-kernel"


def kernel_config(image: bytes) -> bytes:
    """Extract the embedded IKCONFIG from an ARM compressed kernel image."""
    offset = 0
    while (offset := image.find(b"\x1f\x8b\x08", offset)) >= 0:
        try:
            unpacked = zlib.decompress(image[offset:], 31)
            marker = unpacked.find(b"IKCFG_ST")
            if marker >= 0:
                return zlib.decompress(unpacked[marker + 8:], 31)
        except zlib.error:
            pass
        offset += 1
    raise ValueError("kernel has no embedded gzip IKCONFIG")


def build(candidate: Path, timeout: int) -> Path:
    """Cache source/build products; rebuild changed drivers with the same kernel ABI."""
    lock = json.loads((ROOT / "dma/builder.lock.json").read_text())
    validate_candidate(candidate)
    if timeout < 1:
        raise ValueError("timeout must be positive")
    BUILD.mkdir(parents=True, exist_ok=True)
    downloads = BUILD / "downloads"
    downloads.mkdir(exist_ok=True)
    base = fetch(lock["rootfs"], downloads)
    packages = [fetch(p, downloads) for p in lock["packages"]]
    kernel_package = next(p for p in packages if p.name.startswith("linux-virt-"))
    entries = tar_entries(base)
    # Boot-driver modules must exist before APK can mount the build disk/share.
    with tarfile.open(kernel_package) as archive:
        for member in archive:
            if member.name.startswith("boot/vmlinuz-"):
                (BUILD / "Image.gz").write_bytes(archive.extractfile(member).read())
            if member.isfile() and member.name.startswith("lib/modules/"):
                entries.append((member.name, archive.extractfile(member).read(), stat.S_IFREG | member.mode))
    compressed = (BUILD / "Image.gz").read_bytes()
    (BUILD / "Image").write_bytes(gzip.decompress(compressed) if compressed[:2] == b"\x1f\x8b" else compressed)
    entries += [("packages", b"", stat.S_IFDIR | 0o755)]
    entries += [(f"packages/{p.name}", p.read_bytes(), stat.S_IFREG | 0o644)
                for p in packages if p != kernel_package]
    entries.append(("init", (ROOT / "dma/kernel-build.sh").read_bytes(), stat.S_IFREG | 0o755))
    names = {n for n, _, _ in entries}
    parents = {str(p) for n in names for p in Path(n).parents if str(p) != "."} - names
    entries += [(n, b"", stat.S_IFDIR | 0o755) for n in parents]
    entries.sort(key=lambda e: (e[0].count("/"), not stat.S_ISDIR(e[2]), e[0]))
    initrd = BUILD / "builder.cpio.gz"
    initrd.write_bytes(gzip.compress(cpio(entries), mtime=0))
    source = fetch(lock["kernel"], downloads)
    # The sole shared directory is this experiment's build cache, never a home directory.
    share = BUILD / "share"
    share.mkdir(exist_ok=True)
    archive_link = share / "linux-xlnx.tar.gz"
    archive_link.unlink(missing_ok=True)
    os.link(source, archive_link)
    (share / "kernel.config").write_bytes(kernel_config((candidate / "zImage").read_bytes()))
    if (share / "driver").exists():
        shutil.rmtree(share / "driver")
    shutil.copytree(ROOT / "dma/driver", share / "driver")
    disk = BUILD / "builder.ext4"
    stamp = BUILD / "disk-source.sha256"
    source_hash = lock["kernel"]["sha256"]
    if disk.exists() and (not stamp.exists() or stamp.read_text() != source_hash):
        raise ValueError(f"kernel source changed or cache untracked; remove only {disk} and {share / 'disk-initialized'} to rebuild")
    if not disk.exists():
        with disk.open("wb") as output:
            output.truncate(6 * 1024 ** 3)
        stamp.write_text(source_hash)
        (share / "disk-initialized").unlink(missing_ok=True)
    log = BUILD / "build-uart.log"
    command = ["qemu-system-aarch64", "-M", "virt", "-accel", "hvf", "-cpu", "host",
               "-m", "4096", "-smp", "4", "-nographic", "-monitor", "none", "-nic", "none",
               "-no-reboot", "-kernel", str(BUILD / "Image"), "-initrd", str(initrd),
               "-append", "console=ttyAMA0 rdinit=/init panic=-1",
               "-drive", f"file={disk},if=virtio,format=raw",
               "-virtfs", f"local,path={share},mount_tag=host,security_model=none"]
    print(f"Building kernel/modules on ARM64; UART log: {log}", flush=True)
    with log.open("wb") as output:
        subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, check=True, timeout=timeout)
    if b"PASS: matching Zynq kernel and modules built" not in log.read_bytes().splitlines():
        raise RuntimeError(f"kernel build failed: {log}")
    output = share / "output"
    (output / "manifest.json").write_text(json.dumps({
        "kernel_source": lock["kernel"], "builder_lock_sha256": digest(ROOT / "dma/builder.lock.json"),
        "base_kernel_sha256": digest(candidate / "zImage"),
        "inputs": {str(p.relative_to(ROOT)): digest(p) for p in
                   [Path(__file__), ROOT / "dma/kernel-build.sh", *sorted((ROOT / "dma/driver").glob("*"))]
                   if p.is_file()},
        "files": {p.name: digest(p) for p in output.iterdir() if p.is_file() and p.name != "manifest.json"}
    }, indent=2) + "\n")
    initrd.unlink()
    return output


def main() -> None:
    """Build from a board boot candidate with a bounded local VM lifetime."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--timeout", type=int, default=3600)
    args = parser.parse_args()
    print(build(args.candidate.resolve(), args.timeout))


if __name__ == "__main__":
    main()
