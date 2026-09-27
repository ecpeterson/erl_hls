# Explicit registers inside reciprocal division

The isolated divider now maps to **one DSP per combinational path**, down from three. Its covered native routed period improves **43.5–44.3% across two seeds**. This meets the [registered structural expectation](../yap/staged-reciprocal.md); retain it as a path-shortening candidate even while other core paths prevent an overall clock gain. No decoder step-rate improvement has been measured.

| Isolated signed-37 divide-by-twelve | Whole product, then delay | Split products and recombination |
|---|---:|---:|
| Maximum serial DSPs between fabric registers¹ | 3 | 1 |
| DSP48E1 | 6 | 4 |
| LUTs | 59 | 350 |
| Fabric FFs² | 108 | 323 |
| CARRY4 | 24 | 26 |
| Enabled cycles of latency | 3 | 3 |
| Initiation interval | 1 | 1 |

¹ Conservative cell-connectivity count; not a delay estimate. ² All DSP registers are disabled in this accepted comparison. Totals exclude the physical measurement harness. The candidate uses `xilinx_dsp.multonly` to preserve its explicit registers; the reference retains ordinary DSP mapping. This policy difference is part of the experiment, not a global application setting.

The candidate splits the numerator into 24/13-bit limbs and the reciprocal into 17/17/4-bit limbs. Six independent products are registered; two smaller constant products become fabric logic. Carry-save compression produces two registered rows, followed by a carry-propagating sum and quotient slice. Rounding remains nearest with ties away from zero; precision and divisor are unchanged. Numerator preparation and output saturation are outside this probe.

Both wrappers have three stages to compare register placement. The reference pads the output of the original combinational divider with registers; it is **not** an optimally scheduled three-stage executor. Consequently, equal wrapper latency does not establish unchanged application latency. Integration must account for dependent recurrence rounds and the existing executor schedule.

The [retained summary](staged-reciprocal-2026-09-27/summary.json) records source/tool identities, mapped cells and generated/mapped RTL simulation witnesses. Each of the four runs checks 161,506 outputs, with 11,597 stalled cycles and 19 reset assertions. Inputs cover signed extremes, half ties, limb boundaries and deterministic random values. The integer oracle is independent of reciprocal multiplication. Reset intentionally discards pending values; these tests are not exhaustive correctness claims. Source contracts and Dialyzer also pass.

| Native routed period, ns | Reference | Staged |
|---|---:|---:|
| Seed 1 | 15.497 | 8.753 |
| Seed 2 | 15.399 | 8.570 |
| Mean | 15.448 | 8.661 |
| Population variance, ns² | 0.00239 | 0.00837 |
| Best / worst | 15.399 / 15.497 | 8.570 / 8.753 |

These are two descriptive placement samples, not a confidence interval. Both use the same calibrated native tool, part, 5 ns target and preserved launch/capture boundaries; all required endpoint checks pass. Neither meets 5 ns. Seed 1 changes from three serial DSPs followed by two carry chains (10.2 ns logic, 5.3 ns routing) to one DSP between launch/product registers (5.6 ns logic, 3.2 ns routing). The shorter multiplication stage still limits this isolated pipeline; it is not yet evidence of its rank inside the complete core. The [standard path report](staged-reciprocal-2026-09-27/native-paths.md), [manifest](staged-reciprocal-2026-09-27/native-manifest.json) and [statistics](staged-reciprocal-2026-09-27/native-summary.json) retain the distinction between rounded path text and periods derived from reported frequency.

Use [the reusable runners](../timing_chains/README.md#exact-rounded-division) to reproduce both screens. The [vendor inputs](staged-reciprocal-2026-09-27/vendor-inputs.tar.gz) are also ready for the existing physical batch workflow; no EC2 run was used here. Next, include numerator preparation and saturation, then integrate the cut and measure its application path ranking and added recurrence latency. Keep path improvements while tackling neighboring limits; judge the eventual combination by step time.

The initial mapped-reference simulation exposed a separate installed-toolchain issue: extracting an enabled three-register delay line produced `SRL16E` cells with `CE=1`, dropping stalls. The [minimal input and mapping evidence](staged-reciprocal-2026-09-27/srl-enable.json) reproduce it with both ABC and ABC9; `-nosrl` retains the enable. The final comparison uses `-nosrl` on both variants, matching the existing complete-core flow. This identifies a local mapping failure, not its upstream cause; isolate the binary/support-file versions before reporting it upstream.

The first staged mapping also failed after DSP-register absorption, reproduced with [two registered signed products sharing an operand](staged-reciprocal-2026-09-27/dsp-registers/input.v). Both ABC and ABC9 fail the candidate simulation; preserving registers with `xilinx_dsp.multonly` passes. The smaller packed area (304 LUTs, 195 FFs, four `MREG`s) is rejected evidence, not a usable result. Retain the [failure](staged-reciprocal-2026-09-27/rejected-dsp-packing-simulation.log) and [mapping evidence](staged-reciprocal-2026-09-27/dsp-registers.json) for a separate toolchain investigation before using absorbed registers.
