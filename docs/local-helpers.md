# Local helper functions

Initializers and actor callbacks can call pure functions defined in the same include-expanded Erlang module. A helper needs no export. Both `helper(Value)` and `?MODULE:helper(Value)` name the same definition. Only functions reachable from `init/1`, `hls_gs` handlers, declared `hls_statem` phase functions, or `reduce/3` are translated; unrelated host utilities retain their ordinary Erlang implementation.

```erlang
-spec prepare_reply(#data_cell{}, hls_nums:u32(), hls_pauli:pauli()) -> #data_cell{}.
prepare_reply(Cell, RequestId, Measurement) ->
    Anticommutes = hls_pauli:anticommutes(Cell#data_cell.accumulated_pauli, Measurement),
    Cell#data_cell{
        reply_request_id = RequestId,
        reply_anticommutes = case Anticommutes of
            false -> hls_type:as(hls_nums:u32(), 0);
            true -> hls_type:as(hls_nums:u32(), 1)
        end
    }.
```

`phenom_data_cell` uses this helper from its three query-handling phases. Each caller separately chooses the protocol transition and continuation phase.

## Types and supported bodies

Each helper has one concrete `-spec`. Arguments and results can use `hls_type` provider types, including integers, fixed-point numbers and fixed-size vectors, `boolean()`, fixed tuples of supported types, and the actor's declared data/message records. XLS checks argument and result types. Specs such as `integer()`, polymorphic variables, overloaded signatures, and local type aliases do not give the current translator a supported concrete representation. A call does not insert a numeric cast or normalization; use the type provider's operations explicitly where needed. The existing [numeric contracts](numeric-contract.md) also apply inside helpers.

Signatures supply integer-literal widths through tuple fields, local bindings, arithmetic and `case`/`if` results. For example, a helper taking `{boolean(), hls_nums:u16(), hls_nums:s32()}` accepts `{Flag, 0, -1}` without casts around the literals. A helper returning that tuple can select `{true, 1, -1}` or `{false, 65535, 2}`. Literals must fit their declared type; existing values are not widened or narrowed, and a bound value used at incompatible widths remains a type error. Comparisons, shift counts and provider arguments retain their independent typing rules; signatures do not supply a default width for unrelated expressions.

Helpers may have multiple clauses with the same pattern and guard subset as callbacks, including fixed-list patterns, aliases, repeated variables, and semicolon guard alternatives. Clauses are tried in source order. If no head and guard match, the helper raises `function_clause`; a failure in a selected body does not try a later clause. Pattern matching, `case`, `if`, and short-circuit Boolean expressions are also available in the body. Nested calls and multiple arities are supported. Type descriptors are compile-time objects used inside expressions, rather than runtime helper parameters; parametric helper signatures are not supported.

Helpers compute values. Callback result tuples, transition directives, output ports, action-list structure, and reduction declarations must remain visible to the existing callback analysis. For example, a cast can return `{active, update_data(Cell, Offset), consume}`, and an entry can emit `{cast, out, #report{value = calculation(Cell)}}`. Factoring the complete callback result or an action list into a helper is outside the supported structural subset. Calling a hardware callback as a helper is rejected. External expression operations still require their provider's `transpile/3` implementation; arbitrary OTP calls and side effects are not hardware operations.

## Branch bindings

`case` and `if` make a new variable available afterward when every arm binds it. This applies in helpers, initializers, and callback bodies, including nested branches and variables introduced by `case` patterns.

```erlang
-spec select(hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
select(X, Y) ->
    case X < Y of
        true -> Smaller = X, Larger = Y;
        false -> Smaller = Y, Larger = X
    end,
    Larger - Smaller.
```

Every exported value must have one XLS type across its arms. Use explicit provider conversions when widths or representations differ. The expression's result also retains the existing fixed-type requirement. Unused local names stay inside their arms and may have different types. The compiler exports only values used afterward; those joins are ordinary combinational selections, with no added actor state or scheduling boundary.

Matching an exported or previously bound variable checks equality and preserves its original value. A failed match contributes to the selected callback's failure flag, including when the branch expression's result is discarded. A name bound in only some arms is unsafe to read or match afterward; the diagnostic includes the use location and originating branch location. Right operands of `andalso` and `orelse` cannot export a definitely bound variable because they may be skipped.

## Callback result bindings

