# Zynq PS–PL register probe

This bring-up image connects the Zynq processing system's GP0 AXI port to five registers in the programmable logic. CPU reads and writes test that the PS interface, fabric clock and reset operate together, before adding application logic or DMA. It uses FCLK0 and no PL package pins.

The image compiles for `xc7z030sbg485-1` with the [native openXC7 toolchain](../experiments/07-openxc7/README.md#setup). **Hardware operation is unverified.** Board boot software must configure DDR/MIO, enable GP0 and FCLK0, enable PS–PL level shifters, and release fabric/interface resets. The build does not supply that board configuration. See AMD's [PS–PL interface reference](https://docs.amd.com/r/en-US/ug585-zynq-7000-SoC-TRM/PS-PL-AXI-Interfaces).

## Build and check

From the repository root, with Python 3.11+, a C compiler and Icarus Verilog installed:

```sh
python3 experiments/07-openxc7/test_zynq_ps_probe.py
experiments/07-openxc7/run_zynq_ps_probe.sh
```

The first command tests the register interface and host diagnostic without FPGA tools. The second also simulates the technology-mapped register block, builds the PS7 wrapper through placement/routing and bitstream assembly, and verifies the configuration-bit round trip. It uses the checked [SBG485 package overlay](../experiments/07-openxc7/zynq7030.md) and its tool/output-directory overrides. Outputs are under `experiments/07-openxc7/build/zynq-ps-probe/` by default.

## CPU access

The register base is `0x40000000`. Use aligned, uncached 32-bit device accesses; the probe accepts one transaction per direction and does not support write-data interleaving.

| Offset | Register | Behavior |
| --- | --- | --- |
| `0x00` | Identity | Read-only `0x45524c48` (ERLH) |
| `0x04` | ABI version | Read-only `1` |
| `0x08` | Scratch | Read/write; byte strobes select updated lanes |
| `0x0c` | Fabric cycles | Read-only; increments on each active FCLK0 edge |
| `0x10` | Accepted writes | Read-only; increments on each successful scratch write, including a zero strobe mask |

Scratch and counters reset to zero; counters wrap modulo 2³². Reads snapshot the value when their address is accepted. A simultaneous scratch write becomes visible to subsequent reads.

On Linux, expose the first 4 KiB at this base as map 0 of a [UIO device](https://docs.kernel.org/driver-api/uio-howto.html), with mapping offset zero and device-memory attributes. Confirm the address/size/offset in `/sys/class/uio/uioN/maps/map0/`, then build and run on the board:

```sh
cc -std=c11 -Wall -Wextra -Werror -O2 \
  experiments/07-openxc7/probe_zynq_ps.c -o probe_zynq_ps
./probe_zynq_ps /dev/uioN
```

The diagnostic requires exclusive access. It checks identity/version before writing, tests 36 scratch patterns, checks readback and write accounting, waits for the cycle counter, then restores the original scratch value. Restoration is also attempted after a failed check. It uses ordered, volatile 32-bit accesses; it neither programs the FPGA nor changes PS clocks/resets. A stopped interface can hang or fault an MMIO access, so clock/reset setup must precede this test. The program cannot impose a timeout on an individual CPU bus access.

## Interface and reset

Single-beat, aligned 32-bit FIXED/INCR transactions are supported. Other sizes, lengths, burst modes, locked accesses, invalid addresses and writes to read-only registers receive `SLVERR`. Unsupported writes drain all advertised beats without changing scratch; unsupported reads return the advertised number of zero/error beats. Responses preserve transaction IDs and remain stable under backpressure. Sources must obey AXI validity/beat-count rules.

Either FCLK0 reset or GP0 interface reset asserts the probe reset immediately; release waits for two FCLK0 edges. Reset discards outstanding work. Quiesce CPU accesses before resetting or reconfiguring PL; this probe does not recover a master's abandoned transactions.

## Evidence and limits

CI exercises byte masks, address/data ordering, captured IDs, simultaneous reads/writes, response stalls, invalid accesses, rejected bursts and reset during pending transactions, both before and after register-block synthesis. Host tests inject lost/duplicated writes, stopped counters and restoration failure, including counter wrap.

The [recorded native run](../experiments/07-openxc7/zynq-ps-probe-result.json) on 2026-09-20 retained one PS7 and one BUFG, placed 281 LUT BELs and 168 flip-flops, and recovered all 16,950 non-ECC configuration set bits from the assembled bitstream. It used one placement, with no BRAM or DSP. The reported 138.20 MHz estimate against a 100 MHz target is **not clock qualification**: PS boundary timing and physical operation remain unverified. The target does not program FCLK0's frequency.
