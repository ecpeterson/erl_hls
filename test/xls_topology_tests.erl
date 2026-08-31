-module(xls_topology_tests).

-include_lib("eunit/include/eunit.hrl").

phi_phenom_topology_normalizes_test() ->
    Plan = xls_topology:from_module(phi_phenom_topology),
    ?assertEqual(
        [data, phi, syndrome],
        [maps:get(id, Actor) || Actor <- maps:get(actors, Plan)]
    ),
    ?assertEqual(14, length(maps:get(routes, Plan))),
    ?assertEqual(
        [#{id => announcement, direction => out, schemas => [phenom_anyon]}],
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
        [data, syndrome],
        [maps:get(target, Item) || Item <- maps:get(startup, Plan)]
    ).

all_outputs_and_aliased_lanes_are_explicit_test() ->
    Plan = xls_topology:from_module(phi_phenom_topology),
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

unordered_sections_normalize_identically_test() ->
    Spec = phi_phenom_topology:topology(),
    Reordered = Spec#{
        externals := lists:reverse(maps:get(externals, Spec)),
        routes := lists:reverse(maps:get(routes, Spec)),
        startup := lists:reverse(maps:get(startup, Spec))
    },
    ?assertEqual(
        xls_topology:normalize(Spec),
        xls_topology:normalize(Reordered)
    ).

startup_order_is_local_to_each_actor_test() ->
    Spec = phi_phenom_topology:topology(),
    Forward = xls_topology:normalize(Spec#{
        startup := [{data, [first, second]}]
    }),
    Reverse = xls_topology:normalize(Spec#{
        startup := [{data, [second, first]}]
    }),
    ?assertNotEqual(maps:get(startup, Forward), maps:get(startup, Reverse)).

