# TEF1002 SFP status probe

This standalone SD candidate checks communication with the **TEF1002-03-A carrier controller** and reads SFP module presence, loss-of-signal and transmitter fault. It uses ordinary PL pins on the **TE0715-05-71C33-A**, so the missing GTX configuration data does not block its bitstream. It can also read the SFP identification EEPROM. It does not exercise the serial data link or PCS/MAC.

The probe sends non-activating RGPIO frames. The carrier retains its default power and SFP control behavior; the probe cannot select transmitter disable or rate. Start with a cold boot, since replacing an existing design that owns RGPIO would release that design's controls. RGPIO's marker identifies the protocol, not the carrier firmware revision.

## Prepare and run

First prepare the [native tools](../README.md), [base boot candidate](te0715-boot.md) and [25-MHz FSBL](te0715-regsvc.md). Confirm **J4 selects 1.8 V for VCCIOA / module bank 13** before programming. The SFP need not be inserted for the first communication check. For EEPROM reads, leave the FMC and CRUVI connectors empty, insert the cable/module at least 300 ms before the read, and keep it inserted until completion.

From `experiments/07-openxc7`:

```sh
bash run_sfp_probe.sh
python3 prepare_sfp_probe.py build/boot/candidate build/routed-dma/fsbl \
    build/sfp-probe build/boot build/sfp-probe/candidate
python3 test_sfp_probe.py --candidate build/sfp-probe/candidate
```

The packager requires a new output directory. It reuses the existing native compiler, musl and Bootgen under `build/boot`; it checks source/image hashes, the 25-MHz FSBL, all four BOOT.bin partitions, Linux FIT payloads and static ARM executables. The optional QEMU check exercises Linux/UIO discovery and the diagnostic's fake-register tests; it does not connect QEMU to the RGPIO RTL.

Copy the candidate's `BOOT.bin`, `boot.scr`, `image.ub` and `probe_sfp` to an otherwise empty FAT SD partition. Use the [base boot procedure](te0715-boot.md) and retain the UART log. In Linux:

```sh
modprobe uio_pdrv_genirq of_id=generic-uio
cat /sys/class/uio/uio*/name
cat /sys/class/uio/uioN/maps/map0/{addr,size,offset}
# Select erl-hls-probe: address 0x40000000, size 0x1000, offset 0.
./probe_sfp /dev/uioN
./probe_sfp /dev/uioN --eeprom
```

The diagnostic verifies the SFP7 identity, two distinct returned challenge bytes and an advancing frame counter. It then prints `present`, `los` and `tx_fault` from one atomic status word. An absent module or asserted LOS/fault is a valid observation, not a communication-test failure. A failed echo directs investigation toward clock/reset, voltage, wiring or firmware before interpreting those flags. The challenge byte is restored on success and ordinary error returns; checking RGPIO preserves the I²C command bits. With a passive DAC, LOS/TX-fault may be tied low and do not establish link health.

## Read cable identification

