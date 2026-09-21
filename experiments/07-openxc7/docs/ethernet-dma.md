# Packet DMA test fixture

This optional bring-up fixture lets Linux send arbitrary Ethernet frames through the [packet endpoint](ethernet-packets.md). It tests the host and link interfaces together; **it is not the intended application wiring**. An erl_hls application can connect DMA and Ethernet to separate application interfaces and place clock crossings where those interfaces require them.

```text
Linux frame I/O → PL330 → AXI mailbox → packet CDC → MAC/PCS
Linux frame I/O ← PL330 ← AXI mailbox ← packet CDC ← MAC/PCS
                                                       ↕
                                               ideal TBI loopback
```

The co-simulation runs ARM Linux and its PL330 controller in QEMU, with the actual mailbox, packet bridge and PCS/MAC RTL in Icarus. Host clock stepping advances a separate 125-MHz packet clock; this functional schedule does not model throughput. Standalone CDC tests additionally use unrelated TX/RX clocks, including frequency drift and stopped clocks. No hard GTX or programmable board image is involved.

## Frame I/O

The diagnostic driver profile accepts one Ethernet frame per `write`, 14–1514 bytes before FCS. `read` returns received frames, 60–1514 bytes including MAC padding and excluding FCS. Partial reads retain the remainder for that reader. Closing a reader discards its unread remainder. Polling, exclusive reader/writer ownership, failed-transfer handling and unbind follow the [DMA mailbox contract](te0715-dma.md).

A successful write means publication to the mailbox, not network delivery. Ethernet remains lossy: no retries, delivery acknowledgement or network stack are added. This profile requires device-tree compatible `erl-hls,ethernet-diagnostic-v1`, identity `0x484c454d` (`HLEM`) and ABI 1. The routed-frame profile retains its separate identity and format.

Inside the fixture, a word-aligned envelope holds the exact byte length followed by padded data words. The driver adds/removes this envelope; user buffers contain only Ethernet bytes. A 1,514-byte frame needs 1,520 mailbox bytes. The mailbox's register protocol is unchanged, with its word capacity selected by the fixture.

## Clocks and recovery

Each direction adds one whole-packet CDC slot. A writer publishes only a complete frame and cannot reuse its memory until the reader releases it. The TX cursor expands words into bytes; RX collects bytes before publishing a length. Backpressure may stop either consumer indefinitely without changing its visible beat.

Link recovery does not reset the host mailbox or interrupt an AXI transaction. A pending TX slot restarts at byte zero if its copy into the endpoint is interrupted. A frame already accepted by the endpoint can still be lost. An incomplete RX copy is discarded on its directional reset; a completed RX slot remains readable even with the RX clock stopped. Shared device reset discards all ownership and requires quiescent host users. Each direction synchronizes reset release to its own clock before accepting transfers.

The two CDC memories map to two `RAMB18E1` blocks. This is an isolated fixture cost, not an erl_hls application overhead. Physical qualification still needs synchronizer placement and a settling constraint for each held length bus. Matching clock frequencies alone does not establish synchrony; a recovered RX clock remains a separate domain unless the integration establishes otherwise.

## Run the checks

From the experiment directory, using Python 3.12+, Icarus and Yosys:

```sh
python3 test_ethernet_dma.py --yosys /path/to/yosys
```

CI runs this through the PS-probe entry point. It checks raw/mapped CDC behavior and BRAM retention, then drives public AXI transactions through the real PCS/MAC, including retained receive data during link loss. The recorded result lives in `build/ethernet-dma/result.json`.

For full ARM Linux/PL330 coverage, reuse the prepared [boot/kernel and co-simulation tools](te0715-cosim.md):

```sh
python3 build_te0715_kernel.py build/boot/candidate
python3 run_qemu_cosim.py build/boot/candidate build/dma-kernel/share/output \
  --ethernet --yosys /path/to/yosys
```

The disposable guest checks fourteen frame lengths, final partial words, partial reads, invalid lengths, retained RX through link loss and fresh traffic after renegotiation. `check_dma_packets --cosim` uses explicitly emulated fault controls; that option is not a board interface. UART/RTL logs and provenance remain in `build/cosim/ethernet/`. Neither this run nor the portable tests establish physical DMA coherency, interrupt delivery, transceiver operation or timing closure.

The [recorded native result](../results/packet-dma-2026-09-21.json) includes both the packet fixture and the original routed-frame Linux regression. The isolated CDC bridge uses 367 LUT primitives, 144 flip-flops and two RAMB18s; this excludes the mailbox and MAC/PCS. No placed-and-routed measurement is claimed for this fixture.
