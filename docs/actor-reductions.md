# Actor-owned reductions

Actor-owned reductions are phase-local barriers over ordinary incoming
messages. They let an actor describe a commutative, associative fold without
requiring every accepted contribution to update the actor's ordinary data or
run a visible state transition.

The CPU reference and the canonical XLS lowering implement the contract below.
Optimized placement is staged separately: the canonical hardware path keeps
contributions as ordinary mailbox messages and reduction state actor-local.

## Ownership and addressing

The receiving actor owns the reduction. Senders still address that actor and
send its ordinary protocol messages. They do not address a collector, choose a
hardware transport, or mark their sends as reduction traffic.

The receiver's cast clause recognizes a contribution message and returns a
`contribute` directive. This keeps collection an implementation decision of
the receiver:

```erlang
gathering(cast, #phi{epoch = Epoch, values = Values}, Cell) ->
    {gathering, Cell, {contribute, diffusion, Epoch, Values}}.
```

## Opening a reduction

A phase-entry action opens at most one reduction:

```erlang
gathering(enter, _OldPhase, Cell) ->
    Epoch = diffusion_epoch(Cell),
    {Cell, [
        {open_reduction, diffusion, Epoch, {count, 4},
            {commutative_monoid, zero_phi_sum()}},
        {cast, north, phi_message(Cell)},
        {cast, east, phi_message(Cell)},
        {cast, west, phi_message(Cell)},
        {cast, south, phi_message(Cell)}
    ]}.
```

The open action must be first in the entry action list. Cast actions may follow
it. Installing the reduction before emitting those casts gives the outgoing
requests a well-defined destination epoch even in a cyclic topology.

The reduction name is an atom and the key is an arbitrary exact Erlang term.
The name identifies the reducer; the key distinguishes successive instances
of the same barrier. The callback module supplies the combination operation:

```erlang
reduce(diffusion, Left, Right) ->
    add_phi_sums(Left, Right).
```

`reduce/3` is optional for actors that never open a reduction. Opening one
without exporting that callback is an error.

## Populations

The initial contract supports two nonempty populations of at most 255
participants:

- `{count, N}` accepts exactly `N` matching contributions. Equal values count
  separately. This mode relies on the protocol to supply exactly one value per
  intended participant and cannot detect duplicate senders.

- `{members, Members}` accepts one contribution for each exact member term.
  Members must be unique. Unexpected and duplicate members are errors, and
  arrival order is irrelevant.

A count contribution has the form:

```erlang
{Phase, Data, {contribute, Name, Key, Value}}
```

A fixed-member contribution includes the member identity:

```erlang
{Phase, Data, {contribute, Name, Key, Member, Value}}
```

The directive is a consuming disposition when accepted. Its phase and data
must exactly equal the phase and data passed to the cast callback. Partial
contributions therefore update only private reduction state; they cannot emit
protocol effects or mutate ordinary actor data.

## Fold law

`{commutative_monoid, Identity}` promises that `reduce/3` is associative and
commutative over the actual bounded representation, with `Identity` as its
identity. Implementations may combine accepted values in any association and
order.

This is stronger than saying that one observed arrival-order fold happens to
work. Integer sums need enough width for the bounded population, or must
intentionally use modular arithmetic. Saturating and floating-point addition
do not generally satisfy the law.

The CPU scheduler currently combines in acceptance order. Programs must not
depend on that incidental ordering; hardware implementations are free to use
trees, fragments, or other placements.

## Completion and phase boundaries

The final accepted contribution closes the reduction and produces one private
event before the scheduler selects another external mailbox entry:

```erlang
gathering(internal,
        {reduction_complete, diffusion, Epoch, Sum}, Cell) ->
    {relaxing, relax(Cell, Sum), consume}.
```

An internal completion handler may consume, fail, change phase, or return a
`repeat_phase` result. It cannot postpone or contribute. Completion is not a
mailbox message and consumes no mailbox capacity.

An actor cannot leave or repeat its phase while a reduction is incomplete.
Unrelated same-phase messages may still be consumed or postponed normally.
Explicit failure remains legal and retains the returned diagnostic state.

An internal completion may enter a phase that immediately opens the next
reduction. That sequence closes the old instance before installing the new
one, so reduction storage has a single owner throughout.

## Mismatch, errors, and diagnostics

After a cast clause returns a `contribute` directive, `hls_statem` compares its
name and key with the actor's open reduction. A mismatch is automatically
postponed by the runtime; the callback does not need a separate `postpone`
clause for it. A contribution received before any reduction opens is treated
the same way. A later phase boundary or `repeat_phase` makes postponed
messages eligible again in their original arrival order.

Postponed contributions retain ordinary mailbox capacity. A topology must
leave room for the message that can open or advance the appropriate reduction,
just as it must for any other postponed-message protocol.

Once name and key match, these are protocol errors rather than reasons to
wait:

- using a count contribution for member mode, or vice versa;
- contributing an unexpected member;
- contributing the same member twice.

`hls_statem:info/1` reports whether reduction state is idle. For an open
reduction it exposes the name, key, population, accepted count, and remaining
count, but not the accumulator value.

## Event-kind typing

