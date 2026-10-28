-module(hls_parametric_topology_tests).

-include_lib("eunit/include/eunit.hrl").
-include("hls_routing_fixture.hrl").

%% Checks grid torus normalizes without expanded actor instances.
-spec grid_torus_normalizes_without_expanded_actor_instances_test() -> ok.
grid_torus_normalizes_without_expanded_actor_instances_test() ->
    Plan = hls_topology:from_module(hls_grid_topology_fixture),
    ?assertEqual(1, maps:get(version, Plan)),
    ?assertEqual([], maps:get(actors, Plan)),
    ?assertEqual([], maps:get(routes, Plan)),
    Startup = maps:get(startup, Plan),
    ?assertEqual(6, length(Startup)),
    ?assertEqual(
        [{grid, X, Y} || X <- lists:seq(0, 1), Y <- lists:seq(0, 2)],
        [maps:get(target, Item) || Item <- Startup]
    ),
    Seeds = [
        Config#seed.seed
        || #{messages := [Config = #seed{}]} <- Startup
    ],
    ?assertEqual(6, length(lists:usort(Seeds))),
    ?assert(lists:all(fun(Seed) -> Seed =/= 0 end, Seeds)),
    ?assertEqual(7, length(maps:get(route_relations, Plan))),
    [Family] = maps:get(families, Plan),
    ?assertEqual(grid, maps:get(id, Family)),
    ?assertEqual(hls_grid_cell_fixture, maps:get(module, Family)),
    ?assertEqual([2, 3], maps:get(shape, Family)),
    ?assertEqual(6, maps:get(instance_count, Family)),
    ?assertEqual(
        [north, east, west, south, query, result, status],
        maps:get(outputs, Family)
    ),
    ?assertEqual(
        [
            #{
                id => request_events,
                direction => out,
                schemas => [request]
            },
            #{
                id => result_events,
                direction => out,
                schemas => [result, status]
            }
        ],
        maps:get(externals, Plan)
    ).

%% Checks topology normalizer rejects obsolete version.
-spec topology_normalizer_rejects_obsolete_version_test() -> ok.
topology_normalizer_rejects_obsolete_version_test() ->
    Spec = hls_grid_topology_fixture:topology(),
    ?assertError(
        {unsupported_version, 0},
        hls_topology:normalize(Spec#{version := 0})
    ).

%% Checks family size does not expand routes but does enumerate v0 startup.
-spec family_size_does_not_expand_routes_but_does_enumerate_v0_startup_test() -> ok.
family_size_does_not_expand_routes_but_does_enumerate_v0_startup_test() ->
    Small = hls_topology:normalize(hls_grid_topology_fixture:topology(5, 5)),
    Large = hls_topology:normalize(hls_grid_topology_fixture:topology(50, 50)),
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

%% Checks wrapped routes resolve one boundary member.
-spec wrapped_routes_resolve_one_boundary_member_test() -> ok.
wrapped_routes_resolve_one_boundary_member_test() ->
    Plan = hls_topology:normalize(hls_grid_topology_fixture:topology(5, 4)),
    Routes = hls_topology:routes_for_instance(Plan, grid, [0, 0]),
    ?assertEqual(7, length(Routes)),
    ?assertEqual(
        [{actor, {grid, 0, 3}}],
        maps:get(recipients, route(Routes, north))
    ),
    ?assertEqual(
        [{actor, {grid, 1, 0}}],
        maps:get(recipients, route(Routes, east))
    ),
    ?assertEqual(
        [{actor, {grid, 4, 0}}],
        maps:get(recipients, route(Routes, west))
    ),
    ?assertEqual(
        [{actor, {grid, 0, 1}}],
        maps:get(recipients, route(Routes, south))
    ),
    ?assertEqual(
        [{external, request_events}],
        maps:get(recipients, route(Routes, query))
    ),
    ?assertEqual(
        [{external, result_events}],
        maps:get(recipients, route(Routes, result))
    ),
    ?assertEqual(
        [{external, result_events}],
        maps:get(recipients, route(Routes, status))
    ),
    ?assert(lists:all(
        fun(Route) ->
            {{grid, 0, 0}, _Port} = maps:get(source, Route),
            maps:get(delivery, Route) =:= direct
        end,
        Routes
    )).

%% Checks two by two torus exposes opposite port aliases.
-spec two_by_two_torus_exposes_opposite_port_aliases_test() -> ok.
two_by_two_torus_exposes_opposite_port_aliases_test() ->
    Plan = hls_topology:normalize(hls_grid_topology_fixture:topology(2, 2)),
    ?assertEqual(4, length(maps:get(lane_relations, Plan))),
    ?assertEqual(
        [north, south],
        maps:get(source_ports, lane_relation(
            Plan,
            {family, grid, {translate, [0, 1], wrap}}
        ))
    ),
    ?assertEqual(
        [east, west],
        maps:get(source_ports, lane_relation(
            Plan,
            {family, grid, {translate, [1, 0], wrap}}
        ))
    ),
    ?assertEqual(
        [query],
        maps:get(source_ports, lane_relation(
            Plan,
            {external, request_events}
        ))
    ),
    ?assertEqual(
        [result, status],
        maps:get(source_ports, lane_relation(
            Plan,
            {external, result_events}
        ))
    ).

%% Checks three by three torus has distinct cardinal lanes.
-spec three_by_three_torus_has_distinct_cardinal_lanes_test() -> ok.
three_by_three_torus_has_distinct_cardinal_lanes_test() ->
    Plan = hls_topology:normalize(hls_grid_topology_fixture:topology(3, 3)),
    ?assertEqual(6, length(maps:get(lane_relations, Plan))),
    lists:foreach(
        fun({Destination, Ports}) ->
            ?assertEqual(
                Ports,
                maps:get(source_ports, lane_relation(Plan, Destination))
            )
        end,
        [
            {{family, grid, {translate, [0, -1], wrap}}, [north]},
            {{family, grid, {translate, [1, 0], wrap}}, [east]},
            {{family, grid, {translate, [-1, 0], wrap}}, [west]},
            {{family, grid, {translate, [0, 1], wrap}}, [south]},
            {{external, request_events}, [query]},
            {{external, result_events}, [result, status]}
        ]
    ).

%% Checks route relation order is canonical.
-spec route_relation_order_is_canonical_test() -> ok.
route_relation_order_is_canonical_test() ->
    Spec = hls_grid_topology_fixture:topology(3, 4),
    Reordered = Spec#{
        route_relations := lists:reverse(maps:get(route_relations, Spec))
    },
    ?assertEqual(
        hls_topology:normalize(Spec),
        hls_topology:normalize(Reordered)
    ).

