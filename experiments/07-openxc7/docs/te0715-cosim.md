# Linux–RTL DMA co-simulation

Run the [DMA loopback](te0715-dma.md) without a board: ARM Linux and BEAM execute in QEMU, while Icarus executes the unchanged mailbox RTL. CPU register accesses and PL330 packet copies both reach its AXI port; its interrupt reaches QEMU's GIC and the real Linux driver.

```text
ARM Linux / BEAM → character driver → QEMU CPU + PL330
                                             ↕ memory accesses / IRQ
                                      Unix socket bridge
                                             ↕ AXI transactions / IRQ
                              Icarus mailbox RTL → stream loopback
```

The [routed image](te0715-regsvc.md) uses the same bridge with two mailbox banks and separate interrupt lines, connecting application and debug streams to generated actors. Select it with `--regsvc build/routed-dma/rtl` and its assembled SD runtime. Protocol version 2 carries the two interrupt levels as a bitmap; rebuild QEMU when updating the bridge.

The bridge has no substitute packet RAM, mailbox registers or completion logic. The testbench drives public AXI/stream ports and periodically stalls the loopback. VPI carries commands and responses; it does not read or modify internal DUT state.

## Run

Use the boot, kernel and optional DMA runtime candidates from the [DMA build guide](te0715-dma.md). Keep its native static-musl compiler cache. Building QEMU requires a C/C++ toolchain, Python 3.11+, `pkg-config`, GLib and libfdt; on macOS, Homebrew supplies the dependencies (`brew install pkg-config glib dtc`). Icarus must provide `iverilog`, `iverilog-vpi` and `vvp`.

From `experiments/07-openxc7`:

```sh
python3 build_qemu_cosim.py --jobs 4
python3 test_qemu_cosim.py --qemu build/cosim/qemu-build/qemu-system-arm
python3 run_qemu_cosim.py build/boot/candidate build/dma-kernel/share/output \
    --runtime build/dma/candidate
```

The builder pins QEMU 10.2.0 and Ninja sources by SHA-256 and builds only the ARM system emulator. It attaches the PL window/IRQ to `xilinx-zynq-a9` when `HLS_COSIM_SOCKET` is set. Without that variable the machine is unchanged. Everything stays under `build/cosim/`; keep that directory for incremental builds. The tested native Apple Silicon cache occupies about 1.2 GiB. No x86 host or privileged host device access is required.

The runner verifies kernel and runtime manifests, builds the current C diagnostic and boots a disposable initramfs. With `--runtime`, it requires the same kernel/modules and device tree as the kit, compares the loaded driver and C diagnostic with the installed loopback-image copies, and runs the ARM BEAM diagnostic from a temporary decompressed SD root; omit the option for C-only checks. It never modifies the candidate images and removes the temporary 512-MiB root on exit. UART, RTL and compiler logs, plus a result/input-hash report, remain in `build/cosim/run/`. The default whole-guest timeout is 120 seconds.

## Coverage

The C and BEAM diagnostics each loop back all 256 routed frame sizes, including zero and maximum payloads. Additional C checks fill both slots and require `EAGAIN` for a third write, drain frames in order, wake a blocked read on completion, and unbind with a blocked reader that must receive `ENODEV`. The guest then rebinds for the BEAM run and unloads the driver. Partial reads, malformed writes and exclusive direction ownership are also checked.

Success requires guest pass markers, both simulators exiting successfully, and RTL evidence: 515 completed stream frames (259 without BEAM), interrupt edges, clock steps and actual backpressure stalls. [The recorded run](../te0715-cosim-result.json) includes hashes and counters. Host wall time measures test cost, not transport performance.

CI runs `test_qemu_cosim.py` through the existing PS-probe suite: real Icarus/AXI traffic, slot ownership, reset, fragmented socket messages and rejection of malformed/truncated requests. The optional `--qemu` checks corrupt/truncated replies and peer loss against the native emulator. Full Linux/BEAM co-simulation is a local acceptance check; CI does not build its kernel, runtime image or QEMU.

## What still needs hardware

This is a functional schedule, not a timing model. Each memory access completes an AXI transaction; a QEMU virtual timer advances 64 extra RTL cycles per millisecond after the first access, allowing the stream to progress while Linux sleeps. The test does not model the selected physical fabric clock, CPU/fabric clock ratios or throughput.

QEMU splits wider memory accesses into single 32-bit AXI transactions here. It does not reproduce the PS's GP0 burst conversion, arbitration, cache/coherency behavior or electrical interfaces. Existing standalone RTL/mapped-core tests cover AXI bursts; silicon must still qualify the complete PS–PL path.

The pinned [QEMU PL330 model](https://gitlab.com/qemu-project/qemu/-/blob/v10.2.0/hw/dma/pl330.c) ignores memory-transaction error returns. Consequently, this run cannot validate AXI errors becoming PL330 faults or the driver's response to those faults. Bridge disconnects, invalid replies, unknown RTL response bits and stalled bus transactions instead fail the experiment explicitly. Snapshot/migration and independent simulator restart are unsupported; restart the entire run.

Board boot, DDR, clocks/resets, physical interrupt delivery, DMA error handling and throughput remain acceptance work. Co-simulation adds integration evidence; it does not qualify a board image.
