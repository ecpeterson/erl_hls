# Materialized FIFO storage, 2026-09-26

Compact depth-one FIFOs remove 7,218 flip-flops from the four-phi testbench while preserving every observed interface cycle. The experiment changes XLS materialization, not FIFO depth, bypass policy or pipeline latency. Compiler defaults remain unchanged; the source patches are retained for review.

[Calibration and workload](xc7-timing-application-2026-09-26.md) · [Reproduction](../timing_chains/README.md#materialized-xls-fifos) · [Machine-readable evidence](fifo-storage-2026-09-26/evidence.json)

## Hypotheses and variants

The general XLS ring buffer allocates an extra storage slot and head/tail pointers, even at depth one. A one-slot implementation needs only a payload register and an occupancy bit. Separately, suppressing writes during an empty bypass makes the payload enable depend on downstream readiness. Writing every accepted push can remove that dependency when push readiness is registered; the extra write is unobservable but may cost switching power.

Before implementation, the predictions were: 5–8 ns off the targeted ready/control path, an uncertain 0–10% whole-core timing gain, and 5,000–8,000 fewer mapped flip-flops with compact storage. Replacing just two 424-bit queue definitions was expected to save 600–850 flip-flops and 1–3% LUTs. After the combined candidate, a compact-storage-only control retained the original empty-bypass write suppression. The unit-schedule control was then added because the calibrated baseline did not finish routing; its registered hypothesis was a 10–30% period reduction with unchanged cycles.

All patches start from XLS `20bf86d9c9e90f9df380a0280a5973ce0c33a59a`:

- [Accepted push](fifo-storage-2026-09-26/accepted-push.patch): write payload on every accepted push; preserve the general ring.
- [Compact storage](fifo-storage-2026-09-26/compact-storage.patch): specialize valid depth-one configurations; preserve empty-bypass write suppression and all larger FIFOs.
- [Combined](fifo-storage-2026-09-26/accepted-and-compact.patch): both changes. This is the strongest observed whole-core timing candidate, pending stronger physical validation.

## Complete core

Same optimized IR, stage count, mapped-core harness, native tools, part and placement seed. Candidate construction substitutes only FIFO module definitions with identical ports; all other RTL remains byte-identical. Area excludes the activity harness. Native place/route requests 25 MHz, with 30/45-minute limits. A timeout supplies no frequency estimate.

| Schedule / FIFO | LUT cells | Flip-flops | Completed native route | Cycles × native period |
|---|---:|---:|---:|---:|
| Calibrated, original FIFO | 33,650 | 29,226 | Route timed out (45 min) | — |
| Accepted-push only | 33,620 | 29,226 | Stopped (20.6 min) | — |
| Compact storage only | 32,965 | 22,008 | 21.53 MHz | 3.681 µs |
| Compact + accepted push | 33,171 | 22,008 | 25.21 MHz | 3.144 µs |
| Only two 424-bit queues | 33,651 | 28,506 | Not routed | — |
| Unit, original FIFO | 33,509 | 29,411 | 17.75 MHz | 5.254 µs |
| Unit, compact + accepted push | 32,665 | 22,194 | 18.17 MHz | 5.132 µs |

DSPs and BRAM remain at 56 / 44 RAMB18 / 8 RAMB36. Normal/stalled cycles stay 79.25 / 79.8333 for every calibrated candidate; the unit control retains 93.25 / 93.25. These native periods use a partial model and cannot be substituted for the separate Vivado OOC measurements or treated as board clocks.

The combined candidate saves 24.7% of flip-flops and 1.4% of LUTs; storage alone saves the same flip-flops and 2.0% of LUTs. The two-queue experiment saves 720 flip-flops but adds one LUT, falsifying its predicted LUT reduction: the original per-bit data selection already maps to one LUT, so fewer inputs do not remove that LUT.

Compact storage and the combined candidate complete place/route in about twelve minutes each. The calibrated original FIFO exceeds the 45-minute routing budget after about 25 minutes of placement. That is evidence of lower routing pressure, not a quantified frequency improvement against the unfinished baseline. The combined candidate's limiting path moves to scheduler state RAM through arithmetic (20.4 ns native logic, 19.2 ns routing); storage alone is routing dominated (3.9 ns logic, 42.5 ns routing). Coarse native DSP cascade costs remain a limitation. Required FF, BRAM and combinational-DSP endpoints pass the explicit timing audit; that audit does not certify every arc or internal clock constraint.

The unit-schedule control improves 17.75→18.17 MHz: only a 2.3% period reduction, below the registered 10–30% prediction. Its implied step changes 5.254→5.132 µs. The critical path changes from a 4.3 ns logic / 52.1 ns routing control path to the executor-request FIFO occupancy bit through arithmetic at 22.2 ns logic / 32.9 ns routing. That bit selects bypassed versus stored request data, which then traverses the executor arithmetic. Compact storage removes redundant registers but preserves this combinational bypass path; it does not create a new pipeline boundary. This one-seed result does not establish a robust timing advantage.

The accepted-write-only route was stopped after roughly twenty minutes of routing (plus 28 minutes of placement), once the compact controls completed and the microprobes showed no write-only benefit. Its remaining congestion and partial path estimates are retained, but no frequency is reported.

## Isolated FIFO

The same 424-bit depth-one registered-push/bypass FIFO is measured between preserved stimulus/capture registers at a 200 MHz request. Counts include that harness. Each row uses seeds 1–3; variance is population variance. Period statistics and individual seeds are in the JSON.

| Variant | LUT / FF | Best MHz | Mean MHz | Variance MHz² | Worst MHz |
|---|---:|---:|---:|---:|---:|
| Original | 433 / 1705 | 188.61 | 173.12 | 126.11 | 162.34 |
| Accepted push | 433 / 1705 | 177.81 | 163.33 | 242.12 | 141.74 |
| Compact storage | 428 / 1278 | 226.81 | 187.22 | 2226.73 | 120.90 |
| Compact + accepted push | 428 / 1278 | 252.84 | 211.24 | 1329.88 | 164.04 |

Placement variance is large. The accepted-push change alone does not demonstrate its predicted timing gain: the critical endpoint changes from pointer-to-enable to pointer-to-data while routing still dominates. Compact storage has a clear resource benefit, but these microprobes cannot rank the two compact variants reliably. No power estimate was taken.

## Correctness and next decision

Each candidate passes 215 XLS FIFO tests against the independent interpreter, including newly covered depth-one configurations, zero-width payloads, bypass/store/full replacement/stalls and reset. The combined 424-bit FIFO also passes twelve symbolic cycles with unrestricted inputs and later resets: a bounded equivalence check, not an unbounded proof. Four-phi and D3 RTL co-simulations run 12,000 cycles per candidate with long output stalls and reset, comparing both valid signals and every valid payload cycle for cycle. Passive debug discovery accepts the compact registered occupancy/full alias and rejects a wrong clock, capacity or full predicate.

The storage reduction merits an upstream proposal after review. Keep accepted-push writes separately assessable because their switching cost and incremental whole-core timing benefit remain uncertain. The next timing work should address the now-exposed state-read/arithmetic path and validate promising candidates with the retained vendor flow; do not insert latency solely to improve a local MHz number. Score changes by complete step time.
