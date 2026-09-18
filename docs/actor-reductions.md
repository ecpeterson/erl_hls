# Actor-owned reductions

A reduction is a phase-local barrier: the receiving actor folds a bounded set of ordinary messages, then receives one private completion event. Senders address the actor normally. Partial folds change only private reduction state.

## Opening and contributing

Open at most one reduction as the first entry action; later casts can solicit contributions:

```erlang
gathering(enter, _OldPhase, Cell) ->
    {Cell, [{open_reduction, diffusion, Cell#cell.epoch, {count, 4},
             {commutative_monoid, #sum{value = 0}}},
            {cast, neighbors, #request{epoch = Cell#cell.epoch}}]}.

gathering(cast, #contribution{epoch = Key, value = Value}, Cell) ->
    {gathering, Cell, {contribute, diffusion, Key, #sum{value = Value}}}.

reduce(diffusion, #sum{value = A}, #sum{value = B}) ->
    #sum{value = A + B}.
```

The name selects `reduce/3`; the key distinguishes successive instances. CPU keys can be any exact Erlang term. Opening requires an exported reducer. An accepted contribution consumes its message and must return the unchanged callback phase and data.

| Population | Accepted contribution | Obligation |
| --- | --- | --- |
| `{count, N}` | `{contribute, Name, Key, Value}` | Exactly N contributions; equal values count separately and duplicate senders are not detected. |
| `{members, Members}` | `{contribute, Name, Key, Member, Value}` | Exactly one contribution per unique member; unexpected or repeated members are errors. |

Both populations contain 1–255 participants. Count/member forms cannot be mixed.

## Fold law

`{commutative_monoid, Identity}` promises associativity, commutativity and identity over the **actual bounded representation**. Implementations may reorder and reassociate values. Use sufficient integer width or intentional modular arithmetic; saturation and floating-point addition generally violate this promise. Do not rely on the CPU's acceptance-order fold.

## Completion and phase boundaries

The final accepted contribution closes a successful window and dispatches its completion before another external message for that actor:

```erlang
gathering(internal, {reduction_complete, diffusion, Key, Sum}, Cell) ->
    {relaxing, apply_sum(Cell, Key, Sum), consume}.
```

Completion consumes no mailbox slot. Its handler may consume, fail, change phase or repeat the phase; it cannot postpone or contribute. It may enter a phase that opens the next reduction.

An incomplete reduction prevents leaving or repeating its phase. Other same-phase messages may consume or postpone normally; explicit failure remains legal and retains its diagnostic state. A contribution with no matching open name/key is automatically postponed. Phase change or repetition retries postponed messages in arrival order. They retain mailbox capacity, so the protocol must leave room for the message that advances the window.

## Failure and inspection

A supported exception in `reduce/3` becomes an absorbing failure: retain the first error, accept the remaining valid contributions, and stop combining. Only a complete population releases that error to the destination actor; its completion callback and dependent effects do not run. A missing contributor can leave either a healthy or failed window waiting indefinitely. There is no implicit timeout, cancellation or failure propagation to other actors.

BEAM re-raises the saved class, reason and stack. Hardware latches the source-located failure on completion; until then it is visible as a pending reduction failure, while the actor itself remains nonterminal. Duplicate/unexpected members remain protocol errors, and unrelated callbacks can still fail while a window drains.

“First” follows the chosen fold order. Source-fragment placement can change that order and omit combining the first value with the identity. Absorbing failure prevents a detected error from becoming success; it does not make a partial combiner a valid monoid.

`hls_statem:info/1` reports idle/open status, name, key, population and accepted/remaining counts. Hardware exposes committed [reduction observations](topology-debug.md#reduction-observations) through `hls_debug`; neither interface reveals the accumulator.

## Event-kind typing

Use disjoint overloads when a phase handles several event kinds:

```erlang
-spec gathering(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #contribution{}, #cell{}) -> hls_statem:cast_result(#cell{});
    (internal, hls_statem:reduction_complete(), #cell{}) -> hls_statem:internal_result(#cell{}).
```

`hls_statem:callback_result/0,1` is available when that distinction is unnecessary.

## Current XLS subset

One reduction may be active per actor. Sites share one private accumulator-record type; each reducer has one unguarded clause and may call [typed local helpers](local-helpers.md). Keys and fixed-member identities are `hls_nums:u32()`.

The open must lead a supported literal action list, with a literal population tuple and complete literal identity record. Contribution directives must directly finish a leading clause group for the message/phase, retain phase/data, and build a complete accumulator record from message fields. These are current translation limits, not CPU protocol requirements.

Entry evaluation is transactional: a selected expression failure suppresses both the open and every cast. Reopening an active reduction also fails without committing entry data or effects. See [entry outcomes](entry-outcomes.md), including conditional opens.

## Source-fragment placement analysis

`hls_reduction_plan:normalize/3` accepts `#{Family => source_fragments}` to select offloading; omission keeps actor-local reduction. The topology must prove:

- A fully scheduled two-dimensional family and one unambiguous, actor-state-independent contribution schema per site, with an irrefutable head.
- An unconditional, population-sized entry prefix of direct wrapped translations into that family; the translation multiset is inverse-closed, including aliases.
- No other uses of captured ports, no overtaking uncaptured self-route, and no ordinary route, ingress or startup contribution into the selected family.

Fixed-vector patterns can use [source-derived shape evidence](source-context.md#logical-type-shapes), rechecked against emitted DSLX dimensions. The plan still records semantic assumptions: actors must traverse coherent name/key/site windows, and aggregates must commute with unrelated ordinary mail. Structural analysis does not prove these properties.

## Source-fragment hardware realization

Use the selected profile and the matching `aggregate_only` artifacts from `xls_topology_dslx:artifact_requirements/2`. Groups sharing a compiled module cannot mix ordinary and aggregate-only instances. Public messages and CPU behavior are unchanged; aggregates use private delivery and consume no ordinary mailbox credit.

The offload remains bounded and backpressured. It delivers only after the destination has opened its window, preserves later ordinary effects, and fails closed on malformed aggregates. Partial offloaded progress is not visible in the recipient's snapshot. Storage, arbitration and qualification details belong in the [maintainer reference](../yap/actor-reductions.md).
