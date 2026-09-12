# Phase-entry outcomes

An `hls_statem` entry callback returns `{NextData, Actions}`. The complete callback must succeed before any action can be emitted. XLS combines the returned data, ordered effects, optional reduction key/identity, and selected failure code in a typed `EntryOutcome`.

An unselected `andalso`, `orelse`, `case`, or `if` expression branch contributes no failure.

## Branching and storage

An entry may choose its complete `{NextData, Actions}` result or an action-list segment with nested `case`/`if` expressions. Arms may contain local computations and return different ports, message schemas, or list lengths. Lists must be built from literal cons cells, `[]`, and `++` over supported segments. Segments may be named and aliased, and tuple destructuring may bind ordinary values and segments together using fresh variables or `_`. Refutable patterns in these segment bindings are unsupported. Recursive list construction, function-produced lists, dynamic ports, and matching an already-bound segment are rejected. Each port may occur once per selected path.

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

The compiler normalizes each leaf into one typed outcome. One eight-bit layout selector identifies its ordered port/schema sequence. Shared payload storage is sized to the largest alternative. The layout determines the selected list length; every slot in that list emits a message. Hardware may still contain computations and multiplexers for multiple alternatives. At most 256 expanded paths per entry and 256 layouts per actor are supported; excessive expansion is diagnosed. Every individual message must satisfy the existing word-aligned, at-most-three-word wire format.

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

The outcome is combinational: an entry can be recomputed from unchanged incoming data while its effects drain or its batch waits for space.

## Failure scope

Hardware latches failure until reset; ERTS terminates with an Erlang exception. The committed code retains the first selected reason and source location, available through verified shared-actor debug queries; it does not emit an exception packet. Earlier successful entries are not rolled back. A cast that successfully transitions into a failing entry has already selected the new phase and incoming entry data; those values are preserved.

This contract covers supported matches, `case_clause`, and `if_clause` failures. It does not cover general Erlang exceptions or arithmetic-domain errors. Entry heads and action lists must belong to the bounded subset; a missing branch invalidates the entry just as a failed match does. See [control-flow failures](control-flow.md). Initialization and reset do not follow the entry contract.

## Testing

Run `bash tools/test_entry_outcomes.sh XLS_ROOT` to compare BEAM-derived outcomes with direct and shared execution in DSLX, JIT, and Icarus Verilog. The fixtures cover failed and successful entries, eager named segments, skipped expression branches, ordered outputs, and stalled egress. Branching fixtures also check varying schemas and payload lengths, nested choices, partial output acceptance, skipped failures, and nonexhaustive complete results, guarded choices, action-list tails, and unused named segments. Additional DSLX/JIT fixtures exercise unconditional and conditional reduction opens, blocked commits, and invalid reopens.
