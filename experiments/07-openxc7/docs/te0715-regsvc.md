# Routed application and debug over DMA

This TE0715-05-71C33-A / TEF1002-03-A candidate runs two translated register-service actors, addressed as endpoints 1 and 2. Application and debug each have a separate DMA device and packet buffers. A stalled application response therefore leaves its debug counters and trace accessible. Both paths share GP0, PL330 and a **25-MHz FCLK0**; they are independent queues, not independent fault domains. Board operation remains unverified.

```text
ARM BEAM
  hls_gs clients ── application broker ── /dev/hls-dma0 ── application router ── actors 1, 2
  hls_debug clients ── debug broker ───── /dev/hls-dma1 ── debug router ──────── monitors 1, 2
```

The existing `hls_fabric` brokers own the raw device handles and route responses to their clients. Neither the character driver nor the mailbox interprets actor operations. The FPGA routes each complete frame to its endpoint; response routing and transaction IDs use the ordinary runtime protocol. [The mailbox contract](te0715-dma.md#character-device-contract) applies to both devices, including partial reads, bounded packet slots and teardown.

| Path | Character device | GP0 window | PL330 TX/RX channels | GIC interrupt ID |
|---|---|---|---|---|
| Application | `/dev/hls-dma0` | `0x40000000`–`0x40002fff` | 0 / 1 | 61 |
| Debug | `/dev/hls-dma1` | `0x40004000`–`0x40006fff` | 2 / 3 | 62 |

Device-tree aliases `hlsdma0` and `hlsdma1` fix these identities, including when the driver probes or rebinds in reverse order. Each bank retains one 1028-byte packet per direction; a full 64-event trace fits in one 800-byte routed frame. AXI read and write transactions select their bank at address acceptance and retain it through the final response. Only one transaction per direction is outstanding.

## Build and simulate

First prepare the [boot](te0715-boot.md), [Linux/OTP](te0715-runtime.md), [kernel](te0715-dma.md#build) and [QEMU bridge](te0715-cosim.md#run) prerequisites. Rebuild the kernel/driver for this revision: the driver now requires the aliases installed by the image builder. From `experiments/07-openxc7`, using a native XLS binary directory containing `ir_converter_main`, `opt_main`, `codegen_main` and `xls/dslx/stdlib`:

```sh
python3 build_regsvc_rtl.py "$XLS_ROOT"
bash run_zynq_regsvc.sh build/routed-dma/rtl
python3 build_regsvc_fsbl.py
python3 prepare_te0715_dma.py build/boot/candidate build/runtime/candidate \
    build/dma-kernel/share/output build/zynq-regsvc/xc7z030sbg485-1.bit \
    --regsvc build/routed-dma
python3 run_qemu_cosim.py build/boot/candidate build/dma-kernel/share/output \
    --runtime build/routed-dma/candidate --regsvc build/routed-dma/rtl
```

The RTL builder compiles current Erlang/DSLX, runs the existing two-actor regression, and records source, output and compiler-binary hashes. The physical build requires four mailbox `RAMB18E1`s and six trace `RAMB36E1`s. The separate FSBL changes only FCLK0's second divider in all three silicon initialization tables: the checked 100-MHz configuration becomes 25 MHz before PL startup. The image builder verifies the matching RTL, bitstream, clock and driver manifests. It preserves the preceding boot/loopback candidates.

`build/routed-dma/candidate/` contains the SD files; `build/cosim/routed/` retains integration logs and input hashes. Co-simulation runs the **installed** BEAM modules and acceptance script from a disposable copy of this SD root against Icarus. It tests:

- separate register state and 260 concurrent call pairs, crossing transaction-ID reuse;
- debug queries while the application RX slot is deliberately held full, requiring nonzero application stall counters and zero observation drops;
- both actors' full traces, bounded overflow accounting, and empty second drains;
- confirmed raw-handle closure, reverse-order driver rebind, stable device names and preserved actor state.

The last check drains all replies before unbinding. It establishes quiescent transport teardown, not a device reset, work fence or recovery from an interrupted transaction.

CI adds a short paired-mailbox regression to the existing PS-probe suite: bank isolation, maximum AXI bursts, held responses, concurrent reads/writes, unmapped windows and reset. Full Linux/BEAM integration remains a local acceptance run; CI does not rebuild its kernel or XLS tools.

## Board acceptance

Qualify the register probe and DMA loopback first, then install the routed SD files as described in the runtime guide. Use the complete candidate, including its 25-MHz FSBL. With no other clients owning either device:

```sh
modprobe hls_dma_mailbox
ERL_LIBS=/opt/erl-hls/lib escript /opt/erl-hls/bin/check_regsvc_dma.escript
rmmod hls_dma_mailbox
```

The script deliberately fills application queues, drains both traces and unbinds/rebinds the driver. It finishes with both devices unbound; actor state is preserved. Save its output and the candidate manifest. `modprobe hls_dma_mailbox` after the final unload restores the devices for further quiescent use.

## Measured compile result

The complete design occupies **10,811 `SLICE_LUTX` slots, 4,918 flip-flops, four `RAMB18E1`s and six `RAMB36E1`s**, with no DSPs. The preceding single-mailbox loopback used 811 LUT slots, 166 flip-flops and two `RAMB18E1`s; the new total includes both actors, their routers and full debug instrumentation, so the difference is not merely DMA plumbing overhead. Trace width is now 192 bits, requiring three 36-Kib primitives per actor.

One deterministic placement reports **48.50 MHz** for the available timing paths; the candidate selects 25 MHz. The bitstream round trip recovers 531,434 non-ECC set bits. [The recorded result](../te0715-regsvc-result.json) binds these measurements to the sources and image. This is not timing qualification: the flow's BRAM/PS boundary coverage is incomplete, and co-simulation uses a synthetic schedule. Actual boot, GP0 behavior, interrupts, DMA errors and throughput remain hardware acceptance work.
