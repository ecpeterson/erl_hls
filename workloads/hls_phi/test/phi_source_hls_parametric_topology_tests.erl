-module(phi_source_hls_parametric_topology_tests).

-include_lib("eunit/include/eunit.hrl").
-include("phi_protocol.hrl").

%% Checks phi torus normalizes without expanded actor instances for the retained Phi application.
-spec phi_torus_normalizes_without_expanded_actor_instances_test() -> ok.
phi_torus_normalizes_without_expanded_actor_instances_test() ->
    Plan = hls_topology:from_module(phi_torus_topology),
    ?assertEqual(1, maps:get(version, Plan)),
    ?assertEqual([], maps:get(actors, Plan)),
    ?assertEqual([], maps:get(routes, Plan)),
    Startup = maps:get(startup, Plan),
    ?assertEqual(6, length(Startup)),
    ?assertEqual(
        [{phi, X, Y} || X <- lists:seq(0, 1), Y <- lists:seq(0, 2)],
        [maps:get(target, Item) || Item <- Startup]
    ),
    Seeds = [
        Config#phi_config.seed
        || #{messages := [Config = #phi_config{}]} <- Startup
    ],
    ?assertEqual(6, length(lists:usort(Seeds))),
    ?assert(lists:all(fun(Seed) -> Seed =/= 0 end, Seeds)),
    ?assertEqual(7, length(maps:get(route_relations, Plan))),
    [Family] = maps:get(families, Plan),
    ?assertEqual(phi, maps:get(id, Family)),
    ?assertEqual(phi_halo_cell, maps:get(module, Family)),
    ?assertEqual([2, 3], maps:get(shape, Family)),
    ?assertEqual(6, maps:get(instance_count, Family)),
    ?assertEqual(
        [north, east, west, south, syndrome, correction, status],
        maps:get(outputs, Family)
    ),
    ?assertEqual(
        [
            #{
                id => decoder_events,
                direction => out,
                schemas => [phi_correction, phi_status]
            },
            #{
                id => syndrome_requests,
                direction => out,
                schemas => [phenom_request]
            }
        ],
        maps:get(externals, Plan)
    ).

%% Checks family size does not expand routes but does enumerate v0 startup for the retained Phi application.
-spec family_size_does_not_expand_routes_but_does_enumerate_v0_startup_test() -> ok.
family_size_does_not_expand_routes_but_does_enumerate_v0_startup_test() ->
    Small = hls_topology:normalize(phi_torus_topology:topology(5, 5)),
    Large = hls_topology:normalize(phi_torus_topology:topology(50, 50)),
    ?assertEqual([], maps:get(actors, Small)),
    ?assertEqual([], maps:get(actors, Large)),
    ?assertEqual([], maps:get(routes, Small)),
    ?assertEqual([], maps:get(routes, Large)),
    ?assertEqual(7, length(maps:get(route_relations, Small))),
    ?assertEqual(7, length(maps:get(route_relations, Large))),
    [SmallFamily] = maps:get(families, Small),
    [LargeFamily] = maps:get(families, Large),
    ?assertEqual(25, maps:get(instance_count, SmallFamily)),
    ?assertEqual(2500, maps:get(instance_count, LargeFamily)),
    ?assertEqual(
        maps:without([instance_count, shape], SmallFamily),
        maps:without([instance_count, shape], LargeFamily)
    ),
    ?assertEqual(
        maps:get(route_relations, Small),
        maps:get(route_relations, Large)
    ),
    ?assertEqual(25, length(maps:get(startup, Small))),
    ?assertEqual(2500, length(maps:get(startup, Large))).

