# Collector delivery

Baseline: one-hot admission (PR #64), 256.590551 mean clocks, 8.744 ns routed period and 171,235 routed LUTs on ZU7EV-2. Keep ordinary actor source, per-recipient order, finite queues, protocol faults and live debug.

- [x] Join donor publication, channel handshakes, receiver capture and indexed writes on the exact baseline.
- [x] Identify substantial publication opportunity without treating overlapping waits as additive savings.
- [x] Publish a consecutive disjoint prefix using source-established payload sharing; retain dynamic checks and receiver write limits.
- [x] Compare the full 128-round cohort, blocked outputs and component/full-core synthesis; refresh causal profiles.
- [x] Finish matched routing and compare mean clocks × routed period before accepting the candidate.

Evidence: `hls_artifacts/runs/collector-delivery-2026-10-02/`. Heavy local work runs serially under a 3 GiB process-tree cap. All 88,344 internal requests and 55,692 indexed writes have exact ancestry; observed resource order remains distinct from causality.

## Hypotheses and outcomes

Registered publication forecast: 20–40 fewer clocks/round, screening against roughly 5% LUT growth. Freed router work was 39–46 clocks/group/round at width two; that was an opportunity bound, not an end-to-end prediction.

Full-frame width two saved 25.504 clocks (9.94%), but grew synthesized LUTs 18.7% (172,576→204,895). Per-destination payload selection dominated. Removing inactive-zero gates and retaining full-frame XOR differences failed component screening: router 0 still cost 3,787 / 4,015 LUTs versus 1,414 serial.

The retained candidate derives equality from typed compact-effect storage: homogeneous batches share identical live fields, with only constant differences kept separately. No application hint or sampled equality is trusted. Forecast: 16–25 fewer clocks and at most 5% full-core LUT growth. Observed: 231.086614 mean clocks, identical completion timestamps to full-frame width two; 176,496 synthesized LUTs (+2.27%), 104,134 FFs, 48 BRAM36. The example needs three constant-difference bits.

Width three failed both representations. The original full-frame version averaged 256.401575 clocks. With shared payloads, the first 16 rounds took 4,485 clocks versus 4,068 at width two: an additional router pipeline stage reduced sustained publication. The preregistered extra 8–15 clocks/round saving was not achieved; no further full-cohort or physical run was warranted.

## Validation and remaining limits

All 128 reference rounds and 1,125 corrections pass. Five production-router RTL modes cover aliases, multicast, empty batches, serial fallback, stalls, partial-send reset and bounded lookahead. A 16-round application replay blocks both outputs for 256 clocks and then returns all 117 corrections. These finite witnesses are not a general equivalence proof.

Mean result→batch wait falls 5.951→3.867 clocks and batch→send 2.525→1.570. Capture→store rises 1.441→2.669 as publication exposes receiver write contention. These overlapping intervals do not sum to the measured round saving. Width is a physical choice; independent destinations may observe different interleavings.

Physical qualification uses the same ZU7EV-2 part, 5 ns constraint, wrappers and Vivado directives as PR #64. **9.709034 ns is the calculated break-even period, not a measured slowdown or forecast.** Only the routed result establishes the throughput trade.

## Physical qualification

The uninterrupted candidate measures 9.951 ns, or 2.299543 µs/round: 2.49% slower than the original baseline despite the cycle saving. Reopening synthesis checkpoints gives 8.852 ns baseline and 10.270 ns candidate; neither procedure wins. Routed candidate area is 175,018 LUTs / 104,138 FFs / 48 BRAM36. All runs have nonnegative hold and pulse slack; these are setup-derived periods, not closure at the requested 5 ns or board validation.

The six services retain identical RTL expressions and pipeline boundaries after alpha-renaming internal identifiers. Their worst paths change during mapping and routing; the candidate’s 50 worst paths include indexed admission, retirement and ordinary mailbox bookkeeping. Restoring the baseline internal names gives exactly the same 9.951 ns and routed area; identifier changes do not explain this regression.

Two further router variants failed preregistered local area screens and were reverted: retaining the base frame across windows saved only 0.4–5.1% of representative router LUTs (target ≥10%); direct output-port predicates grew them 1.8–13.2%. Both preserved the complete 16-round event stream. Patches and measurements remain in the external archive.

An ordinary-mailbox one-hot selector preserves the entire 128-round event stream without adding a stage. Full-core synthesis costs 178,864 LUTs (+1.34% against publication alone), exceeding the registered +1% screen; its estimated period improves 8.983→8.559 ns. Total area remains within the original publication budget, so a recorded exception permitted routing. That route gives **9.226 ns and 2.132005 µs/round: 4.98% faster rounds than baseline**, with 177,323 routed LUTs (+3.56%), 104,659 FFs and 48 BRAM36. Hold/pulse checks and internal timing coverage pass. The uninterrupted confirmation gives **9.373 ns and 2.165975 µs/round (−3.46%)**, with identical area and passing hold/pulse/coverage checks. Use this matched-flow result for acceptance. Selector-only instead gives 8.992 ns and 2.307262 µs/round (+2.84% versus baseline), with 173,640 LUTs. Keep the combined implementation: neither constituent wins alone on this fixture. The selector refactor also applies to serial configurations; it is not a universally faster implementation.

Fresh 16-round profiles retain simultaneous publication lanes on separate physical tracks and preserve explicitly joined donor boundaries in receiver-focused views. Combined actor tracks remain presentation-only. All 159 actor-profile tests, two combined-view tests and 19 source-audit tests pass; the audit reports zero new/changed gaps.

Component correction: the initial depth-12 probe misread `STARTUP_COUNT` as mailbox capacity; the actual depth is 24. Full application and physical runs were correct. At the real 19/22 producer counts, full-width native LUTs grow 5.27%/9.88%; explicitly narrowed range proxies save 6.27%/9.05%. All four exact-depth probes prove all 73 outputs equivalent. The archived dimension check derives counts from named generated parameters and the depth constant; do not infer them from encoded proc names.

Acceptance: the matched uninterrupted combined run reduces round time 3.46% (throughput +3.59%) for 3.56% more LUTs, within the original 5% area budget. Both final jobs completed successfully. Keep original and restored-checkpoint results; do not select a favorable procedure or infer general PPA improvement from this one configuration.

Timing-model limit: both one-hot controls estimate 8.559 ns before routing, but route to 8.992/9.373 ns. The selector-only estimate improves against baseline while its routed clock regresses. Use early timing to screen; qualify the complete configuration physically.

## Follow-up control simplification: rejected

A same-cycle candidate exposed the accepted reservation bank before failure masking and computed consumed-offer completion from the original membership mask. Four whole-output combinational checks passed at the capacity-three fixture and actual capacity-six shape; all 75 collector DSLX/JIT tests passed. Both full128 and stalled16 transcripts were byte-identical. Integrated IR confirmed removal of the two intended dependencies. Forecast: roughly 1–1.6% potential round-time saving, zero added cycles, at most 1% incremental synthesized LUTs.

Full synthesis passed the area gate at 179,457 LUTs (+0.33%), but its estimated period worsened 8.559→9.000 ns. Matched routing gave **9.471 ns / 2.188621 µs**, 1.05% slower than the retained combined implementation, for 178,076 routed LUTs (+0.42%). The exact old retirement/cursor pairs improved 9.373→9.252 and 9.337→9.092 ns; their family maxima were 9.468 and 9.292 ns. Ordinary mailbox allocation became worst at 9.471 ns. Shorter isolated cones did not shorten the complete set of control paths.

Restore the prior production code. `transition-facts-r1/` in the external evidence directory retains the patch, finite circuit domains/tool hashes, matched path reports and rejected release. Subsequent cuts should cover complete admission and retirement transactions and all near-tied path families; a helper-depth improvement alone is insufficient. No new stage or unmeasured combination is retained.

The rejected standalone run took 63m57s: 21m28s synthesis, 17m14s placement and 20m33s routing. Its two-thread limit underused the eight-vCPU EC2 host. Future EC2 jobs select eight threads explicitly; local defaults remain two. Record and match thread settings in comparisons. These completed measurements retain their original settings; no eight-thread speedup has yet been measured.
