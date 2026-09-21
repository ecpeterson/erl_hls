# TE0715 DMA loopback

This SD candidate connects Linux/BEAM to a 32-bit PL stream on **TE0715-05-71C33-A / TEF1002-03-A**. The stream loops back inside the FPGA. It uses Zynq's built-in PL330 controller and Linux DMAengine; no Vivado DMA IP, custom DMAengine provider or HP port is required. Physical board operation remains unverified.

For first-board tests, use the [matched vendor DMA kit](ps-sd.md). The native build below remains available for toolchain comparison; both use this driver and packet contract.

```text
write(frame) → coherent DDR → PL330 / GP0 → TX packet RAM
                                               ↓ stream loopback
read(bytes) ← coherent DDR ← PL330 / GP0 ← RX packet RAM
```

Each direction has one 1028-byte packet slot, physically one 18-Kib BRAM. Software publishes TX only after its DMA copy completes. RX becomes readable only after TLAST and remains immutable until software releases it after copying. A full RX slot backpressures the stream and can hold the next TX frame. Packet bytes and ordering are preserved; the loopback does not swap routing addresses or interpret application tags.

This is a bounded bring-up transport. Copies between userspace and coherent DDR remain, and per-frame DMA setup, interrupts and syscalls may dominate short packets. GP0 is shared with CPU register access. Measure the board before choosing deeper queues or a PL DMA master on an HP port. No throughput claim follows from the synthesis clock estimate.

## Build

Start with the [boot candidate](te0715-boot.md) and [Linux/OTP image](te0715-runtime.md). Retain the boot build's native Bootgen and static-musl compiler cache. Install `qemu-system-aarch64` as well as the existing native tools. From `experiments/07-openxc7`:

```sh
bash run_zynq_dma.sh
python3 build_te0715_kernel.py build/boot/candidate
python3 test_te0715_dma_qemu.py build/boot/candidate build/dma-kernel/share/output
python3 prepare_te0715_dma.py build/boot/candidate build/runtime/candidate \
    build/dma-kernel/share/output build/zynq-dma/xc7z030sbg485-1.bit
```

The kernel builder uses a networkless ARM64 QEMU guest accelerated by Apple's hypervisor, four CPUs and 4 GiB RAM. Its sparse 6-GiB virtual disk retains kernel objects for incremental module builds. Only an experiment-local cache directory is shared. The tested cache occupies about 2.5 GiB; a cold kernel build took about 4½ minutes and a warm rebuild about 13 seconds inside the guest. No UTM VM, x86 host, root privileges or host disk mounting is needed. This builder entry point currently targets Apple Silicon.

Downloads are SHA-256 pinned in [builder.lock.json](../dma/builder.lock.json); APK also checks their signatures. The kernel uses AMD's `a19da02c` 2023.2 source, the preceding kernel's embedded configuration and the release suffix `-erlhls-dma`. The image carries its newly built matching modules and symbol versions; it does not mix them with the vendor kernel. Source/configuration, driver inputs and output hashes are recorded in manifests. Keep downloads and `build/dma-kernel/` for offline/incremental rebuilds; generated images are not bytewise reproducible.

`build/dma/candidate/` contains `BOOT.bin`, `boot.scr`, `image.ub`, `rootfs.ext4.gz` and a manifest. Install the first three on FAT SD partition 1 and the decompressed root filesystem on partition 2, as in the runtime guide. Assembly updates a copy of the previous runtime image; it never formats a host device. The FSBL, board PS initialization and U-Boot are retained. The PL, device tree, kernel and driver change together.

## Board checks

Use this loopback image, with no application owning the device. The module normally autoloads through the device tree; explicit loading is harmless:

```sh
modprobe hls_dma_mailbox
cat /sys/bus/platform/devices/40000000.dma-mailbox/status
/opt/erl-hls/bin/check_dma_device /dev/hls-dma0
ERL_LIBS=/opt/erl-hls/lib escript /opt/erl-hls/bin/check_dma_beam.escript /dev/hls-dma0
```

Both diagnostics check all 256 payload lengths (0–255 words). The C check also exercises partial reads, malformed-write rejection, exclusive direction ownership, empty/full nonblocking I/O, ordered draining under backpressure and wakeup of a blocked read. The BEAM check uses separate raw-file handles and the current `hls_fabric_io:encode/3` format. Save the UART output and candidate manifest.

After successful loopback, explicitly test removal with a blocked reader:

```sh
/opt/erl-hls/bin/check_dma_device /dev/hls-dma0 --unbind
echo 40000000.dma-mailbox > /sys/bus/platform/drivers/hls-dma-mailbox/bind
```

The reader must wake with `ENODEV`; the command leaves the driver unbound until the second line. The read-only `status` file reports TX busy, RX full/incomplete, hardware/software fault, RX length, interrupt events and interrupt mask without consuming data. Its fields are observations across several register reads, not an atomic snapshot. Kernel faults appear in `dmesg`.

