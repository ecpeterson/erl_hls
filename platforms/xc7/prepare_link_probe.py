#!/usr/bin/env python3
"""Package retained, timing-checked GTX/Ethernet reference images as separate SD kits."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess

from boot.reference import REFERENCE, verify_reference as verify_image
from check_zynq_boot import check_directory, check_linux_elf
from prepare_te0715_boot import check_fit, digest, fdt, run
from prepare_te0715_runtime import validate_candidate
from clocking.profile import audit, read_rows, VENDOR_SHA256

ROOT = Path(__file__).resolve().parent
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
    return verify_image(profile, bitstream, REFERENCE)


def verify_clock(fsbl: Path) -> dict:
    """Require the unchanged, board-specific 25-MHz FSBL and its source provenance."""
    clock = json.loads((fsbl / "manifest.json").read_text())
    if clock["fclk0_hz"] != 25000000 or digest(fsbl / "fsbl.elf") != clock["fsbl_sha256"]:
        raise ValueError("link probes require the verified 25-MHz FSBL")
    for name, expected in clock["inputs"].items():
        if digest(ROOT / name) != expected:
            raise ValueError(f"FSBL source changed: {name}")
    if clock.get("fsbl_programs_si5338"):
        if (clock.get("clock_profile") != audit(read_rows(ROOT / "clocking/profile.h")) or
                clock.get("clock_vendor_table_sha256") != VENDOR_SHA256 or
                clock.get("vccio34_mv_required") != 1800):
            raise ValueError("FSBL clock profile or electrical prerequisites differ")
    return clock


def program_sources(profile: str, clock_startup: bool) -> dict[str, list[Path]]:
    """Select each diagnostic and its shared sources for this kit's boot contract."""
    configuration = PROFILES[profile]
    names = [configuration["program"]] + (["test_probe_gtx"] if profile == "prbs" else [])
    sources = {name: [ROOT / configuration["source"] / f"{name}.c"] for name in names}
    if clock_startup:
        for name, core in (("probe_clock", "si5338"), ("test_si5338", "si5338"), ("test_ps_i2c", "ps_i2c")):
            sources[name] = [ROOT / "clocking" / f"{name}.c", ROOT / "clocking" / f"{core}.c"]
    return sources


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
    if manifest["programs"] != list(program_sources(profile, manifest.get("fsbl_programs_si5338", False))):
        raise ValueError("candidate diagnostic set changed")
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
    if manifest.get("fsbl_programs_si5338"):
        if (fdt(tree, "/axi/i2c@e0005000", "status", "s") != "okay" or
                fdt(tree, "/aliases", "i2c0", "s") != "/axi/i2c@e0005000"):
            raise ValueError("candidate PS I2C1 mapping changed")
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
    sources = program_sources(profile, clock.get("fsbl_programs_si5338", False))
    programs = list(sources)
    compiler = next((sdk / "compiler").glob("*/bin/arm-none-eabi-gcc"))
    musl = sdk / "work/musl-build"
    for name in programs:
        run([compiler, f"-specs={musl / 'static-musl.specs'}", "-std=c11", "-Wall", "-Wextra", "-Werror",
             "-Os", "-mcpu=cortex-a9", "-mfpu=vfpv3", "-mfloat-abi=hard", "-static", "-Wl,-z,noexecstack",
             f"-Wl,-T,{musl / 'linux-static.ld'}", *sources[name],
             "-o", output / name], output, log, env)
    (output / "boot.bif").write_text("the_ROM_image:\n{\n [bootloader] fsbl.elf\n probe.bit\n"
                                    " u-boot.elf\n [load=0x00100000] system.dtb\n}\n")
    bootgen = next((sdk / "work/bootgen").glob("*/bootgen"))
    run([bootgen, "-arch", "zynq", "-image", "boot.bif", "-o", "BOOT.bin", "-w", "on"], output, log, env)
    manifest = {**clock, "module": board["module"], "carrier": board["carrier"], "part": board["part"],
        "profile": profile, "configuration": configuration, "hardware_validated": False,
        "reference_clock_hz_required": 125000000,
        "fsbl_programs_si5338": clock.get("fsbl_programs_si5338", False),
        "reference_sha256": digest(REFERENCE), "base_manifest_sha256": digest(base / "manifest.json"),
        "fsbl_manifest_sha256": digest(fsbl / "manifest.json"), "compiler_sha256": digest(compiler),
        "bootgen_sha256": digest(bootgen), "boot_partitions": check_directory(output), "programs": programs,
        "sources": {str(p.relative_to(ROOT)): digest(p) for p in
                    [Path(__file__), ROOT / "check_zynq_boot.py", ROOT / "boot/probe.its", ROOT / "boot/boot.cmd",
                     *(p for files in sources.values() for p in files)]},
        "sd_files": ["BOOT.bin", "boot.scr", "image.ub", configuration["program"],
                     *(["probe_clock"] if clock.get("fsbl_programs_si5338") else [])],
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
