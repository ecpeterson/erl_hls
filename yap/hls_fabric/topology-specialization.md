# Topology specialization campaign

This campaign is closed. `Notes/erl_xls/Roadmap.md` is the sole active task list: G5 owns selected decoder/performance work, G2/G3 cover compiler and collection contracts, G4 covers observations, and P6/G7 cover selected deployment and alternative tools. Indexed snapshots, compact control, one-hot admission and parallel publication retain their measured improvement. Later ownership, phase-control, continuation and placement probes did not justify extending the small-optimization campaign. [Architecture options](physical-architecture-options.md) preserves its original hypotheses and cost policy, not another active plan.

The campaign preserved ordinary Erlang source, logical actor identity, ordered effects, failure behavior, finite admission and coherent debug observations. Its target was sustained 1 MHz resolved sheets with bounded backlog, followed by area reduction; the finite results below do not establish that target. New work is selected only in the master.

## Retained baseline and comparison scope

The historical #65 configuration is `experiments/snowflake/actors/configurations/indexed-snapshots.json` (see [artifact lookup](../docs/artifacts.md#historical-reports)): full D3/H3 Snowflake actor decoder, 36 vertices, six shared executors, tree acknowledgments, local phase advancement, exclusive transfer/acknowledgment collectors, indexed snapshots and width-two publication. The 128-sheet p = 0.005 phenomenological cohort checks all 1,125 corrections.

| Retained stage | Mean round clocks | Routed period | Mean-round proxy | Routed LUTs |
| --- | ---: | ---: | ---: | ---: |
| Original ordinary collector control | 346.000 | 8.587 ns | 2.971 µs | 153,740 |
| Indexed snapshots and control cuts, #61 | 256.591 | 10.585 ns | 2.716 µs | 213,580 |
| Disabled next-value splitting, #62 | 256.591 | 9.903 ns | 2.541 µs | 170,147 |
| One-hot admission, #64 | 256.591 | 8.744 ns | 2.244 µs | 171,235 |
| **Width-two publication + ordinary selection, #65** | **231.087** | **9.373 ns** | **2.166 µs** | **177,323** |

#65 retains 104,659 FFs and 48 BRAM36 on XCZU7EV-2. Its 127 round gaps span 212–423 clocks, population variance 2,496.678 clocks². These are single matched setup-derived periods under a 5 ns constraint, not clock-closure or board measurements; finite mean cycles × period does not establish sustained service. The 9.226-ns restored-checkpoint result does not replace #65's uninterrupted 9.373-ns control. Sibling #66–68 experiments use their recorded parents, chiefly #64; do not interpret their percentages as #65 deltas.

Original source roots and intermediate commits identify historical evidence, not bases for new branches. Public history has since been recreated; old public PR numbers refer to the historical repository. Use the current compiler pin and current main ancestry for new work.

## Completed work

- [x] Lower the complete Erlang decoder through normal actor compilation, preserving reference state and ordered corrections.
- [x] Integrate finite early scalar collections, member-indexed snapshots, two-key leases, immutable borrowing and retirement release, with ordinary fallback when optimized placement is disabled.
- [x] Qualify empty sets, membership faults, source failure/postponement, current/successor skew, reset, blocked outputs and live observations through the retained finite fixtures.
- [x] Package reproducible builds and combined actor/executor, donor/member, collection and publication profiles; keep retained measurements outside repositories.
- [x] Diagnose indexed-storage area growth and recover device fit through constrained dispatch, local field updates, admission representation and the XLS update policy.
- [x] Improve routed timing with one-hot admission and independent validity; qualify shared payload publication with ordinary admission selection.
- [x] Reject ownership replication, local-admission, phase-field and continuation variants whose complete physical result or representative area screen loses; retain the mechanisms and controls.
- [x] Test balanced actor grouping and conditional receiver banking; retain the analysis tools without changing default placement.

The final grouping probe reduces mean round clocks by 2.18%, to 226.055; its area and routed period are unmeasured. It would lose against #65 above 9.582 ns. The continuation fold saves 6.55% of its parent's clocks but worsens round time by 2.76%. Neither is evidence that a larger scheduling gain was overlooked.

## Acceptance constraints for selected future work

