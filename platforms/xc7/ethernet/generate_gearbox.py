#!/usr/bin/env python3
"""Export LiteEth's 10/20-bit PCS gearbox with explicit related-clock resets."""

import argparse
from pathlib import Path

from migen import ClockDomain, Signal
from litex.gen import LiteXModule
from litex.build.xilinx import XilinxPlatform
from liteeth.phy.pcs_1000basex import PCSGearbox


class Gearbox(LiteXModule):
    """Bridge each 125-MHz symbol stream to its related 62.5-MHz word clock.

    Each clock pair must have a constrained 2:1 relationship, as from one MMCM.
    This is not an asynchronous FIFO. Reset both domains of a direction before
    use and after clock reacquisition; release only with stable related clocks.
    """

    def __init__(self) -> None:
        """Reuse the pinned upstream gearbox without changing its datapath."""
        for name in ("eth_tx", "eth_tx_half", "eth_rx", "eth_rx_half"):
            setattr(self.clock_domains, "cd_" + name, ClockDomain(name))
        self.gearbox = PCSGearbox()

    def ports(self) -> set[Signal]:
        """Name the raw words, symbols, clocks and synchronous domain resets."""
        ports = {name: getattr(self.gearbox, name)
                 for name in ("tx_data", "tx_data_half", "rx_data", "rx_data_half")}
        for name in ("eth_tx", "eth_tx_half", "eth_rx", "eth_rx_half"):
            domain = getattr(self, "cd_" + name)
            ports.update({name + "_clk": domain.clk, name + "_rst": domain.rst})
        for name, signal in ports.items():
            signal.name_override = name
        return set(ports.values())


def main() -> None:
    """Generate deterministic Verilog into the requested output directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    core = Gearbox()
    result = XilinxPlatform("xc7z030-sbg485-1", []).get_verilog(
        core, ios=core.ports(), name="liteeth_pcs_gearbox")
    body = result.main_source
    body = body[body.index("module "):body.rindex("endmodule") + len("endmodule")]
    (args.output / "liteeth_pcs_gearbox.v").write_text(
        "// Generated from pinned LiteEth PCSGearbox; see LICENSE.* and sources.lock.json.\n" + body + "\n")


if __name__ == "__main__":
    main()
