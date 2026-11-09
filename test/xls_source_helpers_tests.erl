-module(xls_source_helpers_tests).
-moduledoc "Source-only remote helper closure, namespace, preprocessing and saved-plan checks.".
-include_lib("eunit/include/eunit.hrl").

%% A public source function may use private helpers without importing host code.
-spec exported_function_and_private_closure_test() -> ok.
exported_function_and_private_closure_test() ->
    with_sources([
        {"root.erl", root("remote_math:outer(Value) + remote_math:outer(Value)")},
        {"remote_math.erl", module(remote_math, ["outer/1"], [
            function(outer, "inner(Value)"),
            function(inner, "Value + 1"),
            "host_only() -> io:format(\"not hardware\"), unsupported().\n"
        ])}
    ], fun(Directory) ->
        {Forms, Helpers} = prepare(Directory, []),
        ?assertEqual(2, length(Helpers)),
        ?assertEqual(2, length(lists:usort([Name || #{name := Name} <- Helpers]))),
        ?assertEqual([], remote_calls(remote_math, Forms)),
        ?assertEqual(false, contains_atom(host_only, Helpers)),
        ?assertEqual([remote_math], dependency_modules(Forms)),
        ok
    end).

%% Qualified self calls obey ordinary Erlang export visibility.
-spec qualified_public_self_call_test() -> ok.
qualified_public_self_call_test() ->
    with_sources([
        {"root.erl", root("public_math:outer(Value)")},
        {"public_math.erl", module(public_math, ["outer/1", "inner/1"], [
            function(outer, "public_math:inner(Value)"), function(inner, "Value + 1")])}
    ], fun(Directory) ->
        {_, Helpers} = prepare(Directory, []),
        ?assertEqual(2, length(Helpers)),
        ok
    end).

%% A remote spelling cannot use a private implementation even inside its own module.
-spec qualified_private_self_call_is_rejected_test() -> ok.
qualified_private_self_call_is_rejected_test() ->
    with_sources([
        {"root.erl", root("public_math:outer(Value)")},
        {"public_math.erl", module(public_math, ["outer/1"], [
            function(outer, "public_math:inner(Value)"), function(inner, "Value + 1")])}
    ], fun(Directory) ->
        ?assertException(error, {unexported_xls_source_helper, {public_math, inner, 1}, _},
            prepare(Directory, [])),
        ok
    end).

%% Identically named functions in three source modules must not capture each other.
-spec module_namespaces_are_distinct_test() -> ok.
module_namespaces_are_distinct_test() ->
    with_sources([
        {"root.erl", [root("value(Value) + left_math:value(Value) + right_math:value(Value)"),
            function(value, "Value + 3")]},
        {"left_math.erl", module(left_math, ["value/1"], [function(value, "Value + 1")])},
        {"right_math.erl", module(right_math, ["value/1"], [function(value, "Value + 2")])}
    ], fun(Directory) ->
        {_, Helpers} = prepare(Directory, []),
        ?assertEqual(3, length(Helpers)),
        ?assertEqual(3, length(lists:usort([Name || #{name := Name} <- Helpers]))),
        ok
    end).

%% A transitive remote call adds its own public function and private implementation once.
-spec nested_remote_calls_test() -> ok.
nested_remote_calls_test() ->
    with_sources([
        {"root.erl", root("outer_math:value(Value)")},
        {"outer_math.erl", module(outer_math, ["value/1"], [
            function(value, "inner_math:value(Value)")])},
        {"inner_math.erl", module(inner_math, ["value/1"], [
            function(value, "private_value(Value)"), function(private_value, "Value + 4")])}
    ], fun(Directory) ->
        {Forms, Helpers} = prepare(Directory, []),
        ?assertEqual(3, length(Helpers)),
        ?assertEqual([inner_math, outer_math], dependency_modules(Forms)),
        ?assertEqual([], remote_calls(inner_math, Helpers)),
        ok
    end).

%% Public remote syntax does not grant access to a private source function.
-spec private_remote_function_is_rejected_test() -> ok.
private_remote_function_is_rejected_test() ->
    with_sources([
        {"root.erl", root("private_math:value(Value)")},
        {"private_math.erl", module(private_math, [], [function(value, "Value")])}
    ], fun(Directory) ->
        ?assertException(error, {unexported_xls_source_helper, {private_math, value, 1}, _},
            prepare(Directory, [])),
        ok
    end).

%% An exported declaration without a definition cannot become an opaque provider call.
-spec missing_exported_definition_is_rejected_test() -> ok.
missing_exported_definition_is_rejected_test() ->
    with_sources([
        {"root.erl", root("missing_math:value(Value)")},
        {"missing_math.erl", module(missing_math, ["value/1"], [])}
    ], fun(Directory) ->
        ?assertException(error, {undefined_xls_source_helper, {missing_math, value, 1}, _},
            prepare(Directory, [])),
        ok
    end).

%% Source recursion remains a finite graph and reaches the ordinary recursion diagnostic.
-spec cross_module_recursion_is_rejected_test() -> ok.
cross_module_recursion_is_rejected_test() ->
    with_sources([
        {"root.erl", root("cycle_left:value(Value)")},
        {"cycle_left.erl", module(cycle_left, ["value/1"], [
            function(value, "cycle_right:value(Value)")])},
        {"cycle_right.erl", module(cycle_right, ["value/1"], [
            function(value, "cycle_left:value(Value)")])}
    ], fun(Directory) ->
        ?assertException(error, {recursive_xls_helpers, _}, prepare(Directory, [])),
        ok
    end).

%% Macro definitions and includes come from the caller's captured preprocessing context.
-spec explicit_source_root_and_macro_context_test() -> ok.
explicit_source_root_and_macro_context_test() ->
    with_sources([
        {"root.erl", root("configured_math:value(Value)")},
        {"library/configured_math.erl", module(configured_math, ["value/1"], [
            "-include(\"offset.hrl\").\n", function(value, "Value + ?OFFSET")])},
        {"library/offset.hrl", "-define(OFFSET, ?BASE_OFFSET).\n"}
    ], fun(Directory) ->
        Options = [{i, filename:join(Directory, "library")}, {d, 'BASE_OFFSET', 17}],
        {Forms, Helpers} = prepare(Directory, Options),
        ?assertEqual([configured_math], dependency_modules(Forms)),
        ?assertMatch([#{clauses := [{clause, _, _, _, [
            {op, _, '+', {var, _, 'Value'}, {xls_typed_integer, _, _, 17}}
        ]}]}], Helpers),
        ok
    end).

%% A matching filename with another module declaration is not the requested library.
-spec mismatched_module_declaration_is_rejected_test() -> ok.
mismatched_module_declaration_is_rejected_test() ->
    with_sources([
        {"root.erl", root("expected_math:value(Value)")},
        {"expected_math.erl", module(unrelated_math, ["value/1"], [function(value, "Value")])}
    ], fun(Directory) ->
        ?assertException(error, {xls_source_module_mismatch, expected_math, unrelated_math, _},
            prepare(Directory, [])),
        ok
    end).

%% A custom provider's export keeps its operations at the established transpile boundary.
-spec source_provider_precedence_test() -> ok.
source_provider_precedence_test() ->
    with_sources([
        {"root.erl", root("custom_provider:value(Value)")},
        {"custom_provider.erl", module(custom_provider, ["value/1", "transpile/3"], [
            function(value, "unsupported(Value)"),
            "transpile(_, _, _) -> error(must_not_be_called_during_selection).\n"
        ])}
    ], fun(Directory) ->
        {Forms, Helpers} = prepare(Directory, []),
        ?assertEqual([], Helpers),
        ?assertMatch([_], remote_calls(custom_provider, Forms)),
        ok
    end).

%% Standard provider calls stay external even if a misleading same-named source is adjacent.
-spec builtin_provider_precedence_test() -> ok.
builtin_provider_precedence_test() ->
    with_sources([
        {"root.erl", root("hls_nums:u32()")},
        {"hls_nums.erl", module(hls_nums, ["u32/0"], ["u32() -> unsupported().\n"])}
    ], fun(Directory) ->
        {Forms, Helpers} = prepare(Directory, []),
        ?assertEqual([], Helpers),
        ?assertMatch([_], remote_calls(hls_nums, Forms)),
        ok
    end).

%% Compiling source must not load a BEAM or execute an on_load callback.
-spec source_discovery_never_executes_module_test() -> ok.
source_discovery_never_executes_module_test() ->
    with_sources([
        {"root.erl", root("source_only_math:value(Value)")},
        {"source_only_math.erl", module(source_only_math, ["value/1"], [
            "-on_load(trap/0).\n",
            "trap() -> error(source_module_was_loaded).\n",
            function(value, "Value")])}
    ], fun(Directory) ->
        ?assertEqual(false, code:is_loaded(source_only_math)),
        {_, [_]} = prepare(Directory, []),
        ?assertEqual(false, code:is_loaded(source_only_math)),
        ok
    end).

%% The first source-helper slice does not merge module-local record or alias namespaces.
-spec unsupported_imported_types_test_() -> [{string(), fun(() -> ok)}].
unsupported_imported_types_test_() ->
    [{atom_to_list(Reason), fun() ->
        with_sources([
            {"root.erl", root("typed_math:value(Value)")},
            {"typed_math.erl", module(typed_math, ["value/1"], Body)}
        ], fun(Directory) ->
            ?assertException(error,
                {unsupported_xls_source_helper, {typed_math, value, 1}, Reason},
                prepare(Directory, [])),
            ok
        end)
    end} || {Reason, Body} <- [
        {local_type_alias, ["-type sample_number() :: hls_nums:u32().\n",
            "-spec value(sample_number()) -> sample_number().\nvalue(Value) -> Value.\n"]},
        {record_values, ["-record(number, {value :: hls_nums:u32()}).\n",
            "-spec value(#number{}) -> hls_nums:u32().\n",
            "value(#number{value = Value}) -> Value.\n"]}
    ]].

%% Erlang imported-function bindings must not accidentally resolve in the actor namespace.
-spec imported_function_declaration_is_rejected_test() -> ok.
imported_function_declaration_is_rejected_test() ->
    with_sources([
        {"root.erl", root("importing_math:value(Value)")},
        {"importing_math.erl", module(importing_math, ["value/1"], [
            "-import(other_math, [helper/1]).\n", function(value, "helper(Value)")])}
    ], fun(Directory) ->
        ?assertException(error,
            {unsupported_xls_source_helper, {importing_math, helper, 1}, imports},
            prepare(Directory, [])),
        ok
    end).

%% A declared import wins over an auto-imported BIF even for recognized binary operations.
-spec imported_size_function_cannot_become_builtin_test() -> ok.
imported_size_function_cannot_become_builtin_test() ->
    with_sources([
        {"root.erl", root("size_math:value(Value)")},
        {"size_math.erl", module(size_math, ["value/1"], [
            "-import(other_math, [byte_size/1]).\n",
            function(value, "byte_size(Value)")])}
    ], fun(Directory) ->
        ?assertException(error,
            {unsupported_xls_source_helper, {size_math, byte_size, 1}, imports},
            prepare(Directory, [])),
        ok
    end).

%% Reachable functions alone enter binary syntax and anonymous-function hardware checks.
-spec unreachable_host_syntax_is_ignored_test() -> ok.
unreachable_host_syntax_is_ignored_test() ->
    with_sources([
        {"root.erl", root("mixed_math:value(Value)")},
        {"mixed_math.erl", module(mixed_math, ["value/1", "host_binary/1", "host_fun/0"], [
            function(value, "Value + 1"),
            "host_binary(Value) -> <<Value:32/native>>.\n",
            "host_fun() -> fun() -> io:format(\"host only\") end.\n"])}
    ], fun(Directory) ->
        {Forms, [Helper]} = prepare(Directory, []),
        ?assertEqual([mixed_math], dependency_modules(Forms)),
        ?assertEqual(false, contains_atom(host_binary, Helper)),
        ?assertEqual(false, contains_atom(host_fun, Helper)),
        ok
    end).

%% The imported module's parse-transform semantics cannot be inferred from raw source.
-spec imported_parse_transform_is_rejected_without_running_test() -> ok.
imported_parse_transform_is_rejected_without_running_test() ->
    with_sources([
        {"root.erl", root("transformed_math:value(Value)")},
        {"transformed_math.erl", module(transformed_math, ["value/1"], [
            "-compile({parse_transform, source_transform_trap}).\n",
            function(value, "Value")])},
        {"source_transform_trap.erl", module(source_transform_trap, ["parse_transform/2"], [
            "parse_transform(_, _) -> error(source_transform_was_executed).\n"])}
    ], fun(Directory) ->
        ?assertEqual(false, code:is_loaded(source_transform_trap)),
        ?assertException(error,
            {unsupported_xls_source_helper, {transformed_math, value, 1}, parse_transform},
            prepare(Directory, [])),
        ?assertEqual(false, code:is_loaded(source_transform_trap)),
        ok
    end).

%% Selecting an already captured closure is idempotent and does not reread mutable files.
-spec repeated_selection_uses_captured_source_test() -> ok.
repeated_selection_uses_captured_source_test() ->
    with_sources([
        {"root.erl", root("captured_math:value(Value)")},
        {"captured_math.erl", module(captured_math, ["value/1"], [function(value, "Value + 1")])}
    ], fun(Directory) ->
        {ok, Forms} = hls_source:parse_file(filename:join(Directory, "root.erl"), []),
        Once = xls_hardware_source:select(Forms, [{root, 1}]),
        ok = file:write_file(filename:join(Directory, "captured_math.erl"),
            module(captured_math, ["value/1"], [function(value, "Value + 2")])),
        ?assertEqual(Once, xls_hardware_source:select(Once, [{root, 1}])),
        ok
    end).

%% Saved plans bind the actual imported source; a fresh compilation sees a helper edit.
-spec saved_plan_rejects_changed_helper_test() -> ok.
saved_plan_rejects_changed_helper_test() ->
    with_sources([
        {"root.erl", actor()},
        {"plan_math.erl", module(plan_math, ["value/1"], [function(value, "Value + 1")])}
    ], fun(Directory) ->
        File = filename:join(Directory, "root.erl"),
        {_, Plan} = xls_statem_plan:from_file(File, []),
        ok = xls_statem_plan:validate(File, [], Plan),
        Before = xls_statem_plan:provenance(Plan),
        ok = file:write_file(filename:join(Directory, "plan_math.erl"),
            module(plan_math, ["value/1"], [function(value, "Value + 2")])),
        {_, Changed} = xls_statem_plan:from_file(File, []),
        After = xls_statem_plan:provenance(Changed),
        ?assertNotEqual(maps:get(source_sha256, Before), maps:get(source_sha256, After)),
        ?assertNotEqual(maps:get(artifact_sha256, Before), maps:get(artifact_sha256, After)),
        ?assertError(stale_statem_plan, xls_statem_plan:validate(File, [], Plan)),
        ok
    end).

%% Imported failure references keep their include origin through function namespacing.
-spec imported_body_failure_keeps_source_location_test() -> ok.
imported_body_failure_keeps_source_location_test() ->
    with_sources([
        {"root.erl", actor()},
        {"plan_math.erl", module(plan_math, ["value/1"], [
            "-include(\"math_impl.hrl\").\n"])},
        {"math_impl.hrl", function(value, "case Value of 0 -> 0 end")}
    ], fun(Directory) ->
        Emitted = xls_parse:to_artifact(filename:join(Directory, "root.erl")),
        Sites = xls_emitted:sites(Emitted),
        ?assertMatch([_ | _], [Site || Site = #{kind := case_clause,
            file := <<"math_impl.hrl">>, line := 2} <- Sites]),
        ok
    end).

%% Build-local paths must not distinguish the same captured source tree after relocation.
-spec relocated_source_tree_preserves_plan_identity_test() -> ok.
relocated_source_tree_preserves_plan_identity_test() ->
    Math = module(plan_math, ["value/1"], [function(value, "Value + 1")]),
    with_sources([
        {"first/root.erl", actor()}, {"first/plan_math.erl", Math},
        {"second/root.erl", actor()}, {"second/plan_math.erl", Math}
    ], fun(Directory) ->
        {_, First} = xls_statem_plan:from_file(filename:join([Directory, "first", "root.erl"]), []),
        {_, Second} = xls_statem_plan:from_file(filename:join([Directory, "second", "root.erl"]), []),
        ?assertEqual(xls_statem_plan:identity(First), xls_statem_plan:identity(Second)),
        ok
    end).

%% Keep the test directories independent while removing only files created by this fixture.
-spec with_sources([{file:filename(), iodata()}], fun((file:filename()) -> ok)) -> ok.
with_sources(Sources, Run) ->
    Directory = filename:absname(filename:join("_build", "source-helper-tests-" ++
        integer_to_list(erlang:unique_integer([positive])))),
    lists:foreach(fun({Relative, Body}) ->
        Filename = filename:join(Directory, Relative),
        ok = filelib:ensure_dir(Filename),
        ok = file:write_file(Filename, Body)
    end, Sources),
    try Run(Directory)
    after file:del_dir_r(Directory)
    end.

%% A non-callback root isolates helper discovery from protocol structure.
-spec root(iodata()) -> iodata().
root(Expression) -> [
    "-module(source_helpers_root).\n-hls_data(cell).\n-hls_tags([report]).\n",
    "-record(cell, {value = hls_type:zero() :: hls_nums:u32()}).\n",
    "-record(report, {value = hls_type:zero() :: hls_nums:u32()}).\n",
    "root(Value) -> ", Expression, ".\n"
].

%% Source modules need only ordinary exports and concrete value specifications.
-spec module(atom(), [string()], [iodata()]) -> iodata().
module(Name, Exports, Body) -> [
    "-module(", atom_to_list(Name), ").\n-export([", lists:join(", ", Exports), "]).\n", Body
].

%% Common arithmetic keeps this suite concerned with source ownership, not numeric lowering.
-spec function(atom(), iodata()) -> iodata().
function(Name, Expression) -> [
    "-spec ", atom_to_list(Name), "(hls_nums:u32()) -> hls_nums:u32().\n",
    atom_to_list(Name), "(Value) -> ", Expression, ".\n"
].

%% A small complete actor permits saved-plan identity checks without a workload fixture.
-spec actor() -> iodata().
actor() -> [
    "-module(source_helpers_actor).\n-behavior(hls_statem).\n",
    "-hls_data(cell).\n-hls_tags([request, report]).\n-hls_phases([waiting]).\n-hls_outputs([out]).\n",
    "-hls_mailbox_capacity(2).\n",
    "-record(cell, {value = hls_type:zero() :: hls_nums:u32()}).\n",
    "-record(request, {value = hls_type:zero() :: hls_nums:u32()}).\n",
    "-record(report, {value = hls_type:zero() :: hls_nums:u32()}).\n",
    "init([]) -> {ok, waiting, #cell{}}.\n",
    "waiting(enter, _, Cell) -> {Cell, [{cast, out, #report{value = Cell#cell.value}}]};\n",
    "waiting(cast, #request{value = Value}, Cell) ->\n",
    "  {repeat_phase, Cell#cell{value = plan_math:value(Value)}, consume}.\n"
].

%% Use the same public preparation entry as ordinary compiler helper tests.
-spec prepare(file:filename(), [hls_source:option()]) -> {[hls_source:form()], [map()]}.
prepare(Directory, Options) ->
    {ok, Forms} = hls_source:parse_file(filename:join(Directory, "root.erl"), Options),
    xls_helpers:prepare(Forms, [{root, 1}]).

%% Dependency ordering is not part of this assertion; module membership is.
-spec dependency_modules([hls_source:form()]) -> [atom()].
dependency_modules(Forms) ->
    lists:sort([Module || #{module := Module} <- xls_source_helpers:dependencies(Forms)]).

%% Inspect preserved provider syntax without interpreting or loading its module.
-spec remote_calls(atom(), term()) -> [term()].
remote_calls(Module, Call = {call, _, {remote, _, {atom, _, Module}, _}, Args}) ->
    [Call | remote_calls(Module, Args)];
remote_calls(Module, Map) when is_map(Map) -> remote_calls(Module, maps:values(Map));
remote_calls(Module, Tuple) when is_tuple(Tuple) -> remote_calls(Module, tuple_to_list(Tuple));
remote_calls(Module, List) when is_list(List) -> lists:append([remote_calls(Module, X) || X <- List]);
remote_calls(_, _) -> [].

%% Search only syntax atoms, avoiding incidental text in source metadata.
-spec contains_atom(atom(), term()) -> boolean().
contains_atom(Name, {atom, _, Name}) -> true;
contains_atom(Name, Map) when is_map(Map) -> contains_atom(Name, maps:values(Map));
contains_atom(Name, Tuple) when is_tuple(Tuple) -> contains_atom(Name, tuple_to_list(Tuple));
contains_atom(Name, List) when is_list(List) -> lists:any(fun(X) -> contains_atom(Name, X) end, List);
contains_atom(_, _) -> false.
