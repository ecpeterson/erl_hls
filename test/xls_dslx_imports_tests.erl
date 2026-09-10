-module(xls_dslx_imports_tests).

-include_lib("eunit/include/eunit.hrl").
-export([dslx_imports/0]).

%% A provider whose declarations can exercise malformed metadata as well as
%% multiple dependencies without creating an implementation for each import.
dslx_imports() -> get(test_dslx_imports).

nested_type_provider_test() ->
    Forms = [form("-type fields() :: hls_lists:list(phi_field:scalar(), 2).")],
    ?assertEqual([phi_field], xls_dslx_imports:from_forms(Forms)).

nested_call_provider_test() ->
    Forms = [form("probe() -> hls_type:zero(hls_lists:list(phi_field:scalar(), 2)).")],
    ?assertEqual([phi_field], xls_dslx_imports:from_forms(Forms)).

composed_providers_test() ->
    Forms = [form("-type fields() :: hls_vec:vector(hls_fixed:signed(16, 8), 3).")],
    ?assertEqual([hls_fixed, hls_vec], xls_dslx_imports:from_forms(Forms)).

providers_without_companions_test() ->
    Forms = [form("probe() -> hls_type:zero(hls_nums:u32()).")],
    ?assertEqual([], xls_dslx_imports:from_forms(Forms)).

deterministic_unique_imports_test() ->
    with_imports([zeta, axis, 'math.fixed', alpha, alpha], fun() ->
        Forms = [form("probe() -> xls_dslx_imports_tests:probe(phi_field:scalar()).")],
        Imports = xls_dslx_imports:from_forms(Forms ++ Forms),
        ?assertEqual([alpha, axis, 'math.fixed', phi_field, zeta], Imports),
        ?assertEqual(
            <<"import axis;\nimport alpha;\nimport math.fixed;\n"
              "import phi_field;\nimport zeta;\n">>,
            iolist_to_binary(xls_dslx_imports:emit([axis], Imports)))
    end).

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

included_types_reach_gs_emission_test() ->
    Source = "test_data/hls_companion_gs_fixture.erl",
    {ok, Forms} = xls_parse:parse_file(Source),
    ?assertEqual([hls_fixed, hls_vec, phi_field], xls_dslx_imports:from_forms(Forms)),
    Generated = iolist_to_binary(xls_parse:to_xls(Source)),
    ?assertEqual(1, length(binary:matches(Generated, <<"import phi_field;">>))),
    ?assertNotEqual(nomatch, binary:match(Generated, <<"phi_field::Scalar[2]">>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<"phi_field::relax_bulk(">>)).

both_statem_artifacts_import_companions_test() ->
    lists:foreach(fun(Mode) ->
        Generated = iolist_to_binary(xls_parse:to_xls(
            "src/examples/phi_decoder/phi_halo_cell.erl",
            #{shared_service => Mode})),
        ?assertEqual(1, length(binary:matches(Generated, <<"import phi_field;">>))),
        ?assertNotEqual(nomatch, binary:match(Generated, <<"phi_field::relax(">>))
    end, [ordinary, aggregate_only]).

form(Source) ->
    {ok, Tokens, _} = erl_scan:string(Source),
    {ok, Form} = erl_parse:parse_form(Tokens),
    Form.

with_imports(Imports, Fun) ->
    put(test_dslx_imports, Imports),
    try Fun() after erase(test_dslx_imports) end.
