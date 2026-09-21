# TE0715 reference-clock startup

The clock-startup SD kits initialize the TE0715 Si5338 before loading the PRBS/Ethernet PL image, then verify it again before handing control to U-Boot. They program volatile registers only; factory NVM is unchanged. The [recorded build](../results/clock-startup-2026-09-21.json) identifies the three retained kits and their software checks. **Physical operation remains unverified.**

## Board and clock contract

Use **TE0715-05-71C33-A on TEF1002-03-A**, with **VCCIO34 set to 1.8 V**, and start from power off. Do not use warm restart or load this FSBL while existing PL logic is active: clock programming stops its consumers. Check carrier supplies and [SFP prerequisites](sfp-management.md) before booting. VCCIO34 is available at module test point TP18 ([module TRM](https://wiki.trenz-electronic.de/display/PD/TE0715+TRM)).

| Signal | Required configuration | Consumer |
| --- | --- | --- |
| Si5338 input IN3 | On-module 25-MHz oscillator | Clock-generator PLL |
| CLK2 | 125 MHz, 1.8-V LVDS | GTX reference on U5/V5 |
| CLK3A | 50 MHz, 1.8-V CMOS | PL bank 34 input K2; unused by these probes |
| CLK0/CLK1 | Disabled | Unused |
| PS I²C1 | MIO48/49, chip address `0x70` | Si5338 control |
| PS FCLK0 | 25 MHz | Probe control interface |

The [exact module schematic](https://www.trenz-electronic.de/trenzdownloads/Trenz_Electronic/Modules_and_Module_Carriers/4x5/TE0715/REV05/Documents/SCH-TE0715-05-71C33-A.PDF), sheets 9, 13 and 15, supplies the wiring and voltage constraints. CLK3's output supply is VCCIO34; CLK2 has a fixed 1.8-V supply. The I²C translator presents 3.3 V to the clock chip. PS CPU/DDR clocks are independent of these outputs. The schematic's `FCLK125` net name does not establish CLK3's programmed frequency.

Factory clock settings vary with module production history; [Trenz's 2024 OTP change notice](https://www.trenz-electronic.de/trenzdownloads/Trenz_Electronic/Modules_and_Module_Carriers/4x5/TE0715/PCN/PCN-20240619%20TE0715-05%20SI5338%20OTP%20Content%20Update.pdf) records changes to output enables and I²C voltage. These kits require Si5338A silicon revision B, record its NVM code, and apply the pinned Trenz 2023.2 profile regardless of its initial contents.

## Boot and readback

The FSBL reports `CLOCK before`, `CLOCK configured`, and `CLOCK handoff`. An initial profile mismatch is allowed; an unreadable or unexpected chip is not. Successful configuration requires masked register readback, input presence, PLL lock, copied calibration and the expected output enables. Any failure prevents the next boot stage. A failed programming attempt also tries to mute outputs and restore register page zero; a broken bus can prevent cleanup. Power off before retrying or restoring an earlier SD kit.

Input and lock waits each allow 1,000 one-millisecond intervals plus I²C costs. PS I²C idle/completion waits each allow 10 ms; failures are not retried. The UART report distinguishes identity, transport, input, lock and verification failures, with the first differing register and any cleanup error. These bounds apply to the clock code, not to the FSBL's other boot operations.

After Linux starts, use the bundled readback client as root:

```sh
modprobe i2c-dev
readlink -f /sys/class/i2c-dev/i2c-0/device
# Require the e0005000.i2c controller in the path, then run from the SD directory:
./probe_clock /dev/i2c-0
```

Use exclusive access to the chip. The client writes only its register-page selector, restores page zero, and checks profile, calibration and live alarms. It does not reprogram clocks or force access past a bound kernel driver. Bus numbering is fixed by this kit's device-tree alias; confirm it if using another image. A passing readback establishes programmed state, **not measured frequency, jitter or signal integrity**. Continue with the separate [PRBS, internal Ethernet and external-link acceptance steps](link-sd.md#board-sequence).

## Rebuild and test

Reuse the [native boot SDK](te0715-boot.md) and retained Vivado images. From `experiments/07-openxc7`:

```sh
python3 test_clock_startup.py
python3 build_clock_fsbl.py
python3 prepare_link_probe.py build prbs \
  build/boot/candidate build/clock-startup/fsbl \
  /path/to/erl-hls-vivado-20260921/release/results/prbs/candidate.bit \
  build/boot build/clock-startup/prbs/candidate
python3 test_link_probe.py --candidate build/clock-startup/prbs/candidate
```

Repeat packaging/testing for `ethernet-loopback` and `ethernet-external`, using their matching bitstreams and new output directories. Copy only the selected manifest's `sd_files` onto the boot SD partition. Earlier kits and FSBLs are preserved; never mix their files.

The builder checks the original vendor table's digest, decodes its integer dividers/electrical settings, and verifies that the compact generated table is unchanged. Programming follows [Si5338 datasheet Figure 9](https://www.skyworksinc.com/-/media/Skyworks/SL/documents/public/data-sheets/Si5338.pdf); masks and calibration registers follow the [reference manual](https://www.skyworksinc.com/-/media/Skyworks/SL/documents/public/reference-manuals/Si5338-RM.pdf). The experiment replaces the vendor board hook and uses a bounded PS register transport.

Ordinary CI runs host tests of the real driver, register model and boot hooks, including every configuration/readback I/O failure boundary, accepted-but-reported-failed writes, stuck buses, missing clocks, failed lock and calibration corruption. Optional ARM/QEMU tests run the same chip/controller models under Linux, check the I²C device and reject non-I²C files. QEMU bypasses FSBL/U-Boot and models neither the physical Si5338 nor the GTX reference clock. Board validation must still retain UART output across repeated cold boots and measure the reference before qualifying the external link.