`--eeprom` first checks carrier communication and presence, then reads bytes 0–95 from 7-bit address `0x50` (SFF's `A0h`). It sends only the offset-pointer write and repeated START needed for the read; it does not write EEPROM data or access module controls. The report contains bounded ASCII vendor/part/revision/serial/date fields, raw capability codes, the advertised nominal rate and all 96 bytes as hex. Both [SFF-8472](https://members.snia.org/document/dl/25916) checksums must pass before fields are reported. An advertised nominal rate does not establish a minimum rate or compatibility with our link.

The carrier forwards SCL to every management bus, drives only the selected bus's SDA, and returns the AND of all SDA inputs. This probe fixes selection to SFP. There is no SCL feedback: clock stretching and multiple controllers are unsupported. An unrelated device holding SDA low can therefore block identification. Each line change waits at least 5 µs, keeping the clock below 100 kHz; Linux scheduling may make a read slower.

Use one diagnostic process with exclusive UIO access. NACKs and observed removal abort the read; ordinary completion/error attempts STOP and leaves commands idle. A stuck-low wire can prevent the device from recognizing STOP. A stuck SDA or non-idle initial command fails without bus-clear clocks, which could turn an interrupted pointer transaction into an EEPROM write. If the diagnostic is killed mid-transfer, cold-boot the probe and power-cycle/reinsert the module as needed before retrying. Reset or module removal is not a coherent EEPROM snapshot. The probe does not change carrier power to recover a bus.

## Register and wire contract

All accesses are aligned 32-bit words in the GP0 page. The common [PS probe AXI rules](../../../docs/zynq-ps-probe.md) apply.

| Offset | Access | Meaning |
| --- | --- | --- |
| `0x00` | R | `0x53465037` (`SFP7`) |
| `0x04` | R | ABI 2 |
| `0x08` | RW | Challenge 7:0; bit 8 drives SCL low, bit 9 drives SDA low; other bits have no pin effect |
| `0x0c` | R | FCLK cycle counter |
| `0x10` | R | Accepted register writes |
| `0x14` | R | Latest RGPIO word: marker 31:28=`A`, TX fault 19, module absent 18, LOS 17, echo 7:0 |
| `0x18` | R | Completed RGPIO transactions, including invalid responses |
| `0x1c` | R | Wire-clock quarter-period in FCLK cycles: 25 |
| `0x20` | R | Bit 0: synchronized aggregate SDA; other bits zero |

Control reset value zero drives SCL high and releases SDA. Use the matching ABI-2 diagnostic and image; the original status-only ABI-1 pair is incompatible. Counters wrap at 32 bits. At 25-MHz FCLK, RGPIO runs at 250 kHz with a 128-µs frame period. A completed frame alone does not prove communication: verify the marker and a changed echo. RGPIO has no CRC, and this liveness check does not qualify electrical integrity or identify firmware. Read individual status words atomically; separate MMIO reads are not a common-time snapshot.

The constraints follow the [module schematic](https://www.trenz-electronic.de/trenzdownloads/Trenz_Electronic/Modules_and_Module_Carriers/4x5/TE0715/REV05/Documents/SCH-TE0715-05-71C33-A.PDF) (pages 6 and 8) and [carrier schematic](https://www.trenz-electronic.de/trenzdownloads/Trenz_Electronic/Modules_and_Module_Carriers/4x5/4x5_Carriers/TEF1002/REV03/Documents/SCH-TEF1002-03-A.PDF) (pages 5 and 9). The mating connectors swap odd/even contacts:

| PL signal | Carrier / JB1 | Module / JM1 | FPGA pin |
| --- | --- | --- | --- |
| RGPIO receive | `A_01_N` / 35 | `B13_L6_P` / 36 | U13 |
| RGPIO transmit | `A_02_P` / 39 | `B13_L4_P` / 40 | V11 |
| RGPIO clock | `A_02_N` / 41 | `B13_L4_N` / 42 | W11 |
| I²C SCL command | `A_00_P` / 36 | `B13_L5_P` / 35 | U11 |
| I²C SDA release command | `A_00_N` / 38 | `B13_L5_N` / 37 | U12 |
| I²C SDA return | `A_01_P` / 37 | `B13_L6_N` / 38 | U14 |
| I²C select bit 0 | `A_06_N` / 49 | `B13_L8_P` / 50 | AA12 |
| I²C select bit 1 | `A_07` / 34 | `B13_L3_N` / 33 | W13 |

## Qualification and next steps

`test_sfp_probe.py` checks the reader against a pinned, GHDL-translated Trenz slave, before and after Yosys mapping. It covers all SFP flag combinations, changing echoes, stuck return wires and reset with the slave left running. Every received control nibble is checked against accidental activation. An independent edge-driven EEPROM peer checks the host command sequence, all 96 bytes, final NACK, errors and absence of data writes. GPIO direction, selection, reset and SDA synchronization are checked before/after mapping. These simulations do not qualify the carrier's installed firmware or PCB delays. [Recorded build evidence](../sfp-probe-result.json) retains source/image identities and checks completed before hardware access.

Before enabling transmitter/rate controls, confirm the installed carrier firmware's bit map and the required values of the other outputs activated by RGPIO. The [carrier documentation](https://wiki.trenz-electronic.de/display/PD/TEF1002+SC+CPLD+MAX10) disagrees with itself about write bits 20–22. Published REV03 source assigns them to SFP rate/disable controls, while the REV04 download provides only a programming image. The read flags and echo have an inspectable reference; live writes need that additional qualification. Further Ethernet preparation is a simulated 1000BASE-X PCS/MAC, followed by GTX configuration and physical link tests. The carrier I²C mapping follows its published documentation and must still be confirmed against the installed controller.
