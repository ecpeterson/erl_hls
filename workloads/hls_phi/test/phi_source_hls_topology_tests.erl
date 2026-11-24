-module(phi_source_hls_topology_tests).

-include_lib("eunit/include/eunit.hrl").

%% Checks phi phenom topology normalizes for the retained Phi application.
-spec phi_phenom_topology_normalizes_test() -> ok.
phi_phenom_topology_normalizes_test() ->
    Plan = hls_topology:from_module(phi_phenom_topology),
    ?assertEqual(
        [data, phi, syndrome],
        [maps:get(id, Actor) || Actor <- maps:get(actors, Plan)]
    ),
    ?assertEqual(17, length(maps:get(routes, Plan))),
    ?assertEqual(
        [
            #{
                id => announcement,
                direction => out,
                schemas => [phenom_anyon]
            },
            #{
                id => data_measurements,
                direction => out,
                schemas => [pauli_reply]
            },
            #{
                id => decoder_events,
                direction => out,
                schemas => [phi_correction, phi_status]
            }
        ],
        maps:get(externals, Plan)
    ),
    ?assertEqual(
        #{
            source => {syndrome, phi},
            delivery => queued,
            recipients => [{actor, phi}, {external, announcement}]
        },
        route(Plan, {syndrome, phi})
    ),
    ?assertEqual(
        #{
            source => {phi, correction},
            delivery => direct,
            recipients => [{external, decoder_events}]
        },
        route(Plan, {phi, correction})
    ),
    ?assertEqual(
        #{
            source => {phi, status},
            delivery => direct,
            recipients => [{external, decoder_events}]
        },
        route(Plan, {phi, status})
    ),
    ?assertEqual(
        #{
            source => {data, measurement},
            delivery => direct,
            recipients => [{external, data_measurements}]
        },
        route(Plan, {data, measurement})
    ),
    ?assertEqual(
        [data, phi, syndrome],
        [maps:get(target, Item) || Item <- maps:get(startup, Plan)]
    ).

%% Checks all outputs and aliased lanes are explicit for the retained Phi application.
-spec all_outputs_and_aliased_lanes_are_explicit_test() -> ok.
all_outputs_and_aliased_lanes_are_explicit_test() ->
    Plan = hls_topology:from_module(phi_phenom_topology),
    Outputs = lists:sort([
        {maps:get(id, Actor), Port}
        || Actor <- maps:get(actors, Plan),
           Port <- maps:get(outputs, Actor)
    ]),
    ?assertEqual(
        Outputs,
        [maps:get(source, Route) || Route <- maps:get(routes, Plan)]
    ),
    ?assertEqual(
        #{
            source => phi,
            destination => {actor, phi},
            source_ports => [east, north, south, west]
        },
        lane(Plan, phi, {actor, phi})
    ).

%% Checks actor output abi order is preserved for the retained Phi application.
-spec actor_output_abi_order_is_preserved_test() -> ok.
actor_output_abi_order_is_preserved_test() ->
    Plan = hls_topology:from_module(phi_phenom_topology),
    Phi = hd([
        Actor
        || Actor <- maps:get(actors, Plan),
           maps:get(id, Actor) =:= phi
    ]),
    ?assertEqual(
        [north, east, west, south, syndrome, correction, status],
        maps:get(outputs, Phi)
    ).

%% Checks generated topology is deterministic for the retained Phi application.
-spec generated_topology_is_deterministic_test() -> ok.
generated_topology_is_deterministic_test() ->
    Spec = phi_phenom_topology:topology(),
    Reordered = Spec#{
        externals := lists:reverse(maps:get(externals, Spec)),
        routes := lists:reverse(maps:get(routes, Spec)),
        startup := lists:reverse(maps:get(startup, Spec))
    },
    Profile = phi_phenom_topology_dslx:profile(),
    Forward = iolist_to_binary(xls_topology_dslx:emit(
        hls_topology:normalize(Spec),
        Profile
    )),
    Reverse = iolist_to_binary(xls_topology_dslx:emit(
        hls_topology:normalize(Reordered),
        Profile
    )),
    ?assertEqual(Forward, Reverse),
    ?assertEqual(Forward, iolist_to_binary(
        phi_phenom_topology_dslx:to_dslx()
    )).

