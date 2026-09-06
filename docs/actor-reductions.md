# Actor-owned reductions

This is the working design for phase-local incast reduction. The state-function
callback surface is the first implementation step. Reduction actions and
internal completion events below are proposed syntax, not implemented features.
Update this document as that contract becomes more precise.

## Ownership and source syntax

A reduction belongs to its receiving actor and is active during a phase.
Senders use the same PID, topology address, and ordinary cast or eventual
call/reply protocol. There is no separately addressed collector and no special
sender-side delivery operation. Shared reduction RAM or an execution unit is
a compiler placement choice.

The callback mode is `callback_mode() -> [state_functions, state_enter]`.
Each declared phase exports `Phase(EventType, Content, Data)`. For example,
the proposed diffusion phase is:

```erlang
gathering(enter, _OldPhase, Cell) ->
    Epoch = diffusion_epoch(Cell),
    {keep_state, Cell, [
        {open_reduction, diffusion, Epoch, {count, 4},
            {commutative_monoid, zero_phi_sum(), fun add_phi/2}},
        {cast, north, phi_message(Cell)},
        {cast, east, phi_message(Cell)},
        {cast, west, phi_message(Cell)},
        {cast, south, phi_message(Cell)}
    ]};
gathering(cast, #phi{epoch = Epoch, values = Values}, _Cell) ->
    {keep_state_and_data, [{contribute, diffusion, Epoch, Values}]};
gathering(internal, {reduction_complete, diffusion, Epoch, Sum}, Cell) ->
    %% Relax once, then advance or repeat the diffusion phase.
    ...
```

These helper calls illustrate the design; accepting each expression in the
lowerer is separate work. A source-aware alternative uses
`{members, ExpectedMembers}` when opening and
`{contribute, Name, Key, Member, Value}` when contributing. Expected membership
is an expression, leaving room for correlators whose active participants are
chosen at runtime. Hardware still needs a finite capacity or member universe.
The initial implementation can require a static count or fixed-universe set.

## Semantics

The operator is a commutative monoid under its actual bounded representation.
Its identity and combination operation must remain valid under every allowed
association and ordering. Integer sums must be wide enough for the bounded
contribution set (or explicitly use modular arithmetic); saturating and
floating-point addition do not in general meet this contract. Phi diffusion
uses widened sums, movement uses XOR, and comparison retains a maximum with
enough tie information to combine deterministically.

Each accepted contribution merges into actor-owned state containing the key,
accumulator, and remaining count or seen-member set. There is no prescribed
fold order or reorder queue. Count mode relies on a protocol invariant of
exactly N contributions and cannot detect duplicate senders. Member mode can
reject unexpected and duplicate contributors. Ordinary ERTS casts carry no
implicit sender identity: source-aware protocols must already carry a member
label, or eventually use request metadata. Do not change phi's wire protocol
merely to reveal the reduction implementation.

The final contribution produces one typed internal completion event before
the next external mailbox event. The actor processes that event using its
phase function; partial contributions emit no protocol effects or arbitrary
actor-data updates. Other messages retain ordinary phase handling, postponement,
and failure behavior. Early contributions for an unopened reduction remain in
the bounded mailbox, with the same capacity and deadlock obligations as other
postponed messages. Missing and slow contributions cannot be distinguished
without additional protocol or diagnostic machinery.

## XLS/RTL contract

Lowering must recognize a restricted admission clause: its match, key/member
extraction, and value projection depend on the incoming message and explicitly
stored reduction metadata, without arbitrary actor-data reads or effects.
The compiler can then execute admission and combination in the mailbox manager
without issuing the full actor callback. CPU execution of the same phase
clause defines the reference behavior. Unsupported clauses must be diagnosed
or explicitly use a normal actor visit; silently assuming the optimization
would invalidate the performance argument.

Initially allow one active bounded reduction per actor. Opening, contribution
acceptance, accumulator writes, completion publication, and closing must have
explicit linearization and capacity rules. Completion must be published once,
and reserved storage must survive output stalls. Opening a subsequent epoch
must not overwrite an undelivered result. Phase entry must install the
reduction before making its outgoing requests visible.

Accumulators and completion values are typed private data, not public
`hls_tags` frames; widened diffusion sums can exceed the 96-bit wire payload.
A stored result with a private descriptor is one possible representation.
The chosen representation must preserve completion priority and bounded
ownership through actor execution. Shared bounded reduction resources also
belong in the effect-window backpressure dependency analysis.

Before implementing this path, settle the behavior of zero participants,
overlapping opens, wrong keys, phase exit while incomplete, reset, and
completion storage exhaustion. Dynamic membership syntax does not yet imply
dynamic arming, cancellation, timeouts, or arbitrary sets are synthesizable.

## Stages and measurements

1. Convert `hls_statem` and all examples to phase-named state functions, keeping
   runtime and generated hardware behavior intact.
2. Add the reduction actions and internal completion events to the CPU reference,
   with permutation, skew, duplicate, key, postponement, and reset coverage.
3. Lower one active bounded reduction per actor, instrumenting occupancy,
   completion latency, and avoided executor visits.
4. Convert the three phi barriers and measure cadence and area against the
   global effect-window baseline.

At twelve diffusion rounds, the projected main-actor visits fall from 57 to
15 per cell-step. The existing three-cell shard still has about 59 serialized
outgoing action positions per cell-step, or a roughly 177-clock retirement
floor. Treat these as profiling hypotheses: if reduction does not materially
move cadence toward that floor, investigate the bottleneck before extending
the abstraction.

## State-function surface implemented in stage one

Entry clauses return `{keep_state, Data}` or `{keep_state, Data, Casts}`.
Cast clauses return `{next_state, Phase, Data}`, `{keep_state, Data}`, or their
four-/three-element forms with `[]` or `[postpone]`. The
`keep_state_and_data` shorthand and its action-list form retain callback data;
lowered clauses must bind the whole data value in their head when using it.
`{stop, fail, Data}` is the bounded fail-stop result. Output actions remain
restricted to entry, with a literal ordered list and at most one action per
output port in lowered code.

`{repeat_phase, Data}` is an HLS extension that consumes the current input,
enters the current phase again, and retries postponed messages in arrival
order. It preserves the existing hardware scheduling boundary. It is not
named `repeat_state`, because OTP's operation requests re-entry without a
state change that would release postponed events. Ordinary same-phase
`next_state` and `keep_state` results do not retry postponed inputs.
See the [OTP state-machine semantics](https://www.erlang.org/doc/system/statem.html).

This is a restricted callback vocabulary, not a promise of full `gen_statem`
compatibility. Calls, timeouts, arbitrary stop reasons, `next_event`, and the
proposed reduction actions remain outside stage one.
