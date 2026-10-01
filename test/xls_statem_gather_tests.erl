-module(xls_statem_gather_tests).
-moduledoc "Compiler boundaries for typed indexed gathers and scalar collections.".
-include_lib("eunit/include/eunit.hrl").
-define(FIXTURE, "test_data/xls_statem_gather_fixture.erl").

%% Ordered payload storage is independent of callback data and the scalar accumulator.
-spec distinct_collection_types_test() -> ok.
distinct_collection_types_test() ->
    Spec = xls_parse:actor_artifact(?FIXTURE, []),
    Gather = maps:get(gathers, Spec),
    [Site] = maps:get(sites, Gather),
    ?assertMatch(#{element := #{name := element}, padding := #{body := _, result := _},
        population := #{size := 4}, completion := #{}}, Site),
    ?assertMatch(#{accumulator := #{name := parity}}, maps:get(reductions, Spec)),
    ?assertEqual(74, xls_statem_gather_codegen:progress_width(Gather)),
    ?assertEqual(32, xls_statem_gather_codegen:payload_width(Gather)),
    ?assertEqual(106, xls_statem_gather_codegen:storage_width(Gather)),
    ?assertEqual(72, maps:get(data_width, Spec)),
    ?assertMatch([#{independent_lift := #{}, source_transportable := false}], maps:get(contributions, Site)).

%% Structural compilation and closed lowering describe the same storage contract.
-spec structural_interface_test() -> ok.
structural_interface_test() ->
    Spec = xls_parse:actor_artifact(?FIXTURE, []),
    Interface = xls_parse:actor_interface(?FIXTURE),
    ?assertEqual(xls_statem_gather_lower:interface(maps:get(gathers, Spec)), maps:get(gathers, Interface)),
    ?assertEqual(106, hls_actor_interface:gather_storage_width(Interface)),
    ?assert(lists:member(piece, hls_actor_interface:dispatched_schemas(Interface))),
    ?assertEqual(0, hls_actor_interface:gather_storage_width(#{})).

%% Default constructors and explicit constant padding both lower as typed values.
-spec padding_expression_test() -> ok.
padding_expression_test() ->
    with_change(<<"#element{}}]}">>, <<"#element{value = 9}}]}">>, fun(Path) ->
        Text = iolist_to_binary(xls_parse:to_xls(Path)),
        ?assertNotEqual(nomatch, binary:match(Text, <<"value: u8:9">>))
    end).

%% Contributions may inspect actor data for applicability but cannot capture it as a value.
-spec contribution_value_provenance_test() -> ok.
contribution_value_provenance_test() ->
    with_change(<<"{gather, items, Key, Member, #element{value = Value}}">>,
        <<"{gather, items, Key, Member, #element{value = Cell#cell.mask}}">>, fun(Path) ->
            ?assertError({invalid_hls_statem_reduction_origin, data, [message]}, xls_parse:actor_artifact(Path, []))
        end).

%% Indexed collection callbacks cannot silently update ordinary actor state.
-spec contribution_mutation_test() -> ok.
contribution_mutation_test() ->
    with_change(<<"{collecting, Cell, {gather,">>, <<"{collecting, Cell#cell{value = 1}, {gather,">>, fun(Path) ->
        ?assertException(error, {unsupported_hls_statem_gather, _, _, _}, xls_parse:actor_artifact(Path, []))
    end).

%% A nonconstant element would otherwise require duplicating actor context in physical storage.
-spec nonconstant_padding_test() -> ok.
nonconstant_padding_test() ->
    with_change(<<"#element{}}]}">>, <<"#element{value = Cell#cell.mask}}]}">>, fun(Path) ->
        ?assertException(error, {nonconstant_hls_statem_reduction_identity, _, _}, xls_parse:actor_artifact(Path, []))
    end).

%% Each site supplies its own element layout, including gather-only actors without a reducer.
-spec differing_site_types_test() -> ok.
differing_site_types_test() ->
    Spec = xls_parse:actor_artifact("test_data/xls_statem_gather_sites_fixture.erl", []),
    ?assertEqual(none, maps:get(reductions, Spec)),
    Gather = maps:get(gathers, Spec),
    ?assertEqual([small, large], [maps:get(name, maps:get(element, S)) || S <- maps:get(sites, Gather)]),
    ?assertEqual(48, xls_statem_gather_codegen:payload_width(Gather)),
    ?assertEqual(120, xls_statem_gather_codegen:storage_width(Gather)).

%% Source variations remain isolated from the reviewed generic fixture.
-spec with_change(binary(), binary(), fun((file:filename()) -> term())) -> term().
with_change(From, To, Check) ->
    Path = filename:join("_build/gather-source-check", integer_to_list(erlang:unique_integer([positive])) ++ ".erl"),
    ok = filelib:ensure_dir(Path),
    {ok, Source} = file:read_file(?FIXTURE),
    ?assertNotEqual(nomatch, binary:match(Source, From)),
    ok = file:write_file(Path, binary:replace(Source, From, To)),
    try Check(Path) after file:delete(Path) end.
