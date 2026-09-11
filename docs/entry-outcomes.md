# Phase-entry outcomes

An `hls_statem` entry callback returns `{NextData, Actions}`. The complete callback must succeed before any action can be emitted. XLS combines the returned data, ordered effects, optional reduction key/identity, and supported match-failure predicate in a typed `EntryOutcome`.

A `{cast_if, false, Port, Message}` suppresses sending but still evaluates `Message`, on both ERTS and XLS. An unselected `andalso`, `orelse`, `case`, or `if` expression branch contributes no match failure.

## Execution contract

| Outcome | Direct service | Shared executor |
| --- | --- | --- |
| Supported match failure or invalid reduction reopen | Preserve incoming entry data/reduction; emit nothing; clear entry pending; latch failure regardless of egress readiness. | Same; report neither a valid batch nor egress blockage. |
| Successful entry with blocked enabled output | Preserve data/reduction and the current effect index. | Preserve the machine until space for the batch is available. |
| Successful entry with accepted output | Emit allocated slots in source order; skip disabled slots; commit data/reduction after the last slot. | Commit data/reduction and publish the ordered batch in one activation. |
| Successful entry with no enabled effects | Traverse any disabled slots, then commit without requiring egress readiness. | Commit without requiring egress readiness. |

The direct service may have emitted part of a successful entry when a later destination stalls. Accepted effects are not rolled back. The shared scheduler owns draining an accepted batch. Neither path dispatches another mailbox message for that actor while entry remains pending.

The outcome is combinational: an entry can be recomputed from unchanged incoming data while its effects drain or its batch waits for space.

## Failure scope

Hardware latches failure until reset; ERTS terminates with an Erlang exception. Hardware failure carries no exception packet, source location, or first-failure reason. Earlier successful entries are not rolled back. A cast that successfully transitions into a failing entry has already selected the new phase and incoming entry data; those values are preserved.

This contract covers supported match failures, not general Erlang exceptions or arithmetic-domain errors. Entry heads and action lists must have statically supported shapes; `case`/`if` expressions must be exhaustive. Initialization and reset do not follow the entry contract.

## Testing

Run `bash tools/test_entry_outcomes.sh XLS_ROOT` to compare BEAM-derived outcomes with direct and shared execution in DSLX, JIT, and Icarus Verilog. The fixtures cover failed and successful entries, eager `cast_if` payloads, skipped expression branches, ordered outputs, and stalled egress. Additional DSLX/JIT fixtures exercise reduction opens and invalid reopens.
