# Scheduler pipeline plan

Design target, not implemented behavior. The [complete control-frontier audit](../results/aggregate-ready-boundary-2026-09-27.md#complete-storage-frontier) replaces the earlier endpoint-only timing screen. Use the 2×1 fixture for attribution; the application target remains a 2×4-qubit patch at 1 µs/step.

## Cut the shared cause

`SharedService` currently performs capture, result retirement, ready selection, state/mailbox reads, mailbox admission and next-selection updates in one logical activation. The `retired` value forwards freshly changed metadata directly into both dispatch and admission. XLS's common stage-completion conditions reconnect their RAM responses and channel readiness to many register enables. A channel or proc boundary alone is therefore not a pipeline cut.

The selected actor's state-read address is a recognizable midpoint: it occurs after 13 of 25 conservative primitive levels for the deepest X enable chain, and 12 of 24 for Z. However, another 25-level Z chain updates the mailbox order array, and a 24-level chain reaches the mailbox write address without crossing that landmark. A dispatch-address register alone misses these admission dependencies.

The first redesign should make **committed metadata visible before either arbitration decision**, then hand accepted work to a **registered dispatch ticket**. This divides both `retire → choose work → read/enable` and `retire → choose admission → append/write` chains. The buffer in #186 isolates a downstream load; it does not accomplish either division.

## End-to-end arrangement

These are ownership/visibility boundaries, not a promise that each becomes one XLS stage or one clock. Keep one metadata owner and one actor-state RAM. Do not copy a writable actor machine into the scheduler.

| Boundary | Responsibility | Retained value and release condition |
|---|---|---|
| Capture | Retain admitted producer requests, credits and aggregates independently of execution progress. | Pending receptacles; release only after the next owner accepts them. Credit capture must continue when retirement waits for egress. |
| Metadata owner | Apply completed state writes, mailbox admissions, retirement outcomes, credit returns and new reservations atomically. | One registered allocation/order/readiness/ownership state. No current completion or credit bypass into either arbiter. |
| Dispatch reservation | Choose an eligible actor from committed metadata; reserve its execution and a completion-storage credit. | Registered ticket with actor and work kind, plus ownership of any aggregate. Advance round-robin cursor exactly once on accepted reservation. |
| Load | Select the locked actor's stable mailbox entry, issue at most one read on each 1R1W RAM interface, and assemble responses. | Ticket, selected physical/logical mailbox indices, and reserved response space. Hold until the executor accepts the complete request. |
| Execute | Run the existing exact callback/recurrence pipeline. | Actor machine and selected input. No extra numerical-state owner; return one result for each ticket. |
| Commit | Retain the result, write actor state, and apply its mailbox/phase/failure outcome through the metadata owner. | Completion reservation remains live until the write is visible and the retirement update is accepted. No same-actor reissue before that point. |
| Publish | Drain the committed effect batch in its existing order. | Existing shared or per-actor outbox ownership; return credit only when drained. Publication cannot borrow readiness from an unrelated current dispatch. |

Mailbox admission is a parallel path: `captured request → reserve a free physical slot → write mailbox → report visibility to metadata owner`. A reserved but unwritten slot consumes capacity but is not selectable. Dispatch and admission read the same committed metadata snapshot; neither reads the other arbiter's combinational result.

Keep both arbiters beside that authoritative register bank initially: they read its current outputs, and their accepted reservations update it atomically with ticket creation at the edge. Do not send delayed metadata copies to independent arbiters and assume their grants remain valid. Splitting arbitration into a separate proc would require an explicit reservation request/acceptance protocol. The read/execution stage is separate and consumes only accepted tickets.

Use real registered producer outputs plus bounded buffering whose upstream readiness depends only on retained occupancy. A positive FIFO depth with empty bypass is not sufficient to establish forward latency. Verify both data and ready paths in generated RTL. Each stage must have a local advance condition: putting all stages behind one late `stage_done` merely recreates the old chain at their enables.

## Reservations and concurrent changes

- **Actor:** at most one ticket from reservation through commit. A completion still committing this cycle remains excluded from this cycle's grant. Fresh availability becomes usable after the metadata edge.
- **Mailbox:** retain the selected message until consume/postpone is known; do not free it at read. Appends to other free cells may overlap execution. Split admission selection from application of its delta: never replace a whole metadata row computed from an older snapshot.
- **Same-row retirement and admission:** merge the identified consume/postpone/phase change and the accepted append, preserving order and counts. Keep current failure precedence. Admission may use only capacity already free in its selection snapshot; it cannot immediately reuse a slot freed by the same-cycle retirement. Measure the resulting full-mailbox recovery bubble.
- **Aggregate:** transfer ownership of the selected pending aggregate to its ticket, or retain its receptacle under an explicit reservation until load. Later capture cannot overwrite that value. The work kind is fixed when the ticket is accepted; later arrivals remain pending.
- **RAM:** pending writes keep addresses reserved. Same-actor reads wait for state-write visibility; mailbox reads wait for the selected cell's write visibility. Other addresses may overlap when the RAM contract permits it. Start with the existing conservative write-order fence; changing its scope is a separate experiment.
- **Completion capacity:** every accepted ticket consumes a result-storage credit, regardless of whether it eventually emits effects. Returning that credit must not depend on accepting another ticket. Size and report the bound across all load/execution stages; II=1 requires enough capacity, not merely an II annotation.
- **Egress:** the small fixture uses the shared-outbox mode, **not** per-actor outboxes. Preserve both modes. Shared-mode results may await output credit in their reserved completion space; do not assume an outbox can be reserved independently for every actor. Per-actor mode retains its existing whole-batch reservation rule.
- **Commit and publication:** park any effects before releasing a result; make them publishable only when the state write and metadata retirement are committed. Reuse a retained result's storage until effect ownership transfers, rather than unconditionally adding another wide batch copy. Account for any extra visibility cycle.
- **Reset:** flush tickets, responses, completions and reservations consistently with the existing whole-design reset. This is not a new partial-recovery protocol.

Ordinary fairness remains round-robin over eligible actors, with the existing per-actor work priority sampled at reservation. Added registers can change which arrivals are visible at a decision edge; require per-actor semantic order, no loss and bounded fairness, not identical global interleaving. Directed tests must cover an arrival at each visibility edge and a held grant under backpressure.

## Staged experiment and acceptance gates

1. **Complete the measurement boundary first.** Run `control_frontier.py` on both mapped designs. It follows the selected launch to every reachable register/RAM input and external/unsupported boundary, including new endpoints. Preserve the deepest representative per category and totals before truncating detail. Add newly introduced control registers as launch signals in the next candidate; measuring only the old launches would miss an equally long replacement chain.
2. **Separate the metadata transaction from its consumers.** Split mailbox admission into reservation intent and atomic metadata application. Feed dispatch/admission from registered metadata; remove current-result/current-aggregate/current-credit forwarding into arbitration. Preserve conservative RAM ordering and existing execution/arithmetic. This is a correctness-sensitive architecture change, not just replacing `retired` with `state` in two expressions.
3. **Register the accepted dispatch ticket before load.** Reserve actor and completion capacity at the same edge, keep the ticket stable while blocked, and isolate each stage's enables. Measure metadata-to-ticket and ticket-to-read/control separately. This closes the pipeline shape even if the first metadata cut leaves selection/load too long.
4. **Only then tune execution/commit boundaries.** Preserve exact DSP arithmetic initially. Use the same all-endpoint audit for commit, publication and their replacement registers; independently test any narrower numerical-state-owner design later. Combine promising control cuts with the DSP change for matched physical timing.

**Structural hypothesis:** committed-metadata visibility removes the old combinational result-availability dependencies into both read arbitration and mailbox admission. The selected-address path suggests roughly 12–13 levels on each side of a useful cut, before new control logic. Treat **≤16 levels in each affected region** as a screening target, not a frequency forecast; abandon that prediction if reservations or enable logic reconstruct a 20+-level chain. Count CE as well as D, RAM address/enable/data and uncovered DSP boundaries. Untouched paths may remain limiting.

**Cycle hypothesis:** do not forecast unchanged step cycles. The fixture has twelve dependent diffusion rounds. One or two additional exposed clocks per round would change 79.25 cycles/step to 91.25 or 103.25 and require period reductions greater than **13.2% or 23.2%** to break even. These are latency-only scenarios, not bounds: contention, admission bubbles, commit visibility and global egress can change the answer. Instrument ticket reservation, RAM response, result, state-write visibility, retirement and first/last effect for every round; distinguish causal delay from unrelated resource ordering.

**Storage accounting:** price narrow tickets and reservation bits separately from wide request/result buffers. Keep callback precision, scheduler count, outbox mode and original application queues fixed. Never buy an apparent gain by silently reducing offered work or enlarging mailbox/outbox capacity. Reuse existing pending/completion storage where ownership permits; enumerate any new full-width copies before mapping.

**Promotion gate:** semantic and stall/reset witnesses first, whole-frontier structural comparison second, then matched routing including every new control endpoint. Use period × measured cycles/step and the actual 2×4 workload before claiming application progress. A disappearing old endpoint, lower cell-only estimate, or unchanged II is insufficient. No hardware implementation of this redesign is included in the report correction.