actor_dictionary_is_required_test() ->
    Spec = phi_phenom_topology:topology(),
    Actors = maps:get(actors, Spec),
    ActorList = maps:to_list(Actors),
    ?assertError(
        {invalid_topology_field, actors, ActorList},
        xls_topology:normalize(Spec#{actors := ActorList})
    ).

invalid_actor_ids_are_rejected_test() ->
    Spec = phi_phenom_topology:topology(),
    Actors = maps:get(actors, Spec),
    PhiModule = maps:get(phi, Actors),
    lists:foreach(
        fun({InvalidId, InvalidPart}) ->
            InvalidActors = maps:put(
                InvalidId,
                PhiModule,
                maps:remove(phi, Actors)
            ),
            ?assertError(
                {invalid_topology_id, InvalidPart},
                xls_topology:normalize(Spec#{actors := InvalidActors})
            )
        end,
        [
            {1.0, 1.0},
            {{}, {}},
            {{phi, -1}, -1},
            {{phi, 1.0}, 1.0}
        ]
    ).

invalid_actor_module_is_rejected_test() ->
    Spec = phi_phenom_topology:topology(),
    Actors = maps:get(actors, Spec),
    ?assertError(
        {invalid_actor_module, phi, 42},
        xls_topology:normalize(Spec#{actors := Actors#{phi := 42}})
    ).

indexed_tuple_actor_ids_normalize_and_emit_without_mangling_test() ->
    Id = {phi, 17, {tile, 2, 3}},
    Spec = rename_actor_id(phi_phenom_topology:topology(), phi, Id),
    Plan = xls_topology:normalize(Spec),
    ?assert(lists:member(Id, [maps:get(id, Actor)
        || Actor <- maps:get(actors, Plan)])),
    Profile = (phi_phenom_topology_dslx:profile())#{
        name := indexed_phi_topology
    },
    Generated = iolist_to_binary(xls_topology_dslx:emit(Plan, Profile)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "{phi,17,{tile,2,3}} (phi_halo_cell)"
    >>)),
    ?assertNotEqual(nomatch, binary:match(
        Generated,
        <<"spawn phi_halo_cell::Service(\n">>
    )).

route_sources_are_checked_and_total_test() ->
    Spec = phi_phenom_topology:topology(),
    [First | Rest] = maps:get(routes, Spec),
    ?assertError(
        {unknown_actor_output, phi, up},
        xls_topology:normalize(Spec#{
            routes := [{{phi, up}, [{actor, phi}]} | Rest]
        })
    ),
    ?assertError(
        {unrouted_outputs, [{phi, north}]},
        xls_topology:normalize(Spec#{routes := Rest})
    ),
    ?assertError(
        {duplicate_route_sources, [{phi, north}]},
        xls_topology:normalize(Spec#{routes := [First, First | Rest]})
    ).

route_recipients_are_checked_and_unique_test() ->
    Spec = phi_phenom_topology:topology(),
    Source = {syndrome, phi},
    ?assertError(
        {unknown_actor, missing, {route_recipient, Source}},
        xls_topology:normalize(replace_route(
            Spec,
            Source,
            {Source, buffered, [{actor, missing}, {actor, phi}]}
        ))
    ),
    ?assertError(
        {empty_route, Source},
        xls_topology:normalize(replace_route(Spec, Source, {Source, []}))
    ),
    ?assertError(
        {duplicate_route_recipients, Source, [{actor, phi}]},
        xls_topology:normalize(replace_route(
            Spec,
            Source,
            {Source, buffered, [{actor, phi}, {actor, phi}]}
        ))
    ).

fanout_delivery_is_explicit_test() ->
    Spec = phi_phenom_topology:topology(),
    Source = {syndrome, phi},
    ?assertError(
        {fanout_delivery_required, Source},
        xls_topology:normalize(replace_route(
            Spec,
            Source,
            {Source, [{actor, phi}, {external, announcement}]}
        ))
    ),
    ?assertError(
        {invalid_fanout_delivery, Source, accidental},
        xls_topology:normalize(replace_route(
            Spec,
            Source,
            {Source, accidental, [
                {actor, phi},
                {external, announcement}
            ]}
        ))
    ).

startup_targets_are_known_and_unique_test() ->
    Spec = phi_phenom_topology:topology(),
    ?assertError(
        {unknown_actor, missing, startup},
        xls_topology:normalize(Spec#{startup := [{missing, [config]}]})
    ),
    ?assertError(
        {duplicate_startup_targets, [data]},
        xls_topology:normalize(Spec#{startup := [
            {data, [first]},
            {data, [second]}
        ]})
    ).

live_runtime_identity_is_rejected_test() ->
    Spec = phi_phenom_topology:topology(),
    ?assertError(
        {live_topology_value, pid},
        xls_topology:normalize(Spec#{startup := [{data, [self()]}]})
    ),
    ?assertError(
        {live_topology_value, reference},
        xls_topology:normalize(Spec#{startup := [{data, [make_ref()]}]})
    ).

actor_output_abi_order_is_preserved_test() ->
    Plan = xls_topology:from_module(phi_phenom_topology),
    Phi = hd([
        Actor
        || Actor <- maps:get(actors, Plan),
           maps:get(id, Actor) =:= phi
    ]),
    ?assertEqual(
        [north, east, west, south, syndrome],
        maps:get(outputs, Phi)
    ).

incompatible_actor_route_schema_is_rejected_test() ->
    Spec = phi_phenom_topology:topology(),
    Source = {phi, syndrome},
    ?assertError(
        {incompatible_route_schemas,
            Source,
            {actor, data},
            [phenom_request],
            [phenom_config, phenom_query]},
        xls_topology:normalize(replace_route(
            Spec,
            Source,
            {Source, [{actor, data}]}
        ))
    ).

incompatible_actor_route_layout_is_rejected_test() ->
    SourceFields = [#{
        name => value,
        type => {xls_type, xls_nums, u32, []}
    }],
    DestinationFields = [#{
        name => value,
        type => {xls_type, xls_nums, u64, []}
    }],
    ?assertError(
        {incompatible_route_schema_layout,
            {source, out},
            {actor, destination},
            message,
            SourceFields,
            DestinationFields},
        xls_topology:normalize(layout_fixture_topology())
    ).

incompatible_external_route_schema_is_rejected_test() ->
    Spec = phi_phenom_topology:topology(),
    ?assertError(
        {incompatible_route_schemas,
            {syndrome, phi},
            {external, announcement},
            [phenom_anyon],
            [phi]},
        xls_topology:normalize(Spec#{
            externals := [{announcement, out, [phi]}]
        })
    ).

incompatible_startup_schema_is_rejected_test() ->
    Spec = phi_phenom_topology:topology(),
    ?assertError(
        {incompatible_startup_schema,
            data,
            0,
            phenom_request,
            [phenom_config, phenom_query]},
        xls_topology:normalize(Spec#{
            startup := [{data, [{phenom_request, 0}]}]
        })
    ).

