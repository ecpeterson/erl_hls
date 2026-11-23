-module(xls_hardware_source_closure_tests).
-moduledoc false.
-include_lib("eunit/include/eunit.hrl").
-export([identity/1, transpile/3, dslx_imports/1]).
-export_type([host_value/0]).

%% The actor emitters have distinct callback-root sets.
-type mode() :: statem | immediate | deferred.

-doc "A host-only type whose provider callback must not be reached by hardware discovery.".
-type host_value() :: integer().

-doc "Returns its argument unchanged for the closure fixture's provider call.".
-spec identity(hls_nums:u32()) -> hls_nums:u32().
identity(Value) -> Value.

-doc "Preserves the argument expression while exercising provider discovery.".
-spec transpile(identity, [xls_clause_lower:ir()], xls_clause_lower:clause_state()) ->
    xls_clause_lower:ir().
transpile(identity, [Value], _State) -> Value.

-doc "Records the names discovered by hardware compilation and declares a companion import.".
-spec dslx_imports([atom()]) -> [atom()].
dslx_imports(Names) ->
    self() ! {closure_provider_imports, Names},
    [hls_fixed].

%% Source-valid host utilities must neither alter emitted hardware nor invoke providers.
-spec unused_host_code_test_() -> [{string(), fun(() -> ok)}].
unused_host_code_test_() ->
    [{atom_to_list(Mode) ++ " ignores " ++ atom_to_list(Flag), fun() ->
        Baseline = generated(Mode, []),
        ?assertEqual([], provider_calls()),
        ?assertEqual(Baseline, generated(Mode, [Flag])),
        ?assertEqual([], provider_calls()),
        ok
    end} || Mode <- modes(), Flag <- host_flags()].

%% The same functions remain subject to hardware restrictions once called by a root.
-spec reachable_unsupported_code_test_() -> [{string(), fun(() -> ok)}].
reachable_unsupported_code_test_() ->
    [{atom_to_list(Mode) ++ " rejects reachable host operations", fun() ->
        ?assertException(error, {unsupported_xls_comparison, _, '<', integer, other},
            generated(Mode, ['HOST_COMPARISON', 'REACH_COMPARISON'])),
        ?assertException(error, {unsupported_xls_bit_syntax, _, native_endian},
            generated(Mode, ['HOST_BINARY', 'REACH_BINARY'])),
        ?assertException(error, {recursive_xls_helpers, _},
            generated(Mode, ['HOST_RECURSION', 'REACH_RECURSION'])),
        ok
    end} || Mode <- modes()].

%% A reachable provider is still discovered, including its declared companion.
-spec reachable_provider_test_() -> [{string(), fun(() -> ok)}].
reachable_provider_test_() ->
    [{atom_to_list(Mode) ++ " retains reachable provider imports", fun() ->
        ?assertEqual([], provider_calls()),
        Generated = generated(Mode, ['HOST_PROVIDER', 'REACH_PROVIDER']),
        ?assertEqual(1, length(binary:matches(Generated, <<"import hls_fixed;">>))),
        Calls = provider_calls(),
        ?assert(lists:member([identity], Calls)),
        ?assertEqual([], lists:usort(lists:append(Calls)) -- [identity]),
        ok
    end} || Mode <- modes()].

%% Include expansion retains nested helper types and both spellings of a local BIF name.
-spec included_hardware_dependencies_test_() -> [{string(), fun(() -> ok)}].
included_hardware_dependencies_test_() ->
    [{atom_to_list(Mode) ++ " retains included helpers and nested records", fun() ->
        Generated = generated(Mode, []),
        {Inner, _} = binary:match(Generated, <<"pub struct Closureinner">>),
        {Sample, _} = binary:match(Generated, <<"pub struct Closuresample">>),
        ?assert(Inner < Sample),
        ?assertNotEqual(nomatch, binary:match(Generated, <<"fn hls_local_bit_size__1">>)),
        ?assertNotEqual(nomatch, binary:match(Generated, <<"fn hls_local_sample_value__1">>)),
        case Mode of
            deferred -> ?assertNotEqual(nomatch,
                binary:match(Generated, <<"fn hls_local_continuation_value__1">>));
            _ -> ok
        end,
        ok
    end} || Mode <- modes()].

