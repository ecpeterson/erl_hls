# Register and DMA SD kits

These complete SD kits pair the retained, timing-checked Vivado register and DMA-loopback images with the **100-MHz FCLK0** boot configuration for **TE0715-05-71C33-A on TEF1002-03-A**. The [result manifest](../results/ps-sd-2026-09-21.json) identifies the archived files and software checks. Physical operation remains unverified.

| Kit | Linux interface | SD layout |
| --- | --- | --- |
| `register` | Polling UIO, `erl-hls-probe`, GP0 `0x40000000` | FAT partition 1; Linux root is in `image.ub` |
| `dma` | `/dev/hls-dma0`, PL330, interrupt-driven packet loopback | FAT partition 1 plus ext4 root on partition 2 |

Both retain the checked Trenz DDR/MIO initialization, source-built FSBL and vendor U-Boot. They leave the Si5338 unchanged and do not depend on it. The DMA kit includes the matched kernel/modules, ARM BEAM, C and Erlang diagnostics. It loops frames back inside the PL; it contains neither application actors nor Ethernet.

## Build and verify

Reuse the [base boot SDK](te0715-boot.md), [ARM runtime](te0715-runtime.md), and [DMA kernel cache](te0715-dma.md). Extract the retained [Vivado reference archive](vivado-reference.md), keeping each `candidate.bit` beside its `input-manifest.json`. The packager rejects a swapped image, changed RTL, wrong FSBL or incompatible kernel. It requires a new output directory and preserves existing candidates and build caches. No Vivado host is needed.

From `experiments/07-openxc7`:

```sh
python3 prepare_ps_probe.py build register build/boot/candidate \
  /path/to/erl-hls-vivado-20260921/release/results/register/candidate.bit \
  build/ps-sd/register
python3 prepare_ps_probe.py build dma build/boot/candidate \
  /path/to/erl-hls-vivado-20260921/release/results/dma/candidate.bit \
  build/ps-sd/dma --runtime build/runtime/candidate \
  --kernel build/dma-kernel/share/output
python3 prepare_ps_probe.py check build/ps-sd/register/candidate
python3 prepare_ps_probe.py check build/ps-sd/dma/candidate
python3 test_ps_probe.py --candidate build/ps-sd/register/candidate
python3 test_ps_probe.py --candidate build/ps-sd/dma/candidate
```

The checker verifies file hashes, exact PL provenance, all four Bootgen payloads, the retained 100-MHz FSBL, FIT payload selection and device-tree clock/address/interrupt/channel bindings. Tests additionally corrupt boot headers, payloads and kit metadata. The register-kit checker also validates both ARM diagnostic executables.

Optional local software acceptance:

```sh
python3 test_te0715_qemu.py build/ps-sd/register/candidate
python3 test_te0715_runtime.py --candidate build/ps-sd/dma/candidate
python3 run_qemu_cosim.py build/boot/candidate build/dma-kernel/share/output \
  --runtime build/ps-sd/dma/candidate
```

The first two checks boot the actual kit kernel and userspace in QEMU. DMA co-simulation connects the matching Linux driver and PL330 to mailbox RTL in Icarus; it compares the loaded module and C diagnostic with the installed SD-root copies, then checks all frame sizes, backpressure, interrupt wakeup, unbind/rebind and the shipped BEAM client. Its kernel and device tree must also match the kit. QEMU bypasses BootROM/FSBL/U-Boot and does not exercise bitstream configuration, physical DDR, GP0, interrupts or board timing.

## First-board sequence

Confirm the delivered revisions, supplies, boot switches and UART access using the [base boot prerequisites](te0715-boot.md#first-board-run). Keep one complete kit per SD image and retain its manifest with the UART log. Copy its `sd_files` onto FAT partition 1. For DMA only, install the decompressed `rootfs.ext4.gz` onto partition 2 using the [runtime installation procedure](te0715-runtime.md); this is an ext4 filesystem image, not a whole-disk image. The packaging tools never write an SD device.

1. Boot `register`; establish repeatable Linux boot, DDR integrity and independent FCLK0 measurement. Run the [UIO identity/scratch/write-accounting diagnostic](te0715-boot.md#first-board-run).
2. Boot `dma`; run the [C and BEAM loopback diagnostics and explicit unbind/rebind check](te0715-dma.md#board-checks). Confirm actual DMA lengths, interrupt delivery and repeated traffic before attaching an application.
3. Use the separate **25-MHz** [clock-startup kits](clock-startup.md) for internal PRBS, internal Ethernet and finally the external DAC link. Verify their additional supply/clock prerequisites first.

The first-board software preparation is complete for those stages. The [routed actor/debug candidate](te0715-regsvc.md), native-toolchain qualification and complete native timing models remain separate follow-ups. Register/DMA vendor images must not be combined with the 25-MHz link or routed-application FSBLs.
