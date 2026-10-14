# Decoder service investigations

Meet sustained 1 MHz sheet resolution with bounded backlog, then reduce area to leave room for the rest of the experiment. This note owns workload selection and acceptance; [topology specialization](topology-specialization.md) summarizes the completed implementation campaign. Updated 2026-10-04. [Architecture options](physical-architecture-options.md) records the next proposals for review, emphasizing physical ownership/locality and regular-protocol transaction removal; no new implementation is selected.

The complete D3/H3 Erlang decoder passes through normal actor lowering. The selected #65 indexed/parallel-publication control has a 2.166 µs mean-cycle × routed-period proxy (231.087 clocks, 9.373 ns, 177,323 LUTs), versus the original 2.971 µs control. Later conditional receiver and balanced-placement probes do not establish another routed gain. Earlier custom-RTL finite 1 MHz cohorts are historical evidence, not actor-lowered throughput. See the campaign summary for exact controls and limitations.

Snowflake, application placement and distribution remain private. Public compiler changes require independent usefulness and generic fixtures. Do not substitute a custom decoder engine behind a thin actor wrapper.

## Decisions from the discussion

- Optimize completed work per sheet, not pipeline utilization. More actors can fill a pipeline while increasing its total work.
- Preserve phi's algorithm, precision and round count. Alternative decoders require separate validity checks, not only lower hardware cost.
- Treat actor granularity, schedulers, placement and storage ownership as provisional. Concentration and halo replication must charge all extra work, state, ports and boundary traffic.
- Use conflict-free access information and inferred regular phases where they preserve ordinary actor semantics. ERTS can ignore placement hints; topology alone does not establish conflict freedom.
- Separate hardware limits from mapping limits. The completed UltraScale+ screen supports that distinction; only matched complete-application timing supports a deployment claim.
- Preserve causal dependencies separately from observed scheduling. Neither a shortened isolated path nor a larger busy fraction establishes higher service capacity.

## Objective and controls

Offer syndrome sheets independently of decoder readiness. Count offered, accepted, completed and pending sheets, including sheets with no corrections; preserve site correction order and the finalized horizon. Report backlog trajectories, latency/service distributions, storage peaks and overload behavior. A finite stable recording is evidence, not a guarantee for every noise history. A hard per-correction deadline is not presently required.

Use 0.5% phenomenological data/measurement error probability as the main cohort, 0.2% as a sensitivity control and 2.5% as stress. Preserve seeds, geometry and noise assumptions in paired comparisons; these probabilities are not circuit-level physical error rates. Algorithmic validity, source/RTL agreement and physical rate are separate obligations.

Keep the physical 4×2-qubit acquisition patch distinct from decoder placement. Spatial commit width, halo, temporal depth and CSS sectors are independent dimensions. Whole-code d=3→d=5 grows space and time together; it is a scaling control, not a spatial-window implementation. Once sustained 1 MHz with burst margin is demonstrated, prioritize area rather than higher peak rate.

## 1. Validate the service model

The reusable profiler retains canonical/Perfetto events, causal versus resource edges, combined actor/executor tracks and snapshot donor joins. The conditional receiver model exactly reproduces retained control writes/completions, but freezes upstream arrivals and consumer timing. It is not a whole-application counterfactual scheduler and rejects the balanced layout's two mismatched writes. Extend it only for a selected architectural question.

- [x] Join exact snapshot donor effects to member writes, readiness, borrowed reads and consuming activations in the shared profile.
- [ ] Add eligibility causes, intermediate routed handshakes and transfer-donor ancestry; distinguish observed post-result retention from attributed waits.
- [ ] Add named physical capacities and recurrence ownership to the shared recording: RAM ports, executor issue, collection service and publication lanes. Extend the existing bank-lease and release observations; do not create a decoder-only format.
- [x] Reconstruct retained collection writes/completions with finite producer slots and exact baseline checks; reject counterfactuals that violate fixed capture/acquisition boundaries.
- [ ] Couple producer/consumer feedback, recurrence ownership and finite resources before forecasting complete-sheet schedules; retain exact baseline reproduction and explicit unsupported cases.
- [ ] Report resource-demand and recurrence lower bounds, then compare legal policies with changed contention and arrivals. Subtracting observed wait spans is not a rescheduling prediction.
- [ ] Qualify the reusable model on phi and a bursty fixture with delayed input and blocked output, as well as Snowflake.

