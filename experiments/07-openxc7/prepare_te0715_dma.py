#!/usr/bin/env python3
"""Package the DMA loopback bitstream, source-built kernel and matched driver on SD."""

import argparse
import gzip
import json
import os
import shutil
import stat
import subprocess
from pathlib import Path

from check_zynq_boot import check_directory, check_linux_elf
from dma.device_tree import mailbox_tree
from prepare_te0715_boot import digest, fetch
from prepare_te0715_runtime import boot_files, guest, tar_entries, validate_candidate
from test_te0715_qemu import cpio

ROOT = Path(__file__).resolve().parent
BUILD = ROOT / "build/dma"


def check_manifest(directory: Path) -> dict:
    """Verify all files in a previous image/kernel manifest before reusing them."""
    manifest = json.loads((directory / "manifest.json").read_text())
    for name, expected in manifest["files"].items():
        if Path(name).name != name:
            raise ValueError("manifest file must be a basename")
        sha256 = expected if isinstance(expected, str) else expected["sha256"]
        if digest(directory / name) != sha256:
            raise ValueError(f"input hash mismatch: {directory / name}")
    return manifest


def diagnostic(output: Path) -> None:
    """Compile the board acceptance tool with the preceding boot build's static musl SDK."""
    compiler = next((ROOT / "build/boot/compiler").glob("*/bin/arm-none-eabi-gcc"))
    musl = ROOT / "build/boot/work/musl-build"
    subprocess.run([str(compiler), f"-specs={musl / 'static-musl.specs'}", "-std=c11",
                    "-Wall", "-Wextra", "-Werror", "-Os", "-mcpu=cortex-a9", "-mfpu=vfpv3",
                    "-mfloat-abi=hard", "-static", "-Wl,-z,noexecstack",
                    f"-Wl,-T,{musl / 'linux-static.ld'}", str(ROOT / "dma/check_dma_device.c"),
                    "-o", str(output)], check=True)
    check_linux_elf(output.read_bytes())


