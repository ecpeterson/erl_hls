# Actor Reductions implementation and validation

Maintainer reference; the [reader contract](../docs/actor-reductions.md) is authoritative for usage. These details describe the current implementation and qualification procedures.

## Source-fragment hardware realization

An actor module used by a selected family is compiled as an `aggregate_only`
shared-service artifact. This is a private hardware ABI, not a second actor
protocol. Senders still emit the same ordinary frames to the same logical
destination ports, and the CPU implementation is unchanged. Shared scheduler
groups for one compiled actor module may not mix ordinary and aggregate-only
instances, so one compiled service never has to guess which transport delivered
a contribution.

For a selected family, a scheduler egress router recognizes the proved
population-sized prefix of an entry-effect batch and sends all of its frames
atomically to the reduction plane. It then advances over that prefix; later
ordinary effects in the same batch retain their normal order and routing. The
captured topology routes are removed from the ordinary router only after the
planner has proved that they have no other use.

The plane transposes those sender batches into one depth-two queue for each
`{fragment ordinal, source actor}` pair. A destination is ready when the head
of every inverse fragment queue is present. Round-robin destination selection
then reads those heads, folds the frames with the actor module's typed reducer,
and sends one `ReductionAggregateRequest` to the scheduler group which owns
that destination slot. Input insertion and aggregate output use independent
handshakes. A scalar pending batch makes insertion across all fragment banks
atomic, and pop-before-push accounting permits a full queue to accept its next
frame in the same activation that its current head retires.

Each source actor's opening batch also supplies an `open_token`. The plane will
not deliver an aggregate for an actor until that actor's own opening entry has
reached the router. This prevents the aggregate from overtaking installation
of its destination reduction state without adding a public acknowledgement.
One bit is sufficient: that actor cannot emit another opening batch until the
current aggregate has completed and released it into the next opening phase.
The fragment queues still need two entries because one sender can advance into
its next window while a different destination is waiting for the rest of its
current window. Clearing before setting is a conservative same-cycle update;
it is not relied upon to represent two open reductions for one actor.

Although captured routes disappear from the ordinary scheduler graph, the
bounded plane still propagates backpressure among all schedulers which feed or
receive it. Effect-window partitioning therefore treats each plane's incident
scheduler set as one undirected hyperedge. This affects ownership analysis
only; it does not manufacture ordinary router channels. Independent ownership
domains remain available for graph components which share neither a routed
effect nor a bounded reduction plane.

The aggregate-only shared scheduler has one register-resident pending
aggregate receptacle per local actor. An aggregate is private work for its
addressed actor, so it consumes neither an ordinary mailbox slot nor mailbox
credit. The plane can therefore deposit work for one actor even while another
actor is in flight or blocked on egress, avoiding a scalar head-of-line
backpressure cycle. One receptacle per actor is sufficient under the same
causal invariant as the plane's `open_token`: an actor cannot emit its next
opening batch until its current aggregate has retired and released it into the
next opening phase, so a second aggregate for that actor cannot arrive while
the first remains pending. The input nevertheless remains continuously
drainable: a duplicate for an in-range slot replaces that slot's pending value
with a poisoned aggregate, while an out-of-range slot maps to slot zero and
deposits a poisoned value there. Either case makes the selected actor artifact
fail closed instead of silently accepting malformed input. After any
already-complete internal event, an aggregate outranks entry and mailbox work
for its actor while actor selection remains round-robin across slots. The
scheduler performs one normal state-RAM read, validates that the aggregate
names a fresh matching open reduction, and applies its completion callback in
the same executor transaction. If that callback crosses or repeats a phase,
the following phase entry and its effect batch are fused into the transaction
as usual. This is safe because aggregate work is already private, highest
priority work for the selected actor: no user message could interleave between
installing a complete accumulator and dispatching its completion event. A
newly captured aggregate may launch that state read in the same scheduler
activation. The bypass excludes a concurrently retiring slot, keeping
same-address behavior outside the 1R1W RAM contract.

Malformed aggregates, invalid slots, and violated fresh-window invariants fail
closed in the actor artifact. An out-of-range source index is structurally
unreachable because router batches derive it from a normalized family address;
the plane retains such a batch rather than silently corrupting another queue.
Where more than one selected family feeds the same homogeneous scheduler, a
small round-robin mux gives every plane a bounded holding slot.

Returned effect credits become eligible after they occupy the scheduler’s existing pending receptacle. A credit captured in the current iteration cannot release a result in that same iteration; this breaks the combinational path through result retirement, router lookahead, and credit return without adding another buffer.

The planes, aggregate muxes, actor schedulers, and effect-window arbiters share
`arbitration::select`. It chooses the first eligible index at or after the
cursor, wrapping to the first eligible index when necessary. An empty set
returns `(false, 0)`. The implementation masks the request bits at the cursor
and priority-encodes the selected region; readiness is an independent reduction
of the request bits. It does not rotate through dynamically indexed candidates.

Plane input/output cursors and aggregate-mux cursors use the smallest unsigned
type which can represent their population, with one bit for a singleton.
`arbitration::successor` compares with the last legal index before incrementing,
so power-of-two populations do not require an extra bit to represent the count.
The output cursor advances after a selected activation commits; downstream
backpressure cannot skip that choice. The input cursor retains its existing
polling policy and pauses while the plane holds a pending batch.

`tools/test_arbitration.py XLS_ROOT` proves the generated combinational RTL
against an independent circular scan for populations 1, 2, 3, 4, 9, 16, 17,
and 32, using both minimal and 32-bit cursors. Every request mask, legal cursor,
and acceptance choice is symbolic. The proof checks the exact winner, empty
result, cursor bounds, and cursor retention without acceptance. It also proves
that a continuously eligible contender is either selected or moves strictly
closer after each accepted competing grant. Consequently it wins within at most
N accepted grants; this is not a wall-clock latency bound when consumers stall
or eligibility is intermittent. Generated plane simulations additionally check
fragment transposition and successive reduction windows under backpressure.

With no selected placement, ordinary generated DSLX remains byte-for-byte
unchanged. Selecting the placement therefore requires both the topology
profile and the matching `aggregate_only` actor artifacts reported by
`xls_topology_dslx:artifact_requirements/2`. The simulation preparation driver
queries every staged family topology and selects the matching actor artifact,
rejecting incompatible requirements for a module before DSLX typechecking.

`bash tools/test_reduction_dslx.sh XLS_ROOT [STAGE]` exercises absorbing failures through the real Erlang reducer, helper calls, direct/shared machines, aggregate delivery, and count/fixed-member bookkeeping. It retains generated fixtures for diagnosis. `bash tools/test_actor_debug.sh XLS_ROOT STAGE reduction` and the `aggregate` variant query source-located arithmetic, case, match, and if failures in generated RTL through the framed debug endpoint; a healthy actor shares the scheduler and completes under output backpressure.
