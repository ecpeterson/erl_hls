# Actor boundaries and exact arithmetic

The tested register boundaries and two-cycle actor recurrence do not improve step time. A bit-preserving arithmetic rewrite does reduce the isolated bulk update from six DSPs to four; its application timing awaits one new calibration shape. No production default changes.

This continues the [architecture experiment](architecture-2026-09-26.md) on the same two-plane 2×1 fixture: four phi actors and four syndrome actors. All boundary experiments derive from its dedicated-actor IR, with two requested pipeline stages, compact FIFOs, unsplit next-value selects, the same calibrated table and a 40 ns physical target. The new routes use seed 1. Native timing remains a partial-model diagnostic, not a qualified board clock.

## Timing and latency

“Actor II2” permits two cycles on phi actor state feedback; other procs retain their one-cycle limits. “Eager merge” is a work-conserving replacement for the dedicated benchmark adapter's alternating-poll egress. It preserves blocked grants and input ordering without adding payload storage.

| Dedicated variant | XLS max stage (ns) | Placement estimate (ns) | Routed period (ns) | Cycles/step | Period × cycles (µs) |
| --- | ---: | ---: | ---: | ---: | ---: |
| Original reference | 27.936 | 70.922 | 56.054 | 64.500 | 3.615 |
| Register collector aggregate output | 27.936 | 60.205 | 54.230 | 92.000 | 4.989 |
| Register individual actor aggregate input | 27.936 | 61.275 | 53.505 | 92.000 | 4.922 |
| Actor II2 | 15.803 | 61.538 | 53.879 | 90.000 | 4.849 |
| Eager merge | — | 68.166 | 55.371 | 62.500 | 3.461 |
| Actor II2 + eager merge | — | 57.013 | 51.600 | 76.583 | 3.952 |
| Actor II2 + registered collector batch input | 15.803 | 55.928 | 51.020 | 91.958 | 4.692 |
| Actor II2 + registered batch input + eager merge | — | 61.387 | 49.677 | 90.000 | 4.471 |

The eager-merge rows include a handwritten RTL leaf, so they have no whole-design XLS stage estimate. Their other proc schedules remain those of the corresponding generated variant. Collector registration plus eager merge takes 76.5 cycles/step; it was not routed because this recovered latency was insufficient to justify another physical run. Relaxing only the two numerical field feedback arcs produced identical schedules and byte-identical RTL: no map or route was needed.

The last combination cuts the seed-1 period by 11.4% but adds 39.5% more cycles, making diagnostic step cost 23.7% worse. Eager merge alone improves this one-seed cost by 4.3%; that is an adapter observation, not a robust placement or backend improvement claim. None displaces the retained default-split shared reference from PR #177: **39.667 ns × 79.25 cycles = 3.144 µs**. That reference uses a different optimizer setting and is not a matched architectural comparison. The preceding report retains the matched shared/dedicated two-seed comparison and its distribution statistics. These follow-ups use single seeds to reject clear losses; they cannot estimate placement variance.

| Dedicated variant | LUTs | FFs | DSPs |
| --- | ---: | ---: | ---: |
| Original reference | 34,745 | 18,220 | 112 |
| Register collector output | 35,596 | 19,104 | 112 |
| Register actor input | 35,056 | 19,400 | 112 |
| Actor II2 | 35,147 | 21,356 | 112 |
| Eager merge | 34,591 | 18,157 | 112 |
| Actor II2 + eager merge | 34,515 | 21,293 | 112 |
| Actor II2 + registered batch input | 35,385 | 22,948 | 112 |
| Actor II2 + registered batch input + eager merge | 35,602 | 22,885 | 112 |

All these dedicated cores use no RAMB primitives. Counts exclude the physical timing harness.

## Why the boundaries missed

The collector and actor-input registers were predicted to reduce the period to 40–48 ns. They isolate their intended interfaces, but leave enough arithmetic and control after the register to require 53.5–54.2 ns. The collector-output variant's path starts at the new FIFO tail register, crosses demultiplexing and actor arithmetic, and ends in actor state: 20.2 ns logic plus 34.0 ns routing. The actor-input variant instead exposes an actor failure-state-to-arithmetic path: 21.4 ns logic plus 32.1 ns routing. Neither delivers the clock gain needed to repay repeated feedback latency.

The II2 hypothesis predicted a 16–20 ns actor stage, 40–45 ns routed period and 65–75 cycles/step. Its actor stage does fall from 27.936 to **14.514 ns**; the largest remaining proc stage is 15.803 ns. However, a composed actor-accumulator-to-collector-enable path replaces arithmetic as the routed limit: **3.8 ns logic plus 50.1 ns routing**. The actual step needs 90 cycles. All 643 changed node-stage assignments in each phi specialization are audited; other proc schedules are identical. Field-only relaxation leaves even the field writes in stage zero; it did not achieve the desired partial pipeline, and this screen does not establish which additional feedback constraints must be relaxed.

