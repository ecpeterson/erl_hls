# Control flow and failures

Supported `case` and `if` expressions try clauses in source order. A catch-all clause is optional. If no clause matches, the selected expression fails with `case_clause` or `if_clause`, respectively. A guarded final variable pattern is still conditional. Supported patterns are integer/Boolean/enum literals, variables, aliases, tuples, homogeneous records, and fixed-array list patterns; guards accept semicolon-separated alternatives, each containing comma-separated Boolean tests from the supported guard subset. Heterogeneous tagged alternatives and general Erlang exceptions remain outside this subset.

```erlang
-spec nonzero(hls_nums:u32()) -> hls_nums:u32().
nonzero(Value) ->
    if Value =/= 0 -> Value end.
```

The helper succeeds with its argument when nonzero and fails with `if_clause` when zero. It may be called from initializers, callbacks, or other typed local helpers. Names bound in every successful arm may be used after the expression. Names bound in only some arms remain unsafe, even if the expression can also fail.

## List and vector patterns

Values represented by fixed DSLX arrays can be destructured with complete lists (`[A, B, C]`), prefixes (`[Head | _]`), and bound tails (`[Head | Tail]`). These patterns work in callback heads, typed helper heads, `case` clauses, and assignments, including inside tuples and record fields. Nested lists, aliases such as `Whole = [A | Rest = [B, C]]`, and repeated variables retain their Erlang meaning. Assigning to an already-bound variable checks equality and preserves its earlier value.

```erlang
-spec select(hls_vec:vector(hls_nums:u32(), 3)) -> hls_nums:u32().
select([0, Second | _]) -> Second;
select([Head | _]) -> Head.
```

The array length is fixed by the surrounding type. A complete-list pattern checks that exact length; a prefix checks its minimum length. A shorter or longer complete pattern can fail and select a later clause. These checks become constants in hardware; they do not introduce variable-length storage. Elements still have the array's homogeneous type, and bound tails retain their element order. `[]` can appear as a pattern, although the current XLS release cannot carry empty array values.

A bound tail must have a positive compile-time length. An empty or overlong bound-tail projection is rejected by the `hls_patterns::tail` constant assertion, including in an otherwise unselected clause; use `_` when the remainder is discarded. The pinned XLS release also has a [generic type-name mangling defect](../test_data/xls_collection_type_repro.x): bound tails whose element type contains a parameterized struct, such as `APFloat`, currently fail IR parsing. Complete-list and discarded-tail patterns use direct element projections and do not have this generic-helper limitation. Improper-list tails, variable-length lists, and heterogeneous list elements are outside this representation.

