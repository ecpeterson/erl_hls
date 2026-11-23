# Packet DMA test fixture

This optional bring-up fixture lets Linux send arbitrary Ethernet frames through the [packet endpoint](ethernet-packets.md). It tests the host and link interfaces together; **it is not the intended application wiring**. An erl_hls application can connect DMA and Ethernet to separate application interfaces and place clock crossings where those interfaces require them.

```text
Linux frame I/O → PL330 → AXI mailbox → packet CDC → MAC/PCS
Linux frame I/O ← PL330 ← AXI mailbox ← packet CDC ← MAC/PCS
                                                       ↕
                                      ideal TBI loopback or physical GTX
```

The co-simulation runs ARM Linux and its PL330 controller in QEMU, with the actual mailbox, packet bridge and PCS/MAC RTL in Icarus. Host clock stepping advances a separate 125-MHz packet clock; this functional schedule does not model throughput. Standalone CDC tests additionally use unrelated TX/RX clocks, including frequency drift and stopped clocks. No hard GTX or programmable board image is involved.

## Frame I/O

The diagnostic driver profile accepts one Ethernet frame per `write`, 14–1514 bytes before FCS. `read` returns received frames, 60–1514 bytes including MAC padding and excluding FCS. Partial reads retain the remainder for that reader. Closing a reader discards its unread remainder. Polling, exclusive reader/writer ownership, failed-transfer handling and unbind follow the [DMA mailbox contract](te0715-dma.md).

A successful write means publication to the mailbox, not network delivery. Ethernet remains lossy: no retries, delivery acknowledgement or network stack are added. This profile requires device-tree compatible `erl-hls,ethernet-diagnostic-v1`, identity `0x484c454d` (`HLEM`) and ABI 1. The routed-frame profile retains its separate identity and format.

Inside the fixture, a word-aligned envelope holds the exact byte length followed by padded data words. The driver adds/removes this envelope; user buffers contain only Ethernet bytes. A 1,514-byte frame needs 1,520 mailbox bytes. The mailbox's register protocol is unchanged, with its word capacity selected by the fixture.

## Clocks and recovery

Each direction adds one whole-packet CDC slot. A writer publishes only a complete frame and cannot reuse its memory until the reader releases it. The TX cursor expands words into bytes; RX collects bytes before publishing a length. Backpressure may stop either consumer indefinitely without changing its visible beat.

While the host is ready, RX prefetches word zero with the length header and requests each following word as its predecessor transfers. The resulting stream sustains one 32-bit word per host clock. A fetch bubble between words makes the application-side drain slower than the private transmit envelope and can overflow a bounded upstream packet store during a sustained burst. The standalone regression requires consecutive header/data transfers; the full two-role PCS/MAC simulation is a bounded integration witness rather than a throughput proof.

Link recovery does not reset the host mailbox or interrupt an AXI transaction. A pending TX slot restarts at byte zero if its copy into the endpoint is interrupted. A frame already accepted by the endpoint can still be lost. An incomplete RX copy is discarded on its directional reset; a completed RX slot remains readable even with the RX clock stopped. Shared device reset discards all ownership and requires quiescent host users. Each direction synchronizes reset release to its own clock before accepting transfers.

The two CDC memories map to two `RAMB18E1` blocks. This is an isolated fixture cost, not an erl_hls application overhead. Physical qualification still needs synchronizer placement and a settling constraint for each held length bus. Matching clock frequencies alone does not establish synchrony; a recovered RX clock remains a separate domain unless the integration establishes otherwise.

## Physical peer fixture

`te0715_ethernet_dma_top` joins the same mailbox and CDC bridge to the hardware-passing external 1000BASE-X endpoint. It is a pipe-fit diagnostic for the intended BEAM → application PL → Ethernet → application PL → BEAM path: it deliberately omits both application PL blocks and does not claim that direct BEAM-to-BEAM Ethernet is a production interface. The design starts the physical link automatically; the device-tree compatible `erl-hls,ethernet-diagnostic-v1` binds the matching driver as `/dev/hls-dma0` during boot. No UIO node is expected.

The SD kit uses the retained DMA kernel/module, the 25-MHz clock-programming FSBL and the saved ED25519 maintenance key. Install its FAT bundle on partition 1 and decompress `ethernet-dma-peer-rootfs.ext4.gz` directly onto partition 2. The already-enabled OpenRC `local` service starts key-only Dropbear from `/etc/local.d/dropbear.start`; its generated host key remains in `/etc/dropbear` on that card's ext4 root. On the boards, configure PS Ethernet independently of the PL link:

```sh
# board A
ifconfig eth0 192.168.77.31 netmask 255.255.255.0 up
# board B
ifconfig eth0 192.168.77.32 netmask 255.255.255.0 up
```

Launch the follower first. `-nT` prevents the local shell job-control race seen with background SSH reads:

```sh
ssh -nT -o BatchMode=yes -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 \
  root@192.168.77.32 '/opt/erl-hls/bin/check_dma_peer /dev/hls-dma0 --follow' \
  > /tmp/dma-peer-b.log 2>&1 &
follow_pid=$!
sleep 1
ssh -nT -o BatchMode=yes -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 \
  root@192.168.77.31 '/opt/erl-hls/bin/check_dma_peer /dev/hls-dma0 --lead' \
  > /tmp/dma-peer-a.log 2>&1
lead_rc=$?
wait "$follow_pid"; follow_rc=$?
cat /tmp/dma-peer-a.log /tmp/dma-peer-b.log
printf 'lead=%s follow=%s\n' "$lead_rc" "$follow_rc"
```

The bounded run exchanges fourteen sizes from 14 through 1,514 bytes in both physical directions, including MAC padding boundaries, final partial words and partial userspace reads. Require both exit statuses to be zero and both logs to end with `PASS: reciprocal PS-PL-DMA-CDC-Ethernet frames, boundaries, padding and partial reads`. This is a two-board integration witness for one run, not throughput, sustained-link, BER, timing or application-event qualification.

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

The disposable guest checks fourteen frame lengths, final partial words, partial reads, invalid lengths, retained RX through link loss and fresh traffic after renegotiation. `check_dma_packets --cosim` uses explicitly emulated fault controls; that option is not a board interface. UART/RTL logs and provenance remain in `build/cosim/ethernet/`. Neither this run nor the portable tests establish physical DMA coherency, interrupt delivery, transceiver operation or timing closure. The board-only elastic endpoint also runs the complete packet regression before physical packaging.

The [recorded native result](../../../docs/hls_fabric/artifacts.md#historical-reports) (`experiments/07-openxc7/results/packet-dma-2026-09-21.json`) includes both the packet fixture and the original routed-frame Linux regression. The isolated CDC bridge uses 367 LUT primitives, 144 flip-flops and two RAMB18s; this excludes the mailbox and MAC/PCS. The physical peer candidate retained a legal route and two identical native assemblies, but its incomplete timing model missed the modeled 125-MHz TX/RX targets. Both boards nevertheless completed one reciprocal fourteen-frame run. That bounded witness does not qualify timing or sustained operation.
