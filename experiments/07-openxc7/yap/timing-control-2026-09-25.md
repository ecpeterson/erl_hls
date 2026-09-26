# Control-path campaign

Target: reduce placed-and-routed step time on xc7z030sbg485-1 without exchanging a clock gain for a larger cycle penalty. Compare current main (97b6bf9), exact tools, constraints and seeds. Preserve all failed attempts. The calibrated native model restores qualified BRAM boundaries; omitted DSP/SRL/internal constraints still prevent a whole-design safe-clock claim.

## H1: local queue updates

Before implementation: frame_queue::update_bank dynamically selects a whole two-frame queue, writes it back, then selects again from the updated bank for the push. Replace these serial selections by statically unrolled independent queues with address-decoded enables. Expect identical cycles and complete state bits, less mux area, and 20–40% less isolated bank-update delay. Whole-core gain is uncertain because the previous 60.5 ns control path also crosses executor, retirement and routing. Prove compiled combinational equivalence for singleton, power-of-two and irregular banks; run board-sized/D3 BEAM/RTL checks and stall/reset comparison; map and route matched probes before a whole-core route.

## H2: discard invalid payload retention

Before implementation: pop currently preserves an old current frame when no valid lookahead exists. The queue contract declares invalid payloads unspecified. Always copying lookahead to current should remove a payload preservation mux without changing valid frames or cycles. Predict a further 5–15% isolated bank delay reduction versus H1; check both timing and area on matched seeds and prove equivalence of validity and live payloads. Keep this separate from H1, whose equivalence includes invalid payload bits.

H2 rejected: two-queue seed periods 7.338/8.846 ns versus H1 6.657/7.069 ns; LUTs 822 versus 823. Both worst paths still traverse address decoding to a high-fanout queue-data control, with 0.9 ns reported logic delay. The superficially removed mux was largely absorbed by mapping; routing worsened instead. Validity/live-payload equivalence passed for 1/2/3/9 queues, but no complete-core candidate was built.

Full-core screening: unchanged and H1 board-sized models both complete at 93.25 cycles/step with either readiness pattern. Mapping yields 33,168→31,366 LUTs and 29,411→29,259 FF, with 56 DSP, 44 RAMB18 and 8 RAMB36 unchanged. Initial placement budget 600 seconds, then route budget 1,800 seconds, seed 1 and a matched 25 MHz target. Preserve failures and checkpoints.

Model coverage: the calibrated XLS scheduler rejects this complete optimized topology at priority selection. Its table stops at 64-bit operation widths and selected fan-ins; this topology contains 65-bit and much wider selections plus uncalibrated one-case forms. No fallback is introduced. The whole-core builds retain the unit schedule; physical probes explicitly use nextpnr-calibrated and its measured RAM boundaries.

Baseline placement exhausted its 600-second screen at heap iteration 7. Extend placement to 1,800 seconds with the identical seed/constraints, retaining the failed attempt. Routing budget remains 1,800 seconds; no seed substitution. Apply the same extension to the candidate if necessary.

The candidate also exhausted the 600-second placement screen at iteration 7. Extend it to the same 1,800-second placement budget; both initial attempts remain recorded.

## H3: local mailbox retirement

Before implementation: retire updates occupied/order arrays and then selects the same actor row again for readiness. Compute next_count and next_order directly, derive readiness from them, and perform one writeback. Enabled actors are in range by contract; disabled outcomes preserve every bit. Expect identical cycles and state, modest mux savings and 5–20% less isolated retirement delay; XLS may already forward these reads. Screen two-actor/four-message retirement before changing the main candidate.

H3 not selected: exact-state SAT equivalence passes, but two matched seed periods are 7.608/8.904 ns before and 7.988/7.880 ns after. LUTs fall only 297→285; FF remains 244. One seed regresses, one improves, and the mean gain (about 3.9%) falls below the 5–20% hypothesis. All four paths terminate at a mail_candidates bit, through address decode and remaining order/postponement selection. The change does not remove that readiness computation. Keep the stronger queue update as the sole compiler change; revisit retirement if a complete route identifies it as limiting. XLS emits inline generate-variable declarations even with Verilog selected, so the probe's Yosys reader now uses -sv, matching the full-core runner.

## H4: register phi effect handoff

Before implementation: the saved H1 placement's estimated 61.0 ns path crosses phi executor output, bypassed scheduler egress, reduction routing and ordinary mailbox write data. Register only the two phi scheduler egress FIFOs (depth 2, no bypass, registered push outputs) to split this chain, leaving source egress and executor scheduling unchanged. Predict a 20–35% shorter whole-core period with less than 10% more cycles/step; judge their product, not cycles alone. First compare accepted actor events and both readiness patterns, then map. If still plausible, screen the same placement seed/25 MHz target and route within the same 1,800-second phase budgets. This is a controlled IR experiment, not a new compiler configuration contract. Retain exact channel edits and hashes.

H1 complete-core routing: the candidate finishes in 1,022 seconds at a modeled 16.72 MHz (59.8 ns), still dominated by executor→router→egress-enable wiring (3.9 ns logic, 55.9 ns routing). The reference reaches 87 routing conflicts when its 1,800-second route budget expires. To obtain a matched reference while H4 runs, retry only that same saved placement/seed with a 3,600-second route budget; retain the earlier timeout and all commands. This extends the time limit, not the sample set or constraints.

H4 simulation: both readiness patterns match all 161 per-actor frames, but cycles/step rise 93.25→122.25 (+31.1%); break-even requires a period below 45.6 ns, versus H1's 59.8 ns. The existing interface profiler shows all 992 effects per plane waiting exactly one cycle at the new boundary instead of zero, with no additional queueing there. Consecutive gathering aggregates for the same actor advance every 8 cycles instead of 6: the boundary is paid repeatedly in the recurrence. Map and place/route to test the remaining possibility that the period gain exceeds this penalty; do not reject or adopt it from cycle count alone.

The H4 trace attributes the two-cycle recurrence increase: actor 0 retires at relative cycle 2 in both versions, but the router consumes it at 2 versus 3; actor 1 then retires at 4 versus 5 and reaches the reduction bank at 4 versus 6. The next same-actor aggregate arrives at 6 versus 8. The shared egress credit is consumed only after a registered pending receptacle, so the extra forward cycle also postpones the next retirement. Eleven interior intervals add 22 cycles; the step-boundary interval adds seven more. All four actor streams show the same distribution.

Do not disable `gate_recvs` globally to remove control masking: XLS documents zero-valued invalid/predicated receives as IR semantics, and the flag can violate those semantics. No such change was made. The current multi-proc pipeline schedules each proc before stitching; XLS's separate synchronous-network scheduler rejects predicated sends/receives and does not support this profile's fixed-stage/II request. Better operation costs do not by themselves solve bypassed inter-proc chains.