Phase-named callback functions retain distinct result types for entry, cast,
and internal events. An overloaded Erlang specification can document that
relationship:

```erlang
-spec gathering(enter, hls_statem:phase(), #cell{}) ->
        hls_statem:enter_result(#cell{});
    (cast, #phi{}, #cell{}) ->
        hls_statem:cast_result(#cell{});
    (internal, hls_statem:reduction_complete(), #cell{}) ->
        hls_statem:internal_result(#cell{}).
```

The singleton first-argument types make the overload domains disjoint. A
generic `hls_statem:callback_result/0,1` union is also available, but does not
preserve the event/result relationship.

## Canonical XLS lowering

The first hardware realization deliberately follows the CPU semantics rather
than choosing a special transport. The generated actor stores one bounded
reduction record beside its callback data. A shared scheduler packs both into
the actor's existing state-RAM row; a direct actor holds both in registers.
Partial contributions use the ordinary dispatch, mailbox, and state-retirement
paths.

Completion is a private internal event, not a mailbox entry. Once the last
contribution makes the reduction complete, a direct service dispatches that
event before receiving another message. A shared scheduler records the actor
as an internal candidate and gives that event priority over entry or mailbox
work for the same actor while retaining round-robin choice among actors. The
completion callback clears the private reduction record and then follows the
ordinary phase-boundary, repeat, and failure rules.

The generated subset supports one active count or fixed-member reduction per
actor. All sites in one actor currently share one private accumulator-record
type, and each reduction name has exactly one unguarded `reduce/3` clause.
Population shapes, contribution clauses, reducer results, and completion
clauses are checked statically. A contribution with the wrong name/key is
postponed; duplicate or unexpected fixed members fail the actor.
Leaving or repeating a phase with an incomplete reduction also fails.

The opening key and identity are evaluated with the entry's data and cast actions in one [entry outcome](entry-outcomes.md). A supported match failure anywhere in that callback prevents both the open and every cast in that entry. An invalid reopen likewise preserves the previous data and reduction state and fails the actor, even when egress is stalled.

The canonical XLS subset currently represents reduction keys and fixed member
identities as `hls_nums:u32()` values even though the CPU contract permits any
exact Erlang term.

This first lowering also requires the open to appear first in a literal entry
action list. Its population and accumulator identity must be written there as
a literal population tuple and a complete literal record; helper calls such as
`zero_phi_sum()` in the CPU-oriented example above are not yet inspected.
Contribution directives must be the direct final result of a leading group of
clauses for that message and phase, must retain the callback phase and data,
and must construct a complete accumulator record from message fields. These
are restrictions of the current static analysis, not additional CPU
semantics.

## Hardware-lowering roadmap

Hardware support should preserve one semantic path and add placement as an
optimization:

1. Permit a source-fragment placement only when the topology proves that each
   ordinary sender can address the unique destination reduction instance.
   Aggregate fragments then reach the destination through a private typed
   event; the public message protocol remains unchanged.
2. Keep optimized admission and effect issue generic scheduler mechanisms, not
   phi-specific modes.

The initial hardware subset retains one active bounded reduction per actor and
fixed compile-time population shapes. Dynamic participant sets may later fit
the same source syntax, but require explicit capacity, arming, cancellation,
and completion rules before they are synthesizable.

## Source-fragment placement analysis

`hls_reduction_plan:normalize/3` is the topology-only boundary for the first
optimized placement. Its third argument explicitly selects families with
`#{Family => source_fragments}`; omission leaves the canonical actor-local
path in place. The result describes selected families, their ordered fragment
translations and inverses, the scheduler groups which cover them, and whether
each shared actor module will eventually need an `ordinary` or
`aggregate_only` service artifact. It does not allocate channels, RAM, slots,
or generated names.

Selection succeeds only after the normalized topology and scheduler plan show
all of the following:

- the two-dimensional reducing family is completely scheduler-owned;
- every site has one unambiguous, actor-state-independent contribution schema
  with an irrefutable contribution clause, and the same complete,
  unconditional, population-sized entry-effect prefix;
- every prefix effect is a direct wrapped translation back into that family;
- captured ports have no other use, and no uncaptured self-route can overtake
  their batch;
- ordinary relations, ingress, and startup cannot carry a contribution into
  the selected family; and
- the translation multiset is inverse-closed, including multiplicity when
  distinct ports alias on a size-two dimension.

Under those assumptions, these facts bound each source fragment to two
reduction windows. The structural analysis alone does not prove that all
actors traverse coherent name/key/site windows, nor that a completed aggregate
can commute with unrelated ordinary mail. Those remain visible
`semantic_assumptions` in the plan until a stronger analysis or source contract
can discharge them. The planner itself changes no runtime or hardware
behavior; the optimized backend below consumes the plan only when the profile
explicitly selects the placement.

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

With no selected placement, ordinary generated DSLX remains byte-for-byte
unchanged. Selecting the placement therefore requires both the topology
profile and the matching `aggregate_only` actor artifacts reported by
`xls_topology_dslx:artifact_requirements/2`. The simulation preparation driver
queries every staged family topology and selects the matching actor artifact,
rejecting incompatible requirements for a module before DSLX typechecking.
