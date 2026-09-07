# Actor-owned reductions

This document defines phase-local incast reduction for `hls_statem`. The CPU
reference implements the full callback contract described here, while the
XLS/RTL backend implements the deliberately smaller, statically bounded subset
below.

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
Phase entry may update ordinary actor data while opening a reduction; hardware
installs the new data and private reduction state atomically.

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

Hardware reset clears mailbox and reduction state, including the completion
latch, as one coherent reset before phase-entry casts become visible; it does
not expose partial pre-reset reduction state.

## Initial XLS/RTL contract

The CPU behavior above is the reference, but the first lowerer accepts only
cases which can be proved bounded and rendered with fixed-width storage:

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

## First XLS/RTL realization

The lowerer recognizes a deliberately closed source subset rather than trying
to infer arbitrary callback semantics. The open must be the first literal
entry action, contribution clauses must form the leading clauses for their
message/phase pair, and each contribution must preserve the ordinary phase and
callback data. Keys and fixed member labels are `u32`; the identity, values,
and result of `reduce/3` use one private, completely constructed accumulator
record. Unsupported shapes fail translation instead of silently taking the
ordinary callback path.

Each actor has one reduction word logically alongside its ordinary callback
state. For an accumulator of width `A` and a largest fixed-member population
of `M`, its packed layout is:

```
status[2] | site[8] | key[32] | remaining[8] |
seen[max(1, M)] | accumulator[A]
```

`site` identifies the statically known phase/open site and thereby its name,
mode, population, and member-to-bit mapping. Count mode leaves `seen` zero.
Mailbox frames and ordering metadata remain in the separate mailbox store.
The first shared realization packed the reduction word into the main actor-
state row. The sidecar realization instead gives every reduction-capable
scheduler a separate per-slot reduction RAM. For the phi actor, the main row
is 338 bits and the reduction row is 182 bits; their logical total remains 520
bits, but an ordinary actor-state read no longer transports the accumulator.

The direct service folds matching mailbox messages in its ordinary machine
step. In the shared service, an open-reduction bit lets a mailbox-head sidecar
read the mailbox frame and the narrow reduction row without reading the main
actor row. It applies the pure fold and returns only the slot, updated reduction
word, fold outcome, and mailbox/order indices. An accepted contribution is
consumed and writes only reduction RAM. A key mismatch is postponed, while a
head which is not a contribution is marked as probed and receives one ordinary
actor visit. Completion and protocol errors likewise schedule one private actor
visit; that visit reads main and reduction RAM in parallel and performs the
callback-data update or failure transition.

This first sidecar subset cannot use callback-data fields to recognize a
contribution: doing so would require the main actor-state read which the
sidecar is intended to avoid. Consequently, every well-shaped contribution
message reaches the reduction key check, and every key mismatch is postponed.
The phi topology relies on its senders never producing stale keys; malformed
stale traffic can otherwise occupy bounded mailbox space indefinitely. A
future lowering can recover the former fail-fast distinction by proving the
callback-data guard from the open-reduction key, or by sending unmatched keys
through the ordinary actor path.

The RAM response and local fold decision do not feed scheduler state directly.
The service sends the narrow fold envelope through a depth-one request channel,
a stateless relay, and a depth-one result channel. This elastic boundary breaks
the RAM-response-to-scheduler-state recurrence. A selected slot stays in flight
until its reduction write acknowledgement, if any, returns, so a later
activation cannot overtake the fold or observe stale reduction state. The same
fence, together with mailbox compaction at retirement, preserves actor-local
mailbox order.

A one-bit fair arbiter polls the returned-fold channel whenever no ordinary
executor result can retire, and on alternating turns while ordinary results
remain continuously ready. A returned fold, including a noncandidate probe
acknowledgement, wins its poll turn. Thus an occupied fold-result channel waits
behind at most one further ordinary scheduler activation, while an ordinary
result also cannot be starved by a continuous fold stream. The two elastic
slots let the service absorb a coincident second fold without forming a
self-channel deadlock.

