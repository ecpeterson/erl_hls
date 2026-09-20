# TE0715 SD boot candidate

This flow prepares the [PS–PL register probe](../../../docs/zynq-ps-probe.md) for **TE0715-05-71C33-A / XC7Z030-1SBG485C**, intended for **TEF1002-03-A**. It builds on Apple Silicon without Vivado, PetaLinux or a Linux VM. Hardware boot is unverified.

The SD boot chain is BootROM → FSBL → PL configuration → U-Boot → Linux → UIO diagnostic. The FSBL uses Trenz's generated DDR/MIO initialization unchanged. Trenz's [module table](https://wiki.trenz-electronic.de/display/PD/TE0715+Test+Board) maps this REV05 SKU to profile `04_30_1c_1gb`; the build checks that mapping and the PS settings before compiling.

| Component | Source |
| --- | --- |
| FSBL | AMD 2023.2 standalone BSP, Trenz hooks and exact-profile PS initialization; compiled locally |
| PL | Native openXC7 register-probe build; supplied explicitly |
| U-Boot, Linux 6.1.30, root filesystem | Unmodified binaries from Trenz's pinned 2023.2 reference archive |
| Device tree | Vendor PS description with its PL register bank replaced by the probe's UIO page |
| Host diagnostic | Existing probe C source, statically linked against source-built musl 1.2.5 |

The four-partition `BOOT.bin` carries FSBL, PL, U-Boot and the device tree. Linux's `image.ub` contains the same device tree, the original kernel and original RAM filesystem. `boot.scr` selects that FIT from SD partition 1. No script formats storage, programs hardware or writes QSPI.

## Build

Use a checkout path without whitespace, Python 3.12+, Apple's command-line C/C++ tools, and native `make`, `patch`, `curl`, OpenSSL 3, `dtc`, and U-Boot tools (`mkimage`/`dumpimage`). Homebrew supplies the latter as `openssl@3`, `dtc`, and `u-boot-tools`. QEMU is optional for the Linux smoke test.

From `experiments/07-openxc7`:

```sh
./run_zynq_ps_probe.sh
python3 prepare_te0715_boot.py \
  --bitstream build/zynq-ps-probe/xc7z030sbg485-1.bit
python3 test_te0715_boot.py --candidate build/boot/candidate
python3 test_te0715_qemu.py build/boot/candidate
```

If the PL build uses `ERL_HLS_OPENXC7_BUILD_ROOT`, pass its resulting `.bit` path instead. Supply `--openssl-prefix` if OpenSSL is outside `/opt/homebrew/opt/openssl@3`.

[sources.json](../boot/sources.json) pins every downloaded archive by SHA-256, including the native ARM GCC toolchain. Downloads are verified on every run; source builds are fresh and use at most four jobs. `build/boot/candidate/manifest.json` records inputs, output hashes and the checked partition map. Builds use a fixed source epoch. Vendor sources, licenses, generated BSP and logs remain under `build/boot/work/` for inspection; none are committed.

The local footprint is about 1.5 GiB: 226 MiB of downloads, 986 MiB of compiler, 206 MiB of rebuildable work, and 69 MiB of candidate files. The optional QEMU overlay adds about 20 MiB. Deleting `build/boot/work/` and `build/boot/qemu/` reclaims scratch space without removing the candidate or download/compiler caches. These paths are separate from the FPGA/XLS caches.

## Validate before hardware

The image checker verifies boot/partition checksums, bounds, non-overlap, load addresses, FSBL on-chip-memory fit, exact ELF payloads, PL word swapping/padding, and the embedded device tree. Corruption tests deliberately alter those fields and payloads. FIT extraction checks its selected payloads and SHA-256 hashes. The ARM executables must map their ELF headers and request a non-executable stack.

The optional QEMU test boots the selected kernel and device tree with a disposable initramfs overlay. It loads the UIO module, verifies the map, runs the ARM diagnostic's mock-register tests and checks CLI failures, including mapping an inert file with the wrong identity. It uses one emulated CPU and bypasses the FSBL/U-Boot chain. It does **not** test DDR training, SD boot, PCAP, fabric clocks/resets or PL MMIO. The shipped root filesystem remains unchanged.

The portable board-profile tests also run through the existing PS-probe CI entry point. Full native assembly and QEMU remain local checks. See [recorded evidence](../te0715-boot-result.json).

## First board run

Before power-up, verify the **REV03 carrier's** voltage and boot selections against its [TRM](https://wiki.trenz-electronic.de/display/PD/TEF1002+TRM), fitted CPLD firmware and the module schematic. The PS profile uses MIO bank 0 at 3.3 V, bank 1 at 1.8 V, SD0 on MIO40–45, UART0 on MIO14–15 and a 100 MHz FCLK0. The carrier's [CPLD revision history](https://wiki.trenz-electronic.de/display/PD/TEF1002+SC+CPLD+MAX10) records changed boot/voltage controls for REV03: older switch tables are insufficient. This candidate does not select or change carrier jumpers.

Copy only `BOOT.bin`, `boot.scr`, `image.ub`, and `probe_zynq_ps` from the candidate to an otherwise empty FAT SD partition 1. Keep the manifest with the experiment log. Connect the carrier's UART at 115200 8N1, select SD boot using the verified board settings, and retain the complete cold-boot log. Trenz's image enables console auto-login.

After Linux boots, as root:

```sh
modprobe uio_pdrv_genirq of_id=generic-uio
cat /sys/class/uio/uio*/name
cat /sys/class/uio/uioN/maps/map0/{addr,size,offset}
# Select the device named erl-hls-probe: address 0x40000000, size 0x1000, offset 0.
# From the mounted SD directory (mount /dev/mmcblk0p1 if necessary):
./probe_zynq_ps /dev/uioN
```

The diagnostic requires exclusive access and restores scratch after its checks. Success reports identity `0x45524c48`, ABI 1, exactly 37 writes and a nonzero cycle delta. Confirm the fabric clock/reset setup before MMIO: an inactive AXI target can stall a CPU access. Linux retains FCLK0 through the vendor `fclk-enable` setting; the FSBL supplies its initial configuration. No interrupt is used.

## Remaining acceptance work

- [ ] Verify the delivered carrier's voltage/boot controls and capture them with board/CPLD revisions.
- [ ] Cold-boot from SD, confirm 1 GiB DDR, retain the UART log and run the UIO diagnostic on each board.
- [ ] Repeat power cycles and a DDR memory test before trusting larger designs; verify FCLK0 frequency independently.
- [ ] Build U-Boot and a minimal Linux/rootfs from source once the vendor baseline works.
- [ ] Validate recovery/reconfiguration separately before adding a persistent hardware service.