def build(base: Path, runtime: Path, kernel: Path, bitstream: Path, timeout: int) -> Path:
    """Create a separate image; never alter the preceding candidate or any host disk."""
    board = validate_candidate(base)
    runtime_manifest = check_manifest(runtime)
    kernel_manifest = check_manifest(kernel)
    if runtime_manifest["base_boot_manifest_sha256"] != digest(base / "manifest.json"):
        raise ValueError("runtime does not derive from this boot candidate")
    if kernel_manifest["base_kernel_sha256"] != digest(base / "zImage"):
        raise ValueError("kernel configuration does not derive from this boot candidate")
    for name, sha256 in kernel_manifest["inputs"].items():
        if digest(ROOT / name) != sha256:
            raise ValueError(f"kernel/driver input changed; rebuild first: {name}")
    BUILD.mkdir(parents=True, exist_ok=True)
    stage = BUILD / "stage"
    if stage.is_symlink():
        raise ValueError("refusing symlinked DMA stage")
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir()
    boot = BUILD / "boot-inputs"
    boot.mkdir(exist_ok=True)
    for name in ("fsbl.elf", "u-boot.elf"):
        shutil.copyfile(base / name, boot / name)
    shutil.copyfile(bitstream, boot / "probe.bit")
    shutil.copyfile(kernel / "zImage", boot / "zImage")
    mailbox_tree(base / "system.dtb", boot / "system.dtb")
    (boot / "boot.bif").write_text("the_ROM_image:\n{\n [bootloader] fsbl.elf\n probe.bit\n u-boot.elf\n [load=0x00100000] system.dtb\n}\n")
    bootgen = next((ROOT / "build/boot/work/bootgen").glob("*/bootgen"))
    env = dict(os.environ, SOURCE_DATE_EPOCH=str(board["source_date_epoch"]))
    with (BUILD / "bootgen.log").open("w") as output:
        subprocess.run([str(bootgen), "-arch", "zynq", "-image", "boot.bif", "-o", "BOOT.bin", "-w", "on"],
                       cwd=boot, stdout=output, stderr=subprocess.STDOUT, env=env, check=True)
    check_directory(boot)
    boot_files(boot, stage, board["source_date_epoch"])
    diagnostic(BUILD / "check_dma_device")

    lock = json.loads((ROOT / "runtime/packages.lock.json").read_text())
    entries = tar_entries(fetch(lock["rootfs"], ROOT / "build/runtime/downloads"))
    entries += [e for e in tar_entries(kernel / "modules.tar.gz")
                if not e[0].endswith(("/build", "/source"))]
    release = (kernel / "kernel.release").read_text().strip()
    entries += [(f"lib/modules/{release}/extra/{name}", (kernel / name).read_bytes(), stat.S_IFREG | 0o644)
                for name in ("hls_dma_selftest.ko", "hls_dma_mailbox.ko")]
    for source, name in ((ROOT / "dma/install-init.sh", "init"),
                         (ROOT / "dma/runtime-check.sh", "dma-runtime-check"),
                         (ROOT / "dma/check_dma_beam.escript", "check_dma_beam.escript"),
                         (BUILD / "check_dma_device", "check_dma_device")):
        entries.append((name, source.read_bytes(), stat.S_IFREG | 0o755))
    names = {n for n, _, _ in entries}
    parents = {str(p) for n in names for p in Path(n).parents if str(p) != "."} - names
    entries += [(n, b"", stat.S_IFDIR | 0o755) for n in parents]
    entries.sort(key=lambda e: (e[0].count("/"), not stat.S_ISDIR(e[2]), e[0]))
    initrd = BUILD / "install.cpio.gz"
    initrd.write_bytes(gzip.compress(cpio(entries), mtime=0))
    image = stage / "rootfs.ext4"
    with gzip.open(runtime / "rootfs.ext4.gz", "rb") as source, image.open("wb") as output:
        shutil.copyfileobj(source, output)
    if digest(image) != runtime_manifest["rootfs_uncompressed"]["sha256"]:
        raise ValueError("uncompressed base runtime differs")
    command = ["qemu-system-arm", "-M", "xilinx-zynq-a9", "-m", "1024", "-smp", "1",
               "-nographic", "-monitor", "none", "-nic", "none", "-no-reboot",
               "-kernel", str(stage / "zImage"), "-dtb", str(stage / "system.dtb"),
               "-initrd", str(initrd), "-append", "console=ttyPS0,115200 rdinit=/init panic=-1",
               "-drive", f"file={image},if=sd,format=raw"]
    print("Installing and checking the matching kernel/driver image...", flush=True)
    log = BUILD / "install-uart.log"
    with log.open("wb") as output:
        subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, check=True, timeout=timeout)
    if b"PASS: DMA SD root assembled" not in log.read_bytes().splitlines():
        raise RuntimeError(f"DMA image installation failed: {log}")
    guest(stage, image, BUILD / "sd-root-uart.log", timeout, None)
    uncompressed = {"bytes": image.stat().st_size, "sha256": digest(image)}
    with image.open("rb") as source, (stage / "rootfs.ext4.gz").open("wb") as output:
        with gzip.GzipFile(filename="", mode="wb", fileobj=output, mtime=0) as compressed:
            shutil.copyfileobj(source, compressed)
    image.unlink()
    initrd.unlink()
    manifest = {"hardware_validated": False, "pl_dma_path_exercised": False,
                "qemu_pl330_memcpy_exercised": True, "module": board["module"], "carrier": board["carrier"],
                "part": board["part"], "kernel_release": release, "rootfs_uncompressed": uncompressed,
                "base_runtime_manifest_sha256": digest(runtime / "manifest.json"),
                "kernel_manifest_sha256": digest(kernel / "manifest.json"), "bitstream_sha256": digest(bitstream),
                "inputs": {str(p.relative_to(ROOT)): digest(p) for p in
                           [Path(__file__), *sorted((ROOT / "dma").rglob("*"))]
                           if p.is_file() and "__pycache__" not in p.parts},
                "files": {p.name: {"bytes": p.stat().st_size, "sha256": digest(p)}
                          for p in stage.iterdir() if p.is_file()}}
    (stage / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    published = BUILD / "candidate"
    if published.is_symlink():
        raise ValueError("refusing symlinked candidate")
    if published.exists():
        shutil.rmtree(published)
    stage.rename(published)
    return published


def main() -> None:
    """Assemble explicit, verified boot/runtime/kernel inputs and a loopback bitstream."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("base", type=Path)
    parser.add_argument("runtime", type=Path)
    parser.add_argument("kernel", type=Path)
    parser.add_argument("bitstream", type=Path)
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args()
    print(build(args.base.resolve(), args.runtime.resolve(), args.kernel.resolve(),
                args.bitstream.resolve(), args.timeout))


if __name__ == "__main__":
    main()
