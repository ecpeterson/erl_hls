"""Tie the routed payload, physical build and 25-MHz boot configuration together."""

import json
from pathlib import Path

from build_regsvc_rtl import PROJECT, ROOT, sources
from prepare_te0715_boot import digest

PART = "xc7z030sbg485-1"
FCLK0_HZ = 25_000_000


def physical_manifest(rtl: Path, stage: Path) -> None:
    """Record a successful physical build only after checking its clock constraint."""
    sources(rtl)
    report = json.loads((stage / f"{PART}-report.json").read_text())
    clocks = report["fmax"]
    if not clocks or any(c["constraint"] != FCLK0_HZ / 1e6 or c["achieved"] < c["constraint"]
                         for c in clocks.values()):
        raise ValueError("routed design must meet the 25-MHz target in the available timing model")
    inputs = [ROOT / name for name in (
        "run_zynq_regsvc.sh", "openxc7_common.sh", "zynq_ps_probe.v", "zynq_ps_probe.xdc",
        "dma/zynq_dma_mailbox.v", "dma/zynq_dma_pair.v", "dma/zynq_regsvc_core.sv",
        "dma/zynq_dma_top.v", "dma/routed_image.py")]
    manifest = {"hardware_validated": False, "fclk0_hz": FCLK0_HZ,
                "rtl_manifest_sha256": digest(rtl / "manifest.json"),
                "inputs": {str(p.relative_to(PROJECT)): digest(p) for p in inputs},
                "files": {name: digest(stage / name) for name in
                          (f"{PART}.bit", f"{PART}-report.json", "stats.json", "netlist.json")}}
    (stage / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


def routed_inputs(regsvc: Path, bitstream: Path) -> tuple[Path, dict]:
    """Reject stale/mismatched RTL, bitstream or FSBL before constructing a boot image."""
    sources(regsvc / "rtl")
    fsbl = regsvc / "fsbl"
    boot = json.loads((fsbl / "manifest.json").read_text())
    physical = json.loads((bitstream.parent / "manifest.json").read_text())
    if boot["fclk0_hz"] != FCLK0_HZ or physical["fclk0_hz"] != FCLK0_HZ:
        raise ValueError("FSBL and physical design must both select 25 MHz")
    if digest(fsbl / "fsbl.elf") != boot["fsbl_sha256"]:
        raise ValueError("FSBL differs from its checked build")
    if physical["rtl_manifest_sha256"] != digest(regsvc / "rtl/manifest.json"):
        raise ValueError("physical design does not derive from this RTL")
    if bitstream.name != f"{PART}.bit":
        raise ValueError("unexpected routed bitstream name")
    for root, inputs in ((ROOT, boot["inputs"]), (PROJECT, physical["inputs"]),
                         (bitstream.parent, physical["files"])):
        for name, expected in inputs.items():
            if digest(root / name) != expected:
                raise ValueError(f"routed build input/output changed: {name}")
    return fsbl / "fsbl.elf", {"fclk0_hz": FCLK0_HZ,
                                "fsbl_manifest_sha256": digest(fsbl / "manifest.json"),
                                "physical_manifest_sha256": digest(bitstream.parent / "manifest.json"),
                                "rtl_manifest_sha256": digest(regsvc / "rtl/manifest.json")}
