"""Extend a passing single-mailbox device tree with the routed debug bank."""

import shutil
import subprocess
from pathlib import Path

from prepare_te0715_boot import fdt


def check_pair_tree(tree: Path) -> None:
    """Require independent application/debug banks sharing the checked PS clock and DMA controller."""
    from prepare_ps_probe import check_mapping
    check_mapping(tree, "dma")
    application = "/amba_pl/dma-mailbox@40000000"
    debug = "/amba_pl/dma-mailbox@40004000"
    dma = fdt(tree, application, "dmas", "x").split()[0]
    gic = fdt(tree, application, "interrupt-parent", "x")
    clocks = fdt(tree, application, "clocks", "x")
    fields = [("/aliases", "hlsdma1", "s", debug),
              (application, "clock-names", "s", "s_axi_aclk"),
              (debug, "compatible", "s", "erl-hls,dma-mailbox-v1"),
              (debug, "reg", "x", "40004000 3000"),
              (debug, "interrupt-parent", "x", gic),
              (debug, "interrupts", "x", "0 1e 4"),
              (debug, "dmas", "x", f"{dma} 2 {dma} 3"),
              (debug, "dma-names", "s", "tx rx"),
              (debug, "clocks", "x", clocks),
              (debug, "clock-names", "s", "s_axi_aclk")]
    for node, name, kind, expected in fields:
        if fdt(tree, node, name, kind) != expected:
            raise ValueError(f"routed DMA mapping differs: {node}/{name}")


def add_debug_mailbox(source: Path, output: Path) -> None:
    """Add one independent debug mailbox without changing the application bank."""
    application = "/amba_pl/dma-mailbox@40000000"
    if fdt(source, application, "compatible") != "erl-hls,dma-mailbox-v1" or \
            fdt(source, "/aliases", "hlsdma0", "s") != application or \
            fdt(source, application, "reg", "x") != "40000000 3000":
        raise ValueError("expected the routed-frame DMA base device tree")
    dma = fdt(source, application, "dmas", "x").split()[0]
    gic = fdt(source, application, "interrupt-parent", "x")
    clock = fdt(source, application, "clocks", "x").split()
    shutil.copyfile(source, output)
    debug = "/amba_pl/dma-mailbox@40004000"
    subprocess.run(["fdtput", "-c", str(output), debug], check=True)
    fields = {
        "compatible": ("s", ["erl-hls,dma-mailbox-v1"]),
        "reg": ("x", ["40004000", "3000"]),
        "clocks": ("x", clock), "clock-names": ("s", ["s_axi_aclk"]),
        "interrupt-parent": ("x", [gic]), "interrupts": ("x", ["0", "1e", "4"]),
        "dmas": ("x", [dma, "2", dma, "3"]), "dma-names": ("s", ["tx", "rx"]),
    }
    for name, (kind, values) in fields.items():
        subprocess.run(["fdtput", "-t", kind, str(output), debug, name, *values], check=True)
    subprocess.run(["fdtput", "-t", "s", str(output), "/aliases", "hlsdma1", debug], check=True)
