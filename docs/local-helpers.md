# Local helper functions

Initializers and actor callbacks can call pure functions defined in the same include-expanded Erlang module. A helper needs no export. Both `helper(Value)` and `?MODULE:helper(Value)` name the same definition. Only functions reachable from `init/1`, `hls_gs` handlers, or declared `hls_statem` phase functions are translated; unrelated host utilities retain their ordinary Erlang implementation.

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

A helper currently has one unguarded clause whose parameters are distinct variables or `_`. Pattern matching, `case`, `if`, and short-circuit Boolean expressions are available in the body with the same restrictions as in a callback. Nested calls and multiple arities are supported. Type descriptors are compile-time objects used inside expressions, rather than runtime helper parameters; parametric helper signatures are not supported.

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

These value joins do not extend the structural callback vocabulary. Complete cast conclusions must still be final tuples or final `case`/`if` expressions, and action-list bindings follow the separate [entry contract](entry-outcomes.md).

## Evaluation and generated code

Every argument is evaluated before the helper body, including arguments bound to `_`. Failures in unused arguments or ignored helper results still fail the selected callback. A helper in an unselected `case`/`if` arm or short-circuit operand contributes no failure. Helper parameters and local bindings have their own function scope.

Generated functions return `(value, hls_failure::Code)`. The caller retains the first selected failure across argument evaluation, the helper body, and later expressions; a helper's `case_clause` or `if_clause` retains its own reason and source location through its callers. State-machine data and effects commit only if the complete callback succeeds; a failing initializer rejects conversion. See [control-flow failures](control-flow.md) for reporting and limits.

The compiler emits each reachable helper once, in dependency order, using a name that preserves the source spelling and distinguishes arities. XLS requires callees to be declared first, so direct and mutual recursion are diagnosed while ordering the graph. XLS performs function inlining and optimization; a helper call does not request a separately scheduled hardware unit, add a clock boundary, or promise resource sharing.

Generated helper and initializer function signatures carry trailing source-line comments, such as `fn hls_local_prepare_reply__3(...) -> (...) {  // L581`. Broader source annotations and include-aware source maps remain roadmap work.

## Verification

`bash tools/test_helpers.sh XLS_ROOT` compares inline and factored implementations with BEAM, the DSLX interpreter, JIT, and generated combinational RTL. It covers nested calls, static literals, tuples, records, fixed-point/vector types, argument bindings, ignored values, selected failures, and branch joins. Joins cover nested `case`/`if`, pattern bindings, repeated matches, records, tuples, and differently typed unused locals. The suite checks XLS rejection of incompatible argument, result, and joined-value types. Yosys additionally proves equivalence between the two RTL implementations for all input bits; set `YOSYS` when it is outside `PATH`. The initialization/reset and entry-outcome regressions also use helpers in direct and shared actors. Entry checks verify that a helper failure prevents partial state updates and effects.
