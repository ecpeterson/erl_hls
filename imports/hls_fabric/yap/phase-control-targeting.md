# Phase-control investigation

Baseline: #64 production controller, D3H3/36 vertices/six executors, 128 sheets, p=.005, seed 0. Keep XLS scheduling, completion storage, memory interfaces and Vivado flow unchanged. The source-equivalent public compiler pin is now cf4e54a; the changed files against the old pin are CI and prose only.

## Targeting

The dependency reporter unions reviewed source families across replicas, counts overlapping coverage once and names untouched competitors. On the 23,362-endpoint census, all indexed-selection sources cover 17,357 endpoints but leave an 8.743-ns ordinary-mailbox path. Adding ordinary depth and retiring actor reaches 21,559 endpoints but leaves an 8.740-ns scalar collector. Baseline is 8.744 ns. These are attribution/sensitivity approximations, not automatic semantic equivalence or predictions of post-change placement. Alternative paths hit their 2,000-path cap.

The source evidence for this census is the earlier validated `one-hot-admission/early-valid` DSLX; `collector-ownership/generated` contains a rejected candidate and is not the baseline. Register field roles above are unchanged between those candidates, but source-level decisions must use the correct version.

## First screen: phase-first source eligibility

The indexed classifier computes current-collection eligibility and, on its complement, ordinary postponement/failure through separate phase dispatches. Specialize the combined decision for each finite phase, then merge its narrow eligibility result. Preserve the original callback bodies, frame checks, invalid-phase fallback and fault precedence. This is ordinary partial evaluation at a known enum value, not an assertion about legal messages or a cache of mutable state. No registers, protocol hints or pipeline stages are added.

Hypothesis before implementation: constant phase eliminates mutually exclusive branches before payload/key logic is merged, shortening some indexed source-check cones by 1–2 LUT levels (roughly .2–.5 ns logic/routing combined in a component). Expect unchanged cycle transcripts and ±2% component LUTs, with no whole-core speedup predicted because ordinary/scalar competitors survive. XLS may already perform the same factoring; identical or worse optimized component structure rejects this formulation before full routing. Screen a pure classifier first, then the 19- and 22-producer services. Do not infer whole-core timing from a pure function result.

If it succeeds, apply the same finite-phase boundary to scalar collection control and inspect ordinary admission separately. If it fails, retain the evidence and use the mapped source dependencies to select a different boundary rather than repeating bank-locality rewrites.

## State-derived phase control

The first probe is equivalent for all 1,000 input bits of the combinational classifier (DSLX/XLS + Yosys SAT trust boundary). Yosys maps 81 → 87 LUTs and retains nine carry primitives; reject phase-first syntax before application implementation. Optimized IR size alone was not the deciding measurement.

Next hypothesis, registered before editing source: cache the exact successor epoch and whether this phase kind permits a successor. Initialization establishes `successor_epoch = epoch + 1 (mod 2^32)` and the kind predicate; epoch advance and phase start preserve them. Every original frame, direction, neighbor, phase and failure check remains. This is a source-level staging experiment on the application, not a new unchecked compiler assertion.

Expect the selected-state increment to disappear from the eligibility cone, roughly 0.2–0.5 ns off paths which traverse it. Storage ceiling is 36×33 = 1,188 additional shadow control bits before optimization, plus the corresponding actor data in existing BRAM packing. Component LUTs should stay within ±2%; all 128-sheet and blocked-output cycle transcripts should remain identical. No whole-core frequency gain is predicted from this alone: ordinary/scalar competitors remain. Check the pure residual classifier and complete services before routing. A retained optimization must justify its added state against measured path reduction, not just reduced IR nodes.

The initial source tests caught a real cache-maintenance hazard: the ready-phase predicate temporarily substitutes kind zero to validate a next-sheet arrival. Drop the cached kind predicate; retain only the successor epoch, whose sole mutation is ready entry. This keeps the experiment focused on the measured arithmetic dependency and reduces the storage ceiling to 1,152 bits. The local-advance suite is the relevant variant; coordinated-only vertex cases run separately with local advance disabled.