Passive interface monitoring separates a latency artifact from the recurrence cost. The original adapter polls actor inputs on alternate cycles. After collector registration, 1,946 of 1,984 effect batches wait one cycle for that poll, versus 166 in the baseline. Eager merge reduces the registered case from 92 to 76.5 cycles/step, exceeding the predicted 10–14-cycle recovery slightly. It reduces the II2 case from 90 to 76.583 cycles, but that still costs 3.952 µs. The RTL substitution is deliberately confined to this fixture: the frozen XLS compiler rejects the direct DSLX expression's repeated nonblocking receives on one channel.

Registering the II2 actor's reduction-batch publication was predicted to reach 35–42 ns. The original egress then exposes an actor-to-external-event path, ending in the timing harness capture register: 4.1 ns logic plus 46.9 ns routing. With eager merge, the limit returns to collector-to-actor arithmetic, ending at an actor adder pipeline register: 20.5 ns logic plus 29.2 ns routing. Cutting one branch of publication does not isolate the ordinary external-output branch or the opposite aggregate direction. These are measured replacement paths, not evidence that every FIFO should gain a register.

Aggregate monitoring matches all 1,848 complete words through the interfaces. Registration moves every aggregate handoff from zero to one cycle; II2 alone splits them evenly between zero and one. Each actor consumes twelve gather aggregates, one compare aggregate and one flip aggregate per measured decoder step. Repeated feedback handoffs make a small interface delay significant. Effect spacing is recorded separately and is not presented as a causal dependency.

## Arithmetic without reduced precision

For the signed bulk numerator `n = a + 7*b + sum`, preserve ties-away rounding with:

```text
round12(n) = round3((n + (n < 0 ? 1 : 2)) >> 2)
```

The complete input range fits signed 36 bits. Bias addition uses signed 37 bits before the arithmetic shift; the result fits signed 35. Final saturation and Q15.16 precision are unchanged.

| Isolated combinational bulk kernel | DSP48E1 | CARRY4 | LUTs |
| --- | ---: | ---: | ---: |
| Existing rounded division by 12 | 6 | 42 | 206 |
| Biased shift, then rounded division by 3 | 4 | 59 | 187 |

The six-to-four DSP prediction succeeds. Extra carry logic could still erase a timing benefit. Four integer SMT checks prove the rounding identity, intermediate bounds, implemented reciprocal expressions and input-sum bound; an intentionally wrong common bias yields a counterexample. Both compiled circuits match an independent integer reference on 158,444 vectors, including extremes and half ties. This combines arithmetic proofs with RTL regression; it is not a full RTL equivalence proof.

The entire optimized application has two uncovered operations, both the new `smul_const_35_37_71_45812984491` shape. The existing center-update products remain covered. Calibrated codegen correctly rejects the missing shape; no unit-model fallback or invented sample is used. Local probes are prepared for that product and for both complete kernels, with 130 preserved input/output registers per kernel and unregistered DSPs. Next: measure them in Vivado, fit the new entry, re-audit scheduling-normalized application IR, then compare equal-latency schedules and whole-core timing. EC2 was not used in this follow-up.

## Validation and reproduction

Every application candidate in the table matches the full 161-event BEAM witness under normal and stalled outputs, plus a 12,000-cycle comparison of per-actor output prefixes, stability, long stalls and reset. These checks permit cross-actor reordering and do not prove all decoder states. The eager leaf also passes directed blocked-grant, late-arrival, fairness and reset tests. Completed routes pass required FF/DSP endpoint checks; endpoint presence does not qualify native delay values. Source-contract tests/checks and Dialyzer pass.

The [runners](../timing_chains/README.md#actor-boundary-experiments) retain exact derivations and reject changed baseline/tool fingerprints. [Measurements](actor-boundaries-2026-09-26/measurements.json) include commands, schedule audits, physical inputs, counts and behavioral results; named critical paths sit beside them. [Handoff evidence](actor-boundaries-2026-09-26/handoffs.json), [arithmetic evidence](actor-boundaries-2026-09-26/arithmetic.json), [proof](actor-boundaries-2026-09-26/finite-width.smt2) and the [remaining vendor batch](actor-boundaries-2026-09-26/vendor-plan.json) are separate. Predictions, including adaptive trials, were recorded [before implementation](../yap/actor-boundaries-2026-09-26.md).
