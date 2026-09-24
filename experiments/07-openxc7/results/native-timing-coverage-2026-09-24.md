# Native timing coverage: 24 September 2026

**The native clock report can improve because a critical path disappears from analysis.** On the multiplier probe, enabling its internal M/P registers changes the reported estimate from 119.30 to 943.40 MHz while removing all 48 connected result ports and 48 A/B input ports from timing analysis. The latter is not evidence of a 943 MHz circuit, nor does the ratio measure the benefit of pipelining.

The [endpoint audit](../timing_coverage/README.md) observes the backend's actual port classes and clock associations. Its six circuits are compile-only diagnostic fixtures, not decoder performance benchmarks. No compiler/application RTL or timing model is changed.

## Measured coverage

| Probe | Reported partial-path MHz | Required endpoints |
| --- | ---: | --- |
| FF logic control | 209.78 | Present |
| BRAM, output register off | 823.05 | BRAM read/write endpoints omitted |
| BRAM, output register on | 823.05 | BRAM read/write endpoints omitted |
| Combinational DSP | 119.30 | Present; combinational delays remain coarse |
| DSP, M/P registers on | 943.40 | DSP input/output endpoints omitted |
| BRAM feeding combinational DSP | 144.05 | BRAM endpoints omitted |

These are one-seed observations at a requested 100 MHz on `xc7z030sbg485-1`. No seed distribution is estimated. The two tools produce identical FASM features, detailed critical paths and clock estimates for each circuit; only version comments may differ. The twelve small routes take 18.563 seconds altogether. Mapping explicitly checks the BRAM output-register and DSP M/P modes: an external fabric register is not accepted as a registered BRAM probe.

“Present” only means the declared ports have the required timing classes and register-clock associations. It does not validate all arcs, delays, hold checks, generated clocks or I/O constraints. Connected-port counts include tied inputs and unused output nets; they are not counts of sensitizable paths.

## Relevance to the decoder

The saved four-phi native placement contains 44 RAMB18s and eight RAMB36s: **all 52 BRAMs have ignored timing ports**. Its 48 DSPs are classified as combinational. This inspection reuses the placement without rerouting or recalculating a frequency. The pinned importer rejects its own saved route encoding; removing only `ROUTING` net attributes permits inspection of the existing cell placements and connected ports. The raw source and audit hashes are retained in the [evidence](native-timing-coverage-2026-09-24.json).

The [retained Vivado reference](../docs/vivado-reference.md) establishes that the missing boundaries matter:

- At the 100 MHz request, the worst reported four-phi setup path starts at a BRAM and traverses arithmetic into an executor register: 17.657 ns data delay, including 11.209 ns logic and 6.448 ns routing. Native analysis excludes its launch boundary. Routing improvement alone cannot fit that measured logic into a 5 ns period.
- At the passing 50 MHz request, the worst path crosses executor/scheduler logic to a reduction-plane enable: 19.291 ns, including 16.718 ns routing. This is a separate control/fanout problem.
- The retained microbenchmark SDF has nonzero mode-specific hard-block delays: BRAM clock-to-output maxima of 2.080 ns without and 0.748 ns with its output register, and 0.383 ns for a registered DSP P output. These support local model development; they are not a complete library or universally applicable constants.

Vivado and native mapping/placement differ. These observations identify missing path classes; they do not isolate timing-model error from placement quality or transfer a vendor frequency to a native route.

## Campaign order

1. Model and validate the RAM boundaries used by the decoder against the retained port/mode data. Require explicit coverage for any newly registered DSP path before comparing its frequency.
2. Compare RAM-to-arithmetic pipeline boundaries and shorter scheduler/reduction control paths. Preserve behavior and measure cycles per step alongside area and modeled path delay; an extra stage can trade clock speed for latency.
3. Establish 100/125 MHz on the representative workload before treating 200 MHz as a practical setting. Keep application and Ethernet clock domains explicit; increasing the application clock does not raise wire bandwidth.
4. Qualify the strongest candidate with complete setup/hold, clock/CDC and interface constraints. A later bounded vendor run can resolve coverage/calibration uncertainties that remain; EC2 was not used here.

## Reproduction and checks

Use the offline-capable build and measurement commands in the [probe guide](../timing_coverage/README.md). Both binaries start from nextpnr `68aeeb39` with the already-tested LUT repairs. The observer patch changes neither placement nor the timing model. The JSON evidence records source/tool/database/constraint/artifact hashes, primitive modes, individual paths and failure examples. Raw probes are retained locally under `build/native-timing-20260924/measurements`.

Validation: six matched routed probes, both native CTest runs, fast endpoint/report tests (including absent clocks, unplaced/missing ports, CLI failure status and mistaken BRAM register mapping), source-contract checks and Dialyzer. Full application simulation and another large route were unnecessary because no application behavior or physical mapping algorithm changed.
