# TE0715 Ethernet diagnostic

This probe joins the buffered [packet service](ethernet-packets.md), [GTX adapter and recovery controller](ethernet-gtx.md), two MMCMs, a fixed-frame generator/checker and the PS GP0 register bank. It targets TE0715-05-71C33-A on TEF1002-03-A. The [Vivado reference flow](vivado-reference.md) produces timing-closed 125-MHz candidates; board operation remains unverified. The [native assembly flow](gtx-configuration.md) also produces checked candidates; its incomplete timing model cannot qualify them.

```text
Linux/UIO ── GP0 control + counter snapshots
                    │
frame generator → TX queue → MAC/PCS → gearbox → GTX
frame checker   ← RX queue ← MAC/PCS ← gearbox ← GTX
                    ↑
       25-MHz startup/clock-loss supervisor
```

The default profile selects internal PMA loopback. `--external` selects the SFP lane and inverts both serial polarities for this carrier/module combination. Neither profile configures the carrier controller or Si5338. Both require the [verified 125-MHz reference and 25-MHz PS clock](gtx.md). Each GTX OUTCLK drives an MMCM producing related 125/62.5-MHz clocks; TX and RX pairs are independent.

## Control and observations

Use the existing GP0 UIO mapping, with identity `0x45544837` (`ETH7`) and ABI 1. Offsets through `0x10` retain the [register-probe contract](../../../docs/zynq-ps-probe.md); control has these meanings:

| Register | Meaning |
| --- | --- |
| `0x08`, bit 0 | Run the physical link; clear to stop and clear a latched fault. |
| `0x08`, bit 1 | Enable fixed test frames; clear to pause their generation. |
| `0x14`, bits 0–15 | [GTX controller status](gtx.md#diagnostic-contract), with reset-done qualified by the corresponding MMCM lock. |
| `0x14`, bits 16–19 | TX link, RX link, TX MMCM lock, RX MMCM lock. |
| `0x18` | Frames admitted by the test producer. This is not a delivery acknowledgement. |
| `0x1c` | Complete frames delivered to the test checker. |
| `0x20` | Delivered frames with the wrong length or byte pattern. |

Frames contain 64 bytes before FCS: broadcast destination, source `02:00:00:00:00:01`, EtherType `0x88b5`, then byte `index XOR 0xa5` for indices 14–63. Generation pauses for 125,000 TX cycles after each admission. The checker accepts only that pattern; unrelated received traffic counts as bad. MAC-rejected frames do not reach the checker, so zero bad frames alone does not establish a healthy link.

Counters wrap at 32 bits and clear on physical reset. Each snapshot is coherent; separate MMIO reads need not belong to one snapshot. If a user clock stops, snapshots retain their last observation until reset. Read physical status before interpreting them. Hard recovery discards queues and partial frames; ordinary PCS link loss retains committed RX frames. Recovery requires clearing and setting run explicitly.

`ethernet/probe_ethernet.c` is a Linux/UIO client. Its default operation is read-only. `probe_ethernet /dev/uioN --run` verifies identity/ABI, clears the previous attempt, enables traffic, and waits at most five seconds for both links and at least five transmitted/received frames without a pattern error. It clears run before returning. Use a matching peer for the external profile. Success establishes packet progress, not BER or timing qualification.

## Native build and evidence

After [installing the experiment tools](../README.md#setup), run from this directory's parent:

```sh
ERL_HLS_NEXTPNR=/path/to/checked/nextpnr-gtx bash run_ethernet_probe.sh
ERL_HLS_NEXTPNR=/path/to/checked/nextpnr-gtx bash run_ethernet_probe.sh --external
```

Use the [GTX backend build](gtx-configuration.md#build), which includes the LUT and clocking fixes. `--no-route` limits the run to synthesis and structural checks. The full command retains the netlist, FASM, timing report and database audit under `build/ethernet-board/{loopback,external}`. It rejects a fallback from dedicated clock routes to fabric routing and independently checks LUT connectivity and emitted truth tables. It never assembles a bitstream.

The two MMCM BEL constraints keep them in the half served by the backend's selected global buffers. These are placement choices, not part of the packet protocol. Frequency constraints do not replace generated-clock relationships: the pinned backend ignores `create_generated_clock`. Full/half gearbox paths must remain timed; held-bus snapshots and asynchronous control crossings also need physical constraints and review before programming.

The [native GTX report](../results/native-gtx-2026-09-21.json) records current area, partial timing and assembled-image checks; the [preceding measurement](../results/ethernet-board-2026-09-21.md) retains the earlier baseline. Digital regressions run in CI; native routing and ARM compilation are separate experiments. To rebuild the static ARM diagnostic after preparing the existing boot tools:

```sh
build/boot/compiler/arm-gnu-toolchain-14.3.rel1-darwin-arm64-arm-none-eabi/bin/arm-none-eabi-gcc \
  -specs=build/boot/work/musl-build/static-musl.specs \
  -std=c11 -Wall -Wextra -Werror -Os -mcpu=cortex-a9 -mfpu=vfpv3 -mfloat-abi=hard \
  -static -Wl,-z,noexecstack -Wl,-T,build/boot/work/musl-build/linux-static.ld \
  ethernet/probe_ethernet.c -o build/ethernet-board/probe_ethernet
```

This builds a diagnostic binary, not an SD image. Use a matching PS boot configuration with the selected PL candidate. Physical transceiver qualification remains outstanding for both toolchains. PS Ethernet and the existing DMA bring-up path are independent of PL GTX qualification.
