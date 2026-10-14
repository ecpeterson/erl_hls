# Collection ownership experiment

The shared-subchain reporter is retained; every ownership candidate is rejected. Production scheduler code stays at #64. Source patches, exact decisions, vectors, reports and hashes are archived in `hls_artifacts/runs/collector-ownership-2026-10-03/`; large checkpoints remain under `/home/ubuntu/hls-collector-ownership/` on EC2.

## Hypothesis and scope

Start from #64 (`6ea3860`); #65 is an independent comparison. Keep the complete D3H3 application: 36 vertices, six shared executors, tree-six barriers, indexed gathers, monoid collectors, two-stage XLS scheduling, 128 sheets, p=0.005 and seed 0. Preserve cycles, payload RAM ports, failure behavior and debug observations. Full-core physical runs use Vivado 2024.2, XCZU7EV-FFVC1156-2-e, 5 ns constraints, Default directives and two threads.

The baseline census finds 23,362 endpoints within 1 ns of 8.744 ns. Repeated 2–3 ns segments feed thousands of metadata, readiness and RAM endpoints. This motivated keeping ownership updates local: predict 0.5–1 ns shorter targeted paths, unchanged cycles, 0–5% whole-core throughput improvement and LUTs within ±5%. Endpoint families can share control; their names do not identify independent bottlenecks. Bounded alternatives and fixed-layout sensitivity are targeting approximations.

## Trials

| Formulation | 19-producer LUT change | 22-producer LUT change | Routed result |
|---|---:|---:|---|
| Per-actor bank decisions | +17.74% | +9.71% | Rejected before routing |
| Decisions shared within three actors | +13.97% | +9.89% | Rejected before routing |
| Local admission, shared retirement/borrow | +2.82% | +4.79% | 9.818 ns; 12.28% slower |
| Field command from reconstructed bank array | +9.91% | Cancelled | Rejected before routing |
| Field command from native scalar-bank operation | +1.26% | +6.30% | 9.418 ns; 7.71% slower |

Generic-cell ablations implicated replicated retirement/opening work, motivating local admission alone. Its key broadcast and shared consumption acknowledgement then became expensive. The final candidate kept decisions shared, emitted field writes before array reconstruction, and retained unchanged fields at their owners. It removed eleven add operations relative to the preceding command formulation. Its preregistered expectation was identical cycles, ±2% full-core LUTs and 0.3–0.6 ns shorter targeted bank-write paths; whole-clock improvement remained uncertain.

The final 22-producer component exceeded the +5% heuristic. Before full execution, the gate was revised explicitly: measure total area and route only below +2%. Both component totals were close to the earlier full-core +1.46% candidate. This justified measuring integration, not assuming its result. Full synthesis passed at +0.54%.

## Completed comparison

| Measurement | #64 | Native field command |
|---|---:|---:|
| Synthesized period | 8.983 ns | 8.561 ns |
| Routed period | 8.744 ns | 9.418 ns |
| Routed LUTs | 171,235 | 172,153 |
| Routed FFs | 103,852 | 105,430 |
| BRAM36s | 48 | 48 |
| Mean cycles | 256.590551 | 256.590551 |
| Mean round time | 2.243628 µs | 2.416570 µs |

The synthesis estimate improved 4.70%; routed round time worsened 7.71%. These are setup-derived operating-point estimates from matched OOC runs, not 5 ns closure or board qualification. Hold/pulse checks pass, all internal endpoints are constrained, and all 242,310 routable nets are routed.

This is broader than one newly exposed leader: 2,184 endpoint-worst paths exceed the baseline's worst period. Scoped context-write paths worsen 8.742 → 9.192 ns, readiness 8.744 → 9.418 ns, indexed-cursor paths 8.744 → 9.382 ns, and ordinary-occupancy paths 8.743 → 9.215 ns. The new leader starts at retiring-actor selection. Local field writes preserved sharing and area, but did not isolate the shared selection/admission/retirement control that reaches readiness and commit. Routing overwhelms the small logic-delay differences between these category leaders; they are different paths, not a matched-cell causal decomposition.

The next campaign experiment should simplify or separate those control decisions, using phase-specific execution as planned. Repeating bank-write locality alone lacks supporting evidence. A small fall in synthesized delay is insufficient to distinguish these candidates; the shared-path census should continue to guide which source dependencies a proposed cut actually removes.

## Evidence and reproduction

The final candidate passes 25 core and 50 adapter DSLX cases, 323 EUnit tests, Dialyzer and zero new source-contract gaps. Full and blocked-output transcripts are byte-identical to #64; cycle variance is 3039.627627, range 234–469. Live-debug witnesses at two and three pipeline stages cover partial gathers, unopened successors, stalled reports and noninterference.

A combinational SAT comparison establishes equal whole next state and every pre-existing admission field for all input-bit valuations of the capacity-three, two-actor/two-producer fixture. Control slots are in range, same-actor issue is excluded during retirement, and selection uses committed state. Trust boundary: DSLX/XLS lowering and Yosys SAT. Application simulations remain witnesses, not arbitrary-capacity or temporal proofs.

The final rejected patch is `native-commands/final-candidate.patch`; `decision-history.md` retains the original sequence of predictions. `native-commands-full-r2/` and `native-command-r2-{timing,report,scopes}/` retain the final physical evidence. `native-path-comparison.json` scopes semantic register labels to their owning proc, since unrelated procs reuse field numbers.

The earlier `native-commands-screen/` is invalid: its preparation script copied the preceding candidate's RTL. `INVALID.json` records both identities. The corrected `-r2` bundle verifies the validated release hash before launch. The reusable batch runner now checks a complete `rtl_sha256` input map; hashing whichever files were copied into a labeled directory cannot detect selecting the wrong release.
