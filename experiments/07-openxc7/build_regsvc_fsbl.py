#!/usr/bin/env python3
"""Build a separate 25-MHz-FCLK0 FSBL from the checked TE0715 source profile."""

import json
import os
import shutil
from pathlib import Path

from boot.board import prepare_fsbl, replace_once
from prepare_te0715_boot import digest, fetch, patch, run, unpack_tar, unpack_vendor

ROOT = Path(__file__).resolve().parent
BUILD = ROOT / "build/routed-dma/fsbl"


def divide_fclk0(source: str) -> str:
    """Change only FCLK0's second divider, from 2 to 8, in all three silicon tables."""
    old = "EMIT_MASKWRITE(0XF8000170, 0x03F03F30U ,0x00200500U)"
    if source.count(old) != 3:
        raise ValueError("unexpected FCLK0 initialization tables")
    source = source.replace(old, "EMIT_MASKWRITE(0XF8000170, 0x03F03F30U ,0x00800500U)")
    return source.replace("0XF8000170[25:20] = 0x00000002U", "0XF8000170[25:20] = 0x00000008U")


def build() -> Path:
    """Preserve the probe FSBL and reuse its verified source archives/native compiler."""
    BUILD.mkdir(parents=True, exist_ok=True)
    lock = json.loads((ROOT / "boot/sources.json").read_text())
    downloads = ROOT / "build/boot/downloads"
    archives = {name: fetch(lock["sources"][name], downloads) for name in ("embeddedsw", "trenz")}
    compiler_cache = ROOT / "build/boot/compiler"
    if (compiler_cache / ".archive-sha256").read_text() != lock["sources"]["arm"]["sha256"]:
        raise ValueError("build the checked boot compiler first")
    compiler = next(compiler_cache.glob("*/bin/arm-none-eabi-gcc")).parent
    # The shared extraction helpers confine replacements to build/boot.
    work = ROOT / "build/boot/routed-fsbl-work"
    if work.exists():
        shutil.rmtree(work)
    work.mkdir()
    env = dict(os.environ, PATH=str(compiler) + os.pathsep + os.environ["PATH"],
               SOURCE_DATE_EPOCH=str(lock["source_date_epoch"]), LC_ALL="C")
    amd = unpack_tar(archives["embeddedsw"], work / "embeddedsw")
    vendor, xsa = unpack_vendor(archives["trenz"], work / "trenz")
    log = BUILD / "build.log"
    patch(amd, "embeddedsw", log, env)
    fsbl = prepare_fsbl(amd, vendor, xsa)
    board = fsbl.parent / "misc/te0715"
    init = board / "ps7_init.c"
    init.write_text(divide_fclk0(init.read_text()))
    header = board / "ps7_init.h"
    header.write_text(replace_once(header.read_text(), "#define FPGA0_FREQ  100000000",
                                  "#define FPGA0_FREQ  25000000"))
    run(["make", "BOARD=te0715", "CFLAGS=-Wall -Os -g -c -DFSBL_DEBUG_INFO",
         "LDFLAGS=-Wl,--start-group,-lxilffs,-lxil,-lgcc,-lc,--end-group", "SHELL=/bin/bash"], fsbl, log, env)
    output = BUILD / "fsbl.elf"
    shutil.copyfile(fsbl / "fsbl.elf", output)
    manifest = {"fclk0_hz": 25000000, "fsbl_sha256": digest(output),
                "original_ps_init_sha256": digest(xsa / "ps7_init.c"),
                "ps_init_sha256": digest(init), "ps_header_sha256": digest(header),
                "sources": {name: lock["sources"][name] for name in ("embeddedsw", "trenz", "arm")},
                "inputs": {str(p.relative_to(ROOT)): digest(p) for p in
                           [Path(__file__), ROOT / "boot/board.py", ROOT / "prepare_te0715_boot.py",
                            *sorted((ROOT / "boot/patches").glob("*"))] if p.is_file()}}
    (BUILD / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return output


if __name__ == "__main__":
    print(build())
