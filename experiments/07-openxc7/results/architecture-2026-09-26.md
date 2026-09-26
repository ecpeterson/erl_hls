# Architecture and fusion controls on the four-phi core

Removing shared execution reduces cycle count, but does not remove the longest composed control/arithmetic paths. The measured fusions repay their latency savings in the first routed controls. No compiler default changes in this experiment.

The proposed local arithmetic and boundary trials are now complete in [Actor boundaries and exact arithmetic](actor-boundaries-2026-09-26.md). Registering the selected interfaces and relaxing actor recurrence did not improve step cost; exact arithmetic factoring reduced isolated DSP use and awaits vendor calibration.

The fixture has two phi sites per plane, both X/Z planes, and four deterministic syndrome sources. The dedicated variant replaces four two-actor shared services with eight dedicated executors, register state and ordinary mailboxes. It preserves the source-fragment collectors, routing groups, effect-window protocol and callbacks; it also adds per-actor batch buffering. This isolates shared execution, not every cost of topology routing. It is a benchmark adapter, not a generally supported backend.

All variants use two requested stages, II=1, the calibrated XC7 table, compact FIFOs, the same native tool/device database, and a 40 ns physical target. The model rejects the default dedicated lowering's 65-way state-update fan-in, so the matched controls use `--split_next_value_selects=0`. This setting changes hardware: the freshly regenerated default-split reference is byte-identical to PR #177, whose retained 39.67 ns × 79.25-cycle result remains a separate reference, not the baseline for attributing the architectural change.

## Measurements

| Variant | XLS max stage (ns) | Placement estimate (ns) | Routed period (ns) | Cycles/step | Period × cycles (µs) |
| --- | ---: | ---: | ---: | ---: | ---: |
| Shared control | 50.012 | 50.226 / 52.743 | 45.025 / 47.125 | 79.25 | 3.568 / 3.735 |
| Dedicated actors | 27.936 | 70.922 / 67.568 | 56.054 / 55.096 | 64.50 | 3.615 / 3.554 |
| Disable immediate reissue | 50.012 | 45.290 | 45.998 | 93.25 | 4.289 |
| Separate phase entry | 50.012 | 52.274 | 54.054 | 127.25 | 6.878 |
| Register egress | 50.012 | 50.403 | 43.403 | 108.25 | 4.698 |

Slash-separated entries are seeds 1 / 2; other rows use seed 1. The default-split PR #177 reference is 49.870 ns (XLS), 46.598 ns (placement), 39.667 ns (route), 79.25 cycles/step and 3.144 µs. Its area is 33,171 LUTs, 22,008 FFs, 56 DSPs, 44 RAMB18 and 8 RAMB36. The new control is intentionally compiled with the dedicated variant’s optimizer setting; do not attribute the difference from PR #177 solely to shared versus dedicated execution.

| Two-seed diagnostic step cost | Mean (µs) | Population variance (µs²) | Best (µs) | Worst (µs) |
| --- | ---: | ---: | ---: | ---: |
| Shared control | 3.651 | 0.006928 | 3.568 | 3.735 |
| Dedicated actors | 3.585 | 0.000953 | 3.554 | 3.615 |

Dedicated execution is 1.3% worse on seed 1 and 4.8% better on seed 2: a 1.8% mean gain with mixed paired results, not a convincing timing improvement. The 20–40% period-reduction prediction fails.

Periods are partial-model native estimates, not qualified board clocks. Compare period × cycles as a diagnostic cost, not deployed throughput. One-seed controls screen hypotheses; their zero sample variance says nothing about placement sensitivity. The architecture comparison uses two seeds because the first result was within 1.3%.

| Variant | LUTs | FFs | DSPs | RAMB18 / RAMB36 |
| --- | ---: | ---: | ---: | ---: |
| Shared control | 36,571 | 23,736 | 56 | 44 / 8 |
| Dedicated actors | 34,745 | 18,220 | 112 | 0 / 0 |
| Disable immediate reissue | 37,180 | 23,736 | 56 | 44 / 8 |
| Separate phase entry | 36,808 | 23,834 | 56 | 44 / 8 |
| Register egress | 37,118 | 25,174 | 56 | 44 / 8 |

