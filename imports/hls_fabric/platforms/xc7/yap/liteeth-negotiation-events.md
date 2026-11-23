# PCS negotiation event reproduction

The pinned LiteEth source, also present at upstream `96547670d9d4776b81edba0c8a82e5f10ed8a1e3`, sets `rx_config_reg_abi.i` and `rx_config_reg_ack.i` in the RX synchronous block but only clears them on reset. `PulseSynchronizer` toggles its source bit on every asserted input cycle, so these latched values continue manufacturing events after configuration reception stops.

An established ideal TBI loopback followed by continuously invalid input reproduces the problem: link-up falls at a checker deadline, then rises again using the old negotiation events. The earlier regression waited for the first down edge and restored the connection shortly afterwards. The packet DMA fixture polls status while holding a committed RX packet; that longer outage exposed the repeated false link-up.

`ethernet.prepare.fix_config_pulses` inserts default zero assignments before the two conditional event assertions in a fresh extraction of the hash-pinned source. `packet_tb.sv` now checks 10,000 additional RX clock cycles without any link-up during invalid input, before permitting fresh negotiation. The packet-DMA fixture additionally retains and reads committed data during that outage. These tests use the public packet, link and AXI boundaries; the isolated source investigation also inspected the PCS checker to identify the stale events.

An upstream proposal can be just the two default assignments plus a focused PCS-only sustained-outage regression. No issue or PR has been submitted. This is a digital reproduction, not a claim about analog loss-of-signal behavior or board qualification.
