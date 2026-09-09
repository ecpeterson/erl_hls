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

1. Derive reduction metadata in a topology analysis pass rather than spreading
   ad hoc inspection through scheduler code generation.
2. Permit a source-fragment placement only when the topology proves that each
   ordinary sender can address the unique destination reduction instance.
   Aggregate fragments then reach the destination through a private typed
   event; the public message protocol remains unchanged.
3. Keep optimized admission and effect issue generic scheduler mechanisms, not
   phi-specific modes.

The initial hardware subset retains one active bounded reduction per actor and
fixed compile-time population shapes. Dynamic participant sets may later fit
the same source syntax, but require explicit capacity, arming, cancellation,
and completion rules before they are synthesizable.
