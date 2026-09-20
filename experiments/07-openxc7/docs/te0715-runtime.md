# TE0715 Linux/OTP image

This SD-root candidate runs OTP 28 and the current `erl_hls` BEAM modules on **TE0715-05-71C33-A / TEF1002-03-A**. It retains the [register-probe boot candidate](te0715-boot.md)'s FSBL, PL, U-Boot, Linux and matching kernel modules. The root filesystem is Alpine 3.23.6 for ARMv7, with OTP 28.5.0.1, `erlc`, crypto/TLS, Dropbear SSH, I²C/device-tree tools, `strace`, `tcpdump`, `ethtool`, and `memtester`. Hardware operation is unverified.

The 512 MiB ext4 image belongs on SD partition 2; partition 1 holds `BOOT.bin`, `boot.scr` and `image.ub`. Linux mounts the root from SD rather than keeping the Erlang installation in an initramfs. No hardware service starts automatically. The PL remains the GP0 register probe: this candidate has no DMA endpoint. The separate [DMA loopback image](te0715-dma.md) adds one.

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

## DMA integration

This register-probe image retains the vendor kernel and its Xilinx DMAengine provider, but contains no DMA hardware endpoint. The separate [PL330 loopback candidate](te0715-dma.md) uses the Zynq's built-in DMA controller, a source-built matching kernel/module set, and the current routed-frame character-device contract. It is the next board acceptance step; keep this probe image as the smaller recovery/diagnostic baseline.
