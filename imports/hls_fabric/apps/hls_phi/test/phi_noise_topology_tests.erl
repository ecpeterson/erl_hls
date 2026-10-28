-module(phi_noise_topology_tests).

-include_lib("eunit/include/eunit.hrl").
-include("phi_protocol.hrl").

-define(DISTANCE, 3).
-define(EXERCISE_RATE, 16#80000000).
-define(SEED_STRIDE, 16#9e3779b9).
-define(U32_MASK, 16#ffffffff).

%% The six roles in the phenomenological-noise witness topology.
-type family() :: data_even | data_odd | phi_x | phi_z | syndrome_x | syndrome_z.
%% One logical member of a two-dimensional witness family.
-type instance() :: {family(), non_neg_integer(), non_neg_integer()}.
%% Named ports for nearest-neighbor connections on the periodic grid.
-type direction() :: north | east | west | south.
%% Actor or external boundary reached by a resolved witness route.
-type recipient() :: {actor, instance()} | {external, atom()}.

%% The default distance-three graph retains six families and its three output boundaries.
-spec default_topology_has_six_bounded_families_test() -> ok.
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
    ?assertEqual(34, length(maps:get(route_relations, Spec))),
    ?assertEqual(
        [
            {x_decoder_events, out, [phi_correction, phi_status]},
            {z_decoder_events, out, [phi_correction, phi_status]},
            {data_measurements, out, [pauli_reply]}
        ],
        maps:get(externals, Spec)
    ).

%% Normalized control targets preserve the even/odd physical-coordinate embeddings.
-spec normalized_control_router_embeds_the_physical_checkerboard_test() -> ok.
normalized_control_router_embeds_the_physical_checkerboard_test() ->
    Plan = hls_topology:from_module(phi_noise_topology),
    ?assertEqual(
        [#{
            id => control_router,
            kind => rectangle,
            shape => [?DISTANCE, 2 * ?DISTANCE],
            targets => [
                #{
                    id => data,
                    schemas => [pauli_query, pauli_update],
                    recipients => [
                        #{
                            family => data_even,
                            scale => [1, 2],
                            offset => [0, 0]
                        },
                        #{
                            family => data_odd,
                            scale => [1, 2],
                            offset => [0, 1]
                        }
                    ]
                },
                #{
                    id => noise,
                    schemas => [noise_cutoff],
                    recipients => [
                        #{
                            family => data_even,
                            scale => [1, 2],
                            offset => [0, 0]
                        },
                        #{
                            family => data_odd,
                            scale => [1, 2],
                            offset => [0, 1]
                        },
                        #{
                            family => syndrome_x,
                            scale => [1, 2],
                            offset => [0, 0]
                        },
                        #{
                            family => syndrome_z,
                            scale => [1, 2],
                            offset => [0, 0]
                        }
                    ]
                }
            ]
        }],
        maps:get(ingresses, Plan)
    ).

%% A family cannot acquire conflicting embeddings through targets of one ingress.
-spec one_ingress_requires_consistent_family_embedding_test() -> ok.
one_ingress_requires_consistent_family_embedding_test() ->
    Spec = phi_noise_topology:topology(1),
    [{control_router, Rectangle, Targets}] = maps:get(ingresses, Spec),
    ChangedTargets = [
        case Target of
            {noise, Schemas, Recipients} ->
                {noise, Schemas, [
                    case Recipient of
                        {family, data_even, {embed, _Scale, Offset}} ->
                            {family, data_even, {embed, [1, 1], Offset}};
                        _ -> Recipient
                    end
                    || Recipient <- Recipients
                ]};
            _ -> Target
        end
        || Target <- Targets
    ],
    ?assertError(
        {ingress_embeddings, control_router, data_even, [
            {[1, 1], [0, 0]},
            {[1, 2], [0, 0]}
        ]},
        hls_topology:normalize(Spec#{
            ingresses := [{control_router, Rectangle, ChangedTargets}]
        })
    ).

%% Even singleton families must use an embedding scale valid for the ingress domain.
-spec singleton_family_scale_must_fit_the_address_domain_test() -> ok.
singleton_family_scale_must_fit_the_address_domain_test() ->
    Spec = phi_noise_topology:topology(1),
    [{control_router, Rectangle, Targets}] = maps:get(ingresses, Spec),
    ChangedTargets = [
        {TargetId, Schemas, [
            case Recipient of
                {family, data_even, {embed, _Scale, Offset}} ->
                    {family, data_even, {embed, [2, 2], Offset}};
                _ -> Recipient
            end
            || Recipient <- Recipients
        ]}
        || {TargetId, Schemas, Recipients} <- Targets
    ],
    ?assertError(
        {ingress_embedding, data_even, [1, 1], [2, 2], [0, 0], [1, 2]},
        hls_topology:normalize(Spec#{
            ingresses := [{control_router, Rectangle, ChangedTargets}]
        })
    ).

