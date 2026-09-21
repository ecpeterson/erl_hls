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
from prepare_te0715_runtime import boot_files, guest, tar_entries, tree_entries, validate_candidate
from dma.routed_image import routed_inputs
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


def diagnostic(output: Path, source: Path | None = None) -> None:
    """Compile an ARM diagnostic using the boot build's static musl SDK."""
    compiler = next((ROOT / "build/boot/compiler").glob("*/bin/arm-none-eabi-gcc"))
    musl = ROOT / "build/boot/work/musl-build"
    subprocess.run([str(compiler), f"-specs={musl / 'static-musl.specs'}", "-std=c11",
                    "-Wall", "-Wextra", "-Werror", "-Os", "-mcpu=cortex-a9", "-mfpu=vfpv3",
                    "-mfloat-abi=hard", "-static", "-Wl,-z,noexecstack",
                    f"-Wl,-T,{musl / 'linux-static.ld'}", str(source or ROOT / "dma/check_dma_device.c"),
                    "-o", str(output)], check=True)
    check_linux_elf(output.read_bytes())


def build(base: Path, runtime: Path, kernel: Path, bitstream: Path, timeout: int,
          regsvc: Path | None = None, output_root: Path | None = None) -> Path:
    """Package loopback/routed inputs; an explicit output root must be a new directory."""
    build_root = output_root or (ROOT / "build/routed-dma" if regsvc else BUILD)
    fsbl, routed = routed_inputs(regsvc, bitstream) if regsvc else (base / "fsbl.elf", None)
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
    build_root.mkdir(parents=True, exist_ok=output_root is None)
    stage = build_root / "stage"
    if stage.is_symlink():
        raise ValueError("refusing symlinked DMA stage")
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir()
    boot = build_root / "boot-inputs"
    boot.mkdir(exist_ok=True)
    shutil.copyfile(fsbl, boot / "fsbl.elf")
    shutil.copyfile(base / "u-boot.elf", boot / "u-boot.elf")
    shutil.copyfile(bitstream, boot / "probe.bit")
    shutil.copyfile(kernel / "zImage", boot / "zImage")
    mailbox_tree(base / "system.dtb", boot / "system.dtb", debug=bool(regsvc))
    (boot / "boot.bif").write_text("the_ROM_image:\n{\n [bootloader] fsbl.elf\n probe.bit\n u-boot.elf\n [load=0x00100000] system.dtb\n}\n")
    bootgen = next((ROOT / "build/boot/work/bootgen").glob("*/bootgen"))
    env = dict(os.environ, SOURCE_DATE_EPOCH=str(board["source_date_epoch"]))
    with (build_root / "bootgen.log").open("w") as output:
        subprocess.run([str(bootgen), "-arch", "zynq", "-image", "boot.bif", "-o", "BOOT.bin", "-w", "on"],
                       cwd=boot, stdout=output, stderr=subprocess.STDOUT, env=env, check=True)
    check_directory(boot)
    boot_files(boot, stage, board["source_date_epoch"])
    diagnostic(build_root / "check_dma_device")

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
                         (build_root / "check_dma_device", "check_dma_device")):
        entries.append((name, source.read_bytes(), stat.S_IFREG | 0o755))
    if regsvc:
        subprocess.run(["rebar3", "compile"], cwd=ROOT.parent.parent, check=True)
        entries += tree_entries(ROOT.parent.parent / "_build/default/lib/erl_hls/ebin", "regsvc/ebin")
        entries.append(("regsvc/check_regsvc_dma.escript", (ROOT / "dma/check_regsvc_dma.escript").read_bytes(),
                        stat.S_IFREG | 0o755))
    names = {n for n, _, _ in entries}
    parents = {str(p) for n in names for p in Path(n).parents if str(p) != "."} - names
    entries += [(n, b"", stat.S_IFDIR | 0o755) for n in parents]
    entries.sort(key=lambda e: (e[0].count("/"), not stat.S_ISDIR(e[2]), e[0]))
    initrd = build_root / "install.cpio.gz"
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
    log = build_root / "install-uart.log"
    with log.open("wb") as output:
        subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, check=True, timeout=timeout)
    if b"PASS: DMA SD root assembled" not in log.read_bytes().splitlines():
        raise RuntimeError(f"DMA image installation failed: {log}")
    guest(stage, image, build_root / "sd-root-uart.log", timeout, None)
    uncompressed = {"bytes": image.stat().st_size, "sha256": digest(image)}
    with image.open("rb") as source, (stage / "rootfs.ext4.gz").open("wb") as output:
        with gzip.GzipFile(filename="", mode="wb", fileobj=output, mtime=0) as compressed:
            shutil.copyfileobj(source, compressed)
    image.unlink()
    initrd.unlink()
    manifest = {"routed_payload": routed, "hardware_validated": False, "pl_dma_path_exercised": False,
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
    published = build_root / "candidate"
    if published.is_symlink():
        raise ValueError("refusing symlinked candidate")
    if published.exists():
        shutil.rmtree(published)
    stage.rename(published)
    return published


def main() -> None:
    """Assemble verified image inputs, optionally selecting the independent debug payload."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("base", type=Path)
    parser.add_argument("runtime", type=Path)
    parser.add_argument("kernel", type=Path)
    parser.add_argument("bitstream", type=Path)
    parser.add_argument("--regsvc", type=Path, help="routed build root containing rtl/ and fsbl/")
    parser.add_argument("--output-root", type=Path, help="new directory; preserve existing DMA candidates")
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args()
    print(build(args.base.resolve(), args.runtime.resolve(), args.kernel.resolve(),
                args.bitstream.resolve(), args.timeout, args.regsvc.resolve() if args.regsvc else None,
                args.output_root.resolve() if args.output_root else None))


if __name__ == "__main__":
    main()
