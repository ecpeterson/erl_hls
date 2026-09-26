# Control-path timing experiments

The local queue rewrite saves **5.4% of mapped core LUTs** and improves isolated queue periods by about one third, but both matched whole-core routes regress. Mean modeled step time rises **5.130→5.536 µs (+7.9%)** at unchanged 93.25 cycles/step. The rewrite remains an experimental patch; compiler defaults are unchanged. Three further screens also fail to justify adoption. The reusable additions are placement-path diagnostics, selection-shape inventory and explicit proof/reproduction fixtures. These native results do not qualify a deployable clock.

The reference is `97b6bf9`. XLS stages/II remain 2/1, with the same `unit` schedule and I/O flops. Physical probes use the calibrated native backend from the [timing-model campaign](xc7-timing-model-2026-09-25.md), exact `xc7z030sbg485-1` database, and retained tool/source hashes. The complete topology rejects calibrated XLS scheduling at unsupported priority-selection shapes; no fallback or timing-table extrapolation was introduced. Even with those shapes covered, this flow schedules procs separately before FIFO stitching: an operation model alone cannot budget the complete path across bypassed boundaries.

The [selection inventory](control-queues-2026-09-25/selection-shapes.json) counts 974 selections in 70 distinct combinations of result width, case count and selector width. Of these nodes, 452 need dimension review: 420 use unsampled case counts, 26 exceed measured widths, 188 use unsampled binary-selector widths, and 11 carry zero data bits (categories overlap). The widest result is 540 bits. These are calibration-corpus gaps, not 452 proven estimator failures; the inventory neither validates other operators nor assigns delays.

## Queue candidate and validation

The reference `frame_queue::update_bank` selects a queue, applies pop, writes it back, then selects the push queue from that updated array. The candidate unrolls the bank and enables each queue's pop/push by address. Pop still precedes push, including a same-address full-queue replacement. Every other queue retains every bit.

The compiled-RTL SAT miter proves exact state/payload equivalence for 1, 2, 3 and 9 queues, arbitrary data and flags, legal enabled addresses and arbitrary disabled addresses. It even compares invalid payload bits. A deliberately omitted pop produces a counterexample. Library interpreter/JIT tests, 1,174 EUnit tests, source-contract checks and Dialyzer pass. Full board-sized and D3 simulations compare each actor's accepted events with the BEAM oracle, under normal and stalled output readiness. D3 remains at 180.00 cycles/step (181.96 stalled); the stricter two-design comparison matches every public output cycle and payload over 12,000 cycles, long stalls and reset.

## Isolated physical probes

Both variants use explicit fabric input/output registers, the same 100 MHz placement target and seeds 1/2. Area below includes this common probe harness. No DSP, RAM or SRL is inferred; connected FF boundaries pass the coverage audit. Variance is population variance over the two deliberately selected seeds, not a confidence estimate.

| Queues | Variant | Seed periods (ns) | Mean (ns) | Variance (ns²) | Best / worst (ns) | LUTs | FFs |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 2 | Indexed reference | 10.536 / 10.176 | 10.356 | 0.0324 | 10.176 / 10.536 | 1,617 | 1,227 |
| 2 | Local updates | 6.657 / 7.069 | 6.863 | 0.0425 | 6.657 / 7.069 | 823 | 1,227 |
| 9 | Indexed reference | 15.662 / 15.399 | 15.530 | 0.0173 | 15.399 / 15.662 | 7,305 | 4,839 |
| 9 | Local updates | 10.705 / 9.860 | 10.283 | 0.1787 | 9.860 / 10.705 | 3,555 | 4,839 |

The means improve by 33.7% and 33.8%. The remaining candidate paths still involve address decoding and high-fanout data selection. [Machine-readable samples](control-queues-2026-09-25/queue-probes.json) retain critical paths, coverage, hashes and distribution statistics.

A second candidate unconditionally copied the tail into the head on pop, relying on the contract that invalid payloads are unspecified. It passed validity/live-payload equivalence but saved only one LUT and worsened both two-queue seed periods to 7.338/8.846 ns (mean 8.092, variance 0.5684 ns²). The reported logic delay stayed at 0.9 ns while routing grew. The mapper had largely absorbed the apparent preservation mux; this candidate was rejected.

A third screen computes mailbox retirement readiness from the updated local row before writing the actor array. Exact-state equivalence passed, but periods were mixed: 7.608/8.904 ns before, 7.988/7.880 ns after, with LUTs 297→285 and FFs fixed at 244. The mean gain is only 3.9%, below the 5–20% hypothesis; all paths still end at mailbox readiness through address/order/postponement selection. This rewrite was not selected. [Samples and statistics](control-queues-2026-09-25/retirement-probes.json) retain the evidence.

## Complete decoder

The whole-core mapping preserves the application in an independent activity harness. FFs fall 29,411→29,259; both versions retain 56 DSP48E1, 44 RAMB18E1 and 8 RAMB36E1. These are one matched mapping pair, separate from the two-seed isolated probes.

