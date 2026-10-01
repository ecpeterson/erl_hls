# Indexed actor gathers

A gather collects one typed value per selected numeric member and passes the ordered list to a private completion callback. It has no reducer or algebraic law. Use it when the consumer must preserve positions or inspect several values together. Senders use ordinary actor messages.

```erlang
collecting(enter, _, Cell) ->
    {Cell, [{open_gather, items, Cell#cell.key,
        {members_mask, 4, Cell#cell.mask}, #element{}}]};
collecting(cast, #piece{key = Key, member = Member, value = Value}, Cell) ->
    {collecting, Cell, {gather, items, Key, Member, #element{value = Value}}};
collecting(internal, {gather_complete, items, Key, Mask, Values}, Cell) ->
    {complete, consume_values(Cell, Key, Mask, Values), consume}.
```

`Capacity` is 1–255. The captured `Mask` selects members `0` through `Capacity - 1`; it may be zero and cannot contain higher bits. Each selected member contributes once. Duplicate or unexpected members fail. The completion list always has `Capacity` entries: member zero occupies its first position, and inactive positions contain the declared padding value. Presence comes from the mask, including when a contribution equals padding.

Only one gather or scalar reduction may be active per actor. Opening must be the first entry action; the complete entry is validated before effects or state commit. An empty gather completes after that entry commits. Contributions retain phase and data, consume accepted messages, and postpone a mismatched name or key. Leaving or repeating a phase with an incomplete gather fails. Normal source clause order, guards and fallback callbacks still determine whether a cast returns a gather directive.

Completion precedes the next mailbox selection and may consume, fail, change phase or repeat the phase. With declared continuations, it may return a fourth field `[{next_event, internal, Name}]`; successor entry runs before that event. Scalar reduction completions support the same action. Neither completion may postpone, contribute or reply. A pure helper can consume `Values` immediately, leaving only a small result in ordinary actor data.

## XLS subset

Each gather site declares its own record element type and capacity. Sites may coexist with scalar reductions of another accumulator type. Padding must be a constant record constructor; typed defaults are allowed. Elements may be record constructors or typed record variables bound from the message, with message-only value provenance. Keys and members use `hls_nums:u32()`. The mask passed to completion has `Capacity` bits, and a pure helper accepts the values as `hls_lists:list(#element{}, Capacity)`. Cast contributions directly finish leading clauses for their message/phase. Their key, member and element expressions use total construction, integral casts or basic integral arithmetic; partial operations and helper calls are rejected in a contribution body. Put checked computation in the completion consumer. Retained calls and gathers are not currently combined in one translated actor.

The closed artifact separates gather progress from ordered payloads. Its ordinary actor implementation preserves the complete CPU scheduling path. A physical backend may retain payloads separately and inject them at completion; completion replaces every inactive lane with the declared padding before invoking source code. No implicit snapshot field is added to callback data, and scalar accumulator storage is unchanged.

## Inspection and witnesses

`hls_statem:info/1` and `hls_debug:info(Actor, gather)` expose membership progress without values. Direct hardware debug uses the existing collection metadata region, identifies gather sites separately from scalar sites, and reports the selected and missing members when their masks fit. Wider sets retain honest remaining counts and mark unavailable membership. Query packets contain no element payload.

`bash tools/test_statem_gathers.sh XLS_ROOT` runs interpreter/JIT simulation witnesses for all capacity-four subsets, empty completion, reversed member arrival, stale inactive lanes, checked member errors, distinct site element types, nonzero padding, completion continuations, output stalls and metadata-only observation. The direct scheduling witness runs 32 steps. These are bounded simulation witnesses, not a proof of arbitrary actor protocols.
