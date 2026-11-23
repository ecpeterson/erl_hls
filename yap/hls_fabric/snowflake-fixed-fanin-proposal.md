# Buffered completion joins: bounded next probe

Reviewed 2026-10-01. Original physical proposal superseded by merged PR #59. Root and leaf acknowledgments now use shared checked collectors, rather than the exact independent-lane join proposed below. Further parallel fan-in is a profile-gated port/storage option in [the service plan](decoder-service-investigations.md), not unfinished baseline integration. Parser restrictions below also predate public PR #192.

Status: deferred implementation after measuring the locally advanced protocol. Root intake remains a candidate; the short leaf tail does not justify replacing leaf actors yet.

## Evidence and decision

The saved eight-sheet stress run contains 56 phase quorums. Its mean last-vertex-publication → last-coordinator-admission interval is 13.70 clocks, but this mixes the expensive drop/grow quorums with merges. Local advancement removes three quorums per sheet: kinds 0, 1 and 3.

| Old-profile subset | Quorums | Last vertex publication → last leaf aggregate | Last leaf aggregate → last coordinator admission |
| --- | ---: | ---: | ---: |
| All phases | 56 | 2.79 mean | 10.91 mean |
| Drop/grow, removed by local advancement | 24 | 3.83 mean | 15.50 mean |
| Merge, retained by local advancement | 32 | exactly 2 | 7–8, mean 7.47 |

These are publication/admission boundaries, not pure compute latency or a critical-path attribution. Leaf collection overlaps vertex work. The old merge data supports investigating the root intake before changing leaf collectors: their final contribution already produces an aggregate two clocks later. Neither row predicts the new protocol's timing.

Evidence: `scheduler-private/_build/snowflake-control-compaction/baseline-retirement/focused.summary.json`, SHA256 `63ad79e4e13376d34c6628a8fbc27638f1c1cbf76db40838470830f8e158bfeb`. This is the eight-sheet stress cohort, not the 128-sheet 0.5% cohort.

## Reuse and missing capability

An ordinary `hls_statem` reduction can express the logical operation: one completion per member, all with the opened epoch and phase, OR their busy flags, then execute the coordinator once. Ordinary reduction delivery still admits six mailbox messages; merely rewriting the callback does not remove that traffic.

The existing physical source-fragment placement is not a setting we can apply directly. `hls_reduction_plan` requires scheduled two-dimensional families, complete unconditional contribution prefixes, and reciprocal same-family translations. Snowflake's vertex → collector → root graph is heterogeneous fan-in among singleton actors. Keep those existing checks; a new explicit fixed-fan-in placement needs its own closure and storage argument.

Reusable pieces are the public reduction parser/aggregate fold, `hls_partition_reduction_dslx`'s independent input receives plus opening token, and the shared executor's `aggregate_only` delivery. A dedicated coordinator currently lacks that aggregate endpoint. The smallest compiler probe is a one-actor shared coordinator with six explicit contributor lanes, using the existing aggregate service; compare it with the same one-actor shared coordinator using ordinary reduction delivery to separate executor overhead from fan-in placement.

The parser currently requires a literal count or member set. It also requires message-only contribution capture. The current collectors use configured source intervals and state-dependent epoch matching. The root is the easier first target: six known collector identities 0–5 and a reduction opened when its phase command is published. Do not disguise source IDs with modulo arithmetic or truncate the 32-bit epoch to encode the phase. Keep the full epoch; carry phase agreement in the aggregate and check it against the opened phase before advancing.

## Storage and protocol obligations

Give each contributor an independently backpressured slot, join the six slots after the matching opening token, and retain the resulting aggregate until accepted. Keep startup readiness and incoming syndrome sheets on the ordinary path. This preserves the eight-credit input contract and avoids storing sheets in the completion lanes.

