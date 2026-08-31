-module(phi_noise_topology_tests).

-include_lib("eunit/include/eunit.hrl").
-include("phi_protocol.hrl").

-define(DISTANCE, 3).
-define(EXERCISE_THRESHOLD, 16#80000000).

default_topology_has_six_bounded_families_test() ->
    Spec = phi_noise_topology:topology(),
    ?assertEqual(1, maps:get(version, Spec)),
    ?assertEqual(#{}, maps:get(actors, Spec)),
    ?assertEqual([], maps:get(routes, Spec)),
    ?assertEqual(
        [data_even, data_odd, phi_x, phi_z, syndrome_x, syndrome_z],
        lists:sort(maps:keys(maps:get(families, Spec)))
    ),
    maps:foreach(
        fun(_Family, #{shape := Shape}) ->
            ?assertEqual([?DISTANCE, ?DISTANCE], Shape)
        end,
        maps:get(families, Spec)
    ),
    ?assertEqual(28, length(maps:get(route_relations, Spec))),
    ?assertEqual(
        [
            {x_announcements, out, [phenom_anyon]},
            {z_announcements, out, [phenom_anyon]}
        ],
        maps:get(externals, Spec)
    ).

family_modules_match_protocol_roles_test() ->
    Families = maps:get(families, phi_noise_topology:topology()),
    ?assertEqual(phi_halo_cell, family_module(phi_x, Families)),
    ?assertEqual(phi_halo_cell, family_module(phi_z, Families)),
    ?assertEqual(
        phenom_syndrome_cell,
        family_module(syndrome_x, Families)
    ),
    ?assertEqual(
        phenom_syndrome_cell,
        family_module(syndrome_z, Families)
    ),
    ?assertEqual(phenom_data_cell, family_module(data_even, Families)),
    ?assertEqual(phenom_data_cell, family_module(data_odd, Families)).

default_mesh_has_distinct_reciprocal_cardinal_edges_test() ->
    Plan = hls_topology:from_module(phi_noise_topology),
    lists:foreach(
        fun(Family) ->
            lists:foreach(
                fun(Coordinates) ->
                    assert_distinct_reciprocal_edges(
                        Plan,
                        Family,
                        Coordinates
                    )
                end,
                coordinates(?DISTANCE)
            )
        end,
        [data_even, data_odd, phi_x, phi_z, syndrome_x, syndrome_z]
    ).

wrapped_cross_family_boundary_routes_test() ->
    Plan = hls_topology:from_module(phi_noise_topology),
    assert_cardinal_destinations(Plan, syndrome_x, [0, 0], [
        {data_odd, 0, 2},
        {data_even, 1, 0},
        {data_even, 0, 0},
        {data_odd, 0, 0}
    ]),
    assert_cardinal_destinations(Plan, syndrome_z, [0, 0], [
        {data_even, 1, 0},
        {data_odd, 1, 0},
        {data_odd, 0, 0},
        {data_even, 1, 1}
    ]),
    assert_cardinal_destinations(Plan, data_even, [0, 0], [
        {syndrome_z, 2, 2},
        {syndrome_x, 0, 0},
        {syndrome_x, 2, 0},
        {syndrome_z, 2, 0}
    ]),
    assert_cardinal_destinations(Plan, data_odd, [0, 0], [
        {syndrome_x, 0, 0},
        {syndrome_z, 0, 0},
        {syndrome_z, 2, 0},
        {syndrome_x, 0, 1}
    ]).

each_data_qubit_touches_two_checks_of_each_plane_test() ->
    Plan = hls_topology:from_module(phi_noise_topology),
    lists:foreach(
        fun(Family) ->
            lists:foreach(
                fun(Coordinates) ->
                    CheckFamilies = lists:sort([
                        element(1, Destination)
                        || Destination <- cardinal_destinations(
                            Plan, Family, Coordinates
                        )
                    ]),
                    ?assertEqual(
                        [syndrome_x, syndrome_x, syndrome_z, syndrome_z],
                        CheckFamilies
                    )
                end,
                coordinates(?DISTANCE)
            )
        end,
        [data_even, data_odd]
    ).

x_and_z_checks_overlap_on_zero_or_two_data_qubits_test() ->
    Plan = hls_topology:from_module(phi_noise_topology),
    XNeighborhoods = [
        cardinal_destinations(Plan, syndrome_x, Coordinates)
        || Coordinates <- coordinates(?DISTANCE)
    ],
    ZNeighborhoods = [
        cardinal_destinations(Plan, syndrome_z, Coordinates)
        || Coordinates <- coordinates(?DISTANCE)
    ],
    Overlaps = [
        length([Data || Data <- XData, lists:member(Data, ZData)])
        || XData <- XNeighborhoods,
           ZData <- ZNeighborhoods
    ],
    ?assertEqual(45, count_value(0, Overlaps)),
    ?assertEqual(36, count_value(2, Overlaps)),
    ?assertEqual([0, 2], lists:usort(Overlaps)).

phi_and_syndrome_pairs_share_coordinates_test() ->
    Plan = hls_topology:from_module(phi_noise_topology),
    lists:foreach(
        fun(Coordinates = [X, Y]) ->
            ?assertEqual(
                [{actor, {syndrome_x, X, Y}}],
                recipients(Plan, phi_x, Coordinates, syndrome)
            ),
            ?assertEqual(
                [{actor, {syndrome_z, X, Y}}],
                recipients(Plan, phi_z, Coordinates, syndrome)
            ),
            assert_announcement_fanout(
                Plan,
                syndrome_x,
                Coordinates,
                {phi_x, X, Y},
                x_announcements
            ),
            assert_announcement_fanout(
                Plan,
                syndrome_z,
                Coordinates,
                {phi_z, X, Y},
                z_announcements
            )
        end,
        coordinates(?DISTANCE)
    ).

noise_startup_is_explicit_distinct_and_nonzero_test() ->
    Spec = phi_noise_topology:topology(),
    Startup = maps:get(startup, Spec),
    ?assertEqual(4 * ?DISTANCE * ?DISTANCE, length(Startup)),
    Seeds = [
        begin
            ?assert(lists:member(Family, [
                data_even,
                data_odd,
                syndrome_x,
                syndrome_z
            ])),
            ?assert(X >= 0 andalso X < ?DISTANCE),
            ?assert(Y >= 0 andalso Y < ?DISTANCE),
            ?assertEqual(?EXERCISE_THRESHOLD, Threshold),
            ?assert(Seed > 0),
            Seed
        end
        || {{Family, X, Y}, [#phenom_config{
                seed = Seed,
                threshold = Threshold
            }]} <- Startup
    ],
    ?assertEqual(lists:seq(1, 36), lists:sort(Seeds)),
    ?assertEqual(length(Seeds), length(lists:usort(Seeds))).

normalized_startup_retains_family_instance_targets_test() ->
    Plan = hls_topology:from_module(phi_noise_topology),
    Startup = maps:get(startup, Plan),
    ?assertEqual(36, length(Startup)),
    ?assertEqual(30, length(maps:get(lane_relations, Plan))),
    ?assert(lists:all(
        fun(#{source_ports := Ports}) -> length(Ports) =:= 1 end,
        maps:get(lane_relations, Plan)
    )),
    ?assertEqual(
        #{
            target => {syndrome_z, 2, 2},
            delivery => cast,
            messages => [#phenom_config{
                seed = 36,
                threshold = ?EXERCISE_THRESHOLD
            }]
        },
        lists:last(Startup)
    ).

family_startup_targets_are_bounded_and_typed_test() ->
    Spec = phi_noise_topology:topology(),
    [{{data_even, 0, 0}, Messages} | Rest] = maps:get(startup, Spec),
    ?assertError(
        {invalid_family_instance, {data_even, 3, 0}, [3, 3]},
        hls_topology:normalize(Spec#{
            startup := [{{data_even, 3, 0}, Messages} | Rest]
        })
    ),
    ?assertError(
        {incompatible_startup_schema,
            {data_even, 0, 0},
            0,
            phenom_request,
            [phenom_config, phenom_query]},
        hls_topology:normalize(Spec#{
            startup := [
                {{data_even, 0, 0}, [#phenom_request{step = 0}]}
                | Rest
            ]
        })
    ).

distance_changes_bounds_and_startup_not_route_rules_test() ->
    Small = phi_noise_topology:topology(3),
    Large = phi_noise_topology:topology(5),
    ?assertEqual(
        maps:get(route_relations, Small),
        maps:get(route_relations, Large)
    ),
    ?assertEqual(36, length(maps:get(startup, Small))),
    ?assertEqual(100, length(maps:get(startup, Large))),
    maps:foreach(
        fun(_Family, #{shape := Shape}) -> ?assertEqual([5, 5], Shape) end,
        maps:get(families, Large)
    ).

explicit_startup_witness_has_a_practical_bound_test() ->
    ?assertError(badarg, phi_noise_topology:topology(0)),
    ?assertEqual(10000, length(maps:get(
        startup,
        phi_noise_topology:topology(50)
    ))),
    ?assertError(badarg, phi_noise_topology:topology(51)).

family_module(Family, Families) ->
    maps:get(module, maps:get(Family, Families)).

assert_distinct_reciprocal_edges(Plan, Family, Coordinates) ->
    Source = list_to_tuple([Family | Coordinates]),
    Destinations = [
        begin
            [{actor, Destination}] = recipients(
                Plan,
                Family,
                Coordinates,
                Port
            ),
            [DestinationFamily | DestinationCoordinates] =
                tuple_to_list(Destination),
            ?assert(lists:member(
                {actor, Source},
                recipients(
                    Plan,
                    DestinationFamily,
                    DestinationCoordinates,
                    opposite(Port)
                )
            )),
            Destination
        end
        || Port <- directions()
    ],
    ?assertEqual(4, length(lists:usort(Destinations))).

assert_cardinal_destinations(Plan, Family, Coordinates, Expected) ->
    Actual = cardinal_destinations(Plan, Family, Coordinates),
    ?assertEqual(Expected, Actual).

cardinal_destinations(Plan, Family, Coordinates) ->
    [
        begin
            [{actor, Destination}] = recipients(
                Plan, Family, Coordinates, Port
            ),
            Destination
        end
        || Port <- directions()
    ].

assert_announcement_fanout(
    Plan,
    Family,
    Coordinates,
    Phi,
    External
) ->
    Route = route(Plan, Family, Coordinates, phi),
    ?assertEqual(queued, maps:get(delivery, Route)),
    ?assertEqual(
        lists:sort([{actor, Phi}, {external, External}]),
        lists:sort(maps:get(recipients, Route))
    ).

recipients(Plan, Family, Coordinates, Port) ->
    maps:get(recipients, route(Plan, Family, Coordinates, Port)).

route(Plan, Family, Coordinates, Port) ->
    [Route] = [
        Candidate
        || Candidate <- hls_topology:routes_for_instance(
            Plan,
            Family,
            Coordinates
        ),
           element(2, maps:get(source, Candidate)) =:= Port
    ],
    Route.

coordinates(Distance) ->
    [
        [X, Y]
        || X <- lists:seq(0, Distance - 1),
           Y <- lists:seq(0, Distance - 1)
    ].

directions() -> [north, east, west, south].

opposite(north) -> south;
opposite(east) -> west;
opposite(west) -> east;
opposite(south) -> north.

count_value(Value, Values) ->
    length([ok || Candidate <- Values, Candidate =:= Value]).
