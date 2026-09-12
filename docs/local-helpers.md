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

## Evaluation and generated code

Every argument is evaluated before the helper body, including arguments bound to `_`. Failures in unused arguments or ignored helper results still fail the selected callback. A helper in an unselected `case`/`if` arm or short-circuit operand contributes no failure. Helper parameters and local bindings have their own function scope.

Generated functions return `(value, failed)`. The caller incorporates `failed` into the callback's existing match-failure accounting. State-machine data and effects commit only if the complete callback succeeds; a failing initializer rejects conversion. This is the current callback failure model, rather than a general Erlang exception object or stack trace.

The compiler emits each reachable helper once, in dependency order, using a name that preserves the source spelling and distinguishes arities. XLS requires callees to be declared first, so direct and mutual recursion are diagnosed while ordering the graph. XLS performs function inlining and optimization; a helper call does not request a separately scheduled hardware unit, add a clock boundary, or promise resource sharing.

Generated helper and initializer function signatures carry trailing source-line comments, such as `fn hls_local_prepare_reply__3(...) -> (...) {  // L581`. Broader source annotations and include-aware source maps remain roadmap work.

## Verification

`bash tools/test_helpers.sh XLS_ROOT` compares inline and factored implementations with BEAM, the DSLX interpreter, JIT, and generated combinational RTL. It covers nested calls, static literals, tuples, records, fixed-point/vector types, argument bindings, ignored values, and selected failures, and checks XLS rejection of incompatible argument/result types. Yosys additionally proves equivalence between the two RTL implementations for all input bits; set `YOSYS` when it is outside `PATH`. The initialization/reset and entry-outcome regressions also use helpers in direct and shared actors. Entry checks verify that a helper failure prevents partial state updates and effects.
