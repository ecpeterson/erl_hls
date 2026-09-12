# Control flow and failures

Supported `case` and `if` expressions try clauses in source order. A catch-all clause is optional. If no clause matches, the selected expression fails with `case_clause` or `if_clause`, respectively. A guarded final variable pattern is still conditional. Supported patterns are literals, variables, aliases, tuples, and homogeneous records; guard clauses accept one supported Boolean guard sequence. Heterogeneous tagged alternatives and general Erlang exceptions remain outside this subset.

```erlang
-spec nonzero(hls_nums:u32()) -> hls_nums:u32().
nonzero(Value) ->
    if Value =/= 0 -> Value end.
```

The helper succeeds with its argument when nonzero and fails with `if_clause` when zero. It may be called from initializers, callbacks, or other typed local helpers. Names bound in every successful arm may be used after the expression. Names bound in only some arms remain unsafe, even if the expression can also fail.

Expressions and helpers carry their value with a three-bit `hls_failure::Kind`. The first selected failure in Erlang evaluation order wins: arguments precede the helper body, a case subject precedes clause selection, and earlier expressions precede later expressions. Matching a bound variable or a Boolean literal contributes `MATCH_FAILURE`. A failed final clause selection takes precedence over anything in that unselected body. An unselected `case`, `if`, `andalso`, or `orelse` arm contributes no failure. Guard mismatch selects the next clause; failure in a selected body does not.

| Consumer | Failure behavior |
| --- | --- |
| Hardware initializer | Reject compilation through the initializer's constant assertion. |
| `hls_gs` hardware callback | Return the first failure code in an error frame and zero callback state. The proxy decodes `match_failure` (2), `case_clause` (4), and `if_clause` (5). |
| `hls_statem` cast or entry | Follow the existing latched failure path. A failed entry preserves incoming data/reduction state and emits no effects, including any computed prefix. |
| ERTS | Raise the usual Erlang exception. |

The GS wire error retains its one-word payload; function-clause (1) and request-length (3) errors retain their meanings. Request-length rejection preserves state. The state-machine failure latch records only that failure occurred: it does not expose a reason or source location through the debug interface. Neither hardware path reports the unmatched value or an Erlang stack trace.

XLS needs a concrete result type even on a failed path. A non-matching final clause therefore supplies an invalid placeholder value and any joined bindings. Its failure kind prevents consumers from committing that value. The same rule applies to normalized entry action lists: a missing branch cannot publish its placeholder effects. This is a semantic selection guarantee; it does not imply that unselected combinational circuits stop switching. Arithmetic-domain errors, explicit `throw`/`exit`, and exception catching are not implemented by this carrier.

Run `bash tools/test_control_failures.sh XLS_ROOT` for BEAM-derived failure/value vectors, DSLX/JIT comparison, constant-initializer rejection, and generated application RTL at three pipeline schedules. `bash tools/test_entry_outcomes.sh XLS_ROOT` exercises direct and shared state-machine entries with blocked output and nonexhaustive action choices.
