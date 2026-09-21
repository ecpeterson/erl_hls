#!/usr/bin/env python3
"""Package retained Vivado register/DMA probes with their matched 100-MHz SD software."""

import argparse
import json
import os
from pathlib import Path
import shutil

from boot.reference import REFERENCE, verify_reference
from check_zynq_boot import check_directory, check_linux_elf
from prepare_te0715_boot import check_fit, digest, fdt, run
from prepare_te0715_dma import build as build_dma, check_manifest
from prepare_te0715_runtime import validate_candidate

ROOT = Path(__file__).resolve().parent
BOOT_REFERENCE = ROOT / "te0715-boot-result.json"
PROFILES = {
    "register": {"programs": ["probe_zynq_ps", "test_probe_zynq_ps"],
                 "sd_files": ["BOOT.bin", "boot.scr", "image.ub", "probe_zynq_ps"], "root_partition": None},
    "dma": {"programs": ["check_dma_device"], "sd_files": ["BOOT.bin", "boot.scr", "image.ub"],
            "root_partition": {"number": 2, "filesystem": "ext4", "gzip_source": "rootfs.ext4.gz"}},
}


def verify_rtl(profile: str, reference: dict, source_manifest: Path) -> dict[str, str]:
    """Bind the retained PL image to the RTL used by this kit's local simulations."""
    if digest(source_manifest) != reference["profiles"][profile]["artifacts_sha256"]["input-manifest.json"]:
        raise ValueError("PL source manifest differs from retained reference")
    files = json.loads(source_manifest.read_text())["files"]
    names = ("zynq_ps_probe.v", "zynq_ps_probe_top.v") if profile == "register" else (
        "dma/zynq_dma_mailbox.v", "dma/zynq_dma_top.v")
    return {name: files["inputs/" + name] for name in names}


def verify_clock(partitions: list[dict], ps_init_sha256: str) -> None:
    """Require the previously checked 100-MHz FSBL payload and unchanged Trenz PS setup."""
    boot = json.loads(BOOT_REFERENCE.read_text())
    expected = boot["boot_partitions"][0]
    if (partitions[0]["sha256"] != expected["sha256"] or
            ps_init_sha256 != boot["ps_init_sha256"]):
        raise ValueError("PS probes require the retained 100-MHz FSBL and PS initialization")


def check_mapping(tree: Path, profile: str) -> None:
    """Require the intended aperture, driver, clock, interrupt and DMA channel bindings."""
    clock = "/axi/slcr@f8000000/clkc@100"
    phandle = fdt(tree, clock, "phandle", "x")
    if fdt(tree, clock, "fclk-enable", "x") != "1":
        raise ValueError("FCLK0 must remain enabled")
    if profile == "register":
        node = "/amba_pl/probe@40000000"
        fields = [(node, "compatible", "s", "generic-uio"),
                  (node, "linux,uio-name", "s", "erl-hls-probe"),
                  (node, "reg", "x", "40000000 1000")]
    else:
        node = "/amba_pl/dma-mailbox@40000000"
        dma = fdt(tree, "/axi/dma-controller@f8003000", "phandle", "x")
        gic = fdt(tree, "/axi/interrupt-controller@f8f01000", "phandle", "x")
        fields = [(node, "compatible", "s", "erl-hls,dma-mailbox-v1"),
                  (node, "reg", "x", "40000000 3000"),
                  (node, "interrupt-parent", "x", gic), (node, "interrupts", "x", "0 1d 4"),
                  (node, "dmas", "x", f"{dma} 0 {dma} 1"), (node, "dma-names", "s", "tx rx"),
                  ("/aliases", "hlsdma0", "s", node)]
    for path, prop, kind, expected in [*fields, (node, "clocks", "x", f"{phandle} f")]:
        if fdt(tree, path, prop, kind) != expected:
            raise ValueError(f"PS probe mapping differs: {path}/{prop}")


def check_runtime_fit(candidate: Path) -> None:
    """Verify the DMA FIT selects the retained kernel/DTB and hashes their exact bytes."""
    fit = candidate / "image.ub"
    if fdt(fit, "/configurations", "default") != "runtime":
        raise ValueError("DMA FIT must select runtime")
    for index, (name, filename) in enumerate((("kernel", "zImage"), ("fdt", "system.dtb"))):
        if fdt(fit, "/configurations/runtime", name) != name:
            raise ValueError(f"DMA FIT does not select {name}")
        extracted = candidate / f"verify-{name}"
        try:
            run(["dumpimage", "-T", "flat_dt", "-p", str(index), "-o", extracted, fit],
                candidate, candidate / "verify.log", dict(os.environ))
            expected = bytes.fromhex(digest(candidate / filename))
            actual = bytes(int(b, 16) for b in fdt(fit, f"/images/{name}/hash", "value", "bx").split())
            if (digest(extracted) != expected.hex() or actual != expected or
                    fdt(fit, f"/images/{name}/hash", "algo") != "sha256"):
                raise ValueError(f"DMA FIT payload/hash differs: {name}")
        finally:
            extracted.unlink(missing_ok=True)


