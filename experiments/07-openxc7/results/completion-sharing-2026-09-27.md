# Shared reduction completion

Selecting completion inputs before calling the actor callback halves small-core DSP use, reduces LUTs by 4.3%, and preserves every observed interface cycle. Routed timing has **not** been measured for this revision.

The fixture remains the two-plane 2×1 attribution core: four phi actors, four syndrome actors and four shared schedulers, without transport. The 1 µs target belongs to the larger **2×4 qubit patch**; this result does not establish its area or step rate.

| Complete core | Selective baseline | Shared completion |
|---|---:|---:|
| DSP48E1 | 56 | 28 |
| LUT1–6 | 33,343 | 31,920 |
| FF | 21,774 | 21,698 |
| CARRY4 | 754 | 588 |
| RAMB18 / RAMB36 | 44 / 8 | 44 / 8 |
| Normal cycles/step | 79.25 | 79.25 |
| Output-stalled cycles/step | 79.833333 | 79.833333 |
| XLS stage 0 estimate (ns) | 10.092 | 10.092 |
| XLS stage 1 estimate (ns) | 10.046 | 9.888 |

## Mechanism and prediction

Previously, internal completion invoked `shared_machine_complete` directly while aggregate delivery invoked it inside `shared_machine_aggregate`. XLS inlined two callback trees. The generator now validates/applies the aggregate, selects its resulting machine or the internally completed machine, and calls completion once. Invalid aggregates preserve actor data/reduction state and record the same failure; internal requests retain priority.

The [preregistered prediction](../yap/timing-next-cones.md#architecture-first-revision) was four→two reciprocal products per executor, or 48→24 reciprocal DSPs across both executors. That happened. The conservative total of 32 assumed the other eight DSPs would remain; they also halve because the tie-selection multiplication belonged to the duplicated callback. No new register stage, transaction or capacity is introduced.

The maximum XLS estimate does not improve. Removing parallel copies does not shorten the surviving three-DSP arithmetic chain. Fewer cells may change placement, while selecting operands earlier may worsen input timing; neither effect has been measured. The baseline's vendor period was 15.151 ns, but applying it to the candidate would assume the conclusion we need to test. Native timing still lacks the baseline's registered-DSP coverage.

## Validation and reproducibility

- The SAT proof compares every executor-result bit against independent pre-sharing dispatch for arbitrary machine/request bits in the count/member reduction fixture. It includes failure codes, invalid aggregates, internal precedence and entry backpressure. Deliberately removing slot validation produces a counterexample.
- Both normal and stalled application runs match all 161 BEAM-oracle events. A separate 12,000-cycle comparison, with long stalls and reset, matches ready/valid and valid output data cycle for cycle: 318 X and 346 Z frames.
- EUnit: 1,180 tests pass. Dialyzer, source-contract checks and local golden regeneration pass. UTM was unreachable; DSLX interpreter/JIT regressions remain assigned to CI.

`completion_experiment.py` replays the frozen source bundle with only aggregate acceptance and executor dispatch changed, then substitutes only the newly scheduled executor into the selective baseline. All surrounding RTL and executor ports remain identical; both use two stages, II=1, the same calibrated table and frozen compiler. Yosys mapping uses identical tools and settings. The [replay instructions](../timing_chains/README.md#actor-boundary-experiments), [summary](completion-sharing-2026-09-27/summary.json), source patch, compiler commands and mapping manifests retain identities and evidence. Counts exclude the timing harness.

## Remaining campaign

1. Measure matched routed timing for shared completion and establish the actual 2×4 workload; retain all competing arithmetic, RAM and control families.
2. Measure per-round operand/commit/publication feedback, then prototype an exact staged numerical recurrence with one owner of local working state. Inspect XLS partial-product support before introducing a lowering mechanism.
3. Change actor/mailbox selection so availability need not wait for the selected address. Preserve ordering and round-robin semantics; prove selection equivalence before mapping.
4. Extend XLS block/codegen optimization to remove receive zeroing only where invalid data is unobservable. This requires compiler-side observability analysis and proof, not a global receive-gating switch.
5. Profile aggregate stalls and evaluate occupancy-only ready buffering if control remains limiting; account for full-buffer recovery bubbles. Retain the actual 17-way router selector experiment separately.

These remain open in the Roadmap and original hypothesis register. This area result completes the first structural experiment, not the timing campaign.
