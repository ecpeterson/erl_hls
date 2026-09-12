# Control flow and failures

Supported `case` and `if` expressions try clauses in source order. A catch-all clause is optional. If no clause matches, the selected expression fails with `case_clause` or `if_clause`, respectively. A guarded final variable pattern is still conditional. Supported patterns are literals, variables, aliases, tuples, and homogeneous records; guard clauses accept one supported Boolean guard sequence. Heterogeneous tagged alternatives and general Erlang exceptions remain outside this subset.

```erlang
-spec nonzero(hls_nums:u32()) -> hls_nums:u32().
nonzero(Value) ->
    if Value =/= 0 -> Value end.
```

The helper succeeds with its argument when nonzero and fails with `if_clause` when zero. It may be called from initializers, callbacks, or other typed local helpers. Names bound in every successful arm may be used after the expression. Names bound in only some arms remain unsafe, even if the expression can also fail.

Expressions and helpers carry their value with a sixteen-bit `hls_failure::Code`. The first selected failure in Erlang evaluation order wins: arguments precede the helper body, a case subject precedes clause selection, and earlier expressions precede later expressions. Matching a bound variable or a Boolean literal contributes `MATCH_FAILURE`. A failed final clause selection takes precedence over anything in that unselected body. An unselected `case`, `if`, `andalso`, or `orelse` arm contributes no failure. Guard mismatch selects the next clause; failure in a selected body does not.

| Consumer | Failure behavior |
| --- | --- |
| Hardware initializer | Reject compilation through the initializer's constant assertion. |
| `hls_gs` hardware callback | Return the first failure reason in an error frame and zero callback state; the source-site bits stay internal. The proxy decodes `match_failure` (2), `case_clause` (4), and `if_clause` (5). |
| `hls_statem` cast, reduction-completion handler, or entry | Retain the selected failure code. A failed entry preserves incoming data/reduction state and emits no effects, including any computed prefix. |
| ERTS | Raise the usual Erlang exception. |

The GS wire error retains its one-word payload; function-clause (1) and request-length (3) errors retain their meanings. Request-length rejection preserves state. State machines retain the first selected code until reset. Verified shared-actor [debug queries](debug-targets.md) decode its reason and originating Erlang file and line from the generated source map. Neither hardware path reports the unmatched value or an Erlang stack trace.

XLS needs a concrete result type even on a failed path. A non-matching final clause therefore supplies an invalid placeholder value and any joined bindings. Its failure code prevents consumers from committing that value. The same rule applies to normalized entry action lists: a missing branch cannot publish its placeholder effects. This is a semantic selection guarantee; it does not imply that unselected combinational circuits stop switching. Arithmetic-domain errors, explicit `throw`/`exit`, and exception catching are not implemented by this carrier.

Run `bash tools/test_control_failures.sh XLS_ROOT` for BEAM-derived failure/value vectors, DSLX/JIT comparison, constant-initializer rejection, and generated application RTL at three pipeline schedules. `bash tools/test_entry_outcomes.sh XLS_ROOT` exercises direct and shared state-machine entries with blocked output and nonexhaustive action choices.

Failure codes use their low four bits for the reason and their upper twelve for an actor-local source-site identity; zero is success. The compiler provisions at most 4095 candidate sites per include-expanded module. The source map assigns deterministic codes to file/line/reason origins, including helpers defined in headers. `case_clause` and `if_clause` identify the expression; a bad match identifies its pattern; an explicit `fail` identifies its returned conclusion. Unmatched callback groups identify the first clause of that group. Two occurrences with the same file, line, and reason share a code. Codes are local to the artifact and can change when source locations change.

Protocol errors without a selected source expression, such as malformed input or an invalid reduction reopen, carry a generic reason without a fabricated file or line. Guard failures remain selection predicates, not latched actor errors. Reduction contribution matching and pure reducer fallback retain their existing semantics; the carrier does not add general exception handling to reduction aggregation.
