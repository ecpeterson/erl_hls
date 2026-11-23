-module(xls_admission_collection_tests).
-moduledoc "Checks collector placement contracts and emits the generated semantic regression fixture.".
-include_lib("eunit/include/eunit.hrl").

%% Opting out retains the ordinary artifact, while unsupported service combinations fail early.
-spec option_contract_test() -> ok.
option_contract_test() ->
    Path = "test/hls_projection_reduction_fixture.erl",
    ?assertEqual(xls_scheduler_actor:to_xls(Path),
        xls_scheduler_actor:to_xls(Path, #{admission_reductions => false})),
    ?assertError({admission_reductions, invalid},
        xls_scheduler_actor:to_xls(Path, #{admission_reductions => invalid})),
    ?assertError(admission_reductions_require_ordinary_reduced_actor,
        xls_scheduler_actor:to_xls(Path, #{shared_service => aggregate_only, admission_reductions => true})),
    ?assertError(admission_reductions_require_ordinary_reduced_actor,
        xls_scheduler_actor:to_xls("test/hls_actor_debug_fixture.erl", #{admission_reductions => true})).

%% A generated module cannot simultaneously serve incompatible ownership policies.
-spec placement_agreement_test() -> ok.
placement_agreement_test() ->
    Ordinary = #{module => fixture}, Selected = Ordinary#{admission_reductions => true},
    Requirements = #{fixture => #{shared_service => ordinary}},
    ?assertMatch(#{fixture := #{admission_reductions := true}},
        xls_collection_codegen:requirements([Selected], [], Requirements)),
    ?assertEqual(Requirements, xls_collection_codegen:requirements([Ordinary], [], Requirements)),
    ?assertError({admission_reductions_module_policy, fixture},
        xls_collection_codegen:requirements([Selected, Ordinary], [], Requirements)),
    ?assertError({admission_reductions_direct_instance, fixture},
        xls_collection_codegen:requirements([Selected], [Ordinary], Requirements)).

%% Append behavioral tests to the actual generated actor, not a replica of its reducer.
-spec generated_semantics_test() -> ok.
generated_semantics_test() ->
    Body = xls_scheduler_actor:to_xls("test/hls_projection_reduction_fixture.erl", #{admission_reductions => true}),
    {ok, Tests} = file:read_file("test/xls/admission_collection.x.in"),
    Path = "_build/admission-collection/unit/collection.x",
    ok = filelib:ensure_dir(Path),
    ok = file:write_file(Path, [Body, "\n", Tests]).

%% Exclusive mode changes ordering by assertion and must not depend on callback data.
-spec exclusive_generated_semantics_test() -> ok.
exclusive_generated_semantics_test() ->
    Body = xls_scheduler_actor:to_xls("test/hls_projection_reduction_fixture.erl", #{admission_reductions => exclusive_epoch}),
    {ok, Tests} = file:read_file("test/xls/exclusive_collection.x.in"),
    Path = "_build/exclusive-collection/unit/collection.x",
    ok = filelib:ensure_dir(Path),
    ok = file:write_file(Path, [Body, "\n", Tests]).

%% Direct collectors reject runtimes whose event/reply ownership is not integrated.
-spec direct_option_contract_test() -> ok.
direct_option_contract_test() ->
    Path = "test/hls_projection_reduction_fixture.erl",
    ?assertEqual(xls_scheduler_actor:to_xls(Path),
        xls_scheduler_actor:to_xls(Path, #{direct_collection => false})),
    ?assertError({direct_collection, invalid},
        xls_scheduler_actor:to_xls(Path, #{direct_collection => invalid})),
    lists:foreach(fun(Options) ->
        ?assertError(direct_collection_incompatible_shared_service,
            xls_scheduler_actor:to_xls(Path, Options#{direct_collection => exclusive_epoch}))
    end, [#{shared_service => aggregate_only}, #{admission_reductions => exclusive_epoch}]),
    ?assertError(direct_collection_requires_reduced_statem,
        xls_scheduler_actor:to_xls("test/hls_actor_debug_fixture.erl", #{direct_collection => exclusive_epoch})).

%% Exercise the ordinary generated callbacks through the direct collection boundary.
-spec direct_generated_semantics_test() -> ok.
direct_generated_semantics_test() ->
    Body = xls_scheduler_actor:to_xls("test/hls_projection_reduction_fixture.erl",
        #{direct_collection => exclusive_epoch}),
    {ok, Tests} = file:read_file("test/xls/direct_collection.x.in"),
    Path = "_build/direct-collection/unit/collection.x",
    ok = filelib:ensure_dir(Path),
    ok = file:write_file(Path, [Body, "\n", Tests]).

%% The placement policy and live early-progress interpretation travel together.
-spec direct_topology_and_debug_test() -> ok.
direct_topology_and_debug_test() ->
    Module = hls_projection_reduction_fixture,
    Plan = hls_topology:normalize(#{version => 1, actors => #{sink => Module}, families => #{},
        ingresses => [{commands, {rectangle, [1, 1]}, [
            {all, [begin_set, piece], [{actor, sink, {at, [0, 0]}}]}]}],
        route_relations => [], startup => [], externals => [{results, out, [result]}],
        routes => [{{sink, out}, [{external, results}]}, {{sink, marker}, [{external, results}]}]}),
    Profile = #{name => collector_test, channel_depth => 1, actor_egress_depth => burst,
        direct_actor_debug => true, direct_collections => #{Module => exclusive_epoch}},
    Requirements = xls_fabric_topology_dslx:artifact_requirements(Plan, Profile),
    Options = maps:get(Module, Requirements),
    ?assertMatch(#{direct_collection := exclusive_epoch, direct_actor_debug := true}, Options),
    Artifact = xls_scheduler_actor:to_artifact("test/hls_projection_reduction_fixture.erl", Options),
    Topology = iolist_to_binary(xls_fabric_topology_dslx:emit(Plan, Profile)),
    ?assertNotEqual(nomatch, binary:match(Topology, <<"::CollectionService<u32:1, u32:0>">>)),
    Projection = #{<<"direct">> := [Bank]} = xls_scheduler_debug:projection(
        Plan, #{}, #{Module => Artifact}, Profile),
    ?assertEqual(ok, xls_scheduler_debug:validate(Plan, #{}, Projection)),
    R = #{<<"fields">> := Fields, <<"width">> := Width} = maps:get(<<"reduction">>, Bank),
    ?assertMatch(#{<<"early_collection">> := true}, R),
    Value = maps:fold(fun(Name, V, Acc) ->
        #{<<"observation_offset">> := Offset} = maps:get(Name, Fields), Acc bor (V bsl Offset)
    end, 1 bsl 25, #{<<"status">> => 1, <<"key">> => 7, <<"seen">> => 1}),
    Resource = #{<<"id">> => 0, <<"kind">> => <<"actor">>, <<"width">> => 56+Width,
        <<"reduction">> => R, <<"failures">> => maps:get(<<"failures">>, Bank),
        <<"phases">> => maps:get(<<"phases">>, Bank)},
    ?assertMatch({ok, #{reduction := #{status := early, key := 7, remaining := undefined}}},
        hls_shared_observation:decode_observation(<<0:32/little, 1:64/little, Value:128/little>>, Resource)),
    ?assertError(actor_projection_mismatch, xls_scheduler_debug:validate(Plan, #{},
        Projection#{<<"direct">> := [Bank#{<<"reduction">> := maps:remove(<<"early_collection">>, R)}]})),
    ?assertError({reserved_collection_startup, sink}, xls_fabric_topology_dslx:emit(
        Plan#{startup := [#{target => sink, messages => [{piece, 7, 0, 1}]}]}, Profile)),
    ?assertError({direct_collection_placement, absent, exclusive_epoch},
        xls_fabric_topology_dslx:emit(Plan, Profile#{direct_collections := #{absent => exclusive_epoch}})).
