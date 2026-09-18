# Phase-entry outcomes

An `hls_statem` entry callback returns `{NextData, Actions}`. The complete callback must succeed before any action can be emitted.

An unselected `andalso`, `orelse`, `case`, or `if` expression branch contributes no failure.

## Branching and storage

An entry may choose its complete `{NextData, Actions}` result or an action-list segment with nested `case`/`if` expressions. Complete results and segments may be named and aliased; returning a named result uses the data and payloads captured when it was constructed. Arms may contain local computations and return different ports, message schemas, or list lengths. Lists must be built from literal cons cells, `[]`, and `++` over supported segments. Tuple destructuring may bind ordinary values and segments together using fresh variables or `_`, including from a named result. Refutable patterns in these segment bindings are unsupported. Recursive list construction, function-produced lists, dynamic ports, and matching an already-bound segment are rejected. Each port may occur once per selected path. See the shared [callback result binding rules](local-helpers.md#callback-result-bindings).

```erlang
running(enter, _OldPhase, Data) ->
    {NextStep, Reports} = case Data#state.send_status of
        true -> {Data#state.step + 1,
            [{cast, status, #status{value = Data#state.value}}]};
        false -> {Data#state.step, []}
    end,
    {Data#state{step = NextStep},
        Reports ++ [{cast, next, #request{step = NextStep}}]}.
```

The selected list retains Erlang source order. Returned data is evaluated before the action list; common list prefixes precede a branching tail. A failure in any selected computation invalidates the whole entry, including effects preceding that failure. Branches preserve selection semantics, not a guarantee that unselected combinational circuitry stops switching. Values and named segments computed before a branch are still eager. A segment captures its payloads when bound; aliases and later uses do not evaluate them again. Even an unused segment retains its selected failure checks.

At most 256 expanded paths per entry and 256 distinct ordered port/schema layouts per actor are supported; excessive expansion is diagnosed. Each message may contain at most 96 packed bits, padded to whole 32-bit transport words. Reservation capacity follows the largest selected list.

A phase can open the same reduction site in several alternatives or leave it unopened. Its opening alternatives must agree on name, population, key expression, and identity; existing data-relative key and constant-identity restrictions apply. An unopened alternative preserves an existing reduction. An opening alternative fails if a reduction is already active. Source-fragment placement additionally requires an unconditional open and an unconditional, complete contribution prefix. A branching suffix after that prefix is supported.

Interface inference records the conservative union of possible effects at each ordered position. A common effect is marked unconditional only when all paths contain it there. Routing checks every possible schema; reservation capacity follows the largest selected list.

## Execution contract

| Outcome | Direct service | Shared executor |
| --- | --- | --- |
| Supported expression failure or invalid reduction reopen | Preserve incoming entry data/reduction; emit nothing; clear entry pending; latch failure regardless of egress readiness. | Same; report neither a valid batch nor egress blockage. |
| Successful entry with blocked output | Preserve data/reduction and the current effect index. | Preserve the machine until space for the batch is available. |
| Successful entry with accepted output | Emit messages in source order; commit data/reduction after the last message. | Commit data/reduction and publish the ordered batch in one activation. |
| Successful entry with no effects | Commit without requiring egress readiness. | Commit without requiring egress readiness. |

The direct service may have emitted part of a successful entry when a later destination stalls. Accepted effects are not rolled back. The shared scheduler owns draining an accepted batch. Neither path dispatches another mailbox message for that actor while entry remains pending.

Callbacks must remain pure: an entry may be reevaluated while waiting for output space.

## Failure scope

Hardware latches failure until reset; ERTS terminates with an Erlang exception. The committed code retains the first selected reason and source location, available through verified shared-actor debug queries; it does not emit an exception packet. Earlier successful entries are not rolled back. A cast that successfully transitions into a failing entry has already selected the new phase and incoming entry data; those values are preserved.

This contract covers supported match, clause-selection and arithmetic/provider failures. It does not cover general Erlang exceptions. Entry heads and action lists must belong to the bounded subset; a missing branch invalidates the entry just as a failed match does. See [control-flow failures](control-flow.md). Initialization and reset do not follow the entry contract.

## Validation

`bash tools/test_entry_outcomes.sh XLS_ROOT` compares BEAM outcomes with direct/shared DSLX, JIT and RTL, including branches, named segments, reductions and stalled egress.
