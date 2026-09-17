-module(xls_actor_observation_tests).
-include_lib("eunit/include/eunit.hrl").
-export([write/1]).

diagnostic_outputs_are_explicit_test() ->
    Source = "test/hls_dense_statem_fixture.erl",
    Plain = iolist_to_binary(xls_parse:to_xls(Source)),
    ?assertEqual(Plain, iolist_to_binary(xls_parse:to_xls(Source, #{direct_actor_debug => false}))),
    ?assertEqual(nomatch, binary:match(Plain, <<"actor_debug_out">>)),
    lists:foreach(fun(Kind) ->
        Plan = plan(Kind),
        Profile = profile(Kind),
        Production = iolist_to_binary(xls_topology_dslx:emit(Plan, Profile)),
        ?assertEqual(Production, iolist_to_binary(xls_topology_dslx:emit(Plan,
            Profile#{direct_actor_debug => false}))),
        ?assertEqual(#{hls_dense_statem_fixture => #{shared_service => ordinary}},
            xls_topology_dslx:artifact_requirements(Plan, Profile)),
        ?assertEqual(#{hls_dense_statem_fixture =>
            #{shared_service => ordinary, direct_actor_debug => true}},
            xls_topology_dslx:artifact_requirements(Plan, Profile#{direct_actor_debug => true})),
        ?assertError({direct_actor_debug, yes},
            xls_topology_dslx:emit(Plan, Profile#{direct_actor_debug => yes}))
    end, [scalar, rectangle]),
    ?assertError({direct_actor_debug, yes}, xls_parse:to_xls(Source, #{direct_actor_debug => yes})),
    ?assertError(direct_actor_debug_requires_hls_statem,
        xls_parse:to_xls("src/examples/regsvc/regsvc.erl", #{direct_actor_debug => true})).

observation_boundary_name_collisions_test() ->
    lists:foreach(fun({Kind, Boundary, Port}) ->
        Plan = plan(Kind, Boundary),
        _ = xls_topology_dslx:emit(Plan, profile(Kind)),
        ?assertError({topology_channel_collision, Port},
            xls_topology_dslx:emit(Plan, (profile(Kind))#{direct_actor_debug => true}))
    end, [{scalar, actor_0_debug, <<"actor_0_debug_out">>},
        {rectangle, family_0_debug, <<"family_0_debug_out">>}]).

rectangular_binding_order_test() ->
    Bindings = xls_actor_observation:bindings(plan(rectangle), #{}),
    ?assertEqual([{{family, cell, [X, Y]}, iolist_to_binary(
        ["_family_0_debug_out__", integer_to_list(X), "_", integer_to_list(Y)])} ||
        X <- lists:seq(0, 1), Y <- lists:seq(0, 2)],
        [{Id, Port} || #{id := Id, port := Port, width := 49} <- Bindings]),
    Specs = #{cells => #{members => [{family, cell}],
        state_storage => block_ram, mailbox_storage => block_ram}},
    ?assertEqual([], xls_actor_observation:bindings(plan(rectangle), Specs)).

partially_scheduled_ingress_retains_direct_observation_test() ->
    {Plan, Specs} = hls_actor_debug_dslx:fixture(mailbox),
    Partial = maps:with([producer], Specs),
    Text = iolist_to_binary(xls_topology_dslx:emit(Plan, (profile(rectangle))#{
        scheduler_groups => Partial, direct_actor_debug => true})),
    ?assertNotEqual(nomatch, binary:match(Text, <<"spawn IngressRouter0">>)),
    ?assertNotEqual(nomatch, binary:match(Text, <<"family_0_debug_out">>)),
    ?assertEqual(nomatch, binary:match(Text, <<"family_1_debug_out">>)).

%% Native compiler smoke fixtures: a standalone actor, scalar topology, and
%% genuinely two-dimensional rectangular family exercise each output path.
write(Stage) ->
    Options = #{direct_actor_debug => true},
    write(Stage, "hls_dense_statem_fixture.x",
        xls_parse:to_xls("test/hls_dense_statem_fixture.erl", Options)),
    lists:foreach(fun(Kind) ->
        Plan = plan(Kind),
        #{name := Name} = Profile = profile(Kind),
        write(Stage, atom_to_list(Name) ++ ".x",
            xls_topology_dslx:emit(Plan, Profile#{direct_actor_debug => true})),
        write(Stage, atom_to_list(Name) ++ ".json", json:encode([
            maps:with([port, width], Binding) ||
            Binding <- xls_actor_observation:bindings(Plan, #{})]))
    end, [scalar, rectangle]),
    write(Stage, "hls_dense_statem_fixture.json",
        json:encode([#{port => <<"_actor_debug_out">>, width => 49}])),
    write(Stage, "hls_actor_observation_fixture.x",
        xls_parse:to_xls("test/hls_actor_observation_fixture.erl", Options)),
    write(Stage, "debug_commit.x", """
    import axis;
    import hls_actor_observation_fixture;
    pub proc Top {
      config(request: chan<axis::Frame> in,
          egress: chan<hls_actor_observation_fixture::Egress> out,
          admission: chan<u1> out,
          actor_debug_out: chan<hls_actor_observation_fixture::ActorObservation> out) {
        spawn hls_actor_observation_fixture::Service(request, egress, admission, actor_debug_out);
        ()
      }
      init { () }
      next(state: ()) { state }
    }
    """),
    write(Stage, "actor_observation_expected.svh", [
        frame_constant("REQUEST", configure, 41),
        frame_constant("FIRST", report, 41),
        frame_constant("SECOND", report, 42)]).

frame_constant(Name, Tag, Value) ->
    Header = (1 bsl 24) bor hls_actor_observation_fixture:pack_tag(Tag),
    Frame = (Header bsl 96) bor Value,
    io_lib:format("localparam [127:0] ~s = 128'h~32.16.0b;~n", [Name, Frame]).

plan(Kind) -> plan(Kind, reports).

plan(scalar, Reports) ->
    hls_topology:normalize(#{version => 1,
        actors => #{first => hls_dense_statem_fixture, second => hls_dense_statem_fixture},
        families => #{}, ingresses => [], route_relations => [],
        externals => [{Reports, out, [report]}],
        routes => [{{Id, out}, queued, [{actor, Id}, {external, Reports}]} || Id <- [first, second]],
        startup => [{first, [{configure, false, 7, -256}]}, {second, [{configure, true, 3, 255}]}]});
plan(rectangle, Reports) ->
    hls_topology:normalize(#{version => 1, actors => #{},
        families => #{cell => #{module => hls_dense_statem_fixture, shape => [2, 3]}},
        ingresses => [{commands, {rectangle, [2, 3]}, [
            {configure, [configure], [{family, cell, {embed, [1, 1], [0, 0]}}]}]}],
        externals => [{Reports, out, [report]}], routes => [],
        route_relations => [{{cell, out}, [{external, Reports}]}],
        startup => [{{cell, X, Y}, [{configure, true, X, Y}]} ||
            X <- lists:seq(0, 1), Y <- lists:seq(0, 2)]}).

profile(Kind) ->
    #{name => case Kind of scalar -> debug_scalar; rectangle -> debug_rectangle end,
        channel_depth => 1, actor_egress_depth => burst}.

write(Stage, Name, Data) ->
    ok = file:write_file(filename:join(Stage, Name), Data).
