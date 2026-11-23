# Phase protocol experiment

**Decision: reject the scheduler option.** The fused candidate reduces mean clocks by 6.55% but increases the routed period by 9.96%, leaving mean round time 2.76% worse. Production remains at the qualified parent; the tested implementation is retained as an external patch.

Preregistered 2026-10-03 on `ede3200` (#67). The hardware control remains #64's frozen D3/H3, six-executor, indexed-gather decoder: 256.590551 mean clocks × 8.744 ns = 2.243628 µs, 171,235 routed LUTs. Artifacts: `hls_artifacts/runs/phase-protocols-2026-10-03/`.

## Candidate and gates

Derive a conservative phase/event summary from source callbacks and their acyclic helpers. Preserve unknowns. Use it to identify narrow internal transitions; it is a cost screen, not permission to omit callback checks.

A pending internal event already precedes mailbox selection. After a successful effect-free activation with no pending entry or live logical collection, fold at most one qualifying internal callback and its entry while retaining actor ownership. Keep effectful entry, failures and ineligible events unchanged. A separate tail proc prevents concatenating this control work onto the arithmetic stage. Intermediate state is unstable (`next_event != 0`), so collectors defer source eligibility there; verify release/open composition against two ordinary control transitions before omitting the intermediate retirement. Retain actual source callbacks, failure identities, FIFO ordering and existing observation of committed state.

The retained #64-compatible 128-sheet activation capture contains 59,076 vertex activations, including 13,824 `ready` continuations (23.4%). Some follow a correction publication and cannot fold. These counts bound eliminated visits, not elapsed time. Predict 8–15% fewer mean round clocks including the added stage, 3–8% more LUTs, and no assumed clock improvement. Accept a full routed throughput improvement; reject an unchanged/worse cycle result or >8% component area growth before full routing unless new evidence justifies a revised design. A 10% cycle improvement tolerates at most an 11.1% period increase merely to break even.

- [x] Derive callback tags/outcomes, local helper closure, explicit state reads/writes and unknown operations; identify narrow internal transitions without decoder-specific names.
- [x] Check silent-tail semantics, first-failure identity, collection release/open composition, early arrivals, output blocking and nonqualifying fallback in the stated finite fixtures.
- [x] Measure unchanged baseline and candidate visits/cycles, then representative mapped area. Keep source and artifact identities.
- [x] Route the surviving whole application; report cycles × period and competing paths. Preserve profiler identities for folded source callbacks.

No claim of decoder validity follows from source/RTL agreement. A finite simulation is a witness; combinational checks identify their quantified inputs and invariants. This task does not establish exclusive tag ownership, key uniformity or bounded epoch overlap.

## Registered-tail cycle screen

The 16-sheet cohort preserves 117 ordered correction frames and all source state checks. Mean interval falls 261.5333 → 248.5333 clocks (4.97%); the last round moves 4,225 → 4,019. This misses the 8–15% expectation. The dedicated stage also delays nonfolding activations. Before another implementation: compare the identical bounded fold composed within the existing two-stage XLS executor, with no extra channel/stage. Predict 8–12% lower mean clocks, at a greater risk of a longer executor period. Screen complete component area against the same 8% budget; no routed saving is assumed. Both variants retain the same source checks and collection/entry guards.

## Complete-cohort cycle and area screen

| Placement | Mean round clocks | Population variance | Min–max | 19-producer LUTs | 22-producer LUTs |
|---|---:|---:|---:|---:|---:|
| Frozen control | 256.590551 | 3039.627627 | 234–469 | 24,939 | 26,847 |
| Separate tail stage | 243.417323 | 3260.510881 | 221–462 | 26,485 (+6.20%) | 28,277 (+5.33%) |
| Fused tail | 239.787402 | 3100.797322 | 216–453 | 25,804 (+3.47%) | 26,628 (−0.82%) |

Both 128-sheet candidates reproduce all 1,125 ordered correction frames. The fused 16-sheet backpressure witness also passes with each output blocked for 4,000 cycles. These are finite source/RTL witnesses, not general equivalence or decoder-correctness proofs. All synthesis reports are checked against their execution-time hashes in `components.json`; the service samples include their executor and channels but not external physical RAMs.

The registered 16-sheet profile contains 5,949 owned activations and 1,611 observed folds, leaving 117 separate ready-phase continuations whose preceding entry publishes a correction. Every activation crosses the added one-clock stage. Removing that stage recovers only another 3.63 mean clocks in the full cohort. The remaining publication and collection waits overlap other work: the 23.4% historical visit opportunity was too generous a proxy for round time. The resulting 5.13%/6.55% gains miss both preregistered cycle ranges.

The paired 16-sheet profiles make the overlap concrete. Both variants have 5,949 owned activations. Removing the tail stage changes every executor boundary from two clocks to one, but the 117 publication-separated ready activations then wait 11.78 rather than 10.78 mean clocks from result to retirement. For snapshot completion, the corresponding wait grows 5.34 → 6.18 clocks. These are population averages, not per-event causal subtraction, but they show why a removed execution clock often relocates into a downstream wait. Future cycle predictions must price retirement/publication capacity as well as eliminated callback visits.

The normal `phase-tail.json` build emits the same DSLX tokens as the measured fused prototype; comments/whitespace and placement metadata differ. The default leaves separate activations intact. Source-derived candidates retain ordinary callbacks and their failure checks. The summary reports explicit field accesses and unresolved operations, not a complete dataflow, cost, reachability or protocol analysis.

The fused candidate passed the area gate and completed the matched full-core route. Component screens use eight threads; the whole-core run uses the retained control's two-thread setting, 5-ns constraint, XCZU7EV-2 and Default directives. An initial eight-thread whole-core attempt was stopped before using any result. At 239.787402 clocks, break-even against the control is approximately 9.357 ns. The final result below fails this gate.


## Profile and qualification

The fresh fused 16-sheet profile joins all 7,038 indexed writes uniquely to generated donor effects, with zero unknown writes or unmatched donors. The full actor/executor SVG and a six-actor view accompany bounded Perfetto output under `fused/profile/`; the display clock is 25 ns, not the physical period. The fused executor includes an optional continuation but has no separately observed internal clock boundary. The staged profile exposes the actual tail boundary.

The unchanged baseline re-emits the same noncomment DSLX tokens as the retained #64 source. A fresh normal packaged build also reproduces all four application RTL files byte-for-byte and the exact 16-sheet event stream; the route therefore measures the packaged implementation, not only a prototype. All 329 EUnit tests, Dialyzer, 97 DSLX interpreter/JIT cases, the physical RAM witness and profile tests pass. The source audit reports 328 preexisting gaps and no changed-declaration gaps. Pipeline-aware donor evaluation now accepts the exact recorded underlying optimizer as well as its frozen wrapper, recording both identities and retaining all other tool/source checks.


## Routed result and decision

Do not promote either placement. The fused candidate fails the preregistered complete-application gate; the separate stage was cycle/area screened but has no demonstrated physical advantage. Preserve the implementation in the external `continuation-fold-candidate.patch` against `ede3200`. Production code and example configurations remain at the qualified parent. Keep the profiler's observed-tail support and the optimizer-wrapper provenance repair.

| Complete D3/H3 core | Qualified control | Fused fold | Change |
|---|---:|---:|---:|
| Mean round clocks | 256.590551 | 239.787402 | −6.55% |
| Synthesis period estimate | 8.983 ns | 8.354 ns | −7.00% |
| Routed setup-derived period | 8.744 ns | 9.615 ns | +9.96% |
| Mean clocks × period | 2.243628 µs | 2.305556 µs | **+2.76%** |
| Routed LUTs | 171,235 | 173,808 | +1.50% |
| Routed FFs | 103,852 | 104,018 | +0.16% |
| BRAM36 | 48 | 48 | unchanged |

The full native run took 3,633 seconds. Hold slack is +0.009 ns, pulse slack +1.958 ns, all routable nets are routed, and no internal endpoints are unconstrained. The requested 5-ns clock fails setup; the table extrapolates the reported limiting period, not a separate closure run or complete board implementation. Both controls exclude external I/O paths and use the same device, directives and two-thread flow. This is one matched run, not a distribution over placements.

The 50 worst paths contain no executor path: seven launch from pending opcode, 40 from ordinary mailbox depth and three from retiring-actor selection. The leader is indexed admission/source eligibility into readiness, at 9.615 ns; the ordinary-mailbox competitor is 9.613 ns. The leader has 3.632 ns logic and 5.853 ns routing. These are different path leaders from the baseline; subtracting their components does not isolate a same-path cause.

All six shared-controller optimized IR bodies are identical after canonical renaming of node identifiers and removal of IDs/source positions; types, constants, operands, state, channels and proc instances remain. The slower mapped/placed realization therefore does not reveal a new controller dependency introduced by folding. Nor does it justify another executor-stage cut: that cut misses every sampled limiting chain. A separate-stage full route would mainly test another physical perturbation, while sacrificing some cycle savings; stop here rather than select a lucky route.

The general lesson is narrower than “fewer visits may not help.” The visit count overestimated recoverable time because result publication/retirement remained occupied; the source cost screen covered the internal callback but not its target entry; and unchanged controller IR did not preserve integrated physical timing. Use the source census to propose candidates, paired boundary profiles to price them, and a whole-application physical gate to accept them. None alone substitutes for the others.

Compact evidence: `routed-comparison.json`, `controller-ir-identity.json`, `routed-paths-summary.json`, `synthesis-comparison.json`, `profile-census.json`, `routed-report/` and `packaging/rtl-identity.json` in the external run directory. The final profile remains useful evidence of the rejected candidate, not the production default.