generated_topology_is_deterministic_test() ->
    Spec = phi_phenom_topology:topology(),
    Reordered = Spec#{
        externals := lists:reverse(maps:get(externals, Spec)),
        routes := lists:reverse(maps:get(routes, Spec)),
        startup := lists:reverse(maps:get(startup, Spec))
    },
    Profile = phi_phenom_topology_dslx:profile(),
    Forward = iolist_to_binary(xls_topology_dslx:emit(
        xls_topology:normalize(Spec),
        Profile
    )),
    Reverse = iolist_to_binary(xls_topology_dslx:emit(
        xls_topology:normalize(Reordered),
        Profile
    )),
    ?assertEqual(Forward, Reverse),
    ?assertEqual(Forward, iolist_to_binary(
        phi_phenom_topology_dslx:to_dslx()
    )).

generated_topology_has_expected_physical_shape_test() ->
    Generated = iolist_to_binary(phi_phenom_topology_dslx:to_dslx()),
    ?assertEqual(3, count(Generated, <<"::Service(">>)),
    ?assertEqual(3, count(Generated, <<"spawn axis::ReservedFrame(">>)),
    ?assertEqual(11, count(Generated, <<"spawn axis::FrameMux2(">>)),
    ?assertEqual(1, count(Generated, <<"spawn QueuedFanout2(">>)),
    ?assertEqual(0, count(Generated, <<"BufferedFanout">>)),
    ?assertEqual(2, count(Generated, <<"proc StartupPrefix">>)),
    ?assertEqual(2, count(Generated, <<"spawn StartupPrefix">>)),
    ?assertNotEqual(nomatch, binary:match(
        Generated,
        <<"Aliased-port lanes permitted to reorder in this fixture">>
    )),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "data (phenom_data_cell) [east,north,south,west] -> "
        "{actor,syndrome} (phenom_syndrome_cell)"
    >>)),
    ?assertNotEqual(
        nomatch,
        binary:match(Generated, <<"u64:0x800000009E3779B9">>)
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(Generated, <<"u64:0x8000000085EBCA6B">>)
    ).

generated_startup_preserves_per_actor_message_order_test() ->
    Spec = phi_phenom_topology:topology(),
    Plan = xls_topology:normalize(Spec#{startup := [
        {data, [
            {phenom_config, 1, 2},
            {phenom_config, 3, 4}
        ]}
    ]}),
    Generated = iolist_to_binary(xls_topology_dslx:emit(
        Plan,
        phi_phenom_topology_dslx:profile()
    )),
    {First, _} = binary:match(
        Generated,
        <<"u32:0 => axis::pack(u8:6, u64:0x0000000200000001)">>
    ),
    {Second, _} = binary:match(
        Generated,
        <<"u32:1 => axis::pack(u8:6, u64:0x0000000400000003)">>
    ),
    ?assert(First < Second),
    ?assertEqual(1, count(Generated, <<"recv_if(\n">>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "let starting = index < u32:2;\n"
        "    let startup_frame = match index"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "let (tok, routed_frame) = recv_if(\n"
        "      join(), routed_in, !starting, zero!<axis::Frame>());\n"
        "    let frame = if starting { startup_frame } else { routed_frame };\n"
        "    send(tok, frame_out, frame);"
    >>)).

generated_startup_prefix_precedes_routed_admission_test() ->
    Generated = iolist_to_binary(phi_phenom_topology_dslx:to_dslx()),
    {Prefix0, _} = binary:match(Generated, <<"spawn StartupPrefix0(">>),
    {Admission0, _} = binary:match(
        Generated,
        <<"spawn axis::ReservedFrame(startup_0_prefix_c">>
    ),
    {Prefix1, _} = binary:match(Generated, <<"spawn StartupPrefix1(">>),
    {Admission1, _} = binary:match(
        Generated,
        <<"spawn axis::ReservedFrame(startup_1_prefix_c">>
    ),
    ?assert(Prefix0 < Admission0),
    ?assert(Prefix1 < Admission1),
    ?assertEqual(0, count(Generated, <<"FrameMux2(startup_">>)).

