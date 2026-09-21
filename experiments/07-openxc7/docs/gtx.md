# TE0715 GTX compile probe

This probe tests the openXC7 prerequisites for the TEF1002 SFP path: one GTX channel, its reference clock, reset sequencing and CPU-visible diagnostics. It generates a routed design, **not a programmable image**. Zynq GTX configuration-frame mappings and feature data remain incomplete. It implements neither Ethernet PCS/MAC nor SFP management.

The independent PS copper Ethernet and [PL330 DMA image](te0715-regsvc.md) do not depend on this GTX work.

## Clock and lane profile

The target is TE0715-05-71C33-A on TEF1002-03-A (`xc7z030sbg485-1`). The candidate uses a 125-MHz reference, a 2.5-GHz CPLL and divide-by-four TX/RX outputs for 1.25-Gbaud PRBS7. Both elastic buffers are enabled; the raw 20-bit datapath uses separate 62.5-MHz TX/RX user clocks. Control and GP0 use **25-MHz FCLK0**. These are requested clock settings, not measurements of the board.

| Signal at the FPGA | SBG485 pins | Resource |
| --- | --- | --- |
| Reference P/N | U5 / V5 | `IBUFDS_GTE2_X0Y1`, Si5338 CLK2 |
| GTX receive P/N | W8 / Y8 | `GTXE2_CHANNEL_X0Y1` |
| GTX transmit P/N | W4 / Y4 | `GTXE2_CHANNEL_X0Y1` |

Pins name the FPGA's native polarity. TE0715 on TEF1002 reverses **both** SFP pairs, so a later external-link design needs RX/TX polarity inversion. This probe selects fixed near-end PMA loopback with both inversion controls zero. It does not qualify the carrier wiring, SFP module, optics or remote receiver. It neither accesses the carrier controller nor enables its SFP transmitter.

Before hardware operation, verify the delivered Si5338 configuration: the existing boot candidate does not reprogram it. Also verify FCLK0, the reset/clock sequence, SFP controls and controller firmware. See the [module schematic, sheets 6/13/15](https://www.trenz-electronic.de/trenzdownloads/Trenz_Electronic/Modules_and_Module_Carriers/4x5/TE0715/REV05/Documents/SCH-TE0715-05-71C33-A.PDF), [carrier schematic, sheets 5/9/17](https://www.trenz-electronic.de/trenzdownloads/Trenz_Electronic/Modules_and_Module_Carriers/4x5/4x5_Carriers/TEF1002/REV03/Documents/SCH-TEF1002-03-A.PDF) and [carrier compatibility overview](https://wiki.trenz-electronic.de/display/PD/4+x+5+SoM+Carriers).

## Diagnostic contract

GP0 provides aligned 32-bit registers at `0x40000000`. One read and one write may be outstanding independently. Unsupported accesses return `SLVERR`; reads snapshot at address acceptance and remain stable under stalls. The control register supports byte writes. Reset aborts pending transactions and clears diagnostics; quiesce the CPU before resetting the peripheral.

| Offset | Access | Meaning |
| --- | --- | --- |
| `0x00` | RO | Identity `0x47545837` (`GTX7`) |
| `0x04` | RO | Register ABI 1 |
| `0x08` | RW | Bit 0: run; bit 1: force PRBS errors; other bits reserved, write zero |
| `0x0c` | RO | Control-clock cycles, modulo 2³² |
| `0x10` | RO | Accepted control writes, modulo 2³² |
| `0x14` | RO | State, synchronized lock/reset-done levels, measurement enable and latched fault |
| `0x18` | RO | RX user-clock cycles, modulo 2³² |
| `0x1c` | RO | RX cycles reporting PRBS errors while measurement is enabled; saturates at `0xffffffff` |
| `0x20` | RO | TX user-clock cycles, modulo 2³² |

Status bits `2:0` are `0` boot delay, `1` reset held, `2` awaiting PLL lock, `3` awaiting user clocks, `4` awaiting reset-done, `5` settling, `6` measuring, `7` fault. Bits 4/5/6 report CPLL lock/TX reset-done/RX reset-done; bit 8 enables measurement. Bits `15:12` report one fault: `1` startup timeout, `2` lost PLL lock, `4` lost reset-done, `8` stopped user clock. Other status bits are zero.

Hold run low to clear an attempt, then set it high. Startup waits beyond the post-configuration reset exclusion interval, holds reset until the preceding PLL lock disappears, releases the PLL, observes new lock and user-clock progress, and waits for reset-done plus settling. Startup has a 1-ms deadline at 25 MHz. During measurement, absent clock snapshots for about 41 µs cause a fault. Faults hold GTX reset and require run low before retry; there is no automatic retry loop.

Clock counts advance during startup too. Each counter value is a coherent, delayed snapshot; separate register reads need not describe the same instant. Run low clears the snapshots even if a user clock has stopped. PRBS error cycles are **not a bit-error count**: one corrupted bit can cause several checker errors. Measurement-ready reports completed reset sequencing, not a healthy PRBS stream or Ethernet link. After hardware qualification, compare counter deltas during an error-free interval, force errors briefly with control bit 1, then confirm detection and recovery. [AMD UG476, reset/loopback and PRBS chapters](https://docs.amd.com/api/khub/documents/SgVweevU5cLv0LyXoCVoPg/content).

## Build and evidence

Use the pinned [native toolchain](../README.md#setup), then from the repository root:

```sh
bash experiments/07-openxc7/run_gtx_probe.sh
```

The command downloads about 300 KiB of pinned logical metadata and structural site definitions, checks them against Zynq's sites, and builds a separate cached chip database. It never modifies the installed toolchain or the working Zynq bit database. Yosys checks primitive retention; nextpnr uses seed 1 and explicit control/user-clock constraints. Outputs live in `build/gtx-probe/`, including the source manifest, routed FASM, logs, timing report and `result.json`.

The [recorded native result](../gtx-result.json) demonstrates synthesis and routing. The audit identifies missing frame mappings and segment-bit definitions for the used GTX channel/common/interface tiles. The command has no assembly step, even if a later database fills these entries: their contents would still need independent validation. Virtex metadata is reusable where site structure agrees; Virtex configuration-frame addresses are not evidence for Zynq addresses.

Digital regression runs through the existing PS-probe CI entry point. It exercises original/extended AXI registers and GTX sequencing/snapshots before and after Yosys synthesis, including stale lock, missing clocks, fault latching and coordinated restart. It does not simulate the analog GTX. Native timing covers only modeled paths; PS/GTX timing and physical CDC constraints remain unqualified. In particular, the counter snapshot bus must settle before its synchronized acknowledgement is consumed.

The static GTX attributes/reserved-port ties derive from the pinned LiteICLink source in [sources.lock.json](../gtx/sources.lock.json), configured for the clock profile above; its [license](../gtx/LICENSE.liteiclink) is retained. Replacing this candidate with a qualified vendor/transceiver configuration remains possible without changing the diagnostic register contract.

## Remaining qualification

1. Establish Zynq GTX frame addresses and validate donor feature encodings with the prepared [device-specific reference task](gtx-configuration.md) before enabling assembly.
2. Check physical clock/reset and CDC timing; qualify repeated startup, stopped-clock recovery and PRBS error detection on hardware.
3. Integrate the prepared [carrier management](sfp-management.md) and [PCS/MAC gearbox adapter](ethernet-gtx.md); then qualify external polarity, loss-of-signal, module compatibility and sustained traffic.