%% Each family binds the decoder, syndrome or data actor matching its protocol role.
-spec family_modules_match_protocol_roles_test() -> ok.
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

%% Every distance-three family member has four distinct neighbors with reciprocal routes.
-spec default_mesh_has_distinct_reciprocal_cardinal_edges_test() -> ok.
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

%% Check concrete wrapped neighbors where syndrome and data families cross boundaries.
-spec wrapped_cross_family_boundary_routes_test() -> ok.
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

%% Each distance-three data instance is incident on two X and two Z checks.
-spec each_data_qubit_touches_two_checks_of_each_plane_test() -> ok.
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

%% Both data families publish replies through the same logical measurement boundary.
-spec data_measurement_boundary_hides_family_split_test() -> ok.
data_measurement_boundary_hides_family_split_test() ->
    Plan = hls_topology:from_module(phi_noise_topology),
    lists:foreach(
        fun({Family, X, Y}) ->
            ?assertEqual(
                [{external, data_measurements}],
                recipients(Plan, Family, [X, Y], measurement)
            )
        end,
        [
            {Family, X, Y}
            || Family <- [data_even, data_odd],
               [X, Y] <- coordinates(?DISTANCE)
        ]
    ).

%% Enumerate distance-three X/Z neighborhoods and check their zero-or-two overlap.
-spec x_and_z_checks_overlap_on_zero_or_two_data_qubits_test() -> ok.
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

%% Decoder and syndrome partners keep coordinates and the selected plane output boundary.
-spec phi_and_syndrome_pairs_share_coordinates_test() -> ok.
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
            ?assertEqual(
                [{external, x_decoder_events}],
                recipients(Plan, phi_x, Coordinates, correction)
            ),
            ?assertEqual(
                [{external, z_decoder_events}],
                recipients(Plan, phi_z, Coordinates, correction)
            ),
            ?assertEqual(
                [{external, x_decoder_events}],
                recipients(Plan, phi_x, Coordinates, status)
            ),
            ?assertEqual(
                [{external, z_decoder_events}],
                recipients(Plan, phi_z, Coordinates, status)
            ),
            assert_phi_delivery(
                Plan, syndrome_x, Coordinates, {phi_x, X, Y}
            ),
            assert_phi_delivery(
                Plan, syndrome_z, Coordinates, {phi_z, X, Y}
            )
        end,
        coordinates(?DISTANCE)
    ).

%% Default startup seeds are distinct, nonzero and produce both first-event outcomes.
-spec startup_is_explicit_distinct_and_nonzero_test() -> ok.
startup_is_explicit_distinct_and_nonzero_test() ->
    Spec = phi_noise_topology:topology(),
    Startup = maps:get(startup, Spec),
    ?assertEqual(6 * ?DISTANCE * ?DISTANCE, length(Startup)),
    Seeds = [
        startup_seed(Item) || Item <- Startup
    ],
    ?assertEqual(
        [data_even, data_odd, phi_x, phi_z, syndrome_x, syndrome_z],
        lists:usort([Family || {{Family, _, _}, [_]} <- Startup])
    ),
    ?assertEqual(length(Seeds), length(lists:usort(Seeds))),
    NoiseSeeds = [
        Seed
        || {{Family, _, _}, [#phenom_config{seed = Seed}]} <- Startup,
           lists:member(Family, [
               data_even,
               data_odd,
               syndrome_x,
               syndrome_z
           ])
    ],
    FirstEvents = [hls_prng:xorshift32(Seed) < ?EXERCISE_RATE
        || Seed <- NoiseSeeds],
    ?assert(lists:member(true, FirstEvents)),
    ?assert(lists:member(false, FirstEvents)).

%% Both distance-three syndrome planes contain zero and one first-step announcements.
-spec first_step_syndrome_fixture_is_spatially_nonuniform_test() -> ok.
first_step_syndrome_fixture_is_spatially_nonuniform_test() ->
    Spec = phi_noise_topology:topology(),
    Plan = hls_topology:normalize(Spec),
    Events = maps:from_list([
        {Target, first_event(Config)}
        || {Target, [Config = #phenom_config{}]} <- maps:get(startup, Spec)
    ]),
    lists:foreach(
        fun(SyndromeFamily) ->
            Announcements = [
                syndrome_event(
                    Plan,
                    Events,
                    SyndromeFamily,
                    Coordinates
                )
                || Coordinates <- coordinates(?DISTANCE)
            ],
            ?assertEqual([0, 1], lists:usort(Announcements))
        end,
        [syndrome_x, syndrome_z]
    ).

%% Normalization retains explicit startup targets and coalesced decoder output lanes.
-spec normalized_startup_retains_family_instance_targets_test() -> ok.
normalized_startup_retains_family_instance_targets_test() ->
    Plan = hls_topology:from_module(phi_noise_topology),
    Startup = maps:get(startup, Plan),
    ?assertEqual(54, length(Startup)),
    Lanes = maps:get(lane_relations, Plan),
    ?assertEqual(32, length(Lanes)),
    ?assertEqual(
        [
            #{
                source => phi_x,
                destination => {external, x_decoder_events},
                source_ports => [correction, status]
            },
            #{
                source => phi_z,
                destination => {external, z_decoder_events},
                source_ports => [correction, status]
            }
        ],
        [Lane || Lane = #{source_ports := [_, _ | _]} <- Lanes]
    ),
    ?assert(lists:member(
        #{
            target => {phi_z, 2, 2},
            delivery => cast,
            messages => [#phi_config{
                seed = (54 * ?SEED_STRIDE) band ?U32_MASK
            }]
        },
        Startup
    )),
    ?assertEqual(
        #{
            target => {syndrome_z, 2, 2},
            delivery => cast,
            messages => [#phenom_config{
                seed = (36 * ?SEED_STRIDE) band ?U32_MASK,
                threshold = ?EXERCISE_RATE,
                x = 2,
                y = 2
            }]
        },
        lists:last(Startup)
    ).

