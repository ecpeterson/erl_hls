#!/usr/bin/env python3
"""Package retained, timing-checked GTX/Ethernet reference images as separate SD kits."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess

from check_zynq_boot import bit_payload, check_directory, check_linux_elf
from prepare_te0715_boot import check_fit, digest, fdt, run
from prepare_te0715_runtime import validate_candidate

ROOT = Path(__file__).resolve().parent
REFERENCE = ROOT / "results/vivado-reference-2026-09-21.json"
# Names identify the selected image on disk; the two ETH7 images share an MMIO ABI.
PROFILES = {
    "prbs": {"uio": "erl-hls-gtx", "program": "probe_gtx", "source": "gtx",
             "loopback": "near-end PMA", "rx_polarity": 0, "tx_polarity": 0},
    "ethernet-loopback": {"uio": "erl-hls-ethernet", "program": "probe_ethernet", "source": "ethernet",
                          "loopback": "near-end PMA", "rx_polarity": 0, "tx_polarity": 0},
    "ethernet-external": {"uio": "erl-hls-ethernet", "program": "probe_ethernet", "source": "ethernet",
                          "loopback": "none", "rx_polarity": 1, "tx_polarity": 1},
}


def verify_reference(profile: str, bitstream: Path) -> dict:
    """Reject swapped or altered images, including unqualified native substitutes."""
    if profile not in PROFILES:
        raise ValueError(f"unknown link profile: {profile}")
    reference = json.loads(REFERENCE.read_text())
    expected = reference["profiles"][profile]["artifacts_sha256"]["candidate.bit"]
    if digest(bitstream) != expected:
        raise ValueError(f"bitstream differs from retained {profile} reference")
    bit_payload(bitstream.read_bytes())
    return reference


def verify_clock(fsbl: Path) -> dict:
    """Require the unchanged, board-specific 25-MHz FSBL and its source provenance."""
    clock = json.loads((fsbl / "manifest.json").read_text())
    if clock["fclk0_hz"] != 25000000 or digest(fsbl / "fsbl.elf") != clock["fsbl_sha256"]:
        raise ValueError("link probes require the verified 25-MHz FSBL")
    for name, expected in clock["inputs"].items():
        if digest(ROOT / name) != expected:
            raise ValueError(f"FSBL source changed: {name}")
    return clock


def check_candidate(candidate: Path) -> dict:
    """Check every published file, exact profile/FSBL provenance and both boot containers."""
    manifest = json.loads((candidate / "manifest.json").read_text())
    profile = manifest["profile"]
    reference = verify_reference(profile, candidate / "probe.bit")
    if manifest["part"] != reference["part"] or manifest["fclk0_hz"] != 25000000:
        raise ValueError("candidate part or control clock mismatch")
    if manifest["configuration"] != PROFILES[profile] or manifest["reference_sha256"] != digest(REFERENCE):
        raise ValueError("candidate profile or reference changed")
    verify_clock(candidate)
    for name, expected in manifest["files"].items():
        if digest(candidate / name) != expected:
            raise ValueError(f"candidate file changed: {name}")
    if check_directory(candidate) != manifest["boot_partitions"]:
        raise ValueError("candidate partition map changed")
    tree = candidate / "system.dtb"
    node = "/amba_pl/probe@40000000"
    for prop, kind, value in (("linux,uio-name", "s", PROFILES[profile]["uio"]),
                              ("reg", "x", "40000000 1000"), ("compatible", "s", "generic-uio")):
        if fdt(tree, node, prop, kind) != value:
            raise ValueError(f"candidate UIO property changed: {prop}")
    check_fit(candidate / "image.ub", candidate, candidate / "verify.log", dict(os.environ))
    for name in manifest["programs"]:
        check_linux_elf((candidate / name).read_bytes())
    return manifest


def build(profile: str, base: Path, fsbl: Path, bitstream: Path, sdk: Path, output: Path) -> Path:
    """Create one fresh SD kit from a verified base; reuse the SDK without downloading."""
    reference = verify_reference(profile, bitstream)
    board = validate_candidate(base)
    clock = verify_clock(fsbl)
    if reference["part"] != board["part"]:
        raise ValueError("reference and base board differ")
    configuration = PROFILES[profile]
    output.mkdir(parents=True, exist_ok=False)
    for name in ("u-boot.elf", "system.dtb", "zImage", "rootfs.cpio.gz"):
        shutil.copyfile(base / name, output / name)
    shutil.copyfile(fsbl / "fsbl.elf", output / "fsbl.elf")
    shutil.copyfile(bitstream, output / "probe.bit")
    env = dict(os.environ, SOURCE_DATE_EPOCH=str(board["source_date_epoch"]))
    log = output / "build.log"
    run(["fdtput", "-t", "s", output / "system.dtb", "/amba_pl/probe@40000000",
         "linux,uio-name", configuration["uio"]], output, log, env)
    its = (ROOT / "boot/probe.its").read_text().replace("register-probe candidate", f"{profile} candidate")
    (output / "probe.its").write_text(its)
    run(["mkimage", "-f", "probe.its", "image.ub"], output, log, env)
    script = (ROOT / "boot/boot.cmd").read_text().replace("register-probe candidate", f"{profile} candidate")
    (output / "boot.cmd").write_text(script)
    run(["mkimage", "-A", "arm", "-T", "script", "-C", "none", "-n", f"TE0715 {profile}",
         "-d", "boot.cmd", "boot.scr"], output, log, env)
    programs = [configuration["program"]] + (["test_probe_gtx"] if profile == "prbs" else [])
    compiler = next((sdk / "compiler").glob("*/bin/arm-none-eabi-gcc"))
    musl = sdk / "work/musl-build"
    for name in programs:
        run([compiler, f"-specs={musl / 'static-musl.specs'}", "-std=c11", "-Wall", "-Wextra", "-Werror",
             "-Os", "-mcpu=cortex-a9", "-mfpu=vfpv3", "-mfloat-abi=hard", "-static", "-Wl,-z,noexecstack",
             f"-Wl,-T,{musl / 'linux-static.ld'}", ROOT / configuration["source"] / f"{name}.c",
             "-o", output / name], output, log, env)
    (output / "boot.bif").write_text("the_ROM_image:\n{\n [bootloader] fsbl.elf\n probe.bit\n"
                                    " u-boot.elf\n [load=0x00100000] system.dtb\n}\n")
    bootgen = next((sdk / "work/bootgen").glob("*/bootgen"))
    run([bootgen, "-arch", "zynq", "-image", "boot.bif", "-o", "BOOT.bin", "-w", "on"], output, log, env)
    manifest = {**clock, "module": board["module"], "carrier": board["carrier"], "part": board["part"],
        "profile": profile, "configuration": configuration, "hardware_validated": False,
        "reference_clock_hz_required": 125000000, "fsbl_programs_si5338": False,
        "reference_sha256": digest(REFERENCE), "base_manifest_sha256": digest(base / "manifest.json"),
        "fsbl_manifest_sha256": digest(fsbl / "manifest.json"), "compiler_sha256": digest(compiler),
        "bootgen_sha256": digest(bootgen), "boot_partitions": check_directory(output), "programs": programs,
        "sources": {str(p.relative_to(ROOT)): digest(p) for p in
                    [Path(__file__), ROOT / "check_zynq_boot.py", ROOT / "boot/probe.its", ROOT / "boot/boot.cmd",
                     *(ROOT / configuration["source"] / f"{name}.c" for name in programs)]},
        "sd_files": ["BOOT.bin", "boot.scr", "image.ub", configuration["program"]],
        "files": {p.name: digest(p) for p in output.iterdir() if p.is_file()}}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    check_candidate(output)
    return output


def main() -> None:
    """Build from retained inputs, or independently recheck an existing complete kit."""
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    create = sub.add_parser("build")
    create.add_argument("profile", choices=PROFILES)
    for name in ("base", "fsbl", "bitstream", "sdk", "output"):
        create.add_argument(name, type=Path)
    verify = sub.add_parser("check")
    verify.add_argument("candidate", type=Path)
    args = parser.parse_args()
    if args.command == "check":
        print(check_candidate(args.candidate.resolve())["profile"] + ": verified")
    else:
        print(build(args.profile, *(getattr(args, name).resolve() for name in
                    ("base", "fsbl", "bitstream", "sdk", "output"))))


if __name__ == "__main__":
    main()