%% Checks wrapped routes resolve one boundary member for the retained Phi application.
-spec wrapped_routes_resolve_one_boundary_member_test() -> ok.
wrapped_routes_resolve_one_boundary_member_test() ->
    Plan = hls_topology:normalize(phi_torus_topology:topology(5, 4)),
    Routes = hls_logical_topology:routes_for_instance(Plan, phi, [0, 0]),
    ?assertEqual(7, length(Routes)),
    ?assertEqual(
        [{actor, {phi, 0, 3}}],
        maps:get(recipients, route(Routes, north))
    ),
    ?assertEqual(
        [{actor, {phi, 1, 0}}],
        maps:get(recipients, route(Routes, east))
    ),
    ?assertEqual(
        [{actor, {phi, 4, 0}}],
        maps:get(recipients, route(Routes, west))
    ),
    ?assertEqual(
        [{actor, {phi, 0, 1}}],
        maps:get(recipients, route(Routes, south))
    ),
    ?assertEqual(
        [{external, syndrome_requests}],
        maps:get(recipients, route(Routes, syndrome))
    ),
    ?assertEqual(
        [{external, decoder_events}],
        maps:get(recipients, route(Routes, correction))
    ),
    ?assertEqual(
        [{external, decoder_events}],
        maps:get(recipients, route(Routes, status))
    ),
    ?assert(lists:all(
        fun(Route) ->
            {{phi, 0, 0}, _Port} = maps:get(source, Route),
            maps:get(delivery, Route) =:= direct
        end,
        Routes
    )).

%% Checks two by two torus exposes opposite port aliases for the retained Phi application.
-spec two_by_two_torus_exposes_opposite_port_aliases_test() -> ok.
two_by_two_torus_exposes_opposite_port_aliases_test() ->
    Plan = hls_topology:normalize(phi_torus_topology:topology(2, 2)),
    ?assertEqual(4, length(maps:get(lane_relations, Plan))),
    ?assertEqual(
        [north, south],
        maps:get(source_ports, lane_relation(
            Plan,
            {family, phi, {translate, [0, 1], wrap}}
        ))
    ),
    ?assertEqual(
        [east, west],
        maps:get(source_ports, lane_relation(
            Plan,
            {family, phi, {translate, [1, 0], wrap}}
        ))
    ),
    ?assertEqual(
        [syndrome],
        maps:get(source_ports, lane_relation(
            Plan,
            {external, syndrome_requests}
        ))
    ),
    ?assertEqual(
        [correction, status],
        maps:get(source_ports, lane_relation(
            Plan,
            {external, decoder_events}
        ))
    ).

%% Checks three by three torus has distinct cardinal lanes for the retained Phi application.
-spec three_by_three_torus_has_distinct_cardinal_lanes_test() -> ok.
three_by_three_torus_has_distinct_cardinal_lanes_test() ->
    Plan = hls_topology:normalize(phi_torus_topology:topology(3, 3)),
    ?assertEqual(6, length(maps:get(lane_relations, Plan))),
    lists:foreach(
        fun({Destination, Ports}) ->
            ?assertEqual(
                Ports,
                maps:get(source_ports, lane_relation(Plan, Destination))
            )
        end,
        [
            {{family, phi, {translate, [0, -1], wrap}}, [north]},
            {{family, phi, {translate, [1, 0], wrap}}, [east]},
            {{family, phi, {translate, [-1, 0], wrap}}, [west]},
            {{family, phi, {translate, [0, 1], wrap}}, [south]},
            {{external, syndrome_requests}, [syndrome]},
            {{external, decoder_events}, [correction, status]}
        ]
    ).

%% Finds the actual application route by source or output port.
-spec route(map() | [map()], term()) -> map().
route(Routes, Port) ->
    hd([
        Route
        || Route = #{source := {_Instance, SourcePort}} <- Routes,
           SourcePort =:= Port
    ]).

%% Finds the application family lane by destination relation.
-spec lane_relation(map(), term()) -> map().
lane_relation(Plan, Destination) ->
    hd([
        Lane
        || Lane = #{source := phi, destination := LaneDestination} <-
               maps:get(lane_relations, Plan),
           LaneDestination =:= Destination
    ]).
