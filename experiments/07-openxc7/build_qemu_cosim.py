#!/usr/bin/env python3
"""Build a native Zynq-only QEMU with the experiment's opt-in RTL socket bridge."""

import argparse
import json
import os
import platform
import subprocess
import sys
import tarfile
from pathlib import Path

from boot.board import replace_once
from prepare_te0715_boot import digest, fetch, run

ROOT = Path(__file__).resolve().parent
BUILD = ROOT / "build/cosim"


def write_changed(path: Path, data: bytes) -> None:
    """Preserve timestamps of unchanged build inputs so warm builds remain small."""
    if not path.exists() or path.read_bytes() != data:
        path.write_bytes(data)


def build(jobs: int) -> Path:
    """Fetch pinned sources, attach only the PL window/IRQ, and retain native objects."""
    BUILD.mkdir(parents=True, exist_ok=True)
    downloads = BUILD / "downloads"
    downloads.mkdir(exist_ok=True)
    locks = json.loads((ROOT / "cosim/sources.lock.json").read_text())
    archives = {name: fetch(source, downloads) for name, source in locks.items()}
    for archive in archives.values():
        top = archive.name.split(".tar.")[0]
        if not (BUILD / top).exists():
            with tarfile.open(archive) as tar:
                tar.extractall(BUILD, filter="data")
    ninja = BUILD / "ninja-1.13.1"
    source = BUILD / "qemu-10.2.0"
    env = dict(os.environ)
    log = BUILD / "build.log"
    if not (ninja / "ninja").exists():
        run([sys.executable, "configure.py", "--bootstrap"], ninja, log, env)
    env["PATH"] = str(ninja) + os.pathsep + env["PATH"]
    # Keep pristine patch inputs, avoiding a large decompression on warm builds.
    originals = BUILD / "upstream"
    originals.mkdir(exist_ok=True)
    names = {"hw/arm/xilinx_zynq.c": "board.c", "hw/misc/meson.build": "misc.meson"}
    if not all((originals / name).exists() for name in names.values()):
        with tarfile.open(archives["qemu"]) as tar:
            for name, target in names.items():
                (originals / target).write_bytes(tar.extractfile("qemu-10.2.0/" + name).read())
    board = (originals / "board.c").read_text()
    board = replace_once(board, '#include "qemu/osdep.h"',
                             '#include "qemu/osdep.h"\n#include "hw/misc/hls_cosim.h"')
    board = replace_once(board, '    dev = qdev_new("pl330");',
                             '    hls_cosim_init(address_space_mem, pic[61 - GIC_INTERNAL]);\n\n'
                             '    dev = qdev_new("pl330");')
    meson = (originals / "misc.meson").read_bytes()
    write_changed(source / "hw/arm/xilinx_zynq.c", board.encode())
    write_changed(source / "hw/misc/meson.build", meson +
                  b"\nsystem_ss.add(when: 'CONFIG_ZYNQ', if_true: files('hls_cosim.c'))\n")
    write_changed(source / "configs/devices/arm-softmmu/default.mak",
                  b"CONFIG_ZYNQ=y\nCONFIG_ARM_V7M=y\nCONFIG_UNIMP=y\n")
    for original, target in (("qemu_bridge.c", "hls_cosim.c"),
                              ("qemu_bridge.h", "hls_cosim.h"),
                              ("protocol.h", "hls_cosim_protocol.h")):
        write_changed(source / "hw/misc" / target, (ROOT / "cosim" / original).read_bytes())
    output = BUILD / "qemu-build"
    output.mkdir(exist_ok=True)
    if not (output / "build.ninja").exists():
        flags = []
        if platform.system() == "Darwin":
            prefix = subprocess.check_output(["brew", "--prefix"], text=True).strip()
            flags = [f"--extra-cflags=-I{prefix}/include", f"--extra-ldflags=-L{prefix}/lib"]
        run([source / "configure", "--target-list=arm-softmmu", "--without-default-features",
             "--without-default-devices", "--enable-tcg", "--enable-fdt", "--disable-download",
             "--disable-docs", "--disable-tools", "--disable-guest-agent",
             f"--python={sys.executable}", *flags], output, log, env)
    run([ninja / "ninja", "-j", str(jobs), "qemu-system-arm"], output, log, env)
    binary = output / "qemu-system-arm"
    manifest = {"host": platform.platform(), "sources": locks,
                "inputs": {str(p.relative_to(ROOT)): digest(p) for p in
                           [Path(__file__), *sorted((ROOT / "cosim").glob("*"))] if p.is_file()},
                "qemu_sha256": digest(binary),
                "version": subprocess.check_output([binary, "--version"], text=True).splitlines()[0]}
    (BUILD / "qemu-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return binary


def main() -> None:
    """Build only the ARM system emulator, with a bounded compile parallelism."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jobs", type=int, default=4)
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("jobs must be positive")
    print(build(args.jobs))


if __name__ == "__main__":
    main()
