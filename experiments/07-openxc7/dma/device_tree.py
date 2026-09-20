"""Bind the checked TE0715 GP0 aperture to the packet mailbox and PS PL330."""

import shutil
import subprocess
from pathlib import Path

from prepare_te0715_boot import fdt


def mailbox_tree(source: Path, output: Path) -> None:
    """Replace only the probe node; resolve provider handles from this exact base DT."""
    if fdt(source, "/amba_pl/probe@40000000", "compatible") != "generic-uio":
        raise ValueError("expected the register-probe base device tree")
    dma = fdt(source, "/axi/dma-controller@f8003000", "phandle", "x")
    gic = fdt(source, "/axi/interrupt-controller@f8f01000", "phandle", "x")
    clock = fdt(source, "/amba_pl/probe@40000000", "clocks", "x").split()
    shutil.copyfile(source, output)
    subprocess.run(["fdtput", "-r", str(output), "/amba_pl/probe@40000000"], check=True)
    node = "/amba_pl/dma-mailbox@40000000"
    subprocess.run(["fdtput", "-c", str(output), node], check=True)
    fields = {
        "compatible": ("s", ["erl-hls,dma-mailbox-v1"]),
        "reg": ("x", ["40000000", "3000"]),
        "clocks": ("x", clock), "clock-names": ("s", ["s_axi_aclk"]),
        "interrupt-parent": ("x", [gic]), "interrupts": ("x", ["0", "1d", "4"]),
        "dmas": ("x", [dma, "0", dma, "1"]), "dma-names": ("s", ["tx", "rx"]),
    }
    for name, (kind, values) in fields.items():
        subprocess.run(["fdtput", "-t", kind, str(output), node, name, *values], check=True)
