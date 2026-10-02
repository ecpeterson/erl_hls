# Decoder service investigations

Meet sustained 1 MHz sheet resolution with bounded backlog, then reduce area to leave room for the rest of the experiment. This note owns workload selection and acceptance; [topology specialization](topology-specialization.md) owns the current implementation sequence. Reviewed 2026-10-01 after [#59](https://github.com/ecpeterson/hls_fabric/pull/59) and public [#192](https://github.com/ecpeterson/erl_hls/pull/192) merged. Current: qualify member-indexed snapshot placement against the freshly routed control; then use the completed donor joins to choose the next bottleneck investigation.

The complete D3/H3 Erlang actor decoder now passes through normal actor lowering, with shared schedulers, tree acknowledgments, local advancement and transfer/acknowledgment collectors. The freshly rebuilt control has a mean-cycle × routed-period proxy of 2.971 µs; the historical 2.777-µs result uses different RTL; see the implementation plan for configuration, controls and limitations. Earlier custom-RTL results achieved finite 1 MHz cohorts but do not establish actor-lowered throughput. Preserve them as historical evidence, not the current baseline.

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

The reusable profiler already retains canonical/Perfetto events, causal versus resource edges and combined actor/executor tracks. Earlier finite-resource replay was checked on an independent service witness and the custom controller; it is not yet a validated replay of the current complete actor mapping.

- [x] Join exact snapshot donor effects to member writes, readiness, borrowed reads and consuming activations in the shared profile.
- [ ] Add eligibility causes, intermediate routed handshakes and transfer-donor ancestry; distinguish observed post-result retention from attributed waits.
- [ ] Add named physical capacities and recurrence ownership to the shared recording: RAM ports, executor issue, collection service and publication lanes. Extend the existing bank-lease and release observations; do not create a decoder-only format.
- [ ] Reconstruct representative actor recordings with finite buffers, port counts and recorded arbitration. Match accepted operations, queue occupancy and complete-sheet timing before proposing counterfactual schedules.
- [ ] Report resource-demand and recurrence lower bounds, then compare legal policies with changed contention and arrivals. Subtracting observed wait spans is not a rescheduling prediction.
- [ ] Qualify the reusable model on phi and a bursty fixture with delayed input and blocked output, as well as Snowflake.

Reuse the public [causal profile schema](https://github.com/ecpeterson/erl_hls/blob/main/tools/hls_profile.py) and [step reporter](../tools/phi_step_report.py). Required profiler improvements are maintained work products of this campaign. For arbitration work, require a credible complete-step opportunity of roughly 10% before replacing policy, unless a separate measured area/timing benefit justifies it.

## 2. Screen a sparse streaming decoder and its placement

- [x] Pin an external reference and reproducible fixtures; retain complete-state and ordered-correction comparisons.
- [x] Implement the complete ordinary Erlang actor lifecycle and lower it through the supported parser and backend, including autonomous phases, neighbor exchange, window movement and corrections.
- [x] Establish direct/shared placements, tree barriers, local advancement and checked transfer collectors; compare whole-application cycles, area and timing.
- [ ] Complete the next snapshot stage in [topology specialization](topology-specialization.md), preserving legal current/successor overlap and source-defined member order.
- [ ] Strengthen independent small-pattern and longer noisy-history checks of correction parity, order and logical outcomes. State noise, sample count and uncertainty; source/RTL agreement alone is not decoder validation.
- [ ] Measure sustained independently offered load and blocked-output bursts on the surviving actor configuration. The current autonomous finite transcript is not yet this qualification.
- [ ] Measure a larger normally lowered window when the current design earns a useful service/area result. Report vertex/edge work, phase exchanges, state and boundary bytes; compare constant resource budgets where possible.
- [ ] Specify a real spatial-window workload: commit dimensions, padding on each side, independent time depth, boundary masks and inter-window defect handoffs. Keep roughly 9-wide commit / 18–19-wide enclosing spatial windows in view, verifying their exact definition before implementation.
- [ ] Compare concentration, halo replication and actor granularity together when the measured work/communication ledger suggests a gain. Include snapshot/proposal retention and correction production; fewer messages do not eliminate computation.
- [ ] Investigate circular storage, equal-address/equal-version read reuse or narrow bit planes only when a required window exposes a storage/access limit or worthwhile area saving. Charge translation, flags, readers and physical ports; do not skip inactive vertices whose bookkeeping still matters.
- [ ] Consider a standalone-kernel entry point only for an independently useful compiler need. Reuse normal record/default validation; the old custom harness bypass is not evidence of an actor miscompilation.

Snapshots require a complete immutable neighborhood and fixed merge order; arrival order cannot choose priority. Growth sums, transfer XOR and busy OR have different algebraic contracts. Phase completion includes owned edge updates as well as node state. Keep those distinctions explicit when sharing machinery.

### Registered next screen: 2D workload and bounded service

Historical screen, completed 2026-09-28: the earlier kernel/replay/custom-controller predictions and outcomes are preserved in the [pre-review plan](https://github.com/ecpeterson/hls_fabric/blob/692ee4c769cbe369d4572a5b65bc8458fb712947/yap/decoder-service-investigations.md#registered-next-screen-2d-workload-and-bounded-service). Locate retained reports by their old source-relative names through [artifact lookup](../docs/artifacts.md#historical-reports). Those results do not qualify the later actor implementation or reactivate custom-engine optimization. [Window scaling](snowflake-window-scaling.md) likewise preserves a historical design study; the pending actor/window gates are above.

## 3. Test conflict-free bank ownership

Phi's geometric reduction plane already admits independent source lanes outside actor RAM. The transfer collector serves a different actor protocol. Share lifecycle, observation and storage contracts where useful without serializing phi's lanes.

- [ ] Derive phase-local producers, destinations and accesses from a protocol summary; accept checked placement hints where inference is insufficient. Keep capacity, membership and identity separate from geometry.
- [ ] Compare bank layouts against actual bursts and all allowed concurrent reads/writes, including collector readers and debug service. A bank per direction does not automatically exclude competing producers.
- [ ] Distinguish static ownership from timed service classes; remove an arbiter only where contention is impossible. A dynamic fallback usually retains its mux and selection cost.
- [ ] Evaluate raw member-indexed values plus epoch metadata against shared accumulators, preserving required write parallelism and complete-population failure obligations.
- [ ] Promote only a candidate with measured storage/mux savings and adequate complete-workload service. Activate this stream when snapshots or a required larger window expose a concrete need.

Local schedules must tolerate late arrivals and retain accepted work. A shared route must not wait for one remote input while blocking another needed for progress. No globally timed Ethernet calendar is proposed. Dynamic membership can use identities for a declared monoid; arbitrary gathers need explicit membership and ordered access.

## 4. Census regular phases before specializing them

- [ ] Derive handled/postponed tags, reductions, read/write fields, effects, key progression and possible next phases from the compiler's finite message union. Keep unknown guards/effects explicit; share this summary with collection eligibility and protocol checks.
- [ ] Permit wildcard postponement as a source simplification over that union, retaining clause order, invalid-input failures and supported source semantics. Cleaner matches do not by themselves establish less hardware work.
- [ ] After snapshot offload, recensus remaining mailbox searches and actor visits before specializing eligibility or ownership. Preserve eligible-message order, fairness and phase-change wakeup.
- [ ] Identify a regular phase whose local resources can be reserved together. Count precisely which existing selections, RAM visits and feedback clocks disappear; repackaging today's reservations is not an improvement.
- [ ] Bound the complete-application benefit in the validated model before implementation. Retain early arrivals, epoch validation, failure draining where promised and finite output ownership.

Sources: [actor selection](../priv/xls/lib/scheduler.x), [mailbox admission](../priv/xls/lib/mailbox.x), [service ownership](../src/backend/xls_shared_codegen.erl), [collection semantics](../docs/execution/actor-reductions.md). Closure alone does not establish valid messages, safe epochs or permission to elide failures.

## Measurement discipline

Preregister the exact baseline, controls, eliminated work, competing limits and rejection criterion. Predict component demand before conditional whole-application gains. Refresh historical visit counts before using them as opportunity bounds; visits are not elapsed clocks.

Reuse recordings and local screens. Route the final surviving combination against a matched control, reporting complete-round cycles × period, area and all competing path families; avoid routing obvious cycle/storage losers. Keep source/tool identities, failures and rejected variants in the external artifact archive. Simulations are witnesses; any formal claim must name its domain, assumptions and trust boundary.