An effect-bearing result waiting for credit does not fence a fold from another
actor. The scheduler may therefore speculatively read mail-only actors while
the ordinary completion path is blocked. A non-contribution head is left
unchanged and marked as probed; that slot then leaves sidecar selection and is
eligible for one ordinary actor visit. The mark persists until that visit
classifies the head as consumed, postponed, or failed, or until a phase or
reduction boundary invalidates the probe. This avoids repeated probes without
hiding the actor for an entire blocked interval.
Reduction rows are initialized lazily: reset clears the per-slot active bits,
which gate every sidecar read, and the first successful `open_reduction` writes
the row before making that slot sidecar-ready. Focused native RTL tests cover
count and out-of-order fixed-member reductions, future-key postponement and
retry, incomplete phase boundaries, duplicate members, and blocked local
progress through both the direct service and an external-RAM shared service.

## Implementation stages and measurements

1. Phase-named `hls_statem` callbacks preserve the previous runtime and
   generated-hardware behavior. This stage is complete.
2. The CPU reference adds entry opens, cast contribution directives, named
   `reduce/3`, and private completion events, with permutation, skew,
   duplicate, key, postponement, and failure coverage. This stage is complete.
3. XLS lowers one active bounded reduction per actor, using count or a fixed
   member universe. This stage is complete.
4. The phi actors use reductions for their four-way diffusion, comparison,
   and movement barriers. Cadence, state width, area, and semantic equivalence
   have been measured. This stage is complete.

With the paper's twelve diffusion rounds, the phi actor now uses a count-four
reduction for each diffusion exchange, a fixed-universe
`{north, east, west, south}` reduction for comparison, and a count-four parity
reduction for movement. The complete CPU-versus-native-Icarus run exactly
matches the current paper-parameter witness: it closes at step 18 with 80
accepted corrections and 18 nonuniform final measurements, eight commuting
and ten anticommuting.

Moving the barrier scratch fields out of `#cell{}` shrinks persistent callback
data from 528 to 320 bits. The bounded reduction state occupies 182 bits. The
first lowering therefore reduced a combined actor-state row from 546 to 520
bits. The sidecar splits that 520-bit logical state into a 338-bit main row and
a 182-bit reduction row, allowing contribution folds to avoid the main row.

The first reduction lowering's three-shard, global-effect-window profile
measured steps eight through 32 in 6,479 clocks, or 269.958 clocks per step and
about 740,855 steps/s at 200 MHz. The sidecar instead takes 7,581 clocks, or
315.875 clocks per step and about 633,162 steps/s: a 14.5% step-rate regression
from that baseline. Its main actor-state reads fall from 42,540 to 9,186, about
78.4%, so the storage split works as intended. The remaining per-contribution
mailbox/reduction read, elastic retirement, acknowledged reduction write, and
same-slot in-flight fence turn that traffic reduction into lifecycle and hazard
latency rather than a cadence gain. In the exact whole-device witness, the
application window similarly grows from 5,908 to 6,604 clocks, or 11.8%, while
retaining the same nontrivial result.

An apples-to-apples XC7 complete-wrapper map, including every inferred 1R1W
memory, reports 61,471 estimated logic cells, 65,660 flip-flops, 77,968 LUTs,
48 `DSP48E1`s, and 70 `RAMB36E1`s. The first reduction lowering reports 62,731
cells, 76,508 flip-flops, 78,066 LUTs, 48 DSPs, 22 `RAMB36E1`s, and 90
`RAMB18E1`s, or 67 RAMB36 equivalents. The sidecar therefore changes those
totals by -2.01%, -14.18%, -0.13%, zero, and +4.48%, respectively. Splitting
the shallow row has a modest three-RAMB36 fragmentation cost, but no hidden
logic-area explosion. These are out-of-context inferred-memory results, not
place-and-route or frequency measurements.

The sidecar validates that contributions can update narrow accumulator storage
without transacting the complete actor row, but the present scheduling protocol
is not a throughput win. A useful follow-up must shorten or overlap the fold
lifecycle, relax same-slot exclusion with proven forwarding, or use a stronger
bulk-synchronous lowering which replaces per-message visits with scheduled
aggregate sweeps.

## General mailbox capacity

Postponed messages retain mailbox capacity. The configured capacity must
leave room for a message capable of completing a reduction or crossing a
phase boundary, or the protocol can deadlock under backpressure. On the CPU,
mailbox overflow stops the process. The ordinary BEAM mailbox sits in front of
this bounded queue, so `hls_statem` models scheduling semantics rather than
host-side admission guarantees.