State-machine initializers, ordinary cast callbacks, reduction-completion handlers, and entries can name and alias their complete result tuples. A result binding can select constructors with nested `case`/`if` or `begin` blocks, including arm-local computations and aliases. Each returned alternative must expose the callback's required shape: `{ok, Phase, Data}`, `{NextPhase, Data, Directive}`, or `{NextData, Actions}`. This is structural analysis of local constructors; a helper-produced complete result or an opaque tuple-valued input remains unsupported. Helpers can compute the fields as described above. Reduction contribution callbacks and reducers retain their existing structural rules.

```erlang
running(cast, #request{value = Value}, Data) ->
    Result = case Value > 0 of
        true -> {repeat_phase, update_data(Data, Value), consume};
        false -> {running, Data, fail}
    end,
    Result.
```

Fields are evaluated once, in source order, when the tuple is constructed. Returning or aliasing that tuple uses its captured values. A later branch that discards it cannot discard an earlier selected expression failure. An explicit `fail` directive takes effect only when its conclusion is returned; its source location identifies the original tuple constructor. `repeat_phase` still requires `consume` and schedules a fresh entry into the current phase.

Structural result bindings use fresh variables or fixed tuple patterns of fresh variables and `_`. For example, `{NextPhase, NextData} = case ... end, {NextPhase, NextData, consume}` separates transition selection from the common directive, including when an arm selects `repeat_phase`. Every right-hand-side field is evaluated before destructuring. Ordinary data fields retain their bindings and later equality checks; refutable matching of a structural control value remains unsupported. Action segments follow the [entry contract](entry-outcomes.md). Bind the result of a choice with `Result = case ... end`; defining the result variable separately in each arm and returning it afterward is outside this structural subset. Ordinary typed value joins and their equality checks retain the rules above.

The compiler carries the continuation into structural alternatives so callback control tags and differently shaped entry batches need no common Erlang-value representation in XLS. Expansion is limited to 256 result paths per callback, in addition to entry path/layout limits. These bindings introduce no actor state or scheduling boundary, but branching can duplicate combinational expressions before XLS optimization. Native tagged sums in XLS could allow more of these continuations to rejoin without duplication.

## Evaluation and generated code

Every argument is evaluated before the helper body, including arguments bound to `_`. Failures in unused arguments or ignored helper results still fail the selected callback. A helper in an unselected `case`/`if` arm or short-circuit operand contributes no failure. Helper parameters and local bindings have their own function scope.

Generated functions return `(value, hls_failure::Code)`. The caller retains the first selected failure across argument evaluation, the helper body, and later expressions; a helper's `function_clause`, `case_clause`, `if_clause`, or assignment mismatch retains its reason and source location through its callers. An unmatched helper identifies the first clause in that function. State-machine data and effects commit only if the complete callback succeeds; a failing initializer rejects conversion. See [control-flow failures](control-flow.md) for reporting and limits.

The compiler emits each reachable helper once, in dependency order, using a name that preserves the source spelling and distinguishes arities. XLS requires callees to be declared first, so direct and mutual recursion are diagnosed while ordering the graph. XLS performs function inlining and optimization; a helper call does not request a separately scheduled hardware unit, add a clock boundary, or promise resource sharing.

Generated helper and initializer function signatures carry trailing source-line comments, such as `fn hls_local_prepare_reply__3(...) -> (...) {  // L581`. Broader source annotations and include-aware source maps remain roadmap work.

## Verification

`bash tools/test_patterns.sh XLS_ROOT` checks guarded and patterned helper heads, returned tails, selected-body failures, and argument-failure precedence against BEAM and generated RTL. See [list and vector patterns](control-flow.md#list-and-vector-patterns) for representation limits.

`bash tools/test_helpers.sh XLS_ROOT` compares inline and factored implementations with BEAM, the DSLX interpreter, JIT, and generated combinational RTL. It covers nested calls, static literals, tuples, records, fixed-point/vector types, argument bindings, ignored values, selected failures, and branch joins. Joins cover nested `case`/`if`, pattern bindings, repeated matches, records, tuples, and differently typed unused locals. The suite checks XLS rejection of incompatible argument, result, and joined-value types. Yosys additionally proves equivalence between the two RTL implementations for all input bits; set `YOSYS` when it is outside `PATH`. The initialization/reset and entry-outcome regressions also use helpers in direct and shared actors. Entry checks verify that a helper failure prevents partial state updates and effects.