Every completed variant matches the entire 161-event BEAM witness with and without output stalls. A separate 12,000-cycle comparison checks per-actor event prefixes, output stability, prolonged stalls and reset. These are bounded regressions, not proofs of every decoder state. All completed routes pass explicit FF/DSP endpoint audits, plus RAM endpoints where present; the native DSP cascade and other coverage limitations still apply.

## Why the predictions missed

The dedicated actor cuts the largest XLS per-process estimate from 50.012 to 27.936 ns, but its own execution stage is longer than the shared executor's 14.886 ns. Its routed seed-1 path combines collector comparisons, channel handoff, a three-DSP path, rounding/saturation and actor state update: 23.5 ns logic plus 32.5 ns routing. Separate per-process scheduling estimates do not bound this composed path.

The matched shared control is limited by retirement/output-readiness logic feeding a collector clock enable: 3.8 ns logic and 41.3 ns routing. The last enable net alone costs about 10.2 ns. Disabling immediate reissue leaves other retirement/admission dependencies and broad enables intact. Separating phase entry doubles phi state reads (1,988→3,972 in the unstalled witness) and leaves the largest modeled scheduler stage unchanged. Neither realizes its predicted period saving.

Registering egress was predicted to cost at most 10% more cycles; it actually costs 36.6%. Interface profiling finds identical counts/order through 992 batch handoffs per plane, each moving from zero to one cycle of handoff delay. The resulting feedback latency adds 29 cycles per step without additional state/mailbox reads. There are many more handoffs per step than the initial estimate allowed for. The routed period is 43.40 ns, so period × cycles is 31.7% worse than the matched seed-1 control.

The magnitude-rounding control cannot be scheduled with this calibrated table: four unsigned 38×38→76-bit multiplies lie outside coverage. No unit-model fallback is used for a physical comparison. The dedicated default-lowering gap and this arithmetic gap are retained in the evidence, along with the rejected/failed hypothesis rather than a fabricated timing estimate.

## Narrower arithmetic and next experiments

An isolated bulk-recurrence mapping uses six DSPs at 32 or 31 bits and four at 30/29/28/24/20 bits. At 16 bits it uses two, and at 12 bits one. Q15.14 therefore crosses a useful threshold while preserving Q15.16's integer range, but quadruples the quantization interval. These counts exclude the rest of the decoder and do not establish timing or numerical adequacy.

There may be a better first arithmetic experiment: preserve Q15.16 and factor the rounded division by 12. For arithmetic right shift and ties-away rounding, `round12(n) = round3((n + (n < 0 ? 1 : 2)) >> 2)`. The four-neighbor recurrence fits signed 36 bits; the shifted value fits signed 35. The [integer proof](architecture-2026-09-26/divide12-factor.smt2) checks the identity and range bound. It does not test a DSLX implementation or mapping. Prediction: four rather than six DSPs for the bulk recurrence, unchanged step cycles, and a possible 5–15% improvement when arithmetic limits timing; bias/carry logic could erase it. Its new constant-product shape also needs a matching calibration sample or a validated general estimator before a calibrated pipeline comparison; correctness and isolated mapping can proceed locally.

Before promoting dedicated actors, test allowing a two-cycle actor-state recurrence while keeping queues elastic, then test the collector-to-actor register boundary separately. For the two-cycle recurrence, predict a 16–20 ns XLS execution stage, a 40–45 ns native routed period and 65–75 cycles/step; these are hypotheses for the next run. The collector register must be measured separately: the present feedback traffic could add roughly 14–29 cycles/step, requiring a substantial period reduction to pay for itself. The observed egress penalty makes blanket registration unattractive.

Add a whole-block path screen after channel/FIFO materialization, before expensive routing. Track forward data and backward readiness paths across proc boundaries: the per-process XLS maximum gave the wrong ranking here. Then investigate splitting wide scheduler/collector enables at semantic ownership boundaries rather than merely removing fast reissue. These changes should target the measured path; adding placement seeds alone cannot repair it.

Commands, fingerprints, resource counts, schedule estimates, per-seed timing, endpoint audits, trace attribution and unsupported model shapes are in [the evidence](architecture-2026-09-26/measurements.json). Full named paths are retained beside it. Reproduction uses the [architecture runners](../timing_chains/README.md#small-core-architecture-controls); initial predictions are in [the experiment plan](../yap/architecture-2026-09-26.md).