Reduction contributions may destructure message fields without losing their message provenance. Destructuring actor data does not make it an admissible source for a contribution or key. Source-fragment placement requires a provably total contribution head: a guardless `[A, B]` matches every value of a known two-element vector, but `[A, A]`, `[0, B]`, and wrong-length lists do not. The analyzer follows source type aliases, including `phi_field:field()`, without loading or executing providers. Every array dimension used by a successful proof becomes a DSLX `const_assert!` against the emitted message type. Unknown shapes retain ordinary placement; explicitly requesting source-fragment placement for them is rejected. See [source type discovery](source-context.md#logical-type-shapes).

## Guards and failures

Guard sequences are exception boundaries. A zero divisor rejects the entire sequence, even when the failing expression is the left operand of `orelse`. A later semicolon alternative can still succeed:

```erlang
if
    (X div Y > 0) orelse true -> First;
    X rem Y =:= 0; Y =:= 0 -> Second;
    true -> Third
end
```

With `Y =:= 0`, this selects `Second`. Within a sequence, `andalso` and `orelse` still short-circuit: `Y =:= 0 orelse X div Y > 0` succeeds without selecting the division. In an ordinary body, `(X div Y > 0) orelse true` fails with `badarith` when `Y` is zero. These rules apply to callback heads, `case`, and `if`; they do not make helpers or arbitrary calls legal in guards. Integer operands retain XLS's fixed widths, as described in the [numeric contract](numeric-contract.md).

Expressions and helpers carry their value with a sixteen-bit `hls_failure::Code`. The first selected failure in Erlang evaluation order wins: arguments precede the helper body, a case subject precedes clause selection, and earlier expressions precede later expressions. A failed assignment pattern contributes `MATCH_FAILURE`, including a literal, repeated variable, or list-length mismatch. A failed final clause selection takes precedence over anything in that unselected body. An unselected `case`, `if`, `andalso`, or `orelse` arm contributes no failure. Guard mismatch selects the next clause; failure in a selected body does not.

| Consumer | Failure behavior |
| --- | --- |
| Hardware initializer | Reject compilation through the initializer's constant assertion. |
| `hls_gs` hardware callback | Return the first failure reason in an error frame and zero callback state; the source-site bits stay internal. The proxy decodes `match_failure` (2), `case_clause` (4), `if_clause` (5), and arithmetic `badarith` (13). |
| `hls_statem` cast, reduction-completion handler, or entry | Retain the selected failure code. A failed entry preserves incoming data/reduction state and emits no effects, including any computed prefix. |
| Pure reduction combiner | Retain the first missed-clause or body failure as an absorbing reduction result; drain the remaining valid contributions before failing the destination actor. |
| ERTS | Raise the usual Erlang exception. |

The GS wire error retains its one-word payload; function-clause (1) and request-length (3) errors retain their meanings. Request-length rejection preserves state. State machines retain the first selected code until reset. Verified shared-actor [debug queries](debug-targets.md) decode its reason and originating Erlang file and line from the generated source map. Neither hardware path reports the unmatched value or an Erlang stack trace.

XLS needs a concrete result type even on a failed path. A non-matching final clause therefore supplies an invalid placeholder value and any joined bindings. Its failure code prevents consumers from committing that value. The same rule applies to normalized entry action lists: a missing branch cannot publish its placeholder effects. This is a semantic selection guarantee; it does not imply that unselected combinational circuits stop switching. Explicit `hls_float` operations contribute `BADARITH` for nonfinite operands or results, including overflow. Integer `div` and `rem` contribute `BADARITH` for a zero divisor. Other arithmetic-domain errors, explicit `throw`/`exit`, and general exception catching are not implemented by this carrier.

Run `bash tools/test_patterns.sh XLS_ROOT` for list-pattern and guarded-helper agreement across BEAM, DSLX/JIT, and generated RTL. The actor-debug regression additionally checks included-file assignment, helper-head, and case failure origins through public queries.

Run `bash tools/test_control_failures.sh XLS_ROOT` for BEAM-derived failure/value vectors, DSLX/JIT comparison, constant-initializer rejection, and generated application RTL at three pipeline schedules. `bash tools/test_entry_outcomes.sh XLS_ROOT` exercises direct and shared state-machine entries with blocked output and nonexhaustive action choices.

Failure codes use their low four bits for the reason and their upper twelve for an actor-local source-site identity; zero is success. The compiler numbers only sites referenced after lowering, densely from 1, then combines each number with its reason. Unused structural candidates consume no codes; the 4095-site limit applies to the retained set per actor module, independently of other modules and scheduler instances. Irrefutable callback heads need no fallthrough error, and literal `consume`/`postpone` conclusions need no failure-site check. The source map assigns deterministic codes to file/line/reason origins, including helpers defined in headers. `case_clause` and `if_clause` identify the expression; a bad match identifies its pattern; an explicit `fail` identifies its returned conclusion; an integer arithmetic failure identifies the operator; a float arithmetic failure identifies the provider call. Unmatched callback groups identify the first clause of that group. Two occurrences with the same file, line, and reason share a code. Codes are local to the artifact and can change when source locations or the retained set change. The debug projection reads and verifies the numeric declarations from that exact DSLX artifact; the host checks its canonical numbering and origins against the structural BEAM inventory and binds the table to the verified RTL manifest.

Protocol errors without a selected source expression, such as malformed input or an invalid reduction reopen, carry a generic reason without a fabricated file or line. Guard failures remain selection predicates, not latched actor errors. Reduction contribution matching retains the [reduction admission rules](actor-reductions.md); a failed reduction still waits for all valid contributions, without evaluating further combines or running its successful completion callback.