dslx_backend_rejects_unpacked_startup_data_test() ->
    Spec = phi_phenom_topology:topology(),
    Plan = xls_topology:normalize(Spec#{startup := [
        {data, [not_a_record]}
    ]}),
    ?assertError(
        {invalid_startup_message, data, 0, not_a_record},
        xls_topology_dslx:emit(
            Plan,
            phi_phenom_topology_dslx:profile()
        )
    ).

generated_topology_matches_checked_in_artifact_test() ->
    {ok, Expected} = file:read_file(
        "src/examples/phi_phenom_topology.x"
    ),
    Generated = iolist_to_binary(phi_phenom_topology_dslx:to_dslx()),
    ?assertEqual(Expected, Generated).

dslx_backend_requires_aliased_port_order_policy_test() ->
    Plan = xls_topology:from_module(phi_phenom_topology),
    Profile = phi_phenom_topology_dslx:profile(),
    try xls_topology_dslx:emit(
        Plan,
        Profile#{aliased_port_order := preserve}
    ) of
        _ -> ?assert(false)
    catch
        error:{unsupported_dslx_aliased_port_order, preserve, Lanes} ->
            ?assertEqual(expected_phi_aliased_lanes(), Lanes)
    end.

dslx_backend_rejects_unknown_aliased_port_order_policy_test() ->
    Plan = xls_topology:from_module(phi_phenom_topology),
    Profile = phi_phenom_topology_dslx:profile(),
    ?assertError(
        {invalid_dslx_aliased_port_order, accidental},
        xls_topology_dslx:emit(
            Plan,
            Profile#{aliased_port_order := accidental}
        )
    ).

dslx_backend_rejects_unimplemented_route_tag_remap_test() ->
    Plan = xls_topology:normalize(reordered_fixture_topology()),
    ?assertError(
        {unsupported_dslx_route_tag_remap,
            {source, out},
            {actor, destination},
            message,
            3,
            4},
        xls_topology_dslx:emit(Plan, fixture_profile(selector_fixture))
    ).

dslx_backend_rejects_incoherent_external_schema_encoding_test() ->
    Plan = xls_topology:normalize(external_encoding_fixture_topology()),
    try xls_topology_dslx:emit(
        Plan,
        fixture_profile(external_encoding_fixture)
    ) of
        _ -> ?assert(false)
    catch
        error:{incompatible_dslx_external_schema_encoding,
                shared, message, _Existing, _New} -> ok
    end.

dslx_backend_rejects_ambiguous_external_selector_test() ->
    Plan = xls_topology:normalize(external_selector_fixture_topology()),
    try xls_topology_dslx:emit(
        Plan,
        fixture_profile(external_selector_fixture)
    ) of
        _ -> ?assert(false)
    catch
        error:{ambiguous_dslx_external_selector,
                shared, 3, _ExistingSchema, _NewSchema} -> ok
    end.

dslx_backend_accepts_preserved_nonaliased_graph_test() ->
    Plan = xls_topology:normalize(nonaliased_phi_pair()),
    Profile = (phi_phenom_topology_dslx:profile())#{
        name := nonaliased_phi_pair,
        aliased_port_order := preserve
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

dslx_backend_rejects_stale_cached_lanes_test() ->
    Plan = xls_topology:from_module(phi_phenom_topology),
    [First | Rest] = maps:get(routes, Plan),
    Changed = First#{recipients := [{actor, phi}]},
    try xls_topology_dslx:emit(
        Plan#{routes := [Changed | Rest]},
        phi_phenom_topology_dslx:profile()
    ) of
        _ -> ?assert(false)
    catch
        error:{inconsistent_dslx_plan_lanes, _Realized, _Cached} -> ok
    end.

dslx_backend_rejects_aliased_external_lane_test() ->
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
    Plan = xls_topology:normalize(Spec#{
        externals := [{announcement, out, [
            anyon_move,
            phi,
            phi0,
            phenom_anyon
        ]}],
        routes := Routes
    }),
    try xls_topology_dslx:emit(
        Plan,
        phi_phenom_topology_dslx:profile()
    ) of
        _ -> ?assert(false)
    catch
        error:{unsupported_dslx_aliased_external_lane,
                phi, announcement} -> ok
    end.