%% Interface and value analysis use hardware roots while certificates bind full source.
-spec interface_facts_and_provenance_test() -> ok.
interface_facts_and_provenance_test() ->
    File = "test_data/hls_closure_statem_fixture.erl",
    Options = [{d, Flag} || Flag <- host_flags()],
    ?assertEqual(xls_parse:actor_interface(File, []),
        xls_parse:actor_interface(File, Options)),
    {_, BeforeFacts} = xls_phase_values:from_file(File, []),
    {_, AfterFacts} = xls_phase_values:from_file(File, Options),
    Before = xls_phase_values:manifest(BeforeFacts),
    After = xls_phase_values:manifest(AfterFacts),
    ?assertEqual(maps:remove(source_sha256, Before), maps:remove(source_sha256, After)),
    ?assertNotEqual(maps:get(source_sha256, Before), maps:get(source_sha256, After)),
    {_, BeforePlan} = xls_statem_plan:from_file(File, []),
    {_, AfterPlan} = xls_statem_plan:from_file(File, Options),
    BeforeProvenance = xls_statem_plan:provenance(BeforePlan),
    AfterProvenance = xls_statem_plan:provenance(AfterPlan),
    ?assertNotEqual(maps:get(source_sha256, BeforeProvenance),
        maps:get(source_sha256, AfterProvenance)),
    ?assertEqual(maps:get(artifact_sha256, BeforeProvenance),
        maps:get(artifact_sha256, AfterProvenance)),
    ?assertEqual(xls_statem_plan:callbacks(BeforePlan), xls_statem_plan:callbacks(AfterPlan)),
    ?assertEqual([], provider_calls()),
    ok.

%% An unused record default is ordinary source data, not an accumulator root.
-spec host_record_default_does_not_seed_accumulator_test() -> ok.
host_record_default_does_not_seed_accumulator_test() ->
    Forms = [form(Source) || Source <- [
        "-module(closure_selection_fixture).", "-hls_data(state).", "-hls_tags([request]).",
        "-record(state, {value = hls_type:zero() :: hls_nums:u32()}).",
        "-record(request, {value = hls_type:zero() :: hls_nums:u32()}).",
        "-record(host_accumulator, {value = 0 :: integer()}).",
        "-record(host_wrapper, {value = {open_reduction, host_sum, 1, [], "
            "{commutative_monoid, #host_accumulator{}}} :: term()}).",
        "root() -> 0."
    ]],
    Selected = xls_hardware_source:select(Forms, [{root, 0}]),
    ?assertEqual([state, request], [Name || {attribute, _, record, {Name, _}} <- Selected]),
    ok.

%% Raw alias selection preserves transitive records without expanding unsupported types.
-spec selector_retains_nested_local_aliases_test() -> ok.
selector_retains_nested_local_aliases_test() ->
    Forms = [form(Source) || Source <- [
        "-module(closure_selection_fixture).", "-hls_data(state).", "-hls_tags([request]).",
        "-record(state, {value = hls_type:zero() :: hls_nums:u32()}).",
        "-record(request, {value = hls_type:zero() :: hls_nums:u32()}).",
        "-record(leaf, {value :: hls_nums:u32()}).",
        "-record(outer, {value :: leaf_alias()}).",
        "-type leaf_alias() :: #leaf{}.",
        "-opaque inner_alias(T) :: {T, leaf_alias()}.",
        "-type outer_alias() :: inner_alias(#outer{}).",
        "-type unused_alias() :: xls_hardware_source_closure_tests:host_value().",
        "-record(unused, {value :: unused_alias()}).",
        "-spec helper(outer_alias()) -> outer_alias().",
        "helper(Value) -> Value.", "root(Value) -> helper(Value)."
    ]],
    Selected = xls_hardware_source:select(Forms, [{root, 1}]),
    ?assertEqual([state, request, leaf, outer],
        [Name || {attribute, _, record, {Name, _}} <- Selected]),
    ?assertEqual([leaf_alias, inner_alias, outer_alias],
        [Name || {attribute, _, Kind, {Name, _, _}} <- Selected,
            Kind =:= type orelse Kind =:= opaque]),
    ?assertEqual([], provider_calls()),
    ok.