%% Checks wrapped translation is canonical.
-spec wrapped_translation_is_canonical_test() -> ok.
wrapped_translation_is_canonical_test() ->
    Spec = hls_grid_topology_fixture:topology(3, 4),
    North = {grid, north},
    Positive = replace_relation(
        Spec,
        North,
        {North, [{family, grid, {translate, [0, 3], wrap}}]}
    ),
    ?assertEqual(
        hls_topology:normalize(Spec),
        hls_topology:normalize(Positive)
    ).

%% Checks family outputs are total and unique.
-spec family_outputs_are_total_and_unique_test() -> ok.
family_outputs_are_total_and_unique_test() ->
    Spec = hls_grid_topology_fixture:topology(),
    [First | Rest] = maps:get(route_relations, Spec),
    ?assertError(
        {unrouted_family_outputs, [{grid, north}]},
        hls_topology:normalize(Spec#{route_relations := Rest})
    ),
    ?assertError(
        {duplicate_route_relation_sources, [{grid, north}]},
        hls_topology:normalize(Spec#{
            route_relations := [First, First | Rest]
        })
    ).

%% Checks family shape and translation are bounded.
-spec family_shape_and_translation_are_bounded_test() -> ok.
family_shape_and_translation_are_bounded_test() ->
    Spec0 = hls_grid_topology_fixture:topology(),
    Families0 = maps:get(families, Spec0),
    ?assertError(
        {invalid_family_shape, grid, [0, 2]},
        hls_topology:normalize(Spec0#{
            families := Families0#{grid := #{
                module => hls_grid_cell_fixture,
                shape => [0, 2]
            }},
            startup := []
        })
    ),
    Spec = Spec0,
    Source = {grid, north},
    Invalid = replace_relation(
        Spec,
        Source,
        {Source, [{family, grid, {translate, [-1], wrap}}]}
    ),
    ?assertError(
        {invalid_relation_translation,
            Source,
            {family, grid, {translate, [-1], wrap}},
            [2, 3]},
        hls_topology:normalize(Invalid)
    ).

%% Checks equivalent wrapped fanout recipients are rejected.
-spec equivalent_wrapped_fanout_recipients_are_rejected_test() -> ok.
equivalent_wrapped_fanout_recipients_are_rejected_test() ->
    Spec = hls_grid_topology_fixture:topology(2, 2),
    Source = {grid, north},
    Duplicate = replace_relation(
        Spec,
        Source,
        {Source, coupled, [
            {family, grid, {translate, [0, -1], wrap}},
            {family, grid, {translate, [0, 1], wrap}}
        ]}
    ),
    ?assertError(
        {duplicate_route_relation_recipients,
            Source,
            [{family, grid, {translate, [0, 1], wrap}}]},
        hls_topology:normalize(Duplicate)
    ).

