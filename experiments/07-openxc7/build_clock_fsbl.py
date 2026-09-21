#!/usr/bin/env python3
"""Build the TE0715 25-MHz FSBL with checked, volatile Si5338 startup before PL load."""

import json
import os
from pathlib import Path
import shutil

from boot.board import prepare_fsbl, replace_once
from build_regsvc_fsbl import divide_fclk0
from clocking.profile import audit, render, vendor_rows, VENDOR_SHA256
from prepare_te0715_boot import digest, fetch, patch, run, unpack_tar, unpack_vendor

ROOT = Path(__file__).resolve().parent
BUILD = ROOT / "build/clock-startup/fsbl"


def install_hooks(fsbl: Path) -> dict:
    """Install checked clock hooks into a fresh BSP, rejecting vendor/profile drift."""
    rows = vendor_rows((fsbl / "te_Si5338-Registers.h").read_bytes())
    profile = audit(rows)
    if (ROOT / "clocking/profile.h").read_text() != render(rows):
        raise ValueError("generated clock profile differs from pinned vendor table")
    hooks = fsbl / "te_fsbl_hooks.h"
    hooks.write_text(replace_once(hooks.read_text(), "// #define ENABLE_TE_HOOKS_BD",
                                 "#define ENABLE_TE_HOOKS_BD"))
    if "\n#define ENABLE_TE_HOOKS_BH" not in hooks.read_text():
        raise ValueError("vendor before-handoff hook is not enabled")
    shutil.copyfile(ROOT / "clocking/clock_fsbl.c", fsbl / "te_fsbl_hooks_te0715.c")
    # Unused vendor transports contain unchecked/unbounded I/O. Do not link them.
    for name in ("te_iic_platform.c", "te_si5338.c"):
        (fsbl / name).unlink(missing_ok=True)
    for name in ("si5338.c", "si5338.h", "ps_i2c.c", "ps_i2c.h", "profile.h"):
        shutil.copyfile(ROOT / "clocking" / name, fsbl / name)
    return profile


def build() -> Path:
    """Reuse verified archives/compiler, preserving all previously built FSBLs and kits."""
    BUILD.mkdir(parents=True, exist_ok=True)
    lock = json.loads((ROOT / "boot/sources.json").read_text())
    archives = {name: fetch(lock["sources"][name], ROOT / "build/boot/downloads")
                for name in ("embeddedsw", "trenz")}
    compiler_cache = ROOT / "build/boot/compiler"
    if (compiler_cache / ".archive-sha256").read_text() != lock["sources"]["arm"]["sha256"]:
        raise ValueError("build the checked boot compiler first")
    compiler = next(compiler_cache.glob("*/bin/arm-none-eabi-gcc")).parent
    work = ROOT / "build/boot/clock-fsbl-work"
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
    profile = install_hooks(fsbl)
    board = fsbl.parent / "misc/te0715"
    init, header = board / "ps7_init.c", board / "ps7_init.h"
    init.write_text(divide_fclk0(init.read_text()))
    header.write_text(replace_once(header.read_text(), "#define FPGA0_FREQ  100000000",
                                  "#define FPGA0_FREQ  25000000"))
    run(["make", "BOARD=te0715", "CFLAGS=-Wall -Os -g -c -DFSBL_DEBUG_INFO",
         "LDFLAGS=-Wl,-Map,fsbl.map -Wl,--start-group,-lxilffs,-lxil,-lgcc,-lc,--end-group",
         "SHELL=/bin/bash"], fsbl, log, env)
    for name in ("fsbl.elf", "fsbl.map"):
        shutil.copyfile(fsbl / name, BUILD / name)
    manifest = {"fclk0_hz": 25000000, "fsbl_sha256": digest(BUILD / "fsbl.elf"),
                "fsbl_programs_si5338": True, "clock_profile": profile, "vccio34_mv_required": 1800,
                "clock_vendor_table_sha256": VENDOR_SHA256,
                "clock_hook_phase": "before-bitstream; verify before-handoff",
                "original_ps_init_sha256": digest(xsa / "ps7_init.c"),
                "ps_init_sha256": digest(init), "ps_header_sha256": digest(header),
                "sources": {name: lock["sources"][name] for name in ("embeddedsw", "trenz", "arm")},
                "inputs": {str(p.relative_to(ROOT)): digest(p) for p in
                           [Path(__file__), ROOT / "build_regsvc_fsbl.py", ROOT / "boot/board.py",
                            ROOT / "prepare_te0715_boot.py", ROOT / "clocking/profile.py",
                            *sorted((ROOT / "clocking").glob("*.h")),
                            *(ROOT / "clocking" / name for name in ("clock_fsbl.c", "si5338.c", "ps_i2c.c")),
                            *sorted((ROOT / "boot/patches").glob("*"))] if p.is_file()}}
    (BUILD / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return BUILD / "fsbl.elf"


if __name__ == "__main__":
    print(build())