Two matched seeds use the same mapped inputs, constraints and tools. Periods below are reciprocals of reported MHz; variance is population variance across these two samples. The rewrite regresses by 9.9% on seed 1 and 6.0% on seed 2. This sample is too small to characterize placement reliability, but it gives no basis to promote the isolated gain into a timing optimization.

| Variant | Seed periods (ns) | Mean (ns) | Variance (ns²) | Best / worst (ns) | Mean step (µs) |
| --- | --- | --- | --- | --- | --- |
| Reference | 54.437 / 55.586 | 55.012 | 0.3305 | 54.437 / 55.586 | 5.130 |
| Local queues | 59.809 / 58.928 | 59.368 | 0.1941 | 58.928 / 59.809 | 5.536 |

Initial physical attempts use seed 1 and a matched 25 MHz target, with placement checkpoints before routing. Both initial placements exceeded a 600-second screen; the identical seed/constraints were retried with a 1,800-second placement budget. Routing has a separate 1,800-second budget. H1 finishes in 1,022 seconds; the reference expires with 87 conflicts, then completes in 2,322 seconds when retried from the same saved placement with a 3,600-second route budget. Seed 2 uses 1,800-second placement and 2,700-second route budgets for each; both complete (686/1,658 seconds placement and 384/299 seconds routing for reference/candidate). Failed attempts remain part of the evidence. Calibrated BRAM timing does not fill the remaining registered-DSP, SRL, hold and internal-constraint omissions, so a completed native route still cannot qualify the full board clock.

The reference's seed-1 worst path takes 54.4 ns (3.6 ns logic, 50.9 ns routing), crossing the Z executor, reduction dispatch and egress enable. H1's corresponding bottleneck crosses the X plane: its routed worst path takes **59.8 ns: 3.9 ns logic plus 55.9 ns routing**. It crosses executor output, scheduler egress, reduction dispatch and the router's completion signal before returning to an egress-FIFO register enable. The two slowest nets drive 357/378 input ports and contribute 6.0/5.6 ns. Several other 3.5–4.1 ns hops drive only 2–7 inputs: physical spread matters alongside fanout. The saved-placement diagnostic predicted a nearby 61.0 ns path with a different endpoint (ordinary mailbox RAM write data). Seed 2 changes the reference's limiting path to scheduler request→executor arithmetic (21.4 ns logic, 34.2 ns routing, including coarse DSP arcs); the candidate remains control-limited (3.8 ns logic, 55.1 ns routing). A smaller queue cone has neither removed that chain nor improved its placement. Placement diagnostics locate candidate chains, but routing determines the limiting endpoint. [Core evidence](control-queues-2026-09-25/cores.json) retains commands, hashes, paths, explicit FF/BRAM/combinational-DSP coverage checks and all attempts.

### Registered handoff experiment

A separate IR experiment replaces the two phi scheduler egress FIFOs with depth-two, non-bypassing queues. All accepted actor frames match, but cycles/step rise 93.25→122.25 under both readiness patterns. LUTs rise 31,366→31,521 and FFs 29,259→29,979; RAM/DSP counts stay fixed. It needs a period below 45.6 ns to improve step time relative to H1. Placement completes in 1,587 seconds but estimates only 16.96 MHz / 59.0 ns. The limiting path moves to scheduler request→executor arithmetic (20.7 ns logic, 38.2 ns routing), including coarse DSP cascade arcs. The newly started route was stopped after 193 seconds: this screen does not justify the cycle penalty, and a full route would not resolve those arc costs. The change is not adopted; no routed-frequency or hardware-regression claim is made for it.

The existing interface profiler explains the unexpectedly large penalty. All 992 effect batches per plane wait exactly one cycle at this boundary, versus zero before; none waits longer there. The returned effect credit also arrives later, postponing the second actor's retirement. Eleven within-step gathering intervals grow 6→8 cycles, while the interval crossing a step grows by seven cycles (27–28→34–35): `11×2 + 7 = 29` added cycles per step. This benchmark uses the default shared batch sequencer; the penalty is not a measurement of independent per-actor outboxes. [Trace summaries and exact channel edits](control-queues-2026-09-25/handoff-screen.json) retain this diagnosis.

A fixed-placement sensitivity test sets **all combinational DSP arc delays to zero**, keeping every timing arc and all wiring estimates. H1 remains at 16.40 MHz; the registered handoff improves only to 17.67 MHz (56.6 ns: 4.1 ns logic, 52.5 ns wiring), now limited by executor-control→FIFO-enable logic. Its modeled period×cycles product remains 21.7% worse than H1's corresponding placement estimate. Thus DSP delay uncertainty alone cannot rescue this placement. This deliberately optimistic diagnostic is not a calibration, a reroute or a prediction of different placements. A separate binary was used and the native source restored. [Sensitivity evidence](control-queues-2026-09-25/dsp-sensitivity.json) records the exact edit, hashes, commands and paths.

See the [preregistered hypotheses and rejected candidates](../yap/timing-control-2026-09-25.md) and [probe procedure](../timing_chains/README.md).