Route gate refinement: the 19-producer service stays within the +2% component LUT budget (+1.30%). Route its frozen baseline and cached-epoch checkpoints with the same two-thread Default flow. The hypothesis remains a .2–.5 ns reduction only on paths traversing the old successor calculation; do not infer total component or application period improvement. Reject the cache if access cost or a new competing path erases its benefit. The 22-producer synthesis remains pending.

## Results and decision

Keep the targeting reporter; retain neither source candidate. No application-level throughput improvement is established. The decoder and backend are unchanged; the compiler pin follows the recreated public repository's merged gather API.

The exact successor-add aliases occur on 2,783 of 23,362 full-core endpoint-worst paths. Their worst period is 8.737 ns versus 8.744 ns globally. Even a hypothetical 1-ns reduction on all those sampled paths leaves an 8.744-ns competitor. A launch-register label would incorrectly attribute much more of its downstream cone to this one calculation.

| Boundary | Baseline | Cached successor | Interpretation |
|---|---:|---:|---|
| Pure classifier LUTs / CARRY4 | 81 / 9 | 88 / 1 | Arithmetic removed; LUT count grows |
| 19-producer synthesis LUTs | 24,939 | 25,262 | +1.30%, within allowance |
| 22-producer synthesis LUTs | 26,847 | 28,106 | +4.69%, exceeds allowance |
| 19-producer synthesis period | 9.344 ns | 9.539 ns | Worse estimate |
| 22-producer synthesis period | 8.633 ns | 7.840 ns | Better estimate |
| 19-producer routed LUTs | 25,559 | 25,862 | +1.19% |
| 19-producer routed FFs | 14,640 | 14,518 | −0.83% |
| 19-producer routed period | 10.356 ns | 9.446 ns | Component headline improves 8.79% |
| Routed paths through successor comparison | 9.084 ns | 9.150 ns | Intended family does not improve |

The routed comparison uses frozen synthesized checkpoints, XCZU7EV-2, 5-ns constraints, Default directives and two threads. It measures one complete shared service with six actors, its executor and channels, not the entire decoder. Periods are setup-derived operating-point estimates, not 5-ns closure. The baseline component leader launches from pending target-address bit 20; the full-core checkpoint retains only bit 2 of that register. Upstream constant propagation therefore removes this component leader in the application. The 8.79% headline is insufficient evidence for retaining the cache or predicting application throughput.

The worst successor-comparison paths share their readiness endpoint but have different launches. Their logic/route components change from 2.627/6.437 ns to 2.239/6.892 ns. Removing the increment leaves actor/context selection and publication dependencies in place; additional cached state does not decouple them. This is a comparison of the two family leaders, not a same-path decomposition of causality. No full-core candidate route was run after the failed targeted-path/area screen.

Behavior checks pass: 128-sheet and blocked-output RTL transcripts are cycle-exact, including 1,125 correction frames. Mean round clocks remain 256.590551, population variance 3039.627627 and range 234–469. Coordinated, local-advance and rollover source tests pass. A combinational SAT miter establishes equality of the classifier's 19 output bits for all 1,000 original input bits, with the candidate cache constructed as `epoch + 1 mod 2^32`. Its trust boundary is DSLX/XLS lowering plus Yosys SAT; it does not establish preservation of that invariant over arbitrary executions. The application runs are simulation witnesses.

## Implications for the next experiment

- Map the specific expression being changed, not every path from an upstream register. Union replicated dependencies without counting overlap twice, then inspect untouched alternatives.
- Use component synthesis to screen access cost; before trusting component timing, verify that its limiting launches survive integration. Top-level false paths do not remove an internally captured input that the full design makes constant.
- Require a proposed phase-control boundary to remove selected-context/arbitration dependence, not merely one arithmetic operation within it. Preserve guards, early arrivals, fairness and phase-change wakeup. The broader [phase-specialization work](decoder-service-investigations.md#4-census-regular-phases-before-specializing-them) remains open.

Evidence lives under `hls_artifacts/runs/phase-control-2026-10-03/`: `dependency-plan.json` and `targeting-expression/`, `component-comparison.json`, `synthesis-summary.json`, exact expression aliases, simulation comparisons and `cached-source.patch`. The patch includes the discarded regression tests and applies cleanly to this branch. The original hypotheses and commands remain in that run directory. Bulky generated inputs follow the normal short retention policy; the compact decision and reusable reporter live here.
