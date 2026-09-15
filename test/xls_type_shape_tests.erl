-module(xls_type_shape_tests).
-include_lib("eunit/include/eunit.hrl").
-import(xls_type_shape_fixture, [with_source/1, load/2]).

source_clean_and_incremental_interfaces_agree_test() ->
    with_source(fun(Actor, Provider, _Header) ->
        %% Source-only inference cannot load or call the provider, including
        %% its width/zero/print_type callbacks.
        ?assertEqual(false, code:is_loaded(hls_shape_type_fixture)),
        Source = xls_parse:actor_interface(Actor),
        ?assert(total(Source)),
        ?assertEqual(false, code:is_loaded(hls_shape_type_fixture)),
        ok = load(Actor, []),
        ?assertEqual(Source, hls_actor_interface:from_module(hls_shape_reduction_fixture)),
        %% A stale provider with a different live width does not change facts
        %% derived from its current source declarations.
        ok = load(Provider, [{d, 'SHAPE_COUNT', 3}]),
        ?assertEqual(96, hls_shape_type_fixture:width(vector, [])),
        ?assertEqual(Source, xls_parse:actor_interface(Actor)),
        ?assertEqual(Source, hls_actor_interface:from_module(hls_shape_reduction_fixture)),
        ok = load(Provider, []),
        ?assertEqual(Source, xls_parse:actor_interface(Actor)),
        ?assertEqual(Source, hls_actor_interface:from_module(hls_shape_reduction_fixture))
    end).

changed_alias_header_invalidates_routing_fact_test() ->
    with_source(fun(Actor, _Provider, Header) ->
        ok = load(Actor, []),
        ?assert(total(hls_actor_interface:from_module(hls_shape_reduction_fixture))),
        ok = file:write_file(Header, "-define(SHAPE_COUNT, 3).\n-define(WIRE_COUNT, 3).\n"),
        ?assertNot(total(xls_parse:actor_interface(Actor))),
        ?assertError({stale_hls_actor_interface, hls_shape_reduction_fixture, Actor},
            hls_actor_interface:from_module(hls_shape_reduction_fixture)),
        ok = load(Actor, []),
        ?assertNot(total(hls_actor_interface:from_module(hls_shape_reduction_fixture)))
    end).

preprocessing_context_is_shared_with_type_sources_test() ->
    with_source(fun(Actor, _Provider, _Header) ->
        lists:foreach(fun({Count, Total}) ->
            Options = [{d, 'SHAPE_COUNT', Count}],
            ok = load(Actor, Options),
            Source = xls_parse:actor_interface(Actor, Options),
            ?assertEqual(Total, total(Source)),
            ?assertEqual(Source, hls_actor_interface:from_module(hls_shape_reduction_fixture))
        end, [{2, true}, {3, false}])
    end).

deterministic_build_still_analyzes_with_its_macros_test() ->
    with_source(fun(Actor, _Provider, _Header) ->
        ok = load(Actor, [deterministic, {d, 'SHAPE_COUNT', 3}]),
        ?assertNot(total(hls_actor_interface:from_module(hls_shape_reduction_fixture)))
    end).

unavailable_and_recursive_aliases_remain_unknown_test() ->
    with_source(fun(Actor, Provider, _Header) ->
        lists:foreach(fun(Declaration) ->
            ok = file:write_file(Provider, ["-module(hls_shape_type_fixture).\n", Declaration]),
            ?assertNot(total(xls_parse:actor_interface(Actor)))
        end, [
            "-type vector() :: missing_type:vector().\n",
            "-type vector() :: grow(hls_nums:u32()).\n"
                "-type grow(T) :: grow(hls_vec:vector(T, 2)).\n",
            "-opaque vector() :: hls_vec:vector(hls_nums:u32(), 2).\n",
            "-type vector() :: [hls_nums:u32()].\n"
        ]),
        ok = file:delete(Provider),
        ?assertNot(total(xls_parse:actor_interface(Actor)))
    end).

shared_type_sources_use_explicit_search_paths_test() ->
    with_source(fun(Actor, Provider, Header) ->
        Types = filename:join(filename:dirname(Actor), "types"),
        ok = filelib:ensure_dir(filename:join(Types, "unused")),
        ok = file:rename(Provider, filename:join(Types, filename:basename(Provider))),
        ok = file:rename(Header, filename:join(Types, filename:basename(Header))),
        ?assertNot(total(xls_parse:actor_interface(Actor))),
        Options = [{i, Types}],
        ?assert(total(xls_parse:actor_interface(Actor, Options))),
        ok = load(Actor, Options),
        ?assert(total(hls_actor_interface:from_module(hls_shape_reduction_fixture)))
    end).

nested_parameterized_aliases_resolve_once_per_source_test() ->
    with_source(fun(Actor, Provider, _Header) ->
        ok = file:write_file(Provider,
            "-module(hls_shape_type_fixture).\n"
            "-type vector() :: row(row(hls_nums:u32(), 2), 3).\n"
            "-type row(E, N) :: hls_lists:list(E, N).\n"),
        {ok, Forms} = xls_parse:parse_file(Actor),
        Session = trace:session_create(type_shape_reads, self(), []),
        try
            1 = trace:function(Session, {hls_source, read, 2}, true, [call_count]),
            Shapes = xls_type_shape:records(Forms, [cell, value]),
            ?assertMatch(#{cell := {record, cell, #{values := {array, {array, unknown, 2}, 3}}},
                value := {record, value, #{values := {array, {array, unknown, 2}, 3}}}}, Shapes),
            ?assertEqual({call_count, 1}, trace:info(Session, {hls_source, read, 2}, call_count))
        after
            trace:session_destroy(Session)
        end
    end).

captured_alias_context_survives_a_changed_working_directory_test() ->
    with_source(fun(Actor, _Provider, _Header) ->
        {ok, Original} = file:get_cwd(),
        try
            ok = file:set_cwd(filename:dirname(Actor)),
            Relative = filename:basename(Actor),
            Options = [{d, 'SHAPE_COUNT', 3}],
            ok = load(Relative, Options),
            Source = xls_parse:actor_interface(Relative, Options),
            ok = file:set_cwd(Original),
            ?assertNot(total(Source)),
            ?assertEqual(Source, hls_actor_interface:from_module(hls_shape_reduction_fixture))
        after
            ok = file:set_cwd(Original)
        end
    end).

total(#{reductions := #{sites := [#{source_capture_total := Total}]}}) -> Total.