## Character-device contract

`/dev/hls-dma0` accepts one reader and one writer, or a single combined open. Extra owners receive `EBUSY`. Writes must contain one complete current routed frame: an eight-byte header, followed by exactly `4 * header[4]` payload bytes, at most 1028 bytes total. Bad size returns `EMSGSIZE`; inconsistent header length returns `EPROTO`. A successful write means the complete frame was published to TX, not that the stream has consumed it.

Reads return bytes from one complete received frame, retaining any remainder for subsequent reads. Closing its reader discards a partially read remainder; it does not cancel the writer or clear a complete packet still in hardware. Session identity and late replies remain the runtime's responsibility. `poll` reports frame/slot availability. `O_NONBLOCK` returns `EAGAIN` for an empty RX/full TX slot; an admitted DMA copy still completes synchronously, with a five-second timeout.

A malformed incoming frame, DMA error or interrupted DMA freezes further I/O with `EIO`. Unbinding wakes blocked operations, joins in-flight copies before freeing buffers and leaves existing file descriptors inert. Rebinding requires quiescent hardware. This is not a reset or recovery protocol: if hardware remains busy/faulted, reload the loopback image before retrying. No automatic frame replay is attempted.

## Register/stream boundary

The mailbox occupies GP0 addresses `0x40000000`–`0x40002fff`, clocked by FCLK0 at 100 MHz. PL interrupt 0 maps to GIC SPI 29 (interrupt ID 61). The driver owns the clock, interrupt and PL330 channels selected by the DT. The required `hlsdma0` DT alias fixes the character-device name independently of probe order. No PL peripheral-request handshake is used: DMA performs incrementing-address memory copies to packet RAM. [AMD's PL330 overview](https://xilinx-wiki.atlassian.net/wiki/spaces/A/pages/18842220/Zynq+Linux+pl330+DMA) describes this built-in controller; its old sample driver is not used here.

| Offset | Meaning |
|---|---|
| `0x00`, `0x04` | Identity `0x484c444d`, ABI 1 |
| `0x08` | Status: bit 0 TX busy, bit 1 RX full, bit 2 fault, bit 3 incomplete RX packet |
| `0x0c`, `0x10` | Publish TX byte length; read RX byte length |
| `0x14` | Acknowledge: bit 0 TX done, bit 1 release RX, bit 2 clear fault |
| `0x18`, `0x1c` | Interrupt mask/events: TX done, RX full, fault |
| `0x1000`, `0x2000` | TX/RX packet RAM, 257 valid 32-bit words each |

RAM accepts aligned 32-bit AXI3 INCR bursts of 1–16 beats; registers require single full-word writes. Unsupported transactions complete with SLVERR. Earlier beats of a failed write burst may have modified unpublished TX RAM. Finish every RX read burst before acknowledging it. Reset discards slot ownership and requires a quiescent AXI master. Stream words contain four valid bytes; TLAST marks the packet end. Short/oversized RX packets are discarded and reported as faults, with oversized packets drained through TLAST.

## Evidence and remaining validation

CI sweeps all 256 frame lengths in source RTL. Mapped-core simulation with [pinned AMD functional BRAM models](../dma/models.lock.json) covers 29 lengths: 2–18 words and each larger power of two with its neighbors, through 257 words. Both runs cover every 1–16-beat burst length, byte enables, invalid addresses/IDs/last beats, backpressure, response stability, malformed packets and reset. Synthesis requires exactly two BRAMs. One placement of the final RTL used 811 `SLICE_LUTX` slots, 166 flip-flops and two `RAMB18E1`s; the partially modelled timing estimate was 175.84 MHz. The bitstream round trip recovered 34,946 non-ECC set bits. These are compile results, not board timing qualification.

The standalone QEMU tests boot the actual new kernel and load both modules with version checks enabled. They exercise PL330 DDR copies on both channels at 8, 12, 64, 1024 and 1028 bytes, verify guard bytes, and confirm that the transport refuses absent PL hardware. The resulting SD root also runs the existing 23 BEAM transport tests.

[QEMU–Icarus co-simulation](te0715-cosim.md) additionally runs the real driver and both loopback diagnostics against the mailbox RTL, including PL interrupt delivery through the emulated GIC, backpressure and blocked-reader unbind/rebind. It does not qualify physical GP0 burst conversion, DMA bus-fault propagation, board timing or actual hardware teardown. The board commands above remain required.

- [ ] Verify board loopback and unbind/rebind, then record throughput and CPU cost for representative frame sizes.
- [ ] After board loopback passes, qualify the [routed actor/debug image](te0715-regsvc.md), already exercised through Linux–RTL co-simulation.
- [ ] Use those measurements to decide whether to retain PL330, add buffering, or build a PL DMA engine on an HP port.
