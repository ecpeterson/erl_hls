# Admission selector and reservation cut

Reviewed 2026-10-01. Historical proposal, partly rejected and partly deferred. The [selector-only variant](snowflake-admission-selector-native.md) lost its matched comparison. The proposed shared reservation pipeline remains unimplemented and differs from PR #59’s direct ordinary-message ticket. Revisit only if the post-snapshot census in [the campaign plan](topology-specialization.md) justifies its latency and storage cost.

Proposal only. Wait for the matched routed control before choosing either experiment. Preserve the complete decoder, mailbox capacities and application arithmetic.

## Observed chain

The matched 5 ns control synthesis snapshot's worst path is `occupied[0][4]` → producer eligibility/round-robin selection → destination row → lowest free physical index → `used[0][0]`. It is 31 logic levels, with 7.587 ns data delay: 1.519 ns logic and 6.068 ns estimated interconnect. `producer[0]` has fanout 442. The setup-derived period is 7.742 ns; this is unplaced timing, not a routed measurement.

The reported path reaches `producer[0]` after 14 logic levels and 3.635 ns; the remaining 17 levels consume 3.952 ns. These old-path segments locate a plausible cut, not the predicted periods of new stages. Registering the destination as well as the producer moves its selection mux into the first stage.

Fourteen of the 20 reported paths contain the producer/physical-index chain, ending in either `used` or a mailbox RAM address. The other six run from the executor-request FIFO tail through the vertex's first arithmetic stage, at 7.575 ns. Even perfect removal of the sampled admission paths leaves only about 2.2% synthesized-period headroom, from 7.742 to 7.575 ns. A useful result can therefore be removal of this family without a large immediate whole-core improvement.

Evidence: `snowflake-probe/_build/native/control-synthesis-snapshot5/evidence.tar.gz`, member `results/snowflake-actors-native/synthesis-paths.rpt`, SHA256 `a98e279c30da832bb61cd2ac2d4dc9c65bc7dcef39c5a962651f6f4435796702`. Source boundaries are `mailbox::select_admission` / `apply_admission` and the RUN branch of `xls_shared_codegen:shared_service/1`.

## First control: reuse the parallel selector

`select_admission` builds an after/before linear fold over producers. The existing public `arbitration::select` already supplies the same first-eligible-at-or-after-cursor policy: independent eligibility bits, a cursor mask, first-one selection and `one_hot_sel`. It partitions the mask rather than rotating it. Both implementations wrap an out-of-range cursor to the first eligible producer and return `(false, 0)` for an empty set.

Keep every eligibility predicate, destination check and physical-slot operation unchanged; replace only the producer fold. This is a zero-latency, zero-state experiment which also removes duplicated policy. Hypothesis: explicit mask/one-hot operations allow XLS and synthesis to avoid the observed cascaded producer selection. They may instead produce an equivalent physical cone; no level reduction or clock percentage is promised. Exact combinational equivalence and identical full-core event/cycle traces are required. Compare mapped producer-cone depth, fanout and both synthesized and routed paths before attributing a gain to the representation.

## If necessary: one logical reservation, then physical allocation

Add one registered intent `T = {valid, producer, actor}` per shared service. Keep frames in the existing producer receptacles. `occupied`, `order` and `used` continue to describe committed physical rows; no linked structure, per-message indirection or second allocator is introduced.

**A — choose and reserve.** Select a registered pending non-credit request. Exclude the producer held by `T`. Its destination must satisfy `occupied[a] + reserved[a] < DEPTH`, where `reserved[a] = T.valid && T.actor == a`. This can use comparisons against `DEPTH` and `DEPTH-1` rather than an added count carry chain. Store the producer and destination, but do not choose a physical index, append an order entry or mark mailbox work ready. Do not borrow space freed by the current retirement. No actor execution ownership is acquired, so existing messages of that actor can still run.

**B — allocate and commit.** For the registered ticket, choose the lowest free index from the current registered `used[T.actor]`. Apply the existing retirement first, then append to its resulting order/count and set the used bit. Send the ticket's old pending frame to that RAM row. A slot free before retirement cannot alias an in-flight message, and retirement cannot make that free slot occupied. Continue using the existing write-response fence before the loader receives a dispatch ticket.