dslx_backend_requires_identifier_external_names_test() ->
    Spec = phi_phenom_topology:topology(),
    ExternalId = {announcement, 0},
    Routes = [
        case Route of
            {Source, Delivery, Recipients} ->
                {Source, Delivery, [
                    case Recipient of
                        {external, announcement} -> {external, ExternalId};
                        _ -> Recipient
                    end
                    || Recipient <- Recipients
                ]};
            _ -> Route
        end
        || Route <- maps:get(routes, Spec)
    ],
    Plan = xls_topology:normalize(Spec#{
        externals := [{ExternalId, out, [phenom_anyon]}],
        routes := Routes
    }),
    ?assertError(
        {invalid_dslx_identifier, external_id, ExternalId},
        xls_topology_dslx:emit(
            Plan,
            phi_phenom_topology_dslx:profile()
        )
    ).

dslx_backend_rejects_startup_target_with_initial_effects_test() ->
    Spec = phi_phenom_topology:topology(),
    Plan = xls_topology:normalize(Spec#{startup := [
        {phi, [{phenom_anyon, 0, 0}]}
    ]}),
    try xls_topology_dslx:emit(
        Plan,
        phi_phenom_topology_dslx:profile()
    ) of
        _ -> ?assert(false)
    catch
        error:{startup_target_has_initial_effects,
                phi, phi_halo_cell, Effects} ->
            ?assertMatch([_ | _], Effects)
    end.

dslx_backend_explicitly_rejects_startup_only_actor_test() ->
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
    ],
    [DataStartup] = [
        Messages
        || {data, Messages} <- maps:get(startup, Spec)
    ],
    Plan = xls_topology:normalize(Spec#{
        actors := Actors#{data2 => phenom_data_cell},
        routes := Routes ++ Data2Routes,
        startup := maps:get(startup, Spec) ++ [{data2, DataStartup}]
    }),
    ?assertError(
        {unsupported_dslx_startup_only_actor, data},
        xls_topology_dslx:emit(
            Plan,
            phi_phenom_topology_dslx:profile()
        )
    ).

dslx_backend_rejects_unimplemented_coupled_fanout_test() ->
    Plan = xls_topology:from_module(phi_phenom_topology),
    Source = {syndrome, phi},
    Routes = [
        case Route of
            #{source := Source} -> Route#{delivery := coupled};
            _ -> Route
        end
        || Route <- maps:get(routes, Plan)
    ],
    ?assertError(
        {unsupported_dslx_route_delivery, Source, coupled, 2},
        xls_topology_dslx:emit(
            Plan#{routes := Routes},
            phi_phenom_topology_dslx:profile()
        )
    ).

dslx_backend_rejects_other_unimplemented_fanout_modes_test_() ->
    [
        {atom_to_list(Delivery), fun() ->
            Plan = xls_topology:from_module(phi_phenom_topology),
            Source = {syndrome, phi},
            Routes = [
                case Route of
                    #{source := Source} -> Route#{delivery := Delivery};
                    _ -> Route
                end
                || Route <- maps:get(routes, Plan)
            ],
            ?assertError(
                {unsupported_dslx_route_delivery, Source, Delivery, 2},
                xls_topology_dslx:emit(
                    Plan#{routes := Routes},
                    phi_phenom_topology_dslx:profile()
                )
            )
        end}
        || Delivery <- [buffered, best_effort]
    ].

route(Plan, Source) ->
    hd([
        Route
        || Route <- maps:get(routes, Plan),
           maps:get(source, Route) =:= Source
    ]).

lane(Plan, Source, Destination) ->
    hd([
        Lane
        || Lane <- maps:get(lanes, Plan),
           maps:get(source, Lane) =:= Source,
           maps:get(destination, Lane) =:= Destination
    ]).

replace_route(Spec, Source, Replacement) ->
    Spec#{routes := [
        case Route of
            {Source, _Recipients} -> Replacement;
            {Source, _Delivery, _Recipients} -> Replacement;
            _ -> Route
        end
        || Route <- maps:get(routes, Spec)
    ]}.

