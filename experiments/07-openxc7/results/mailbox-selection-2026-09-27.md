# Parallel mailbox selection

Parallel eligibility within the selected mailbox reduces small-core LUTs by **0.46%**, with unchanged observed cycles. It removes one level from phi service-completion dependencies, but leaves the longer reduction-ready dependencies unchanged. The four-level prediction fails. No routed frequency improvement is established.

The fixture is the two-plane 2×1 attribution core: four phi actors, four syndrome actors, four shared schedulers, no transport. The 1 µs target still belongs to the larger **2×4 qubit patch**. This screen does not measure that application's timing or area.

| Complete core | Shared completion (#182) | Within selected row | All rows in parallel |
|---|---:|---:|---:|
| LUT1–6 | 31,920 | 31,774 | 31,757 |
| FF | 21,698 | 21,698 | 21,698 |
| DSP48E1 | 28 | 28 | 28 |
| CARRY4 | 588 | 588 | 588 |
| RAMB18 / RAMB36 | 44 / 8 | 44 / 8 | 44 / 8 |
| Normal cycles/step | 79.25 | 79.25 | 79.25 |
| Output-stalled cycles/step | 79.833333 | 79.833333 | 79.833333 |

## Mechanism and prediction

The old selector folded availability and the first unpostponed position through one loop. The new selector forms a parallel eligibility mask, obtains availability by OR, and selects the first position with a priority grant. Actor arbitration, cursor updates and immediate issue are unchanged; this introduces neither a readiness cache nor a register boundary.

The first candidate additionally computed every actor's choice before selecting the narrow result. Its two-actor core result concealed a replication cost. A subsequent isolated sweep measured the following LUT counts at depth five:

| Actors | Original | Within selected row | All rows in parallel |
|---|---:|---:|---:|
| 2 | 170 | 143 | 137 |
| 8 | 420 | 421 | 672 |
| 16 | 767 | 770 | 1,315 |

**Decision:** retain the existing actor-row selection in generated services. The bank-wide helper remains an explicit alternative for measured experiments; it is not the compiler default. Its 60–71% isolated area increase at larger banks outweighs the small two-actor advantage. These are selector costs, not whole-core percentages. The narrower candidate was measured independently, with no revised nanosecond forecast.

[Experiment A](../yap/timing-next-cones.md#a-compute-mailbox-availability-independently-of-address-selection) predicted unchanged cycles, at least four fewer control levels, and no more than 3% extra core LUTs. Both small-core cycle/area screens pass; neither achieves the structural target. Its tentative 1–2 ns affected-path estimate remains **untested**, not confirmed by these counts.

All paths below launch from the corresponding executor-result FIFO occupancy bit. Counts are conservative mapped primitive dependencies, not routed or sensitizable timing paths.

| Endpoint | Before | Within selected row | All rows in parallel |
|---|---:|---:|---:|
| Phi X actor read address | 12 | 12 | 13 |
| Phi X service stage completion | 22 | 21 | 19 |
| Phi X reduction ready | 23 | 23 | 21 |
| Phi Z actor read address | 13 | 14 | 14 |
| Phi Z service stage completion | 23 | 22 | 20 |
| Phi Z reduction ready | 24 | 24 | 22 |
| Syndrome 0 service stage completion | 11 | 9 | 9 |
| Syndrome 1 service stage completion | 9 | 10 | 10 |

The prediction underestimated work before mailbox selection. Retirement, candidate eligibility and actor choice still depend on the arriving executor result. Read-address depth can grow under remapping, offsetting downstream savings; one syndrome service also regresses. These longest paths need not be nested, so subtracting two rows does not yield an exact subpath delay. In this two-actor fixture, binary actor selection is only one bit: carrying a one-hot grant alone should not be assumed to remove the preceding eligibility work.

Only the four shared-service modules change in the measured RTL. Executors, reducers, routers, FIFOs and wrappers remain byte-identical to #182. Thus the surviving arithmetic cascade is untouched. Native registered-DSP coverage remains incomplete; the qualified vendor flow is still required for a full-clock comparison. No route was run for this screen.

## Formal and simulation evidence

- **Combinational proofs:** SAT establishes exact `(available, logical position, physical slot)` equality for both variants to an independent sequential specification, for every legal row state, actor index and postponement mask at `(actors, depth) = (1,1), (2,3), (2,5), (3,8)`. Empty/full, postponed and non-power-of-two cases are included by quantification, not selected as test vectors. Reversing priority produces a counterexample.
- **Inductive proofs:** at depths 1, 3, 5 and 8, reset establishes the metadata invariant and every admitted transition preserves it. The checks use the actual retirement/admission helpers, with exclusive consume/postpone directives and independent phase-change/admission/reset requests, including consume-plus-append. They establish bounded occupancy, distinct live slots, retained order, fresh allocation and absence of stale postponement on unused slots for arbitrarily long histories of this metadata model. Scheduler ownership, RAM payloads, multi-producer arbitration and progress are separate obligations. No theorem over all parameter sizes or verified compiler is claimed.
- **Simulation witnesses:** normal and stalled runs each match 161 BEAM events. A 12,000-cycle reset/stall comparison matches ready/valid and valid output data cycle-exactly: 318 X and 346 Z frames.
- **Repository checks:** 1,180 EUnit tests, Dialyzer and source contracts pass. The final change preserves generated DSLX; no golden update is needed. Five structural-reporter tests check attribution and reject unsupported hard arithmetic. Formal checks run in CI alongside the existing reduction checks.

The [summary](mailbox-selection-2026-09-27/summary.json), manifests, source patches, compiler commands, mapped chains and solver verdicts retain evidence and identities. The patches use zero context (`patch -p0` or `git apply --unidiff-zero`). [Replay instructions](../timing_chains/README.md#actor-boundary-experiments) use the existing validation/mapping workflow and reusable named-module substitution. Large regenerable netlists remain local.

## Next decisions

Retain the narrower eligibility expression for its small area saving, without promoting its clock estimate or bank-wide replication. The more substantial control question is whether retirement can stop recomputing the complete issue decision on the same dependency chain; any new boundary needs cycle accounting and slot-ownership refinement. The staged numerical kernel and feedback ledger, guarded XLS receive-zeroing optimization, aggregate-ready buffer, actual 17-way router and 2×4 workload remain recorded in the hypothesis register and Roadmap. None is discharged by this screen.
