#!/usr/bin/env python3
"""Emit pinned LiteEth MAC/PCS stages with byte streams in their wire clock domains."""

import argparse
import os
from pathlib import Path

from migen import ClockDomain, ClockDomainsRenamer, Signal
from migen.genlib.cdc import MultiReg
from litex.gen import LiteXModule
from litex.build.xilinx import XilinxPlatform
from litex.soc.interconnect import stream
from litex.soc.interconnect.stream import BufferizeEndpoints, DIR_SINK
from liteeth.common import eth_phy_description
from liteeth.mac import crc, gap, padding, preamble
from liteeth.phy.pcs_1000basex import PCS


class PacketCore(LiteXModule):
    """Format Ethernet frames and negotiate a full-duplex 1000BASE-X symbol link.

    TX must supply continuous bytes within a committed frame. RX must always
    accept bytes; error is provisional until last. The external frame stores
    enforce these requirements. All exported streams use their direction's
    125-MHz clock, without a system-clock crossing.
    """

    def __init__(self, simulation: bool) -> None:
        """Select accelerated negotiation timers only for the regression core."""
        self.clock_domains.cd_eth_tx = ClockDomain("eth_tx")
        self.clock_domains.cd_eth_rx = ClockDomain("eth_rx")
        self.clock_domains.cd_mac_tx = ClockDomain("mac_tx")
        self.clock_domains.cd_mac_rx = ClockDomain("mac_rx")
        timers = dict(check_period=4096/125e6, breaklink_time=1/125e6,
                      more_ack_time=1/125e6, sgmii_ack_time=1/125e6) if simulation else {}
        self.pcs = PCS(lsb_first=True, **timers)
        self.link_tx = Signal()
        # Terminate negotiation's combinational status path before it drives
        # MAC resets and frame-store admission across the TX datapath.
        self.sync.eth_tx += self.link_tx.eq(self.pcs.link_up)
        self.link_rx = Signal()
        self.specials += MultiReg(self.link_tx, self.link_rx, "eth_rx")
        self.comb += [
            self.pcs.tbi_rx_ce.eq(1),
            # The PCS carries bytes but leaves last_be undriven. The pinned
            # MAC checker needs an explicit enabled byte to evaluate its FCS.
            self.pcs.source.last_be.eq(1),
            self.cd_mac_tx.clk.eq(self.cd_eth_tx.clk),
            self.cd_mac_rx.clk.eq(self.cd_eth_rx.clk),
            self.cd_mac_tx.rst.eq(self.cd_eth_tx.rst | ~self.link_tx),
            self.cd_mac_rx.rst.eq(self.cd_eth_rx.rst | ~self.link_rx),
        ]
        self.tx = stream.Endpoint(eth_phy_description(8))
        self.rx = stream.Endpoint(eth_phy_description(8))
        self.comb += [self.tx.error.eq(0), self.tx.last_be.eq(1), self.rx.ready.eq(1)]

        # Match LiteEthMACCore's byte-wide formatting pipeline, but leave CDC to
        # the future board integration: frame admission belongs after that CDC.
        self.tx_padding = ClockDomainsRenamer("mac_tx")(padding.LiteEthMACPaddingInserter(8, 60))
        self.tx_crc = ClockDomainsRenamer("mac_tx")(
            BufferizeEndpoints({"sink": DIR_SINK})(crc.LiteEthMACCRC32Inserter(eth_phy_description(8))))
        self.tx_preamble = ClockDomainsRenamer("mac_tx")(preamble.LiteEthMACPreambleInserter(8))
        self.tx_gap = ClockDomainsRenamer("mac_tx")(gap.LiteEthMACGap(8))
        self.tx_pipeline = stream.Pipeline(self.tx, self.tx_padding, self.tx_crc,
                                          self.tx_preamble, self.tx_gap, self.pcs.sink)
        self.rx_preamble = ClockDomainsRenamer("mac_rx")(preamble.LiteEthMACPreambleChecker(8))
        self.rx_crc = ClockDomainsRenamer("mac_rx")(
            BufferizeEndpoints({"sink": DIR_SINK})(crc.LiteEthMACCRC32Checker(eth_phy_description(8))))
        self.rx_pipeline = stream.Pipeline(self.pcs.source, self.rx_preamble, self.rx_crc, self.rx)
        self.preamble_errors = Signal(32)
        self.crc_errors = Signal(32)
        self.sync.eth_rx += [
            # Counters survive link loss; only the external reset clears them.
            self.preamble_errors.eq(self.preamble_errors + (self.rx_preamble.error & self.link_rx)),
            self.crc_errors.eq(self.crc_errors + (self.rx_crc.error & self.link_rx)),
        ]

    def ports(self) -> set[Signal]:
        """Return a stable, named HDL boundary without unused stream metadata."""
        pins = dict(tbi_tx=self.pcs.tbi_tx, tbi_rx=self.pcs.tbi_rx,
                    link_tx=self.link_tx, link_rx=self.link_rx,
                    restart=self.pcs.restart, align=self.pcs.align,
                    preamble_errors=self.preamble_errors, crc_errors=self.crc_errors)
        for name, endpoint in (("tx", self.tx), ("rx", self.rx)):
            for field in ("valid", "data", "last"):
                pins[f"{name}_{field}"] = getattr(endpoint, field)
        pins.update(tx_ready=self.tx.ready, rx_error=self.rx.error)
        for domain in (self.cd_eth_tx, self.cd_eth_rx):
            pins[f"{domain.name}_clk"] = domain.clk
            pins[f"{domain.name}_rst"] = domain.rst
        for name, pin in pins.items():
            pin.name_override = name
        return set(pins.values())


def main() -> None:
    """Write RTL and decoder memory initialization into an explicit build directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--simulation", action="store_true")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    os.chdir(args.output)
    core = PacketCore(args.simulation)
    # The default ISE attribute map drops async_reg. Preserve synchronizer
    # placement metadata even when only exporting Verilog for native tools.
    platform = XilinxPlatform("xc7z030-sbg485-1", [], toolchain="vivado")
    result = platform.get_verilog(core, ios=core.ports(), name="liteeth_packet_core")
    # The default header embeds wall time and the calling repository's revision,
    # which is not the pinned LiteX revision. Keep provenance in the build report.
    body = result.main_source
    body = body[body.index("module "):body.rindex("endmodule") + len("endmodule")]
    result.main_source = ("// Generated from LiteEth, LiteX and Migen; see ethernet/LICENSE.* and sources.lock.json.\n"
                          + body + "\n")
    result.write("liteeth_packet_core.v")


if __name__ == "__main__":
    main()
