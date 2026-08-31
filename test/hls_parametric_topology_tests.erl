-module(hls_parametric_topology_tests).

-include_lib("eunit/include/eunit.hrl").

phi_torus_normalizes_without_instances_test() ->
    Plan = hls_topology:from_module(phi_torus_topology),
    ?assertEqual(1, maps:get(version, Plan)),
    ?assertEqual([], maps:get(actors, Plan)),
    ?assertEqual([], maps:get(routes, Plan)),
    ?assertEqual([], maps:get(startup, Plan)),
    ?assertEqual(5, length(maps:get(route_relations, Plan))),
    [Family] = maps:get(families, Plan),
    ?assertEqual(phi, maps:get(id, Family)),
    ?assertEqual(phi_halo_cell, maps:get(module, Family)),
    ?assertEqual([2, 3], maps:get(shape, Family)),
    ?assertEqual(6, maps:get(instance_count, Family)),
    ?assertEqual(
        [north, east, west, south, syndrome],
        maps:get(outputs, Family)
    ),
    ?assertEqual(
        [#{
            id => syndrome_requests,
            direction => out,
            schemas => [phenom_request]
        }],
        maps:get(externals, Plan)
    ).

topology_normalizer_rejects_obsolete_version_test() ->
    Spec = phi_torus_topology:topology(),
    ?assertError(
        {unsupported_version, 0},
        hls_topology:normalize(Spec#{version := 0})
    ).

family_size_does_not_expand_the_normalized_plan_test() ->
    Small = hls_topology:normalize(phi_torus_topology:topology(5, 5)),
    Large = hls_topology:normalize(phi_torus_topology:topology(50, 50)),
    ?assertEqual([], maps:get(actors, Small)),
    ?assertEqual([], maps:get(actors, Large)),
    ?assertEqual([], maps:get(routes, Small)),
    ?assertEqual([], maps:get(routes, Large)),
    ?assertEqual(5, length(maps:get(route_relations, Small))),
    ?assertEqual(5, length(maps:get(route_relations, Large))),
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
    ).

wrapped_routes_resolve_one_boundary_member_test() ->
    Plan = hls_topology:normalize(phi_torus_topology:topology(5, 4)),
    Routes = hls_topology:routes_for_instance(Plan, phi, [0, 0]),
    ?assertEqual(5, length(Routes)),
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
    ?assert(lists:all(
        fun(Route) ->
            {{phi, 0, 0}, _Port} = maps:get(source, Route),
            maps:get(delivery, Route) =:= direct
        end,
        Routes
    )).

two_by_two_torus_exposes_opposite_port_aliases_test() ->
    Plan = hls_topology:normalize(phi_torus_topology:topology(2, 2)),
    ?assertEqual(3, length(maps:get(lane_relations, Plan))),
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
    ).

three_by_three_torus_has_distinct_cardinal_lanes_test() ->
    Plan = hls_topology:normalize(phi_torus_topology:topology(3, 3)),
    ?assertEqual(5, length(maps:get(lane_relations, Plan))),
    lists:foreach(
        fun({Destination, Port}) ->
            ?assertEqual(
                [Port],
                maps:get(source_ports, lane_relation(Plan, Destination))
            )
        end,
        [
            {{family, phi, {translate, [0, -1], wrap}}, north},
            {{family, phi, {translate, [1, 0], wrap}}, east},
            {{family, phi, {translate, [-1, 0], wrap}}, west},
            {{family, phi, {translate, [0, 1], wrap}}, south},
            {{external, syndrome_requests}, syndrome}
        ]
    ).

route_relation_order_is_canonical_test() ->
    Spec = phi_torus_topology:topology(3, 4),
    Reordered = Spec#{
        route_relations := lists:reverse(maps:get(route_relations, Spec))
    },
    ?assertEqual(
        hls_topology:normalize(Spec),
        hls_topology:normalize(Reordered)
    ).

wrapped_translation_is_canonical_test() ->
    Spec = phi_torus_topology:topology(3, 4),
    North = {phi, north},
    Positive = replace_relation(
        Spec,
        North,
        {North, [{family, phi, {translate, [0, 3], wrap}}]}
    ),
    ?assertEqual(
        hls_topology:normalize(Spec),
        hls_topology:normalize(Positive)
    ).

family_outputs_are_total_and_unique_test() ->
    Spec = phi_torus_topology:topology(),
    [First | Rest] = maps:get(route_relations, Spec),
    ?assertError(
        {unrouted_family_outputs, [{phi, north}]},
        hls_topology:normalize(Spec#{route_relations := Rest})
    ),
    ?assertError(
        {duplicate_route_relation_sources, [{phi, north}]},
        hls_topology:normalize(Spec#{
            route_relations := [First, First | Rest]
        })
    ).

