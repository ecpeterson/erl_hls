# Actor-owned reductions

This document defines phase-local incast reduction for `hls_statem`. The CPU
reference implements the callback contract described here. XLS/RTL lowering
is a later stage and will initially accept a deliberately smaller, statically
bounded subset.

## Ownership and source syntax

A reduction belongs to its receiving actor. It is an execution choice made by
that actor, not a separately addressed collector. Senders use the same PID or
topology address and the same ordinary message delivery that they would use
without reduction. A sender neither knows that a reduction is open nor uses a
special transport operation.

The receiving actor opens the reduction as the first action of phase entry,
and returns contribution directives from matching cast clauses:

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
    ]};
gathering(cast, #phi{epoch = Epoch, values = Values}, Cell) ->
    {gathering, Cell, {contribute, diffusion, Epoch, Values}};
gathering(internal, {reduction_complete, diffusion, Epoch, Sum}, Cell) ->
    %% Relax once, then advance or explicitly repeat the phase.
    ...

reduce(diffusion, Left, Right) ->
    add_phi(Left, Right).
```

The callback module exports `reduce/3`. Its first argument is the reduction
name, so one module can define several statically named reductions without
putting a function value in actor-local state. For every accepted value the
CPU reference calls:

```erlang
Module:reduce(Name, Accumulator, Value)
```

The five-element open action is:

```erlang
{open_reduction, Name, Key, Population,
    {commutative_monoid, Identity}}
```

It must be the first entry action. At most one may appear. The runtime
installs it before making any following cast actions visible, so a response to
an entry cast cannot race ahead of its reduction. An open action anywhere
else in the list is an error.

Count reductions use:

```erlang
{contribute, Name, Key, Value}
```

Member reductions use:

```erlang
{contribute, Name, Key, Member, Value}
```

The member label is protocol data, not an implicit ERTS sender identity. A
source-aware protocol must already provide a stable logical label such as a
direction or topology address. It should not expose the collector's physical
placement merely to support this optimization.

## Callback result kinds

Phase-named functions organize source by actor state, but each event kind has
its own closed result shape:

* Entry returns `{Data, EntryActions}`. Casts and one first-position
  `open_reduction` are the supported entry actions.
* Cast returns `{NextPhase, NextData, Directive}`, or the existing
  `{repeat_phase, NextData, consume}` extension. A contribution tuple is a
  cast directive alongside `consume`, `postpone`, and `fail`.
* Reduction completion invokes an internal event clause, which returns
  `{NextPhase, NextData, consume | fail}` or
  `{repeat_phase, NextData, consume}`.

A contribution conclusion has an additional semantic restriction:
`NextPhase` and `NextData` must be exactly the current phase and data. A
partial contribution therefore cannot perform an actor transition, mutate
ordinary actor data, or emit effects. The reduction engine alone updates the
private accumulator. Code which needs other work on each input must use an
ordinary cast path rather than the reduction fast path.

The compiler classifies clauses by `{Phase, EventType, Schema}` before lowering
their bodies and combines only event-specific results of one type. This also
leaves room for a future `call` event and its reply-bearing result without
forcing it to unify with cast or internal-event results. Erlang overloads can
express this event/result pairing through singleton first-argument types; a
`when` spec only constrains type variables and cannot express the implication.

## Population and folding semantics

Exactly one reduction may be active for an actor at a time. An actor module
may define more than one named reduction, but their lifetimes may not overlap.
There is no implicit cancellation or replacement.

Both supported populations are nonempty and contain at most 255 participants:

* `{count, N}` accepts exactly the next `N` matching contributions. It carries
  no source identity and deliberately cannot detect duplicate senders.
* `{members, Members}` fixes one nonempty, duplicate-free member set at open
  time. Contributions may arrive in any order. An unexpected or repeated
  member is a protocol error. CPU member identity uses exact Erlang term/key
  equality.

The CPU reference can evaluate the member-list expression when the reduction
opens. The first hardware implementation is narrower: the set must come from
a statically finite member universe so that seen membership can be represented
as a bounded bit set. The syntax intentionally does not preclude later
support for correlators whose participant set is chosen at runtime.

The operator is a commutative monoid under its actual bounded representation.
The identity and `reduce/3` implementation must be valid under every allowed
association and arrival order. The runtime folds accepted values in arrival
order only as an implementation detail; programs may not depend on that order.
The runtime does not prove the algebraic laws.

Integer sums must be wide enough for the bounded population, or deliberately
use modular arithmetic. Saturating and floating-point addition do not in
general satisfy the contract. Phi diffusion uses widened sums, movement uses
XOR, and comparison retains both a maximum and enough winner information to
combine ties deterministically.

## Keys, postponement, and completion

The name and key identify the currently open reduction. A contribution for a
different name or key, or one offered while no reduction is open, is not a
definite protocol error: it is postponed in the actor's ordinary bounded
mailbox. It becomes eligible again at a real phase boundary or an explicit
`repeat_phase` boundary, following the normal postponed-message rules. This
permits a response for the next epoch to arrive early.

A stale key is not discarded automatically. It can remain postponed and hold
mailbox capacity forever, so protocols still need sound epoch discipline and
enough capacity for a message that can advance the actor.

Each accepted contribution is consumed. An incomplete acceptance updates the
actor-owned accumulator and population bookkeeping. The final acceptance
atomically closes the reduction and installs exactly one private event:

```erlang
{reduction_complete, Name, Key, Accumulator}
```

The completion occupies a reserved internal latch, not the external mailbox,
and is processed before every external mailbox event. It cannot be addressed
or forged by a sender: casting the same Erlang tuple is still a `cast` event,
not an `internal` event. Closing before dispatch lets the completion handler
change phase or explicitly repeat the current phase and open the next
reduction during entry without overlapping the old one.

Returning an ordinary same-phase result from the completion handler does not
re-enter the phase. An actor which wants to open the next epoch in the same
phase must return `{repeat_phase, Data, consume}`.

## Phase boundaries

An actor may continue to process unrelated same-phase messages while a
reduction is active. It may not leave the phase or execute `repeat_phase`
until that reduction completes. Attempting either operation with an open
reduction fails rather than silently cancelling partial work. A second open,
including an open while a completion is still pending, also fails.

These rules make the reduction lifetime a phase-local interval:

1. Entry installs the reduction.
2. Entry effects make requests visible.
3. Matching casts contribute without changing ordinary actor state.
4. The final cast closes the reduction and publishes private completion.
5. The completion handler performs the one ordinary actor-state update and
   may cross or repeat the phase boundary.

## Failure and restart semantics

The CPU reference never silently drops a reduction operation. It stops the
actor on any of the following:

* an invalid reduction name, monoid descriptor, empty or oversized population,
  or duplicate expected member;
* an open action which is not first, a second open, or a phase/repeat boundary
  while reduction work is incomplete;
* use of the count contribution form for member mode or vice versa;
* an unexpected or duplicate member;
* a contribution result which changes the current phase or ordinary data;
* an invalid completion result, a missing clause or reducer callback, or an
  exception in `reduce/3`.

Definite contribution errors retain the offending message in diagnostics and
stop with a reduction-specific reason. Name/key mismatch is the deliberate
exception: it postpones rather than stops. Count mode cannot diagnose a
duplicate source, and a missing contribution simply leaves the reduction open;
those remain protocol obligations. The runtime also cannot check that
`reduce/3` returns the intended accumulator type or obeys the monoid laws.

A process restart is a fresh `init/1`: the bounded mailbox, postponed set,
partial accumulator, seen-member set, and pending completion are all lost.
There is no replay log or recovery handshake, so restarting one actor is not a
transparent continuation of an in-flight topology epoch. A deferred-output
machine is disconnected again until its owner reconnects it. Supervising a
connected topology and deciding which peers or epoch to restart remains a
separate lifecycle design problem.

The eventual hardware reset contract must clear mailbox and reduction state,
including the completion latch, as one coherent reset before phase-entry casts
become visible. It must not expose a partial pre-reset reduction after reset.

## Initial XLS/RTL contract

The CPU behavior above is the reference, but the first lowerer should accept
only cases which can be proved bounded and rendered with fixed-width storage:

* one active reduction slot per actor, from a statically closed set of names;
* fixed-width name, key, accumulator, value, and member representations;
* a compile-time-bounded count, or a member set drawn from a fixed finite
  universe and tracked with a bit set;
* a pure, total, lowerable `reduce/3` clause selected by the static reduction
  name;
* a compiler-recognizable direct contribution path whose value and optional
  member projection depend only on the input plus stored reduction metadata;
* a reserved completion slot and an accumulator wide enough for every legal
  contribution;
* atomic installation before entry casts, atomic contribution bookkeeping,
  and completion priority equivalent to the CPU scheduler;
* reset which clears mailbox, partial reduction, membership, and completion
  together.

The initial lowerer may require every named reduction in one actor module to
use a common private accumulator record. Logically different accumulators can
occupy different fields of that record while only one reduction is live. A
future typed tagged-union representation could avoid the unused fields; the
hardware must not erase types by retaining an Erlang-style arbitrary term or
callback value.
Unsupported callback dataflow must receive a compile-time diagnostic or fall
back explicitly to an ordinary actor visit. Silently treating a general cast
as a reduction fast path would invalidate both semantics and performance
measurements.

Accumulator and completion values are typed private data rather than public
`hls_tags` frames. Widened sums may therefore exceed the 96-bit wire payload.
Shared reduction RAM and any admission/completion queues also participate in
the effect-window backpressure dependency analysis. Completion storage must
remain reserved across downstream stalls; a later open may not overwrite an
undelivered completion.

Dynamic membership, cancellation, timeouts, overlapping reductions, ordered
or noncommutative folds, and reducer effects are explicitly outside the first
hardware contract.

## Implementation stages and measurements

1. Phase-named `hls_statem` callbacks preserve the previous runtime and
   generated-hardware behavior. This stage is complete.
2. The CPU reference adds entry opens, cast contribution directives, named
   `reduce/3`, and private completion events, with permutation, skew,
   duplicate, key, postponement, and failure coverage. This stage is complete.
3. XLS lowers one active bounded reduction per actor and instruments occupancy,
   completion latency, and avoided executor visits.
4. The phi actors adopt the mechanism and cadence and area are measured against
   the global effect-window baseline.

At twelve diffusion rounds, converting the three phi barriers is projected to
reduce main-actor executor visits from 57 to 15 per cell-step: four diffusion
inputs become one completion visit in each round, and the comparison and
parity barriers each become one completion visit. The existing three-cell
shard still has about 59 serialized outgoing action positions per cell-step,
or a roughly 177-clock retirement floor. These are profiling hypotheses. If
the hardware reduction does not materially move cadence toward that floor,
profile the remaining bottleneck before extending the abstraction.

## General mailbox capacity

Postponed messages retain mailbox capacity. The configured capacity must
leave room for a message capable of completing a reduction or crossing a
phase boundary, or the protocol can deadlock under backpressure. On the CPU,
mailbox overflow stops the process. The ordinary BEAM mailbox sits in front of
this bounded queue, so `hls_statem` models scheduling semantics rather than
host-side admission guarantees.