expected_phi_aliased_lanes() ->
    [
        #{
            source => data,
            source_module => phenom_data_cell,
            source_ports => [east, north, south, west],
            destination => {actor, syndrome},
            destination_module => phenom_syndrome_cell
        },
        #{
            source => phi,
            source_module => phi_halo_cell,
            source_ports => [east, north, south, west],
            destination => {actor, phi},
            destination_module => phi_halo_cell
        },
        #{
            source => syndrome,
            source_module => phenom_syndrome_cell,
            source_ports => [east, north, south, west],
            destination => {actor, data},
            destination_module => phenom_data_cell
        }
    ].

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
        version => 0,
        actors => #{
            phi => phi_halo_cell,
            syndrome => phenom_syndrome_cell
        },
        externals => PhiExternals ++ QueryExternals,
        routes =>
            [
                {{phi, Port}, [{external, maps:get(Port, PhiExternalIds)}]}
                || Port <- Directions
            ] ++
            [{{phi, syndrome}, [{actor, syndrome}]}] ++
            [
                {{syndrome, Port}, [
                    {external, maps:get(Port, QueryExternalIds)}
                ]}
                || Port <- Directions
            ] ++
            [{{syndrome, phi}, [{actor, phi}]}],
        startup => []
    }.

layout_fixture_topology() ->
    #{
        version => 0,
        actors => #{
            source => xls_topology_source_fixture,
            destination => xls_topology_layout_fixture
        },
        externals => [{sink, out, [message]}],
        routes => [
            {{source, out}, [{actor, destination}]},
            {{destination, out}, [{external, sink}]}
        ],
        startup => []
    }.

reordered_fixture_topology() ->
    #{
        version => 0,
        actors => #{
            source => xls_topology_source_fixture,
            destination => xls_topology_reordered_fixture
        },
        externals => [
            {message_sink, out, [message]},
            {padding_sink, out, [padding]}
        ],
        routes => [
            {{source, out}, [{actor, destination}]},
            {{destination, message_out}, [{external, message_sink}]},
            {{destination, padding_out}, [{external, padding_sink}]}
        ],
        startup => []
    }.

external_encoding_fixture_topology() ->
    #{
        version => 0,
        actors => #{
            source => xls_topology_source_fixture,
            reordered => xls_topology_reordered_fixture
        },
        externals => [
            {shared, out, [message]},
            {padding_sink, out, [padding]}
        ],
        routes => [
            {{source, out}, [{external, shared}]},
            {{reordered, message_out}, [{external, shared}]},
            {{reordered, padding_out}, [{external, padding_sink}]}
        ],
        startup => []
    }.

external_selector_fixture_topology() ->
    #{
        version => 0,
        actors => #{
            source => xls_topology_source_fixture,
            reordered => xls_topology_reordered_fixture
        },
        externals => [
            {shared, out, [message, padding]},
            {message_sink, out, [message]}
        ],
        routes => [
            {{source, out}, [{external, shared}]},
            {{reordered, message_out}, [{external, message_sink}]},
            {{reordered, padding_out}, [{external, shared}]}
        ],
        startup => []
    }.

fixture_profile(Name) ->
    #{
        version => 0,
        name => Name,
        channel_depth => 1,
        aliased_port_order => preserve
    }.

rename_actor_id(Spec, OldId, NewId) ->
    Actors0 = maps:get(actors, Spec),
    {Module, Actors1} = maps:take(OldId, Actors0),
    Spec#{
        actors := Actors1#{NewId => Module},
        routes := [rename_route_actor(Route, OldId, NewId)
            || Route <- maps:get(routes, Spec)],
        startup := [
            {rename_id(Id, OldId, NewId), Messages}
            || {Id, Messages} <- maps:get(startup, Spec)
        ]
    }.

rename_route_actor({Source, Recipients}, OldId, NewId) ->
    {rename_source(Source, OldId, NewId),
        [rename_recipient(Recipient, OldId, NewId)
            || Recipient <- Recipients]};
rename_route_actor({Source, Delivery, Recipients}, OldId, NewId) ->
    {rename_source(Source, OldId, NewId), Delivery,
        [rename_recipient(Recipient, OldId, NewId)
            || Recipient <- Recipients]}.

rename_source({Id, Port}, OldId, NewId) ->
    {rename_id(Id, OldId, NewId), Port}.

rename_recipient({actor, Id}, OldId, NewId) ->
    {actor, rename_id(Id, OldId, NewId)};
rename_recipient(Recipient = {external, _Id}, _OldId, _NewId) ->
    Recipient.

rename_id(OldId, OldId, NewId) -> NewId;
rename_id(Id, _OldId, _NewId) -> Id.

count(Binary, Pattern) -> length(binary:matches(Binary, Pattern)).
