# 1000BASE-X packet endpoint

This bring-up fixture sends and receives complete Ethernet frames through a MAC and 1000BASE-X PCS. It checks the digital packet path before connecting it to the [GTX lane](gtx.md), [carrier SFP](sfp-management.md) or [DMA mailbox](te0715-dma.md). It produces simulated and synthesized RTL, **not a board image**.

## Frame service

Streams transfer a byte when `valid && ready`; `last` marks its final byte. TX accepts an Ethernet header and payload, from 14 through 1514 bytes, excluding preamble and FCS. The MAC pads short frames to 60 bytes and adds preamble, FCS and an inter-frame gap. RX returns 60–1514 bytes, including padding and excluding preamble/FCS. Padding cannot generally be distinguished from payload without interpreting a higher-layer length.

Each direction has two complete-frame slots. TX can pause while constructing a frame; transmission begins only after its last byte commits the frame. RX never backpressures the wire. If no slot is free at a frame's first byte, that entire frame is discarded, even if a slot becomes free before its end. Errors and invalid lengths also discard the entire frame. A consumer may stall between any output bytes; data and `last` remain stable until accepted.

This is a bounded, lossy Ethernet service. Successful TX admission is neither confirmation of wire transmission nor acknowledgement by a peer. It provides no retransmission, PAUSE flow control, MAC-address filtering, VLAN/jumbo-frame service or IP stack. The tested link mode is full-duplex 1000BASE-X.

## Clocks and link lifetime

TX streams and diagnostics belong to the local 125-MHz `eth_tx_clk`. RX belongs to `eth_rx_clk`, recovered from the peer. The TBI carries one ten-bit 8b/10b symbol per clock, bit zero first. These parallel buses must not cross unrelated clocks. A host-clock adapter will need CDC and must preserve complete-frame admission on the wire side of that crossing.

`link_tx` reports PCS negotiation in the TX domain; `link_rx` is its synchronized RX-domain copy. Link loss flushes queued/unfinished TX work and resets the MAC pipelines. The producer must abandon its current input frame when `link_tx` falls and start a new frame after negotiation succeeds. RX discards unfinished work while preserving committed frames, including an output already stalled at the consumer. Reset both domains to discard all state and clear diagnostics.

The fixture detects sustained absence of configuration/idle activity through the PCS's normal timers. Hardware integration must additionally bring transceiver lock/reset/clock-loss signals into the link lifetime. A stopped recovered clock cannot execute a synchronous RX reset by itself.

## Diagnostics

Counters are ports in their direction's clock domain, wrap modulo 2³², survive link loss and clear on external reset. They require a coherent snapshot before host-clock readout.

| Port suffix | Meaning |
| --- | --- |
| `queued` | Committed frame slots still owned, 0–2; excludes partial input |
| `accepted` | Frames committed to storage |
| `dropped` | Input frames discarded at their final byte because of error, length or capacity |
| `overflowed` | Subset of `dropped` rejected because both slots were occupied at admission |
| `aborted` | Partial reservations discarded by abort, plus queued slots discarded by TX flush |

The suffixes have `tx_`/`rx_` prefixes. `crc_errors` and `preamble_errors` report MAC checker events in the RX domain. A preamble failure can occur before any bytes reach frame storage, so it need not increment `rx_dropped`. A frame already handed fully to the MAC can be interrupted on the wire without appearing in `tx_aborted`; these counters describe their boundaries, not end-to-end delivery.

## Reproduce the checks

Use Python 3.12+, Icarus and Yosys. From the repository root:

```sh
python3 experiments/07-openxc7/test_ethernet.py --yosys /path/to/yosys
```

The command downloads about 4.3 MB of hash-pinned sources/models into `build/ethernet/sources/`; subsequent runs use that cache. It installs no Python packages. The existing PS-probe CI entry point includes these checks when run with `--yosys`.

Alongside 19 upstream PCS tests, the regression checks short/minimum/odd/maximum frames, rejected lengths, gapped TX input, stalled RX output, full-slot drops, FCS/preamble errors and link loss during traffic. The peers' TX clocks differ by 100 ppm; each receiver uses its peer's clock. An independent 8b/10b model checks emitted running disparity, preamble, padding, Python `zlib` FCS and inter-frame gap, and injects good/bad wire frames. A separate store test exercises simultaneous release/commit, release during a rejected frame, sticky errors, a 5000-byte overflow, abort and flush.

Packet scenarios run before and after XC7 mapping; the latter uses AMD's functional BRAM model. Synthesis rejects undriven nets and combinational loops and requires exactly two `RAMB36E1`s with production negotiation timers. Simulation accelerates only negotiation timers; its activity-check interval still exceeds a maximum-length frame. Artifacts and provenance are retained under `build/ethernet/candidate/`; the compact [native result](../ethernet-result.json) records resources and hashes.

The MAC/PCS is generated from pinned [LiteEth](../ethernet/sources.lock.json) components, with licenses retained alongside the generator. Before pre-mapping Icarus simulation, Yosys lowers processes and simplifies expressions to avoid an event-scheduling loop in the generated FSM blocks; this does not map FPGA primitives.

## Hardware follow-through

The 20-bit/62.5-MHz GTX gearbox, clock/reset constraints, receiver synchronization, analog behavior and external cable remain unqualified. This test does not demonstrate 125-MHz timing closure. Connecting DMA requires clock crossings and coherent diagnostics; connecting the SFP requires the board's RX/TX polarity corrections. A programmable image also still requires the missing Zynq GTX configuration database entries described in the GTX probe. These are separate from the packet regression's digital guarantees.