%% Checks generated topology has expected physical shape for the retained Phi application.
-spec generated_topology_has_expected_physical_shape_test() -> ok.
generated_topology_has_expected_physical_shape_test() ->
    Generated = iolist_to_binary(phi_phenom_topology_dslx:to_dslx()),
    ?assertEqual(3, count(Generated, <<"::Service(">>)),
    ?assertEqual(3, count(Generated, <<"proc ActorIngress">>)),
    ?assertEqual(3, count(Generated, <<"spawn ActorIngress">>)),
    ?assertEqual(3, count(Generated, <<"proc ActorRouter">>)),
    ?assertEqual(3, count(Generated, <<"spawn ActorRouter">>)),
    ?assertEqual(1, count(Generated, <<"::Egress, u32:3>">>)),
    ?assertEqual(2, count(Generated, <<"::Egress, u32:4>">>)),
    %% All four aliased source ports select one ordered send to syndrome.
    ?assertEqual(1, count(Generated, <<
        "effect.port == phenom_data_cell::OutputPort::NORTH || "
        "effect.port == phenom_data_cell::OutputPort::EAST || "
        "effect.port == phenom_data_cell::OutputPort::WEST || "
        "effect.port == phenom_data_cell::OutputPort::SOUTH"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated,
        <<"uN[96]:0x00000000800000009E3779B9">>)),
    ?assertNotEqual(nomatch, binary:match(Generated,
        <<"uN[96]:0x000000008000000085EBCA6B">>)),
    ?assertNotEqual(nomatch, binary:match(Generated,
        <<"axis::pack(u8:12, u32:0x6D2B79F5)">>)).

%% Checks generated startup preserves per actor message order for the retained Phi application.
-spec generated_startup_preserves_per_actor_message_order_test() -> ok.
generated_startup_preserves_per_actor_message_order_test() ->
    Spec = phi_phenom_topology:topology(),
    Plan = hls_topology:normalize(Spec#{startup := [
        {data, [
            {phenom_config, 1, 2, 3, 4},
            {phenom_config, 5, 6, 7, 8}
        ]}
    ]}),
    Generated = iolist_to_binary(xls_topology_dslx:emit(
        Plan,
        phi_phenom_topology_dslx:profile()
    )),
    {First, _} = binary:match(
        Generated,
        <<"u32:0 => axis::pack(u8:6, "
          "uN[96]:0x000400030000000200000001)">>
    ),
    {Second, _} = binary:match(
        Generated,
        <<"u32:1 => axis::pack(u8:6, "
          "uN[96]:0x000800070000000600000005)">>
    ),
    ?assert(First < Second),
    ?assertNotEqual(nomatch, binary:match(Generated,
        <<"} else if state.2 < u32:2 {">>)).

%% Checks generated startup and routed receive both require admission for the retained Phi application.
-spec generated_startup_and_routed_receive_both_require_admission_test() -> ok.
generated_startup_and_routed_receive_both_require_admission_test() ->
    Generated = iolist_to_binary(phi_phenom_topology_dslx:to_dslx()),
    [_Preamble | Procs] = binary:split(Generated, <<"proc ActorIngress">>, [global]),
    ?assertEqual(3, length(Procs)),
    lists:foreach(fun(Proc) ->
        {Admission, _} = binary:match(Proc, <<"recv(join(), admission_in)">>),
        {Startup, _} = binary:match(Proc, <<"} else if state.2 < u32:1 {">>),
        {Routed, _} = binary:match(Proc, <<"frame_in[candidate]">>),
        ?assert(Admission < Startup),
        ?assert(Startup < Routed)
    end, Procs).

%% Checks generated topology matches checked in artifact for the retained Phi application.
-spec generated_topology_matches_checked_in_artifact_test() -> ok.
generated_topology_matches_checked_in_artifact_test() ->
    {ok, Expected} = file:read_file(
        "workloads/hls_phi/src/phi_phenom_topology.x"
    ),
    Generated = iolist_to_binary(phi_phenom_topology_dslx:to_dslx()),
    ?assertEqual(Expected, Generated).

%% Checks dslx backend accepts nonaliased graph for the retained Phi application.
-spec dslx_backend_accepts_nonaliased_graph_test() -> ok.
dslx_backend_accepts_nonaliased_graph_test() ->
    Plan = hls_topology:normalize(nonaliased_phi_pair()),
    Profile = (phi_phenom_topology_dslx:profile())#{
        name := nonaliased_phi_pair
    },
    Generated = iolist_to_binary(xls_topology_dslx:emit(Plan, Profile)),
    ?assertEqual(1, count(Generated, <<"spawn phi_halo_cell::Service(">>)),
    ?assertEqual(
        1,
        count(Generated, <<"spawn phenom_syndrome_cell::Service(">>)
    ),
    ?assertEqual(
        nomatch,
        binary:match(Generated, <<"Aliased-port lanes permitted">>)
    ).

