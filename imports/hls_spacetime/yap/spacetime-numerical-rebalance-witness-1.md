# Numerical rebalance across the existing owner boundary

The new RTL witness matches the prospectively frozen **99-clock selected step, 498-clock steps-4–8 interval, and 593-clock complete suffix**. Both Phi actors split their arithmetic across the existing action/entry boundary. No extra service edge is added, and every accepted public word retains its baseline value and clock. No Vivado or EC2 run was performed.

## Intervention

The first existing edge stores two signed 36-bit diffusion numerators together with the completed non-phi action metadata: next epoch/phase, reduction disposition, directive and phase boundary. The existing `action_valid` flag owns this unfinished action. A separate mode bit identifies its numerical representation; it does not introduce another busy clock.

On the following existing entry/commit edge, the owner rounds, adds the anyon contribution, saturates, inserts the final phi into the saved action, and executes ordinary entry/publication. A blocked entry retains the partials and metadata and recomputes only the pure arithmetic suffix. It preserves the old-state outbox rule, including no reuse on the last-drain edge. Ordinary actions and reduction receipts retain their intrinsic behavior. Phase/control decisions stay in the first stage; the second stage does not recompute the completion callback.

The isolated candidate reuses the original generated source population and compiler settings. A diagnostic enable is false through C1774 and true afterward; admission retains its mode even if that input changes while an action is outstanding. Enabled ordinary actions explicitly preserve phi, allowing the unused original arithmetic result to be pruned from that branch. The disabled diagnostic branch still retains the old arithmetic. This is not a qualified constant-enabled physical candidate.

## Frozen prediction and observed result

The prediction was saved before implementation. It reuses the control model’s already-qualified zero-extra-latency schedule: this is a prospective test of preserving that schedule, not a newly calculated scheduler response or a blind workload holdout. The host retains the original offered-input floors, absolute output-ready calendar and response gaps, with releases gated by actual candidate output completion. Expected acceptance clocks are assertions, never stimulus.

| Interval                   | Predicted clocks | RTL clocks | Error |
| -------------------------- | ---------------: | ---------: | ----: |
| Step 4                     |               99 |         99 |     0 |
| Steps 4–8                  |              498 |        498 |     0 |
| Full suffix through step 9 |              593 |        593 |     0 |

Step completions remain C1873, C1972, C2082, C2174, C2272 and C2367; readout completes at C2306. All 70 accepted input words and 153 output words, across 30 output frames, have identical values and clocks. Meaningful public pins also agree during stalls. The complete 2,369-sample capture includes pre-edge C2368, so the C2367 transition has its following Q observation. The subsequently evaluated C2368 transition has no captured Q and is not claimed.

The independent comparison checks 127,926 source-bound control values across all six actors, 56,856 shared exact-width Phi owner field values, and 4,738 committed-machine samples. All match. It checks 346 active private-action samples after reconstructing the numerical phi from saved numerators and the private word’s own anyon; raw partial words intentionally differ. There are 143 enabled numerical launches and 22 numerical blocked-entry samples. The frozen model matches 1,209 Phi boundary events, 17,790 control values, 90 remaining output words and 36 input words. Its `private` event now denotes the existing action-storage boundary, not physically completed arithmetic.

Ten narrowed/eliminated source fields remain uninterpreted: each Phi owner’s action slot, inbox-started state and outbox count/index/layout. They are not treated as decoded source bits. Public behavior and source-qualified control taps are checked independently. Fixed source work and branch decisions remain model assumptions; this witness does not establish unrestricted equivalence or behavior on unseen workloads.

## Structural and local qualification

Fresh source/raw-IR/optimized-IR/RTL bindings recover all requested controls without unsupported entries. Generated RTL contains four 36-bit numerator registers and two one-bit mode registers. Whole-word assignment reachability connects every numerator to its own committed-state and outbox D logic. This verifies a real registered arithmetic intermediate, not an idle delay after a complete result; it is not a sensitized bitwise path proof or a routed-period estimate.

Six owner tests and a 1,000-case composition quickcheck pass under XLS IR-JIT with seed 20261108. They cover unchanged two-edge completion, blocked publication and final-drain behavior, reset cancellation, ordinary receipts, the final diffusion transition into comparison, stale-mode clearing before ordinary work, and reconstruction of the original action/entry result for arbitrary encoded arithmetic inputs under the successful numerical branch. The unchanged arithmetic split tests were reused from the earlier experiment rather than repeated.

Exactly one new RTL witness ran. All local jobs ran serially under the 6 GiB guard and ended without surviving process groups or guard triggers. The first comparison adapter failed because model input words use `word` while output words use `data`; its script and diagnostic are retained. Correcting that schema normalization required only the comparison rerun. No hardware failure or RTL rerun occurred. All 174 original compiled files remain byte-identical.

## Retention and consequence

Artifacts are in `/Users/ecpeterson/Documents/code/hls_artifacts/runs/spacetime-2026-11-08/numerical-rebalance-witness-1/`. `preregistration.json`, `predicted-schedule.json`, `comparison-2.json` and `final-review.json` separate prediction, observation and assessment. The 3,267,960-byte reproduction archive contains 370 hash-verified files: exact candidate sources/IR/RTL, harness, taps, original trace, prediction/profile, comparison inputs, command records and diagnostics. Its README explains original-path relocation and reused tools. Bulk scratch products remain subject to the seven-day policy.

This passes the functional and scheduling experiment. The repeated latency cost of the earlier three-edge pipeline is absent. Whether the second-stage arithmetic plus entry/publication improves the physical period remains unmeasured; no fixed-layout delay estimate or speedup claim is added. A future physical trial must first qualify the constant-enabled design and remove the diagnostic legacy path. A different workload or a changed scheduling response would provide stronger further validation of the control predictor.