%% Reject startup messages with out-of-bounds recipients or unsupported record schemas.
-spec family_startup_targets_are_bounded_and_typed_test() -> ok.
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
            [noise_cutoff, pauli_query, pauli_update,
                phenom_config, phenom_query]},
        hls_topology:normalize(Spec#{
            startup := [
                {{data_even, 0, 0}, [#phenom_request{step = 0}]}
                | Rest
            ]
        })
    ).

%% A zero cutoff reaches all noise actors while preserving decoder configuration targets.
-spec explicit_noise_rate_changes_only_phenomenological_startup_test() -> ok.
explicit_noise_rate_changes_only_phenomenological_startup_test() ->
    Default = maps:get(startup, phi_noise_topology:topology(1)),
    Quiet = maps:get(startup, phi_noise_topology:topology(1, 0)),
    ?assertEqual(
        [Target || {Target, [#phi_config{}]} <- Default],
        [Target || {Target, [#phi_config{}]} <- Quiet]
    ),
    ?assertEqual(
        4,
        length([
            ok
            || {_Target, [#phenom_config{threshold = 0}]} <- Quiet
        ])
    ),
    ?assertError(badarg, phi_noise_topology:topology(1, -1)),
    ?assertError(badarg, phi_noise_topology:topology(1, 16#100000000)).

%% Distances three and five share compact route rules while expanding shapes and startup.
-spec distance_changes_bounds_and_startup_not_route_rules_test() -> ok.
distance_changes_bounds_and_startup_not_route_rules_test() ->
    Small = phi_noise_topology:topology(3),
    Large = phi_noise_topology:topology(5),
    ?assertEqual(
        maps:get(route_relations, Small),
        maps:get(route_relations, Large)
    ),
    ?assertEqual(54, length(maps:get(startup, Small))),
    ?assertEqual(150, length(maps:get(startup, Large))),
    maps:foreach(
        fun(_Family, #{shape := Shape}) -> ?assertEqual([5, 5], Shape) end,
        maps:get(families, Large)
    ).

%% Check the explicit startup cap at distances zero, fifty and fifty-one.
-spec explicit_startup_witness_has_a_practical_bound_test() -> ok.
explicit_startup_witness_has_a_practical_bound_test() ->
    ?assertError(badarg, phi_noise_topology:topology(0)),
    ?assertEqual(15000, length(maps:get(
        startup,
        phi_noise_topology:topology(50)
    ))),
    ?assertError(badarg, phi_noise_topology:topology(51)).

%% Read the actor module from one unnormalized family declaration.
-spec family_module(
    family(), #{family() => #{module := module(), shape := [pos_integer()]}}
) -> module().
family_module(Family, Families) ->
    maps:get(module, maps:get(Family, Families)).

%% Require four distinct destinations and a reverse route on each opposite port.
-spec assert_distinct_reciprocal_edges(hls_topology:plan(), family(), [non_neg_integer()]) -> ok.
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

%% Compare the four resolved neighbors in the established port order.
-spec assert_cardinal_destinations(hls_topology:plan(), family(), [non_neg_integer()],
    [instance()]) -> ok.
assert_cardinal_destinations(Plan, Family, Coordinates, Expected) ->
    Actual = cardinal_destinations(Plan, Family, Coordinates),
    ?assertEqual(Expected, Actual).

%% Resolve one actor destination for each cardinal port, rejecting other route shapes.
-spec cardinal_destinations(hls_topology:plan(), family(), [non_neg_integer()]) -> [instance()].
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

%% Require a direct syndrome announcement to the expected paired decoder instance.
-spec assert_phi_delivery(hls_topology:plan(), family(), [non_neg_integer()], instance()) -> ok.
assert_phi_delivery(Plan, Family, Coordinates, Phi) ->
    Route = route(Plan, Family, Coordinates, phi),
    ?assertEqual(direct, maps:get(delivery, Route)),
    ?assertEqual([{actor, Phi}], maps:get(recipients, Route)).

%% Read the recipients of the unique selected output route.
-spec recipients(hls_topology:plan(), family(), [non_neg_integer()], atom()) -> [recipient()].
recipients(Plan, Family, Coordinates, Port) ->
    maps:get(recipients, route(Plan, Family, Coordinates, Port)).

%% Resolve a family member and require exactly one route for the requested output port.
-spec route(hls_topology:plan(), family(), [non_neg_integer()], atom()) ->
    #{source := {instance(), atom()}, delivery := atom(), recipients := [recipient()]}.
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

%% Enumerate the zero-based coordinates of one square family.
-spec coordinates(pos_integer()) -> [[non_neg_integer()]].
coordinates(Distance) ->
    [
        [X, Y]
        || X <- lists:seq(0, Distance - 1),
           Y <- lists:seq(0, Distance - 1)
    ].

%% Return the cardinal-port order used by concrete neighborhood expectations.
-spec directions() -> [direction()].
directions() -> [north, east, west, south].

%% Select the port used by the reciprocal edge of a cardinal connection.
-spec opposite(direction()) -> direction().
opposite(north) -> south;
opposite(east) -> west;
opposite(west) -> east;
opposite(south) -> north.

%% Count exact occurrences in a finite comparison list.
-spec count_value(term(), [term()]) -> non_neg_integer().
count_value(Value, Values) ->
    length([ok || Candidate <- Values, Candidate =:= Value]).

%% Validate the default configuration and return its nonzero deterministic seed.
-spec startup_seed({instance(), [#phenom_config{} | #phi_config{}]}) -> 1..((1 bsl 32) - 1).
startup_seed({{Family, X, Y}, [#phenom_config{
    seed = Seed,
    threshold = Threshold,
    x = ConfigX,
    y = ConfigY
}]}) ->
    ?assert(lists:member(Family, [
        data_even,
        data_odd,
        syndrome_x,
        syndrome_z
    ])),
    assert_startup_coordinates(X, Y),
    ?assertEqual(?EXERCISE_RATE, Threshold),
    ?assertEqual(X, ConfigX),
    ?assertEqual(configured_y(Family, Y), ConfigY),
    ?assert(Seed > 0),
    Seed;
startup_seed({{Family, X, Y}, [#phi_config{seed = Seed}]}) ->
    ?assert(lists:member(Family, [phi_x, phi_z])),
    assert_startup_coordinates(X, Y),
    ?assert(Seed > 0),
    Seed.

%% Map a family row to its physical data row or unchanged syndrome coordinate.
-spec configured_y(
    data_even | data_odd | syndrome_x | syndrome_z, non_neg_integer()
) -> non_neg_integer().
configured_y(data_even, Y) -> 2 * Y;
configured_y(data_odd, Y) -> 2 * Y + 1;
configured_y(syndrome_x, Y) -> Y;
configured_y(syndrome_z, Y) -> Y.

%% Require startup coordinates to lie inside the default distance-three family.
-spec assert_startup_coordinates(non_neg_integer(), non_neg_integer()) -> ok.
assert_startup_coordinates(X, Y) ->
    ?assert(X >= 0 andalso X < ?DISTANCE),
    ?assert(Y >= 0 andalso Y < ?DISTANCE).

%% Compute the first Bernoulli event from a noise configuration.
-spec first_event(#phenom_config{}) -> 0 | 1.
first_event(#phenom_config{seed = Seed, threshold = Threshold}) ->
    case hls_prng:xorshift32(Seed) < Threshold of
        true -> 1;
        false -> 0
    end.

%% XOR the local measurement event with all four incident data events.
-spec syndrome_event(hls_topology:plan(), #{instance() => 0 | 1}, family(),
    [non_neg_integer()]) -> 0 | 1.
syndrome_event(Plan, Events, Family, Coordinates) ->
    Measurement = maps:get(
        list_to_tuple([Family | Coordinates]),
        Events
    ),
    lists:foldl(
        fun(Data, Parity) -> Parity bxor maps:get(Data, Events) end,
        Measurement,
        cardinal_destinations(Plan, Family, Coordinates)
    ).