Reuse the public [causal profile schema](https://github.com/ecpeterson/erl_hls/blob/main/tools/hls_profile.py) and [step reporter](../tools/phi_step_report.py). Required profiler improvements are maintained work products of this campaign. For arbitration work, require a credible complete-step opportunity of roughly 10% before replacing policy, unless a separate measured area/timing benefit justifies it.

## 2. Screen a sparse streaming decoder and its placement

- [x] Pin an external reference and reproducible fixtures; retain complete-state and ordered-correction comparisons.
- [x] Implement the complete ordinary Erlang actor lifecycle and lower it through the supported parser and backend, including autonomous phases, neighbor exchange, window movement and corrections.
- [x] Establish direct/shared placements, tree barriers, local advancement and checked transfer collectors; compare whole-application cycles, area and timing.
- [x] Qualify indexed snapshots and the selected control/publication changes through complete actor lowering and matched physical measurements; preserve current/successor overlap and source-defined member order.
- [ ] Select a locality/regular-phase architecture from [the proposals](physical-architecture-options.md) after a connected access/recurrence budget; do not resume the rejected micro-optimization queue.
- [ ] Strengthen independent small-pattern and longer noisy-history checks of correction parity, order and logical outcomes. State noise, sample count and uncertainty; source/RTL agreement alone is not decoder validation.
- [ ] Measure sustained independently offered load and blocked-output bursts on the surviving actor configuration. The current autonomous finite transcript is not yet this qualification.
- [ ] Measure a larger normally lowered window when the current design earns a useful service/area result. Report vertex/edge work, phase exchanges, state and boundary bytes; compare constant resource budgets where possible.
- [ ] Specify a real spatial-window workload: commit dimensions, padding on each side, independent time depth, boundary masks and inter-window defect handoffs. Keep roughly 9-wide commit / 18–19-wide enclosing spatial windows in view, verifying their exact definition before implementation.
- [ ] Compare concentration, halo replication and actor granularity together when the measured work/communication ledger suggests a gain. Include snapshot/proposal retention and correction production; fewer messages do not eliminate computation.
- [ ] Investigate circular storage, equal-address/equal-version read reuse or narrow bit planes only when a required window exposes a storage/access limit or worthwhile area saving. Charge translation, flags, readers and physical ports; do not skip inactive vertices whose bookkeeping still matters.
- [ ] Consider a standalone-kernel entry point only for an independently useful compiler need. Reuse normal record/default validation; the old custom harness bypass is not evidence of an actor miscompilation.

Snapshots require a complete immutable neighborhood and fixed merge order; arrival order cannot choose priority. Growth sums, transfer XOR and busy OR have different algebraic contracts. Phase completion includes owned edge updates as well as node state. Keep those distinctions explicit when sharing machinery.

### Historical custom-controller screen

Historical screen, completed 2026-09-28: the earlier kernel/replay/custom-controller predictions and outcomes are preserved in the [pre-review plan](https://github.com/ecpeterson/hls_fabric/blob/692ee4c769cbe369d4572a5b65bc8458fb712947/yap/decoder-service-investigations.md#registered-next-screen-2d-workload-and-bounded-service). Locate retained reports by their old source-relative names through [artifact lookup](../docs/artifacts.md#historical-reports). Those results do not qualify the later actor implementation or reactivate custom-engine optimization. [Window scaling](snowflake-window-scaling.md) likewise preserves a historical design study; the pending actor/window gates are above.

## 3. Physical locality and conflict-free ownership

Review owner-local tiles, versioned neighbor access and fixed channels together; the [architecture proposals](physical-architecture-options.md) define discriminating screens. The completed six-bank conditional replay and demand-balanced layout do not justify more write ports alone. Phi's geometric reduction plane already admits independent source lanes outside actor RAM. The transfer collector serves a different actor protocol. Share lifecycle, observation and storage contracts where useful without serializing phi's lanes.

- [ ] Derive phase-local producers, destinations and accesses from a protocol summary; accept checked placement hints where inference is insufficient. Keep capacity, membership and identity separate from geometry.
- [ ] Compare bank layouts against actual bursts and all allowed concurrent reads/writes, including collector readers and debug service. A bank per direction does not automatically exclude competing producers.
- [ ] Distinguish static ownership from timed service classes; remove an arbiter only where contention is impossible. A dynamic fallback usually retains its mux and selection cost.
- [ ] Evaluate raw member-indexed values plus epoch metadata against shared accumulators, preserving required write parallelism and complete-population failure obligations.
- [ ] Promote only a candidate with measured connected-component costs and improved complete-workload service; include local controller reach, boundary wiring and competing paths, not just storage/mux counts.

Local schedules must tolerate late arrivals and retain accepted work. A shared route must not wait for one remote input while blocking another needed for progress. No globally timed Ethernet calendar is proposed. Dynamic membership can use identities for a declared monoid; arbitrary gathers need explicit membership and ordered access.

## 4. Compile regular regions only with a transaction-saving plan

The rejected prototype derives explicit field accesses, callback outcomes and unresolved operations through local acyclic helpers, then selects one narrow checked continuation. It does not infer tag ownership, legal epoch overlap or general phase protocols. The 128-sheet witness saves 6.55% of mean clocks but worsens routed round time by 2.76%; the implementation remains an external patch. The source-census and scheduling ideas below need a new measured opportunity before more implementation.

- [ ] Derive handled/postponed tags, reductions, read/write fields, effects, key progression and possible next phases from the compiler's finite message union. Keep unknown guards/effects explicit; share this summary with collection eligibility and protocol checks.
- [ ] Permit wildcard postponement as a source simplification over that union, retaining clause order, invalid-input failures and supported source semantics. Cleaner matches do not by themselves establish less hardware work.
- [x] Recount post-snapshot actor visits and test bounded continuation folding; fewer callbacks did not improve its parent's routed round time.
- [ ] Identify complete loader, ownership, routing or retirement transactions that a regular-region lowering can remove; preserve eligible-message order, fairness, phase-change wakeup and all mandatory decoder phases.
- [ ] Identify a regular phase whose local resources can be reserved together. Count precisely which existing selections, RAM visits and feedback clocks disappear; repackaging today's reservations is not an improvement.
- [ ] Establish a complete-sheet access/recurrence budget before implementing a region; do not treat the current conditional receiver model as a validated global scheduler. Retain early arrivals, epoch validation, failure draining, finite output ownership and coherent logical debug.

Sources: [actor selection](../priv/xls/lib/scheduler.x), [mailbox admission](../priv/xls/lib/mailbox.x), [service ownership](../src/backend/xls_shared_codegen.erl), [collection semantics](../docs/execution/actor-reductions.md). Closure alone does not establish valid messages, safe epochs or permission to elide failures.

## Measurement discipline

Follow the [tooling boundaries](../STYLE.md#tooling-boundaries): compiler processing belongs in Erlang; simulation inspection should converge on the same debug channel and native APIs used on-device. These are incremental migration targets, not prerequisites for retaining existing measurements.

- [ ] Move `experiments/snowflake/actors/transfer-collection/publication_boundary.py` channel-policy lowering into the Erlang backend when extending or promoting it. Exercise the existing publication-boundary fixtures against the Erlang entry point and preserve source/IR/RTL guards; keep Python for orchestration and report processing.
- [ ] Use `tools/test_topology_debug_integration.py` and `test/hls_actor_debug_live.erl` as the starting fixtures for profiler/debug-channel coverage. Map each required observation to public snapshots, counters or traces, and record unsupported fields and event rates explicitly.
- [ ] Replace private taps incrementally with manifest-backed, timestamped, bounded debug observations and Erlang consumers. Compare supported observations through the simulated transport under stalls/reset, check application noninterference, and expose overflow/loss before retiring a probe. Preserve internal event history where snapshots are insufficient; price on-device storage and bandwidth.

Preregister the exact baseline, controls, eliminated work, competing limits and rejection criterion. Predict component demand before conditional whole-application gains. Refresh historical visit counts before using them as opportunity bounds; visits are not elapsed clocks.

Reuse recordings and local screens. Route the final surviving combination against a matched control, reporting complete-round cycles × period, area and all competing path families; avoid routing obvious cycle/storage losers. Keep source/tool identities, failures and rejected variants in the external artifact archive. Simulations are witnesses; any formal claim must name its domain, assumptions and trust boundary.
