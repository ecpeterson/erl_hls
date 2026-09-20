# TE0715 Linux/OTP image

This SD-root candidate runs OTP 28 and the current `erl_hls` BEAM modules on **TE0715-05-71C33-A / TEF1002-03-A**. It retains the [register-probe boot candidate](te0715-boot.md)'s FSBL, PL, U-Boot, Linux and matching kernel modules. The root filesystem is Alpine 3.23.6 for ARMv7, with OTP 28.5.0.1, `erlc`, crypto/TLS, Dropbear SSH, I²C/device-tree tools, `strace`, `tcpdump`, `ethtool`, and `memtester`. Hardware operation is unverified.

The 512 MiB ext4 image belongs on SD partition 2; partition 1 holds `BOOT.bin`, `boot.scr` and `image.ub`. Linux mounts the root from SD rather than keeping the Erlang installation in an initramfs. No hardware service starts automatically. The PL remains the GP0 register probe: there is **no DMA endpoint yet**.

## Build and check

First build the register-probe boot candidate. Use the same native tools, plus `qemu-system-arm`, OTP 28 and `rebar3`. No UTM VM, root privileges, mounted host image or host block device is required.

From `experiments/07-openxc7`:

```sh
python3 prepare_te0715_runtime.py build/boot/candidate
python3 test_te0715_runtime.py --candidate build/runtime/candidate
```

The builder checks the base candidate's hashes and boot partitions, verifies each download against [the package lock](../runtime/packages.lock.json), then installs the packages offline in an isolated ARM Linux guest. APK verifies package signatures against the base image's Alpine keys. The guest compiles the selected tests with its own `erlc`, runs 23 existing frame/client tests, and writes a disposable virtual SD image. A second guest boots that ext4 image through BusyBox init and OpenRC, repeats the tests, and loads the UIO driver. Tests use a disk snapshot and cannot alter the published image.

The candidate includes a compressed root filesystem, a kernel/device-tree FIT with checked payload hashes, the SD boot script, and an input/output manifest. QEMU logs remain in `build/runtime/`. Successful assembly removes its large temporary initramfs and uncompressed filesystem. Retain the pinned package cache for offline rebuilds; Alpine repositories may eventually remove superseded versions. Package and boot inputs are pinned; ext4 timestamps and runtime-created files make the output bytewise nondeterministic.

Portable archive/input-corruption tests run through the existing PS-probe CI entry point. Full image assembly and QEMU tests are local checks. QEMU bypasses FSBL/U-Boot and does not model the PL, carrier RTC or board Ethernet PHY; associated peripheral warnings are expected. Passing these checks does not establish SD boot, DDR training, PS–PL transactions or DMA on hardware.

## Use on the board

Follow the voltage, boot-switch and UART checks in the boot-candidate guide. Install the three boot files on FAT partition 1 and decompress/write `rootfs.ext4.gz` to an ext4-sized partition 2 of at least 512 MiB using an appropriate SD imaging tool. The builder never partitions or flashes a device. Keep the manifest with the board's UART log.

The serial console opens a root shell for bring-up. Start the runtime and its checks explicitly:

```sh
export ERL_LIBS=/opt/erl-hls/lib
/opt/erl-hls/bin/runtime-check
erl
```

After confirming fabric clocks/resets, the existing register diagnostic is at `/opt/erl-hls/bin/probe_zynq_ps`; use the UIO-device selection procedure in the boot guide. Ethernet requests DHCP on `eth0`. SSH is installed with password authentication disabled and is not started automatically: provision `/root/.ssh/authorized_keys`, then use `rc-service dropbear start` and optionally `rc-update add dropbear default`. Images contain no pre-generated host keys, machine identity or credited random seed. Configure hostname and time on each board before relying on network services.

The `hls.runtime_check=1` kernel argument is reserved for the isolated QEMU acceptance run: it executes the tests and reboots. Ordinary SD boot omits it.

## DMA integration boundary

The retained kernel registers the Xilinx DMAengine provider (`xilinx-vdma`). This establishes provider availability, not working DMA channels. The earlier experiments combine a PL AXI DMA engine, interrupt/device-tree wiring, that provider, and a character-device client. Our current PL has only a CPU-accessible register bank.

The next hardware/driver work must be developed together:

- [ ] Build a PS–PL stream loopback with a DDR master connection, interrupts, and checked clock/reset/address assignments. Select a synthesizable DMA engine and its matching Linux provider; the Xilinx provider requires the corresponding register/descriptor ABI.
- [ ] Adapt the character-device contract to today's routed frames: two header words plus up to 255 payload words (1028 bytes). The old experiment's one-word header and 256-byte buffers are insufficient. Preserve partial-read state, complete-frame writes, bounded queues and meaningful close/error behavior.
- [ ] Build the client module against the exact kernel configuration and symbol versions. Keep its node absent from the register-probe device tree. Reassess the older interrupt-coalescing patch with low-rate traffic and queued receives.
- [ ] Exercise BEAM → character device → DMA → PL loopback → DMA → BEAM, including independent application/debug traffic, blocked reads, errors and teardown. Inspect DMA status through the supported debug/register interface.

The stock Alpine ARMv7 kernel is not substituted: its inspected configuration omits the Zynq UART and Xilinx DMA provider. A source-built kernel and matching module SDK remain follow-on work; the userspace image does not depend on that replacement.
