# Collection communication investigation

Preregistered 2026-10-04. Start from #65's parallel-publication plus ordinary-mailbox selector configuration: 231.086614 mean round clocks, 9.373 ns matched routed period, 2.165975 µs/round, 177,323 LUTs. Keep source semantics and independent actor observation. #68's rejected continuation fold is not included.

The opening issue burst does not establish sustainable throughput. The prior six-actor excerpt required sixteen member writes per snapshot generation through one write port; completed collections dispatched two clocks after their final write. Target delivery capacity and ordering before changing actor selection.

- [x] Reconstruct named publication lanes, producer receptacles, indexed write ports and collection readiness from exact donor joins. Validate identities and account for every recorded member.
- [x] Replay the observed decisions and finite occupancy before counterfactuals. Separate externally fixed arrivals/eligibility from modeled feedback; refuse an end-to-end speedup claim from a conditional receiver replay.
- [x] Compare original ordering, legal work-conserving ordering, and two/six physical member banks. Preserve producer order, captured membership, generations, row lifetime and shared read/commit limits. No globally timed network calendar.
- [x] Quantify which completion tails move, remaining causal dependencies and input/output demand. Require a credible roughly 10% complete-round opportunity before a substantial backend redesign; local gains alone justify instrumentation, not a promised application gain.
- [x] If the evidence warrants hardware, preregister its cycle/area budget and qualify the complete application. Otherwise retain the useful model and identify the remaining unknowns without promoting a scheduling option.

Initial hypothesis: width-two publication exposes receiver contention; independent write banks should reduce some collection-completion waits, while changing order alone can only redistribute the single port's slots. No quantitative round-time saving is assumed until the replay passes its validation boundary. Any capacity experiment must charge arbitration, metadata updates, read assembly and physical BRAM dimensions—not just payload bits. Retained evidence belongs in `hls_artifacts/runs/collection-communication-2026-10-04/`; local jobs run sequentially under the existing memory limit.

## Placement probe, before implementation

The 16-sheet #65 capture has 1,260 activations per executor, but snapshot demand is `[16,16,19,19,16,16]` member writes per generation. All 69 last collection completions belong to groups 2 or 3. Redistribution can balance 102 contributions across six ports at 17 each: at most 10.5% less work on the busiest port, not a 10.5% round-time forecast. Try one deterministic degree-balanced permutation while keeping six actors per executor, logical identities, barrier membership, source and transport width unchanged. Screen producer fan-in and cross-group edges before compilation; compare complete RTL transcripts/cycles against the immutable control. Hypothesis: balancing receiver demand can advance the slowest completion tail, but may lose locality or increase publication contention. Expect a small (0–5%) round-cycle improvement, with failure to improve a useful negative result. No clock/area improvement is presumed; no routed run is justified by a marginal cycle result alone.


## Result and stopping decision

The receiver replay reconstructs every write/completion in the retained #65 16-sheet trace (7,038 / 2,484) and the earlier width-two 128-sheet trace (55,692 / 19,656). The latter has the same complete external cycle transcript as #65 but different internal RTL; the report retains each identity. This qualifies those recordings, not arbitrary schedules.

Under frozen arrivals, actor transitions, consumer acquisitions and row releases, six independent actor banks advance the final collection in a generation by 2.04 clocks on average (maximum five). Two actor banks and the reordered single-port cases invalidate at least one fixed input/consumer boundary. Their partial savings are not accepted predictions: a coupled upstream simulation would have to move the affected events. Do not multiply per-collection savings to claim a round improvement.

The complete-application placement probe balances writes from `[16,16,19,19,16,16]` to `[17,17,17,17,17,17]`; cross-group edges rise from 42 to 50. It keeps six actors per executor, logical identity, protocol, barrier membership, transport width, optimizer pipeline and completion storage fixed. Regenerated control actor/topology DSLX is byte-identical to the retained control; vector differences are provenance metadata only.

| Round-gap clocks | Control | Balanced |
| --- | ---: | ---: |
| 16 sheets: mean | 235.600 | 230.133 |
| 128 sheets: mean | 231.087 | 226.055 |
| 128 sheets: min / max | 212 / 423 | 206 / 406 |
| 128 sheets: population variance | 2,496.678 | 2,257.863 |

Both complete cohorts check the reference corrections (117 / 1,125). The balanced sixteen-sheet replay also passes seven-cycle stalls on both outputs; passive observation preserves the exact unstalled external transcript. These are simulation witnesses. The 2.18% cycle saving is within the registered 0–5% expectation. Area and routed timing remain unmeasured: a period above 9.582 ns would erase the gain against #65's 9.373 ns. The default placement stays unchanged.

All tied last-write branches remain in the analysis. In the sixteen-sheet control, their mean result-to-batch interval is 8.43 clocks versus 3.80 capture-to-write; balancing changes these to 6.87 and 2.73 but increases producer-result spread from 8.67 to 11.23. These are observed overlapping-path components, not independently recoverable costs. Equalizing receiver totals cannot preserve the initial issue pattern while dependencies and publication capacity continue to shape readiness.

The new layout also exposes the receiver model's boundary: two of 7,038 writes are predicted three clocks early, although every collection completion matches. The analyzer rejects its counterfactuals rather than extrapolating. It does not yet observe controller-wide commit stalls; that is a candidate explanation requiring observation, not an established diagnosis. Fresh donor joins and profiles are valid independently of that model.

Close this performance campaign. This was a bounded check, not stage one of a demonstrated larger gain. Keep the explicit placement option, exact-replay checks and all-tie delivery analysis for future workloads; do not add receiver banks, scheduling policy or routing work on this evidence. Resume architecture exploration only with a separately motivated plan.

Evidence: `hls_artifacts/runs/collection-communication-2026-10-04/`: `comparison.json`, `placement/placement-proposal.json`, `receiver128.json.gz`, `balanced128/result.json`, `balanced-stalled16/result.json`, `balanced-profile16/`, and `balanced-views.{perfetto.json,overview.svg}`. The local converter exceeded the 3 GiB guard; the previously qualified EC2 converter plus unchanged local optimizer/codegen completed with about 2.01 GiB local aggregate peak. Qualification peaked below 0.76 GiB. No physical jobs were started.