The invariant `occupied[a] + reserved[a] <= DEPTH` guarantees a physical row for every live ticket. B can only add the old reservation; retirement only subtracts. A accounts for that old reservation when selecting the next one, so the next invariant follows without predicting retirement. Full mailboxes remain ineligible, including a full mailbox that consumes a message on the same edge. A and B may target the same actor if two logical spaces were available.

Round-robin order needs a look-ahead cursor: when B commits, A searches after B's producer, not after the stale cursor preceding it. Advance the stored cursor only for a committed admission. On same-actor failure retirement, cancel B without consuming its pending request and exclude the failed actor from A on that edge, matching the current admission gate. Cancellation releases the logical reservation; it does not invent a success response or a persistent failed-actor policy. Credit collection continues to use registered requests only.

## Producer replacement is part of the cut

Simply pinning the pending slot until B and retaining the current receive condition adds a throughput bubble: one producer changes from one admission every two clocks to every three; two continuously supplied producers change from one per clock to two per three clocks. That is not an acceptable default interpretation of a throughput-preserving cut.

Allow the producer held by T to capture a replacement on B's successful commit edge. B reads **`state.pending[T.producer]`**, never `captured_pending`; the latter may already contain the next frame. Clear the old valid bit while retaining the replacement capture bit. `scheduler::release_pending` already expresses this ownership transfer. Track the actual per-producer capture, since the existing combined valid mask cannot distinguish an occupied slot from its replacement. No replacement may overwrite a cancelled or stalled ticket. Newly captured credits and messages remain unavailable to this iteration's arbiters.

The alternative is to copy the 128-bit frame into T and release pending at A. It simplifies pending ownership but adds a wide selected payload and its mux to A. Keep that as an explicit alternative if receive replacement cannot preserve a short ready path; do not mix both designs in one measurement. A producer/actor/valid ticket has 65 declared bits with current u32 indices (9 bits suffice for 19 producers and six actors); a copied frame adds 128 bits. Measure actual retained flops rather than assuming width reduction.

## Preregistered checks and expectations

- [ ] For the selector-only variant, SAT-check exact choice, sentinels, cursor wrap, exclusions and invalid destinations; retain current simultaneous retirement/admission and bitmap invariants. Run the full decoder with identical cycle traces before measuring timing.
- [ ] If the cut is selected, extend `test_data/mailbox_refinement.x` and `tools/test_mailbox_formal.py` with the logical-reservation invariant, physical uniqueness and producer ownership transition. Exercise capacities 1, 3 and 24; include counterexamples for missing reservation accounting and lost replacement capture. State finite parameter coverage explicitly.
- [ ] Use generated RTL to test replacement on the committing producer, replacement credits, cancellation on failure, simultaneous retirement/admission to one actor, full and postponed mailboxes, dispatch while admission is reserved, RAM stalls and reset. Require sustained one-write-per-clock service with two supplied producers, and preserve the single-producer interval of two clocks. Keep ordinary and aggregate-only services covered.
- [ ] Observe reservation and RAM acceptance separately. Mailbox-write acceptance remains the profile's admission boundary; a logical reservation must not be presented as an ingested message. Extend capacity diagnostics to distinguish reserved capacity from committed queue depth, without reusing the unrelated actor-execution/outbox reservation labels.
- [ ] Replay the same stress and quiet decoder inputs, compare exact per-site corrections and round order, then compare cycle distributions and matched synthesis/routing. Added cold-message latency is one successful service iteration, normally one clock; a causal chain containing N otherwise unhidden admissions can therefore pay N added clocks. The cut promises no application-level cycle invariance.

The structural prediction is removal of the single-cycle occupied → producer selection → physical allocation path. Saturated admission should retain one write per clock after filling the ticket; this is a test requirement, not evidence already obtained. The old path split suggests where to register, but routing changes, cursor/capacity look-ahead, producer replacement and untouched executor paths can still dominate. Report step-time break-even using measured cycles and routed period; do not infer it from the allocator alone.