%% Checks relation endpoints are checked.
-spec relation_endpoints_are_checked_test() -> ok.
relation_endpoints_are_checked_test() ->
    Spec = hls_grid_topology_fixture:topology(),
    North = {grid, north},
    ?assertError(
        {unknown_family, missing, {route_relation_recipient, North}},
        hls_topology:normalize(replace_relation(
            Spec,
            North,
            {North, [{family, missing,
                {translate, [0, -1], wrap}}]}
        ))
    ),
    Query = {grid, query},
    ?assertError(
        {unknown_external, missing,
            {route_relation_recipient, Query}},
        hls_topology:normalize(replace_relation(
            Spec,
            Query,
            {Query, [{external, missing}]}
        ))
    ).

%% Checks family relation interfaces are checked once per rule.
-spec family_relation_interfaces_are_checked_once_per_rule_test() -> ok.
family_relation_interfaces_are_checked_once_per_rule_test() ->
    Spec = hls_grid_topology_fixture:topology(50, 50),
    MalformedExternals = [
        case External of
            {request_events, out, _Schemas} ->
                {request_events, out, [sample]};
            _ ->
                External
        end
        || External <- maps:get(externals, Spec)
    ],
    ?assertError(
        {incompatible_route_schemas,
            {grid, query},
            {external, request_events},
            [request],
            [sample]},
        hls_topology:normalize(Spec#{
            externals := MalformedExternals
        })
    ).

%% Checks family and exact actor names cannot collide.
-spec family_and_exact_actor_names_cannot_collide_test() -> ok.
family_and_exact_actor_names_cannot_collide_test() ->
    Spec = hls_grid_topology_fixture:topology(),
    ?assertError(
        {actor_family_id_collisions, [grid]},
        hls_topology:normalize(Spec#{
            actors := #{grid => hls_grid_cell_fixture}
        })
    ),
    ?assertError(
        {actor_family_id_collisions, [{grid, 0, 0}]},
        hls_topology:normalize(Spec#{
            actors := #{{grid, 0, 0} => hls_grid_cell_fixture}
        })
    ).

%% Checks family names cannot overlap an instance namespace.
-spec family_names_cannot_overlap_an_instance_namespace_test() -> ok.
family_names_cannot_overlap_an_instance_namespace_test() ->
    Spec = hls_grid_topology_fixture:topology(),
    ?assertError(
        {family_namespace_collisions, [{grid, {grid, 0, 0}}]},
        hls_topology:normalize(Spec#{
            families := #{
                grid => #{module => hls_grid_cell_fixture, shape => [2, 2]},
                {grid, 0, 0} => #{module => hls_grid_cell_fixture, shape => [1, 1]}
            }
        })
    ).

%% Checks instance route coordinates are checked.
-spec instance_route_coordinates_are_checked_test() -> ok.
instance_route_coordinates_are_checked_test() ->
    Plan = hls_topology:from_module(hls_grid_topology_fixture),
    ?assertError(
        {invalid_family_coordinates, grid, [2, 0], [2, 3]},
        hls_topology:routes_for_instance(Plan, grid, [2, 0])
    ),
    ?assertError(
        {invalid_family_coordinates, grid, [0], [2, 3]},
        hls_topology:routes_for_instance(Plan, grid, [0])
    ).

%% Finds the one normalized route selected by source or output port.
-spec route(map() | [map()], term()) -> map().
route(Routes, Port) ->
    hd([
        Route
        || Route = #{source := {_Instance, SourcePort}} <- Routes,
           SourcePort =:= Port
    ]).

%% Finds a compact family lane by its destination relation.
-spec lane_relation(map(), term()) -> map().
lane_relation(Plan, Destination) ->
    hd([
        Lane
        || Lane = #{source := grid, destination := LaneDestination} <-
               maps:get(lane_relations, Plan),
           LaneDestination =:= Destination
    ]).

%% Replaces one family relation in the raw topology.
-spec replace_relation(map(), term(), tuple()) -> map().
replace_relation(Spec, Source, Replacement) ->
    Spec#{route_relations := [
        case Relation of
            {Source, _Recipients} -> Replacement;
            {Source, _Delivery, _Recipients} -> Replacement;
            _ -> Relation
        end
        || Relation <- maps:get(route_relations, Spec)
    ]}.