For valid traffic, one slot per source is sufficient: a source emits at most one terminal completion for each root command, and the root cannot issue the next command before consuming this complete set. A completion may beat its opening notification, so the slot must accept before the opening token arrives. A following completion cannot exist before the previous complete set has been consumed by the root. This argument depends on the command/completion protocol, not the reciprocal-exchange argument used by existing two-slot source fragments.

Check foreign source, duplicate source, malformed payload, wrong epoch, wrong phase and rollover explicitly. A duplicate cannot become a valid contribution to the next epoch. Define failure timing before implementing: the existing reduction contract drains a failed set, whereas the current collector can fail on the offending message immediately. Valid-result equivalence alone does not establish equivalence of those failure paths. Do not weaken diagnostics or introduce a wait for an impossible contributor without stating the protocol change.

Six raw completion records contain 294 semantic bits: six times `(source:8, epoch:32, kind:8, busy:1)`. Six existing 128-bit actor frames require 768 payload-storage bits, plus valid/opening/output state. Direct lane wiring can make source identity implicit only after proving the endpoint membership; otherwise keep and validate it. These are storage-accounting bounds, not LUT estimates. Retaining the old mailbox alongside the new lanes could increase area. Removing its completion capacity is a separate measured change because it still holds startup traffic and eight offered sheets.

## Preregistered experiment

- [ ] Obtain post-local-advance profiles with accepted per-lane input, opening, aggregate publication and coordinator execution. Compare the same eight-sheet stress and 128-sheet 0.5% cohorts; report merge kinds separately. Investigate the root only if its residual join/intake remains a visible serial tail.
- [ ] Build a six-member ordinary `hls_statem` reduction fixture through the normal compiler, then a fixed-fan-in placement of that same fixture. Exercise all arrival permutations, a delayed lane/opening/output, duplicate/foreign/stale/future/phase-invalid reports and epoch rollover. Hold all capacities equal for the initial comparison.
- [ ] Integrate root fan-in only; retain the six existing leaf actors. Compare against a matched ordinary-reduction coordinator using the same actor mapping. Preserve exact per-site correction values/order and round identities; measure steady-state cycles, mean/p95 step time, root tail and queue occupancy. Synthesize both at the same constraint before predicting a routed result.
- [ ] Consider leaf conversion only if the new profile exposes meaningful leaf serialization or a justified storage saving. Do not multiply the old 13.70-clock mixed-phase mean by the new quorum count.

Hypothesis: root fan-in removes five ordinary completion activations per remaining quorum and the corresponding serial admission work. If the old 7–8-clock root tail persists, the maximum improvement available from eliminating that entire measured interval is 7–8 clocks per quorum; a real join still needs opening, aggregate transport and coordinator execution. No numerical net step-rate or area improvement is registered until the new profile and matched executor control establish those costs. For the existing 128-sheet quiet fixture's 290 retained quorums, five fewer activations means 1,450 fewer completion activations, not 1,450 saved clocks.

## Post-local-advance observation

The eight-sheet stress profile has 32 retained quorums. Last vertex publication → last leaf aggregate is now 2–3 clocks (mean 2.59375, population variance 0.241211). Last leaf aggregate → last coordinator admission is 5–9 clocks (mean 6.78125, variance 1.483398). Together they span 7–12 clocks (mean 9.375, variance 1.859375). These statistics use actual terminal completions, not a mixture of intermediate local phases and root commands.

This supports root intake before leaf replacement, but the expected gain is modest relative to the measured 400.8 clocks/round. Eliminating the entire observed intake interval is an optimistic counterfactual; any real join retains transport and execution latency. Balanced neighbor selection now removes the executor arithmetic leader from the separate complete-core synthesis sample. Mailbox-write control and the cost of repeated state visits remain higher priorities. Revisit fixed root fan-in using the same causal boundaries; the six-executor local-advancement placement is a separate measurement cohort. The profile source is `snowflake-probe/_build/local-advance-activations8`; raw observations are unchanged by rendering or command-grouping updates.
