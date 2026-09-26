# Z-7030 timing calibration, 2026-09-25

The opt-in XLS estimator improves the fixed-point update kernel's limiting setup period **10.615→7.909 ns**, at unchanged four-cycle latency and II=1. It also worsens one composed test. Native BRAM timing now includes previously omitted boundaries in six measured configurations; registered DSP timing remains incomplete. **No board clock is qualified.**

> The [application campaign](xc7-timing-application-2026-09-26.md) supersedes this calibration table and its operation-level accuracy statistics. Its stricter post-route audit confirms the eighteen earlier composed-kernel and primitive comparisons.

[Usage and reproduction](../docs/timing-model.md) · [Compact evidence](xc7-timing-model-2026-09-25.json) · [Calibration](../timing_model/xc7_7030.tsv) · [Preregistered hypotheses](../yap/timing-model/hypotheses.md)

## Method

Target `xc7z030sbg485-1`; XLS `20bf86d9c9e90f9df380a0280a5973ce0c33a59a`; native Yosys `0.63+173` (`66306a8ca-dirty`, binary hash retained), `synth_xilinx -abc9`; Vivado 2024.2 build 5239630. Vivado imports the mapped EDIF without resynthesis. Every primitive is preserved; pin connectivity and explicit parameters are checked before placement. Single-operation probes have explicit fabric launch/capture registers, excluding DSP register absorption. External I/O paths are excluded; internal clocks, timing coverage and complete routing are required.

Measure 175 operation probes, including six wire-only reversal controls. Widths 4/8/16/32/64 train 28 operation/fan-in families; 24 is held out. One additional row measures the fixed-point kernel's exact 37×39→76-bit constant multiply. Linear interpolation uses a monotone envelope and never extrapolates above the largest sample. The 28 held-out non-wiring cases are excluded from fitting. Operation costs subtract launch-register clock-to-Q; register setup remains separate.

Each circuit has one implementation. These characterize this mapping, part and placement flow, not a distribution over placements. The wire-only controls are excluded from fitted operation costs and accuracy statistics.

## Prediction accuracy

Error is **predicted minus measured**, in ps. Negative values are optimistic. Underestimation and overestimation magnitudes are reported separately, because a near-zero mean can conceal unsafe optimism.

| Held-out statistic | Cell-only | Including local routing |
|---|---:|---:|
| Mean error | +19.11 | −27.04 |
| Population variance (ps²) | 8,807.38 | 16,730.25 |
| Mean absolute error | 63.82 | 95.39 |
| Error range | −256…+184 | −397…+253 |
| Underestimates / 28 | 4 | 16 |
| Mean underestimate magnitude | 156.50 | 107.12 |
| Worst underestimate | 256 | 397 |
| Overestimates / 28 | 12 | 11 |
| Worst overestimate | 184 | 253 |

The routed model therefore cannot be treated as a conservative clock bound. Future qualification should prioritize its underestimated delays and test additional placements; raising all costs indiscriminately does not necessarily improve stage balance.

## Scheduling results

Same optimized IR, three requested XLS stages, flopped inputs/outputs, resulting latency four cycles and II=1. Both schedules pass 203 streamed vectors per mixed-width test and 253 signed/extreme vectors per fixed-point kernel: **1,724 checked results**. The table reports periods implied by worst setup slack at a requested 5 ns, for the retained placements—not closed-board frequencies or independently optimized timing targets.

| Circuit | Unit period (ns) | Calibrated period (ns) | Change | LUT cells, unit→calibrated | FFs, unit→calibrated |
|---|---:|---:|---:|---:|---:|
| Mixed arithmetic, 16 bits | 3.699 | 5.055 | +36.7% | 77→77 | 128→144 |
| Mixed arithmetic, 24 bits | 6.842 | 4.960 | −27.5% | 161→138 | 233→185 |
| Mixed arithmetic, 32 bits | 7.905 | 6.260 | −20.8% | 215→215 | 305→337 |
| Fixed-point weighted update | 10.615 | 7.909 | −25.5% | 196→195 | 235→166 |

DSP counts remain 1/2/3/6 respectively. The 24-bit case increases SRLs 24→48; other SRL counts are unchanged. LUT counts are mapped cells, not occupied physical LUT sites.

The 16-bit regression exposes a limitation of independent node costs: the unit schedule groups arithmetic that Yosys can fuse into a DSP; the measured model isolates the expensive multiply and crowds the remaining arithmetic/control into the final stage. Conservative individual costs can still produce a poorer schedule. Keep the model opt-in until DSP fusion/register absorption and composed-stage balance are better represented. The fixed-point improvement is useful but still does not meet a 5 ns period.

## Native timing coverage

The native comparison uses nextpnr `68aeeb39f92e39bfb239c7e4a44dd93451fc1889`, existing LUT correctness/endpoint-audit patches, identical Yosys maps and seed 1. Only the experimental BRAM timing model differs.

Measured RAM clock-to-output is 2.080 ns without an output register and 0.748 ns with it. Conservative setup is 0.479 ns for SDP and 0.625 ns for the measured TDP configuration; maximum hold is 0.384 ns. The model is gated to the exact part and measured modes, with worst rise/fall/data/control costs. All required RAM endpoints become covered.

| Fixture | Previous partial MHz | With RAM arcs, partial MHz |
|---|---:|---:|
| RAMB36 TDP, unregistered / registered | 823.05 / 823.05 | 279.88 / 446.23 |
| RAMB36 SDP, unregistered / registered | 803.86 / 803.86 | 294.64 / 473.71 |
| RAMB18 SDP, unregistered / registered | 839.63 / 839.63 | 301.66 / 508.65 |
| RAM feeding DSP | 144.05 | 95.95 |

This drop corrects an omission; it is not a slowdown of the hardware. Logic-only timing remains 209.78 MHz and unregistered DSP timing remains 119.30 MHz. Registered DSP still reports an invalid 943.40 MHz while failing endpoint coverage; this limitation is retained visibly. Internal hard-block period/pulse-width checks, clock relationships and hold closure still need work.

Yosys's ABC9 library is unchanged. Tiny intrinsic LUT delays from SDF are not interchangeable with its mapping costs, which account for physical mux/routing structure differently. The useful native correction here is restoring measured RAM boundaries in nextpnr, not replacing ABC9 numbers without a validated mapping comparison.

## Validation and retained evidence

Ten import/model unit tests, ten installed-XLS acceptance/rejection cases, streamed RTL comparisons, ten native before/after fixtures and the native C++ test pass. Source-contract checks and Dialyzer pass. Existing defaults and CI workflows are unchanged; no full application route or throughput run was needed for these bounded model comparisons.

Compact JSON retains operation measurements, held-out predictions/errors, mapped-netlist hashes, primitive-mode/SDF evidence, native coverage results, pipeline area and tool hashes. Full reports, SDF and manifests are retained locally. EC2 measurements are complete; model use and further analysis need no running vendor host.