G5 requires independent offered-load and burst/backlog measurement on the actual selected implementation, with wider windows justified by explicit commit/halo/time geometry and service/area need. G2/G3 cover source-derived tag ownership, membership, phase/key successors and reader lifetimes where a consumer needs stronger eligibility or reuse guarantees. G4 covers missing controller causes, transfer ancestry and feedback only for a concrete diagnostic or predictive comparison. The balanced receiver capture failed exact write replay and supplies no accepted counterfactuals.

Alternative storage/compute ownership must preserve coherent logical debug and application behavior without serializing Phi’s geometric lanes. These are acceptance constraints, not instructions to reopen the historical campaign or keep application work paused.

The current snapshot placement still asserts reserved-tag ownership, uniform keys, bounded live versions and generation-safe reuse. Runtime failures and adversarial simulations do not establish those properties for arbitrary source. A missing active member remains an obligation; inactive padding is not arrival. Monoid reductions and fixed-order gathers have different algebraic contracts. See [indexed collections](../docs/indexed-collections.md), [exclusive collections](../docs/exclusive-collections.md) and [workload acceptance](decoder-service-investigations.md).

Narrower fields, extra banks, another pipeline cut and callback folding remain possible techniques, not automatic next tasks. Choose them only through the new architecture's access/recurrence ledger. A larger busy fraction or fewer callbacks is not itself higher completed-sheet capacity.

## Evidence

- [Indexed area review](indexed-snapshot-postmortem.md): original assumptions, failed recovery predictions and field/access cost lessons.
- [Indexed control representation](indexed-admission-state.md), [one-hot admission](one-hot-admission.md), [parallel publication](collector-delivery.md): selected implementations and matched comparisons.
- [Collection communication](collection-communication.md): final receiver/placement probe and stopping decision.
- [Architecture options](physical-architecture-options.md): recent failure matrix, physical path census and proposed alternatives.

Retained evidence is under `hls_artifacts/runs/`: `indexed-snapshots-2026-10-01/`, `indexed-admission-state-2026-10-02/`, `one-hot-admission-2026-10-02/`, `collector-delivery-2026-10-02/`, `collector-ownership-2026-10-03/`, `phase-control-2026-10-03/`, `phase-protocols-2026-10-03/` and `collection-communication-2026-10-04/`. The original detailed campaign log is preserved by Git at `4c9ff19:yap/topology-specialization.md`; executable reports and controls remain external. Historical counts/settings retain their own scope.

## TE0715 deployment evidence

The [partition link](../platforms/xc7/docs/partition-link.md#physical-witness) completed two attached 4,096-exchange hardware passes. The [3+3 repetition images](../platforms/xc7/docs/repetition-link.md#physical-result-and-packaging) completed a local status round on each board, and paired PS reboot was physically exercised. These establish bounded actor/DMA/packet-link operation, not general timing, BER, sustained-load or recovery qualification. The [72-bit inferred-memory probe](../platforms/xc7/docs/bram-sdp72.md) also passed its physical patterns; the Yosys mapping correction is upstream.

P6 owns any selected next hardware slice. Its acceptance may require actual six-cell logical-memory readout (`check_repetition_link --memory`, still unqualified on the pair), safe warm lifecycle/transport replacement without PS reboot, interrupted-work and mismatched-peer handling, independent debug during blocked application traffic, and exact image/clock identities. The newer digital recovery contract does not silently qualify this older board bridge. The separate [routed regsvc image](../platforms/xc7/docs/te0715-regsvc.md) likewise retains its own uncompleted board acceptance.

Measured FCLK, DDR stress, physical CDC/reset/timing constraints and stated bidirectional load/PRBS/BER intervals remain distinct requirements. Raising the 12.5-MHz diagnostic application clock needs matched application acceptance at the new qualified rate; do not infer it from a nominal frequency or an out-of-context route.

G4 owns public packet/stage/private-link diagnostics when needed. G6/G7 own a selected tool/platform refresh, including missing `GTX_INT_INTERFACE` frame/segbits data, audited enabled features, and any upstream SDP72 hardware/structural evidence contribution. These are conditional prerequisites, not an automatic board or upstream campaign.