%% Discovery retains reachable provider syntax without executing provider callbacks.
-spec selector_is_syntactic_test() -> ok.
selector_is_syntactic_test() ->
    ?assertEqual([], provider_calls()),
    {ok, Forms} = hls_source:parse_file("test_data/hls_closure_statem_fixture.erl",
        [{d, 'HOST_PROVIDER'}, {d, 'REACH_PROVIDER'}]),
    Selected = xls_hardware_source:statem(Forms, [waiting]),
    ?assertMatch([_], hls_source:find_function(Selected, host_provider, 1)),
    ?assertEqual([], provider_calls()),
    ok.

%% Hardware selection is a view; hls_pack must retain the host's executable functions.
-spec parse_transform_keeps_host_function_test() -> ok.
parse_transform_keeps_host_function_test() ->
    File = "test_data/hls_closure_statem_fixture.erl",
    Module = hls_closure_statem_fixture,
    try
        {ok, Module, Binary} = compile:noenv_file(File,
            [binary, debug_info, report_errors, {parse_transform, hls_pack},
                {d, 'HOST_COMPARISON'}, {d, 'HOST_REDUCTION'}]),
        {module, Module} = code:load_binary(Module, File, Binary),
        ?assertEqual(true, Module:host_comparison()),
        ?assertEqual({open_reduction, host_sum, 1, [],
            {commutative_monoid, {host_accumulator, {host_leaf, self()}}}},
            Module:host_reduction()),
        ?assertEqual({ok, waiting, {state, 2}}, Module:init([])),
        ok
    after
        _ = code:purge(Module),
        _ = code:delete(Module),
        _ = code:purge(Module)
    end.

%% Selecting one server family cannot hide an invalid mixed callback declaration.
-spec mixed_call_arities_are_rejected_test() -> ok.
mixed_call_arities_are_rejected_test() ->
    ?assertError(invalid_hls_pending_calls, generated(deferred, ['MIXED_CALL_ARITY'])).

%% Independently exercise expression, graph, provider, type and accumulator leakage.
-spec host_flags() -> [atom()].
host_flags() -> ['HOST_COMPARISON', 'HOST_BINARY', 'HOST_RECURSION',
    'HOST_PROVIDER', 'HOST_TYPE', 'HOST_REDUCTION'].

%% A qualified self call cannot reinterpret a local helper as a type-provider hook.
-spec qualified_self_call_does_not_invoke_provider_test() -> ok.
qualified_self_call_does_not_invoke_provider_test() ->
    ?assertEqual([], provider_calls()),
    Forms = [form(Source) || Source <- [
        "-module(xls_hardware_source_closure_tests).",
        "root() -> xls_hardware_source_closure_tests:identity(0)."
    ]],
    ?assertEqual([], xls_dslx_imports:from_forms(Forms)),
    ?assertEqual([], provider_calls()),
    %% A self-qualified type still names an explicit provider representation.
    Type = form("-type kept() :: xls_hardware_source_closure_tests:host_value()."),
    ?assertEqual([hls_fixed], xls_dslx_imports:from_forms([Type | Forms])),
    ?assertEqual([[host_value]], provider_calls()),
    ok.

%% Keep the backend matrix explicit so new callback families cannot silently enter it.
-spec modes() -> [mode()].
modes() -> [statem, immediate, deferred].

%% Preprocessor flags select source additions without moving hardware source lines.
-spec generated(mode(), [atom()]) -> binary().
generated(Mode, Flags) ->
    File = "test_data/hls_closure_" ++ atom_to_list(Mode) ++ "_fixture.erl",
    iolist_to_binary(xls_parse:to_xls(File,
        #{source_options => [{d, Flag} || Flag <- Flags]})).

%% Drain only this fixture's observations, leaving unrelated test messages untouched.
-spec provider_calls() -> [[atom()]].
provider_calls() ->
    receive
        {closure_provider_imports, Names} -> [Names | provider_calls()]
    after 0 -> []
    end.

%% Build selector-only declarations without creating another on-disk fixture.
-spec form(string()) -> hls_source:form().
form(Source) ->
    {ok, Tokens, _} = erl_scan:string(Source),
    {ok, Form} = erl_parse:parse_form(Tokens),
    Form.
