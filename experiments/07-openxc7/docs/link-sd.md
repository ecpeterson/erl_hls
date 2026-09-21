# GTX and Ethernet SD diagnostics

These three independent SD kits pair the retained, timing-checked [Vivado images](vivado-reference.md) with a 25-MHz FSBL, Linux/UIO and a matching ARM diagnostic. They target **TE0715-05-71C33-A on TEF1002-03-A**. Hardware operation remains unverified. [Recorded kit hashes and checks](../results/link-sd-2026-09-21.json) identify the retained local archive.

| Kit | Test | UIO name | Diagnostic |
| --- | --- | --- | --- |
| `prbs` | Internal PMA loopback, PRBS7 at 1.25 Gbaud | `erl-hls-gtx` | `probe_gtx` |
| `ethernet-loopback` | Internal PMA loopback, fixed Ethernet frames | `erl-hls-ethernet` | `probe_ethernet` |
| `ethernet-external` | External SFP, matching fixed-frame peer | `erl-hls-ethernet` | `probe_ethernet` |

All use GP0 at `0x40000000`, size `0x1000`, and require a **125-MHz Si5338 reference**. The FSBL sets FCLK0 to 25 MHz but **does not program the Si5338 or carrier controller**. Verify the delivered reference-clock configuration and [carrier prerequisites](sfp-management.md) first. Internal loopback does not qualify the connector or DAC. The external image inverts both serial polarities for this carrier/module combination; use an isolated matching peer, since unrelated traffic fails its pattern checker.

## Prepare and verify

Reuse the [base boot SDK/candidate](te0715-boot.md) and [25-MHz FSBL](te0715-regsvc.md). Extract the retained Vivado evidence archive; its `release/results/<profile>/candidate.bit` files are the accepted images. The packager pins their hashes to the checked-in reference report and rejects swapped profiles or native substitutes. It downloads nothing and requires no Vivado installation.

From `experiments/07-openxc7`:

```sh
python3 prepare_link_probe.py build prbs \
  build/boot/candidate build/routed-dma/fsbl \
  /path/to/erl-hls-vivado-20260921/release/results/prbs/candidate.bit \
  build/boot build/link-sd/prbs/candidate
python3 prepare_link_probe.py check build/link-sd/prbs/candidate
python3 test_link_probe.py --candidate build/link-sd/prbs/candidate
```

Repeat with each Ethernet profile and its corresponding `.bit` and output directory. Outputs must be new directories. The checker compares every recorded file hash, FSBL provenance, four Bootgen partitions, selected FIT payloads and device-tree mapping. The optional test boots Linux in QEMU and exercises ARM userspace; it bypasses FSBL/U-Boot and never accesses physical PL. PRBS fault tests also run in ordinary CI without the SDK or reference images.

## Board sequence

Follow the [SD boot prerequisites](te0715-boot.md#first-board-run), using **one complete kit per boot**. Copy only its manifest's `sd_files` to an otherwise empty FAT SD partition 1. Retain the manifest with the UART log. Do not mix `BOOT.bin`, `image.ub` or clients between kits; the two Ethernet images share an identity register and cannot distinguish their profiles through MMIO.

After boot, as root:

```sh
modprobe uio_pdrv_genirq of_id=generic-uio
cat /sys/class/uio/uio*/name
cat /sys/class/uio/uioN/maps/map0/{addr,size,offset}
# Select the expected name above: address 0x40000000, size 0x1000, offset 0.
# From the mounted SD directory:
./probe_gtx /dev/uioN
./probe_gtx /dev/uioN --run
```

Use exclusive access. The default command is read-only; `--run` changes control registers. Confirm clocks and the programmed image before MMIO: a stopped AXI target can stall a CPU access, beyond the diagnostic's polling timeout.

The PRBS test resets stale state, waits for readiness, checks 20 ms of clean clock progress, injects errors, then resets and checks another clean interval. Each startup has a one-second polling budget; injection has 100 ms. Linux scheduling can extend elapsed time. It reports counter deltas, forced-error cycles and last status before clearing run. RX/TX deltas must be within 10% of the expected 62.5/25-MHz ratio. This detects a gross clock mismatch, not absolute frequency or jitter. SIGINT/SIGTERM request cleanup; abrupt process termination cannot guarantee it. Error cycles are not bit errors, and this short test is not BER qualification.

Once PRBS succeeds repeatedly, boot `ethernet-loopback` and run `./probe_ethernet /dev/uioN --run`. Its [five-second packet test](ethernet-board.md#control-and-observations) requires both links and at least five frames each way. Then use `ethernet-external` with the matching peer and verified carrier/DAC settings. Start `--run` on both peers together so their five-second attempts overlap. Keep these as separate acceptance steps: software/container checks, internal transceiver operation, then external link operation. Record repeated cold boots, restart behavior and sustained traffic separately from these short smoke tests.