%% Checks dslx backend supports aliased external lane for the retained Phi application.
-spec dslx_backend_supports_aliased_external_lane_test() -> ok.
dslx_backend_supports_aliased_external_lane_test() ->
    Spec = phi_phenom_topology:topology(),
    Routes = [
        case Route of
            {{phi, north}, _} ->
                {{phi, north}, [{external, announcement}]};
            {{phi, east}, _} ->
                {{phi, east}, [{external, announcement}]};
            _ -> Route
        end
        || Route <- maps:get(routes, Spec)
    ],
    Plan = hls_topology:normalize(Spec#{
        externals := [
            {announcement, out, [
                anyon_move,
                phi,
                phi0,
                phenom_anyon
            ]},
            {data_measurements, out, [pauli_reply]},
            {decoder_events, out, [phi_correction, phi_status]}
        ],
        routes := Routes
    }),
    Generated = iolist_to_binary(xls_topology_dslx:emit(
        Plan,
        phi_phenom_topology_dslx:profile()
    )),
    ?assertEqual(
        [east, north],
        maps:get(source_ports, lane(Plan, phi, {external, announcement}))
    ),
    ?assertNotEqual(nomatch, binary:match(Generated, <<"proc ActorRouter">>)).

%% Checks dslx backend supports startup only actor for the retained Phi application.
-spec dslx_backend_supports_startup_only_actor_test() -> ok.
dslx_backend_supports_startup_only_actor_test() ->
    Spec = phi_phenom_topology:topology(),
    Actors = maps:get(actors, Spec),
    Directions = [north, east, west, south],
    Routes = [
        case Route of
            {Source = {syndrome, Port}, _Recipients} ->
                case lists:member(Port, Directions) of
                    true -> {Source, [{actor, data2}]};
                    false -> Route
                end;
            _ -> Route
        end
        || Route <- maps:get(routes, Spec)
    ],
    Data2Routes = [
        {{data2, Port}, [{actor, syndrome}]}
        || Port <- Directions
    ] ++ [
        {{data2, measurement}, [{external, data_measurements}]}
    ],
    [DataStartup] = [
        Messages
        || {data, Messages} <- maps:get(startup, Spec)
    ],
    Plan = hls_topology:normalize(Spec#{
        actors := Actors#{data2 => phenom_data_cell},
        routes := Routes ++ Data2Routes,
        startup := maps:get(startup, Spec) ++ [{data2, DataStartup}]
    }),
    Generated = iolist_to_binary(xls_topology_dslx:emit(
        Plan, phi_phenom_topology_dslx:profile())),
    ?assertEqual(4, count(Generated, <<"::Service(">>)),
    ?assertNotEqual(nomatch, binary:match(Generated,
        <<"spawn ActorIngress0(actor_0_req_p, actor_0_admit_c)">>)).

%% Finds the actual application route by source or output port.
-spec route(map() | [map()], term()) -> map().
route(Plan, Source) ->
    hd([
        Route
        || Route <- maps:get(routes, Plan),
           maps:get(source, Route) =:= Source
    ]).

%% Finds the ordered source/destination lane in the application plan.
-spec lane(map(), term(), term()) -> map().
lane(Plan, Source, Destination) ->
    hd([
        Lane
        || Lane <- maps:get(lanes, Plan),
           maps:get(source, Lane) =:= Source,
           maps:get(destination, Lane) =:= Destination
    ]).

%% Separates Phi directional boundaries to exercise the unchanged application schemas.
-spec nonaliased_phi_pair() -> hls_topology:spec().
nonaliased_phi_pair() ->
    Directions = [north, east, west, south],
    PhiExternalIds = #{
        north => phi_north,
        east => phi_east,
        west => phi_west,
        south => phi_south
    },
    QueryExternalIds = #{
        north => query_north,
        east => query_east,
        west => query_west,
        south => query_south
    },
    PhiExternals = [
        {maps:get(Port, PhiExternalIds), out, [anyon_move, phi, phi0]}
        || Port <- Directions
    ],
    QueryExternals = [
        {maps:get(Port, QueryExternalIds), out, [phenom_query]}
        || Port <- Directions
    ],
    #{
        version => 1,
        ingresses => [],
        actors => #{
            phi => phi_halo_cell,
            syndrome => phenom_syndrome_cell
        },
        families => #{},
        externals =>
            PhiExternals ++ QueryExternals ++
            [
                {decoder_events, out, [phi_correction, phi_status]},
                {announcement, out, [phenom_anyon]}
            ],
        routes =>
            [
                {{phi, Port}, [{external, maps:get(Port, PhiExternalIds)}]}
                || Port <- Directions
            ] ++
            [
                {{phi, syndrome}, [{actor, syndrome}]},
                {{phi, correction}, [{external, decoder_events}]},
                {{phi, status}, [{external, decoder_events}]}
            ] ++
            [
                {{syndrome, Port}, [
                    {external, maps:get(Port, QueryExternalIds)}
                ]}
                || Port <- Directions
            ] ++
            [
                {{syndrome, phi}, queued, [
                    {actor, phi},
                    {external, announcement}
                ]}
            ],
        route_relations => [],
        startup => []
    }.

%% Counts exact fragments in the generated application source.
-spec count(binary(), binary()) -> non_neg_integer().
count(Binary, Pattern) -> length(binary:matches(Binary, Pattern)).
