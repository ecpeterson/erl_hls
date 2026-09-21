# Z-7030 vendor reference

The Vivado batch supplies independent configuration and timing evidence for `xc7z030sbg485-1`, plus fallback register, DMA, PRBS and Ethernet images. It never programs hardware. Board clocks, power, DDR, the carrier controller and the physical link still require bring-up. Native development does not need a continuously running Vivado host.

## Reproduce

From `experiments/07-openxc7`, prepare a portable bundle with Python 3.12 or later. Preparation downloads the hash-pinned LiteEth dependencies once; it installs no Python packages. Include `--phi` only when the three generated application RTL files are available:

```sh
python3 vivado/prepare.py build/vendor-bundle --phi /path/to/compiled-profile
```

Transfer the bundle to a licensed Vivado installation supporting the part, source its settings, and run inside the bundle. The recorded batch used Vivado 2024.2 on Linux:

```sh
vivado -mode batch -source build.tcl -tclargs register
vivado -mode batch -source build.tcl -tclargs dma
vivado -mode batch -source build.tcl -tclargs prbs
vivado -mode batch -source build.tcl -tclargs ethernet-loopback
vivado -mode batch -source build.tcl -tclargs ethernet-external
vivado -mode batch -source build.tcl -tclargs micro
vivado -mode batch -source build.tcl -tclargs phi
vivado -mode batch -source build.tcl -tclargs phi 20.0
vivado -mode batch -source wizard.tcl
vivado -mode batch -source simulate.tcl
vivado -mode batch -source simulate.tcl -tclargs ethernet
```

Retain the bundle and `results/`. Each implementation retains checkpoints, SDF, simulation netlist, effective constraints, timing/CDC/DRC reports and tool version. Failed timing leaves reports but prevents a board candidate. The compile-only `micro` and `phi` profiles never emit images. `vivado/evidence.py RESULTS_DIRECTORY` extracts timing, reviewed reset alerts and hard-primitive modes; `test_vivado.py` checks the evidence parser in CI.

Register/DMA profiles require the matching 100-MHz FCLK0 boot configuration; PRBS/Ethernet require 25 MHz. The external Ethernet profile includes both carrier polarity inversions. A generated `.bit` is a PL candidate, not a complete SD image; use the existing [boot workflow](te0715-boot.md) and verify its PS configuration before deployment.

## Clocks and crossings

GTX TXOUTCLK and RXOUTCLK are independent 62.5-MHz timing roots. Each MMCM generates a related 125/62.5-MHz pair; all full/half gearbox paths remain timed. Only arrival at an asynchronous synchronizer's first stage is cut. The PCS ability bus and diagnostic snapshots have settling bounds of 8 ns and 40 ns respectively, in addition to their held-bus handshakes.

The Ethernet CDC report retains six critical alerts for intentional asynchronous reset assertion followed by synchronous release. It also reports the held PCS bus and 96 snapshot bits. These are reviewed structures, not a claim that the report contains no warnings. Unknown data crossings are not waived. The generated core preserves `ASYNC_REG`; RX speed selection uses RX-local negotiated ability, and combinational status/alignment signals are registered before crossing.

## Measured evidence

The [September 21 report](../results/vivado-reference-2026-09-21.json) records exact artifact identities and coverage. The four-phi profile is the same closed application RTL as the preceding native experiment, with four replay cells, both reduction planes, and no transport/debug shell.

| Design | Target | Setup slack | Hold slack |
| --- | --- | ---: | ---: |
| Register probe | 100 MHz | +5.362 ns | +0.108 ns |
| DMA mailbox | 100 MHz | +3.322 ns | +0.069 ns |
| Ethernet | 125/62.5 MHz, 25-MHz control | +1.105 ns | +0.072 ns |
| Four-phi workload | 100 MHz | −7.663 ns | +0.047 ns |
| Four-phi workload | 50 MHz | +0.341 ns | +0.048 ns |

The 50-MHz workload uses 32,942 LUTs, 29,658 FFs, 28 RAMB36s, four RAMB18s and 40 DSPs, including the compile harness. It has no unconstrained internal endpoints or setup/hold/pulse-width failures. This is one implementation, not a frequency distribution or measured application throughput.

The preceding native four-phi route reported 16.52 MHz with incomplete timing coverage. Its mapping and routing differ from Vivado; this comparison does not measure the timing-model error in isolation. Likewise, Vivado Ethernet closure does not qualify the native Ethernet route. The retained microbenchmark exercises both BRAM output-register modes and combinational/pipelined DSPs, supplying mode-specific reference data for improving the native model locally.

Against the previous native Ethernet route, these CDC fixes change occupied physical LUTs from 1,645 to 1,644 and FFs from 1,376 to 1,383, retaining two RAMB36s. The matched single-seed partial estimates change from TX/RX 106.55/123.72 MHz to 122.82/112.28 MHz; they still do not close both 125-MHz targets or establish safe clocks. Vivado's separate Ethernet implementation uses 1,061 LUTs, 1,276 FFs and two RAMB36s.

The vendor-model packet test uses the synthesized MAC/PCS, the actual GTX/MMCM models and a host model driving the existing control/status interface. It verifies checked frame delivery on two attempts separated by stop/reset, with accelerated negotiation and traffic gaps. The PRBS test verifies clean reception and detection of an injected error. Native CI separately covers behavioral/mapped MAC/PCS operation, clock offsets, stalls and recovery; these tests do not establish BER or board operation.

## Configuration evidence

The six [GTX references](gtx-configuration.md) independently locate the selected channel at frame base `0x00442480`, word offset 22, and the common tile at that base, offset zero. Four additional `vivado/refclk.py` references check the bonded reference-buffer controls. All ten are inert references: **never program them**.

Comparison with the final Vivado Ethernet bitstream covers 322 enabled encoded features and the complete 1,933-bit known donor mask, including unset bits. Every enabled feature matches; the only extra known bits are the two native `IBUFDS_GTE2.CLKSWING_CFG` defaults omitted by the writer. The [native assembly flow](gtx-configuration.md) now supplies those defaults and checks three assembled candidates against these references; whole-image semantics and native timing remain unqualified.

The Wizard confirms 1.25 Gbaud from 125 MHz with raw 20-bit data and buffered TX/RX. Its CPLL feedback factors are interchanged but have the same product. Raw PRBS and fabric-encoded Ethernet require different CDR settings ([UG476](https://docs.amd.com/api/khub/documents/SgVweevU5cLv0LyXoCVoPg/content), Tables 4-17 and 4-19); the shared CPLL RXPI setting follows Table 4-11. Reserved settings must not be copied solely because two configurations have the same baud rate. Digital simulation does not qualify the analog channel or DAC.
