#!/usr/bin/env python3
"""Emit the pinned LiteEth 1000BASE-X PCS with explicit diagnostic taps."""

import argparse
import os
from pathlib import Path

from migen import ClockDomain, Signal
from litex.gen import LiteXModule
from litex.build.xilinx import XilinxPlatform
from liteeth.phy.pcs_1000basex import PCS


class PCSProbe(LiteXModule):
    """Run the production PCS while exposing each receive boundary."""

    def __init__(self) -> None:
        """Use production negotiation timers and discard packet traffic."""
        self.clock_domains.cd_eth_tx = ClockDomain("eth_tx")
        self.clock_domains.cd_eth_rx = ClockDomain("eth_rx")
        self.pcs = PCS(lsb_first=True)
        self.comb += [
            self.pcs.tbi_rx_ce.eq(1),
            self.pcs.sink.valid.eq(0),
            self.pcs.sink.data.eq(0),
            self.pcs.sink.last.eq(0),
            self.pcs.sink.last_be.eq(1),
            self.pcs.sink.error.eq(0),
            self.pcs.source.ready.eq(1),
            self.pcs.source.last_be.eq(1),
        ]

    def ports(self) -> set[Signal]:
        """Name the wire symbols, decoded events and negotiation state."""
        pins = {
            "tbi_tx": self.pcs.tbi_tx,
            "tbi_rx": self.pcs.tbi_rx,
            "link": self.pcs.link_up,
            "restart": self.pcs.restart,
            "align": self.pcs.align,
            "rx_data": self.pcs.rx.decoder.d,
            "rx_k": self.pcs.rx.decoder.k,
            "rx_invalid": self.pcs.rx.decoder.invalid,
            "rx_seen_ci": self.pcs.rx.seen_valid_ci,
            "rx_seen_config": self.pcs.rx.seen_config_reg,
            "rx_config": self.pcs.rx.config_reg,
            "lp_abi": self.pcs.lp_abi.i,
            "autoneg_ack": self.pcs.autoneg_ack,
            "config_empty": self.pcs.config_empty,
        }
        for domain in (self.cd_eth_tx, self.cd_eth_rx):
            pins[f"{domain.name}_clk"] = domain.clk
            pins[f"{domain.name}_rst"] = domain.rst
        for name, pin in pins.items():
            pin.name_override = name
        return set(pins.values())


def main() -> None:
    """Generate deterministic Verilog into an explicit directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    os.chdir(args.output)
    core = PCSProbe()
    platform = XilinxPlatform("xc7z030-sbg485-1", [], toolchain="vivado")
    result = platform.get_verilog(core, ios=core.ports(), name="liteeth_pcs_probe")
    body = result.main_source
    body = body[body.index("module "):body.rindex("endmodule") + len("endmodule")]
    result.main_source = ("// Generated from pinned LiteEth PCS; see LICENSE.* and sources.lock.json.\n"
                          + body + "\n")
    result.write("liteeth_pcs_probe.v")


if __name__ == "__main__":
    main()