family_shape_and_translation_are_bounded_test() ->
    ?assertError(
        {invalid_family_shape, phi, [0, 2]},
        hls_topology:normalize(phi_torus_topology:topology(0, 2))
    ),
    Spec = phi_torus_topology:topology(),
    Source = {phi, north},
    Invalid = replace_relation(
        Spec,
        Source,
        {Source, [{family, phi, {translate, [-1], wrap}}]}
    ),
    ?assertError(
        {invalid_relation_translation,
            Source,
            {family, phi, {translate, [-1], wrap}},
            [2, 3]},
        hls_topology:normalize(Invalid)
    ).

equivalent_wrapped_fanout_recipients_are_rejected_test() ->
    Spec = phi_torus_topology:topology(2, 2),
    Source = {phi, north},
    Duplicate = replace_relation(
        Spec,
        Source,
        {Source, coupled, [
            {family, phi, {translate, [0, -1], wrap}},
            {family, phi, {translate, [0, 1], wrap}}
        ]}
    ),
    ?assertError(
        {duplicate_route_relation_recipients,
            Source,
            [{family, phi, {translate, [0, 1], wrap}}]},
        hls_topology:normalize(Duplicate)
    ).

relation_endpoints_are_checked_test() ->
    Spec = phi_torus_topology:topology(),
    North = {phi, north},
    ?assertError(
        {unknown_family, missing, {route_relation_recipient, North}},
        hls_topology:normalize(replace_relation(
            Spec,
            North,
            {North, [{family, missing,
                {translate, [0, -1], wrap}}]}
        ))
    ),
    Syndrome = {phi, syndrome},
    ?assertError(
        {unknown_external, missing,
            {route_relation_recipient, Syndrome}},
        hls_topology:normalize(replace_relation(
            Spec,
            Syndrome,
            {Syndrome, [{external, missing}]}
        ))
    ).

family_relation_interfaces_are_checked_once_per_rule_test() ->
    Spec = phi_torus_topology:topology(50, 50),
    ?assertError(
        {incompatible_route_schemas,
            {phi, syndrome},
            {external, syndrome_requests},
            [phenom_request],
            [phi]},
        hls_topology:normalize(Spec#{
            externals := [{syndrome_requests, out, [phi]}]
        })
    ).

family_and_exact_actor_names_cannot_collide_test() ->
    Spec = phi_torus_topology:topology(),
    ?assertError(
        {actor_family_id_collisions, [phi]},
        hls_topology:normalize(Spec#{
            actors := #{phi => phi_halo_cell}
        })
    ),
    ?assertError(
        {actor_family_id_collisions, [{phi, 0, 0}]},
        hls_topology:normalize(Spec#{
            actors := #{{phi, 0, 0} => phi_halo_cell}
        })
    ).

family_names_cannot_overlap_an_instance_namespace_test() ->
    Spec = phi_torus_topology:topology(),
    ?assertError(
        {family_namespace_collisions, [{phi, {phi, 0, 0}}]},
        hls_topology:normalize(Spec#{
            families := #{
                phi => #{module => phi_halo_cell, shape => [2, 2]},
                {phi, 0, 0} => #{module => phi_halo_cell, shape => [1, 1]}
            }
        })
    ).

instance_route_coordinates_are_checked_test() ->
    Plan = hls_topology:from_module(phi_torus_topology),
    ?assertError(
        {invalid_family_coordinates, phi, [2, 0], [2, 3]},
        hls_topology:routes_for_instance(Plan, phi, [2, 0])
    ),
    ?assertError(
        {invalid_family_coordinates, phi, [0], [2, 3]},
        hls_topology:routes_for_instance(Plan, phi, [0])
    ).

route(Routes, Port) ->
    hd([
        Route
        || Route <- Routes,
           {_Instance, SourcePort} <- [maps:get(source, Route)],
           SourcePort =:= Port
    ]).

lane_relation(Plan, Destination) ->
    hd([
        Lane
        || Lane <- maps:get(lane_relations, Plan),
           maps:get(source, Lane) =:= phi,
           maps:get(destination, Lane) =:= Destination
    ]).

replace_relation(Spec, Source, Replacement) ->
    Spec#{route_relations := [
        case Relation of
            {Source, _Recipients} -> Replacement;
            {Source, _Delivery, _Recipients} -> Replacement;
            _ -> Relation
        end
        || Relation <- maps:get(route_relations, Spec)
    ]}.