def check_candidate(candidate: Path) -> dict:
    """Independently check a complete kit against retained PL/PS references and boot payloads."""
    manifest = check_manifest(candidate)
    profile = manifest["profile"]
    if profile not in PROFILES:
        raise ValueError(f"unknown PS probe: {profile}")
    reference = verify_reference(profile, candidate / "probe.bit")
    if manifest["pl_sources"] != verify_rtl(profile, reference, candidate / "pl-sources.json"):
        raise ValueError("PS probe RTL provenance differs")
    if any(manifest[key] != value for key, value in PROFILES[profile].items()):
        raise ValueError("PS probe programs or SD installation layout differs")
    for key in ("module", "carrier", "part"):
        if manifest[key] != json.loads(BOOT_REFERENCE.read_text())[key]:
            raise ValueError(f"PS probe {key} differs")
    if (manifest["part"] != reference["part"] or manifest["fclk0_hz"] != 100000000 or
            manifest["reference_sha256"] != digest(REFERENCE)):
        raise ValueError("PS probe reference or clock differs")
    partitions = check_directory(candidate)
    if partitions != manifest["boot_partitions"]:
        raise ValueError("PS probe partition map differs")
    verify_clock(partitions, manifest["ps_init_sha256"])
    check_mapping(candidate / "system.dtb", profile)
    if profile == "register":
        check_fit(candidate / "image.ub", candidate, candidate / "verify.log", dict(os.environ))
    else:
        check_runtime_fit(candidate)
    for name in manifest["programs"]:
        check_linux_elf((candidate / name).read_bytes())
    return manifest


def build(profile: str, base: Path, bitstream: Path, output: Path,
          runtime: Path | None = None, kernel: Path | None = None, timeout: int = 180) -> Path:
    """Create a fresh kit with cached tools; preserve base images, native candidates and SDK caches."""
    if profile not in PROFILES or (profile == "dma" and (runtime is None or kernel is None)) or (
            profile == "register" and (runtime is not None or kernel is not None)):
        raise ValueError("select register, or dma with both runtime and kernel")
    reference = verify_reference(profile, bitstream)
    sources = verify_rtl(profile, reference, bitstream.parent / "input-manifest.json")
    for name, expected in sources.items():
        if digest(ROOT / name) != expected:
            raise ValueError(f"current RTL differs from the retained image: {name}")
    board = validate_candidate(base)
    verify_clock(check_directory(base), board["ps_init_sha256"])
    if profile == "dma":
        candidate = build_dma(base, runtime, kernel, bitstream, timeout, output_root=output)
        manifest = json.loads((candidate / "manifest.json").read_text())
        for name in ("fsbl.elf", "probe.bit", "u-boot.elf", "boot.bif"):
            shutil.copyfile(output / "boot-inputs" / name, candidate / name)
        shutil.copyfile(output / "check_dma_device", candidate / "check_dma_device")
    else:
        candidate = output / "candidate"
        output.mkdir(parents=True, exist_ok=False)
        candidate.mkdir()
        manifest = dict(board)
        for name in board["files"]:
            if Path(name).name != name:
                raise ValueError("boot manifest file must be a basename")
            shutil.copyfile(base / name, candidate / name)
        shutil.copyfile(bitstream, candidate / "probe.bit")
        bootgen = next((ROOT / "build/boot/work/bootgen").glob("*/bootgen"))
        run([bootgen, "-arch", "zynq", "-image", "boot.bif", "-o", "BOOT.bin", "-w", "on"],
            candidate, output / "bootgen.log",
            dict(os.environ, SOURCE_DATE_EPOCH=str(board["source_date_epoch"])))
    shutil.copyfile(bitstream.parent / "input-manifest.json", candidate / "pl-sources.json")
    manifest.update({"profile": profile, "fclk0_hz": 100000000, "fsbl_programs_si5338": False,
                     "reference_sha256": digest(REFERENCE), "base_manifest_sha256": digest(base / "manifest.json"),
                     "ps_init_sha256": board["ps_init_sha256"], "boot_partitions": check_directory(candidate),
                     **PROFILES[profile], "part": reference["part"], "hardware_validated": False,
                     "pl_sources": sources,
                     "packaging_inputs": {str(p.relative_to(ROOT)): digest(p) for p in
                         [Path(__file__), ROOT / "boot/reference.py", ROOT / "check_zynq_boot.py"]}})
    manifest["files"] = {p.name: {"bytes": p.stat().st_size, "sha256": digest(p)} for p in candidate.iterdir()
                         if p.is_file() and p.name not in ("manifest.json", "verify.log")}
    (candidate / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    check_candidate(candidate)
    return candidate


def main() -> None:
    """Build from local inputs or recheck a complete retained kit, without accessing board devices."""
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    create = sub.add_parser("build")
    create.add_argument("profile", choices=PROFILES)
    for name in ("base", "bitstream", "output"):
        create.add_argument(name, type=Path)
    for name in ("runtime", "kernel"):
        create.add_argument("--" + name, type=Path)
    create.add_argument("--timeout", type=int, default=180)
    verify = sub.add_parser("check")
    verify.add_argument("candidate", type=Path)
    args = parser.parse_args()
    if args.command == "check":
        print(check_candidate(args.candidate.resolve())["profile"] + ": verified")
    else:
        print(build(args.profile, args.base.resolve(), args.bitstream.resolve(), args.output.resolve(),
                    args.runtime.resolve() if args.runtime else None,
                    args.kernel.resolve() if args.kernel else None, args.timeout))


if __name__ == "__main__":
    main()
