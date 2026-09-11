# Phase-entry outcomes

An `hls_statem` entry callback returns `{NextData, Actions}`. The CPU evaluates that complete Erlang expression before the runtime processes any action. The XLS lowering follows the same boundary for the supported match failures: a failure in the prefix, returned data, reduction identity, cast condition, or message invalidates the entire entry. A `{cast_if, false, Port, Message}` suppresses sending; it does not make `Message` lazy. An unselected `andalso`, `orelse`, `case`, or `if` branch contributes no match failure.

## Lowering and execution

`xls_statem_lower` builds one expression containing the returned data, optional reduction key/identity, and ordered condition/message pairs. `xls_parse:clause_outcome/4` lowers it with its prefix once, retaining the value and combined match-failure predicate. The renderer constructs one typed `EntryOutcome` with data, `EntryEffects`, an optional `ReductionState`, and `failed`. Reduction-site IR retains static population and reducer information; it no longer contains independent key/identity callback evaluators.

The previous lowering evaluated the callback prefix separately for returned data, each outgoing message, each conditional validity bit, and the reduction key and identity. Its fallbacks could keep old data but leave an unconditional effect enabled, emitting a zero-valued message. A failed conditional could merely suppress that slot while later casts escaped. A failed reduction identity could silently open with a zero accumulator. The outcome makes these failures explicit before any effect from the entry is accepted.

| Outcome | Direct service | Shared executor |
| --- | --- | --- |
| Callback failure or invalid reduction reopen | Preserve incoming entry data/reduction; emit nothing; clear entry pending; latch failure regardless of egress readiness. | Same; also report neither a valid batch nor egress blockage. |
| Successful entry with blocked enabled output | Preserve data/reduction and the current effect index. | Preserve the machine until space for the batch is available. |
| Successful entry with accepted output | Emit allocated slots in source order; skip disabled slots; commit data/reduction after the last slot. | Commit data/reduction and publish the ordered batch in one activation. |
| Successful entry with no enabled effects | Traverse any disabled slots, then commit without requiring egress readiness. | Commit without requiring egress readiness. |

The direct service may already have emitted part of a **successful** entry when a later destination stalls. Those accepted effects retain their existing completion contract. The shared scheduler similarly owns draining an accepted batch. Neither path dispatches another mailbox message for that actor while entry remains pending.

“Once” describes the lowered expression graph: the prefix is not independently lowered for each projection. It does not introduce an outcome register or promise that combinational logic is evaluated only once in wall-clock time. A direct entry can be recomputed from unchanged incoming data while its slots drain, and a blocked shared entry can be retried. Machine RAM layout, scheduler protocol, effect-batch layout, and reset mechanism are unchanged. There is no general area or timing improvement claim; XLS already shares and simplifies equivalent pure expressions.

## Failure scope

The hardware uses its existing fail-until-reset state. The CPU terminates with an Erlang exception, so lifecycle and diagnostic behavior are still different. This change adds no exception packet, source location, first-failure reason, rollback of earlier successful entries, or propagation to a supervisor. A cast that successfully transitions into a failing entry has already selected the new phase and incoming entry data; those values are preserved.

Only failures modeled by the expression lowerer are covered. Nonexhaustive `case`/`if`, general Erlang exceptions, arithmetic-domain errors, and initialization/reset parity remain separate compiler work. The entry head and action list retain the existing static restrictions.

## Regressions

Run `bash tools/test_entry_outcomes.sh XLS_ROOT`. It evaluates the same compiled Erlang callback fixtures to construct the oracle, then checks direct and shared execution in the DSLX interpreter, JIT, and Icarus Verilog. Eight entry shapes, four input values, two execution paths, and three readiness schedules give 192 comparisons of final data, failure/pending state, and ordered accepted outputs. The readiness schedules cover always ready, initial and intermittent stalls, and permanent blockage.

Additional DSLX/JIT tests exercise reduction opens in ordinary and aggregate-only actor artifacts: prefix failure, late-message failure, invalid identity, invalid reopen, a stall after the first accepted effect, and shared batch reservation. The existing reduction, ordered-egress, and full actor/topology RTL suites cover successful integration with the mailbox and scheduler. CI runs these tests with the pinned XLS release and retains generated entry fixtures, IR, RTL, and the testbench on failure.

## Matched D3 validation

A matched native comparison of `main` (`f13bf69`) and this lowering used the existing decoder-only, request-paced D3 profile with three shards, two pipeline stages, and initiation interval one. Both completed the nontrivial replay and passed the scheduler/effect-window accounting checks. Across steps 9–32, every interval was 174 clocks on both versions: minimum/mean/maximum 174, population variance zero, total 4,176 clocks. Source/phi state reads (648/8,958), mailbox reads (630/624), and X/Z correction counts (63/64) matched. The generated pipeline declared 22,392 register bits before and 22,319 after; this is a structural count, not a mapped-area result.

The two runs used the same rescued native XLS tools with the fixed-latency RAM response fix. The ordinary CI suite independently uses the pinned Linux release. Run `ERL_HLS_PHI_PROFILE_TRACE=0 bash tools/run_phi_decoder_profile.sh STAGE XLS_ROOT` to reproduce the aggregate profile. For the distribution, the staged testbench additionally logged `cycle_count` immediately after both planes' status masks for a step became complete; the input, ready, clock, and synthesized-design paths were unchanged. This decoder-only profile does not establish physical timing or whole phenomenological-network throughput.
