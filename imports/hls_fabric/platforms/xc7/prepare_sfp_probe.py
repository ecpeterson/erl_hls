#!/usr/bin/env python3
"""Package a separate SFP-status SD candidate from verified existing boot assets."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess

from check_zynq_boot import check_directory, check_linux_elf
from prepare_te0715_boot import check_fit, digest
from prepare_te0715_runtime import validate_candidate

ROOT = Path(__file__).resolve().parent


def verified_inputs(base: Path, fsbl: Path, rtl: Path) -> dict:
    """Require the board profile, 25-MHz FSBL and an unchanged SFP probe build."""
    board = validate_candidate(base)
    clock = json.loads((fsbl / "manifest.json").read_text())
    if clock["fclk0_hz"] != 25000000 or clock["fsbl_sha256"] != digest(fsbl / "fsbl.elf"):
        raise ValueError("SFP probe requires the verified 25-MHz FSBL")
    for name, expected in clock["inputs"].items():
        if digest(ROOT / name) != expected:
            raise ValueError(f"FSBL source changed: {name}")
    design = json.loads((rtl / "manifest.json").read_text())
    if design["part"] != board["part"] or design["fclk0_hz"] != clock["fclk0_hz"]:
        raise ValueError("SFP clock or part mismatch")
    for name, expected in design["inputs"].items():
        if digest(ROOT / name) != expected:
            raise ValueError(f"SFP source changed: {name}")
    for name, expected in design["files"].items():
        if digest(rtl / name) != expected:
            raise ValueError(f"SFP artifact changed: {name}")
    return board


def build(base: Path, fsbl: Path, rtl: Path, sdk: Path, output: Path) -> Path:
    """Create a new SD directory without changing input images or rebuilding the SDK."""
    board = verified_inputs(base, fsbl, rtl)
    output.mkdir(parents=True, exist_ok=False)
    for name in ("u-boot.elf", "system.dtb", "zImage", "rootfs.cpio.gz", "image.ub", "boot.scr"):
        expected = board["files"][name]["sha256"]
        if digest(base / name) != expected:
            raise ValueError(f"boot input changed: {name}")
        shutil.copyfile(base / name, output / name)
    shutil.copyfile(fsbl / "fsbl.elf", output / "fsbl.elf")
    shutil.copyfile(rtl / "xc7z030sbg485-1.bit", output / "probe.bit")
    compiler = next((sdk / "compiler").glob("*/bin/arm-none-eabi-gcc"))
    musl = sdk / "work/musl-build"
    for name in ("probe_sfp", "test_probe_sfp", "test_sfp_eeprom"):
        target = output / name
        subprocess.run([str(compiler), f"-specs={musl / 'static-musl.specs'}", "-std=c11",
            "-Wall", "-Wextra", "-Werror", "-Os", "-mcpu=cortex-a9", "-mfpu=vfpv3",
            "-mfloat-abi=hard", "-static", "-Wl,-z,noexecstack", f"-Wl,-T,{musl / 'linux-static.ld'}",
            str(ROOT / "sfp" / f"{name}.c"), "-o", str(target)], check=True)
        check_linux_elf(target.read_bytes())
    (output / "boot.bif").write_text("the_ROM_image:\n{\n [bootloader] fsbl.elf\n probe.bit\n"
                                    " u-boot.elf\n [load=0x00100000] system.dtb\n}\n")
    bootgen = next((sdk / "work/bootgen").glob("*/bootgen"))
    env = dict(os.environ, SOURCE_DATE_EPOCH=str(board["source_date_epoch"]))
    with (output / "build.log").open("w") as log:
        subprocess.run([str(bootgen), "-arch", "zynq", "-image", "boot.bif", "-o", "BOOT.bin", "-w", "on"],
                       cwd=output, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    partitions = check_directory(output)
    check_fit(output / "image.ub", output, output / "build.log", env)
    manifest = {"module": board["module"], "carrier": board["carrier"], "part": board["part"],
        "hardware_validated": False, "fclk0_hz": 25000000,
        "base_manifest_sha256": digest(base / "manifest.json"),
        "fsbl_manifest_sha256": digest(fsbl / "manifest.json"),
        "rtl_manifest_sha256": digest(rtl / "manifest.json"),
        "packager_sha256": digest(Path(__file__)), "boot_partitions": partitions,
        "compiler_sha256": digest(compiler), "bootgen_sha256": digest(bootgen),
        "sd_files": ["BOOT.bin", "boot.scr", "image.ub", "probe_sfp"],
        "files": {p.name: digest(p) for p in output.iterdir() if p.is_file()}}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return output


def main() -> None:
    """Select verified inputs, the existing boot SDK, and a new output directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("base", "fsbl", "rtl", "sdk", "output"):
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    print(build(*(getattr(args, name).resolve() for name in ("base", "fsbl", "rtl", "sdk", "output"))))


if __name__ == "__main__":
    main()
