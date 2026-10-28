-module(xls_dslx_imports_tests).

-include_lib("eunit/include/eunit.hrl").
-export([dslx_imports/0]).

%% A provider whose declarations can exercise malformed metadata as well as
%% multiple dependencies without creating an implementation for each import.
-doc "Returns deliberately supplied provider metadata for validation tests.".
-spec dslx_imports() -> term().
dslx_imports() -> get(test_dslx_imports).

%% Checks nested type provider.
-spec nested_type_provider_test() -> ok.
nested_type_provider_test() ->
    Forms = [form("-type fields() :: hls_lists:list(hls_companion_provider:scalar(), 2).")],
    ?assertEqual([hls_bits, hls_companion_provider], xls_dslx_imports:from_forms(Forms)).

%% Checks nested call provider.
-spec nested_call_provider_test() -> ok.
nested_call_provider_test() ->
    Forms = [form("probe() -> hls_type:zero(hls_lists:list(hls_companion_provider:scalar(), 2)).")],
    ?assertEqual([hls_bits, hls_companion_provider], xls_dslx_imports:from_forms(Forms)).

%% Checks composed providers.
-spec composed_providers_test() -> ok.
composed_providers_test() ->
    Forms = [form("-type fields() :: hls_vec:vector(hls_fixed:signed(16, 8), 3).")],
    ?assertEqual([hls_bits, hls_fixed], xls_dslx_imports:from_forms(Forms)).

%% Checks collection operations import checks.
-spec collection_operations_import_checks_test() -> ok.
collection_operations_import_checks_test() ->
    Forms = [form("probe(I, Values) -> hls_vec:nth(I, Values)."),
        form("update(I, Values, V) -> hls_lists:set(I, Values, V).")],
    ?assertEqual([hls_bits, hls_lists], xls_dslx_imports:from_forms(Forms)),
    ?assertEqual([hls_bits, hls_lists, hls_vec], xls_dslx_imports:from_forms(Forms ++
        [form("dot(T, A, B) -> hls_vec:dot(T, A, B).")])).

%% Checks bound tail import.
-spec bound_tail_import_test() -> ok.
bound_tail_import_test() ->
    ?assertEqual([hls_patterns], xls_dslx_imports:from_forms([
        form("probe([_ | Tail]) -> Tail.")])),
    ?assertEqual([hls_patterns], xls_dslx_imports:from_forms([
        form("probe(V) -> [_ | Tail = [X, Y]] = V, Tail.")])),
    ?assertEqual([], xls_dslx_imports:from_forms([
        form("probe([X, Y | _]) -> X + Y.")])).

%% Checks providers without companions.
-spec providers_without_companions_test() -> ok.
providers_without_companions_test() ->
    Forms = [form("probe() -> hls_type:zero(hls_nums:u32()).")],
    ?assertEqual([], xls_dslx_imports:from_forms(Forms)).

%% Checks integer operator companion.
-spec integer_operator_companion_test() -> ok.
integer_operator_companion_test() ->
    Forms = [form("probe(X, Y) -> hls_nums:wrap(hls_nums:s8(), X rem Y).")],
    ?assertEqual([hls_integer], xls_dslx_imports:from_forms(Forms ++ Forms)),
    ?assertEqual([], xls_dslx_imports:from_forms([form("probe(X, Y) -> X div Y.")])).

%% Checks shift operator companion.
-spec shift_operator_companion_test() -> ok.
shift_operator_companion_test() ->
    ?assertEqual([hls_integer], xls_dslx_imports:from_forms([
        form("probe(X, Y) -> X bsl Y."), form("probe(X, Y) -> X bsr Y.")])),
    ?assertEqual([hls_integer], xls_dslx_imports:from_forms([
        form("probe(X) -> X bsl 1."), form("probe(X) -> X bsr -2.")])).

%% Checks float imports follow actual uses.
-spec float_imports_follow_actual_uses_test() -> ok.
float_imports_follow_actual_uses_test() ->
    Forms = [form("-type values() :: hls_vec:vector(hls_nums:float32(), 2)."),
        form("probe() -> hls_nums:u32().")],
    ?assertEqual([apfloat, hls_bits], xls_dslx_imports:from_forms(Forms)),
    ?assertEqual([apfloat, hls_float], xls_dslx_imports:from_forms([
        form("probe() -> hls_float:literal(hls_nums:float64(), 0.1).")])).

%% Checks deterministic unique imports.
-spec deterministic_unique_imports_test() -> ok.
deterministic_unique_imports_test() ->
    with_imports([zeta, axis, 'math.fixed', alpha, alpha], fun() ->
        Forms = [form("probe() -> xls_dslx_imports_tests:probe(hls_companion_provider:scalar()).")],
        Imports = xls_dslx_imports:from_forms(Forms ++ Forms),
        ?assertEqual([alpha, axis, hls_companion_provider, 'math.fixed', zeta], Imports),
        ?assertEqual(
            <<"import axis;\nimport alpha;\nimport hls_companion_provider;\n"
              "import math.fixed;\nimport zeta;\n">>,
            iolist_to_binary(xls_dslx_imports:emit([axis], Imports)))
    end).

%% Checks malformed declaration.
-spec malformed_declaration_test() -> ok.
malformed_declaration_test() ->
    Forms = [form("probe() -> xls_dslx_imports_tests:probe().")],
    with_imports(not_a_list, fun() ->
        ?assertError({invalid_dslx_imports, ?MODULE, not_a_list},
            xls_dslx_imports:from_forms(Forms))
    end),
    lists:foreach(fun(Import) ->
        with_imports([Import], fun() ->
            ?assertError({invalid_dslx_import, ?MODULE, Import},
                xls_dslx_imports:from_forms(Forms))
        end)
    end, ["string", 'bad-name', 'bad..path', 'bad;\nimport injected']).

%% Provider types from included records retain their imports and qualified calls in server output.
-spec included_types_reach_gs_emission_test() -> ok.
included_types_reach_gs_emission_test() ->
    Source = "test_data/hls_companion_gs_fixture.erl",
    {ok, Forms} = hls_source:parse_file(Source),
    ?assertEqual([hls_bits, hls_companion_provider, hls_fixed, hls_vec], xls_dslx_imports:from_forms(Forms)),
    Generated = iolist_to_binary(xls_parse:to_xls(Source)),
    ?assertEqual(1, length(binary:matches(Generated, <<"import hls_companion_provider;">>))),
    ?assertNotEqual(nomatch, binary:match(Generated, <<"hls_companion_provider::Scalar[2]">>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<"hls_companion_provider::combine(">>)).

%% Parses one fixture form without expanding it.
-spec form(string()) -> erl_parse:abstract_form().
form(Source) ->
    {ok, Tokens, _} = erl_scan:string(Source),
    {ok, Form} = erl_parse:parse_form(Tokens),
    Form.

%% Scopes the test provider metadata to one assertion.
-spec with_imports(term(), fun(() -> T)) -> T.
with_imports(Imports, Fun) ->
    put(test_dslx_imports, Imports),
    try Fun() after erase(test_dslx_imports) end.

%% Independent collection emitters may require the same runtime companion module.
-spec repeated_runtime_import_test() -> ok.
repeated_runtime_import_test() ->
    ?assertEqual(<<"import axis;\nimport hls_integer;\n">>,
        iolist_to_binary(xls_dslx_imports:emit([axis, hls_integer, hls_integer], [hls_integer]))),
    ?assertError({xls_import_alias_collision, "hls_integer", hls_integer, 'other.hls_integer'},
        xls_dslx_imports:emit([hls_integer, 'other.hls_integer'], [])).
