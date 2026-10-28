-module(hls_topology_tests).

-include_lib("eunit/include/eunit.hrl").

%% Checks hls routing topology fixture normalizes.
-spec hls_routing_topology_fixture_normalizes_test() -> ok.
hls_routing_topology_fixture_normalizes_test() ->
    Plan = hls_topology:from_module(hls_routing_topology_fixture),
    ?assertEqual(
        [data, grid, query],
        [maps:get(id, Actor) || Actor <- maps:get(actors, Plan)]
    ),
    ?assertEqual(17, length(maps:get(routes, Plan))),
    ?assertEqual(
        [
            #{
                id => announcement,
                direction => out,
                schemas => [report]
            },
            #{
                id => data_measurements,
                direction => out,
                schemas => [measurement]
            },
            #{
                id => result_events,
                direction => out,
                schemas => [result, status]
            }
        ],
        maps:get(externals, Plan)
    ),
    ?assertEqual(
        #{
            source => {query, grid},
            delivery => queued,
            recipients => [{actor, grid}, {external, announcement}]
        },
        route(Plan, {query, grid})
    ),
    ?assertEqual(
        #{
            source => {grid, result},
            delivery => direct,
            recipients => [{external, result_events}]
        },
        route(Plan, {grid, result})
    ),
    ?assertEqual(
        #{
            source => {grid, status},
            delivery => direct,
            recipients => [{external, result_events}]
        },
        route(Plan, {grid, status})
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
        [data, grid, query],
        [maps:get(target, Item) || Item <- maps:get(startup, Plan)]
    ).

%% Checks all outputs and aliased lanes are explicit.
-spec all_outputs_and_aliased_lanes_are_explicit_test() -> ok.
all_outputs_and_aliased_lanes_are_explicit_test() ->
    Plan = hls_topology:from_module(hls_routing_topology_fixture),
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
            source => grid,
            destination => {actor, grid},
            source_ports => [east, north, south, west]
        },
        lane(Plan, grid, {actor, grid})
    ).

%% Checks unordered sections normalize identically.
-spec unordered_sections_normalize_identically_test() -> ok.
unordered_sections_normalize_identically_test() ->
    Spec = hls_routing_topology_fixture:topology(),
    Reordered = Spec#{
        externals := lists:reverse(maps:get(externals, Spec)),
        routes := lists:reverse(maps:get(routes, Spec)),
        startup := lists:reverse(maps:get(startup, Spec))
    },
    ?assertEqual(
        hls_topology:normalize(Spec),
        hls_topology:normalize(Reordered)
    ).

%% Checks startup order is local to each actor.
-spec startup_order_is_local_to_each_actor_test() -> ok.
startup_order_is_local_to_each_actor_test() ->
    Spec = hls_routing_topology_fixture:topology(),
    Forward = hls_topology:normalize(Spec#{
        startup := [{data, [first, second]}]
    }),
    Reverse = hls_topology:normalize(Spec#{
        startup := [{data, [second, first]}]
    }),
    ?assertNotEqual(maps:get(startup, Forward), maps:get(startup, Reverse)).

%% Checks actor dictionary is required.
-spec actor_dictionary_is_required_test() -> ok.
actor_dictionary_is_required_test() ->
    Spec = hls_routing_topology_fixture:topology(),
    Actors = maps:get(actors, Spec),
    ActorList = maps:to_list(Actors),
    ?assertError(
        {invalid_topology_field, actors, ActorList},
        hls_topology:normalize(Spec#{actors := ActorList})
    ).

%% Checks invalid actor ids are rejected.
-spec invalid_actor_ids_are_rejected_test() -> ok.
invalid_actor_ids_are_rejected_test() ->
    Spec = hls_routing_topology_fixture:topology(),
    Actors = maps:get(actors, Spec),
    GridModule = maps:get(grid, Actors),
    lists:foreach(
        fun({InvalidId, InvalidPart}) ->
            InvalidActors = maps:put(
                InvalidId,
                GridModule,
                maps:remove(grid, Actors)
            ),
            ?assertError(
                {invalid_topology_id, InvalidPart},
                hls_topology:normalize(Spec#{actors := InvalidActors})
            )
        end,
        [
            {1.0, 1.0},
            {{}, {}},
            {{grid, -1}, -1},
            {{grid, 1.0}, 1.0}
        ]
    ).

%% Checks invalid actor module is rejected.
-spec invalid_actor_module_is_rejected_test() -> ok.
invalid_actor_module_is_rejected_test() ->
    Spec = hls_routing_topology_fixture:topology(),
    Actors = maps:get(actors, Spec),
    ?assertError(
        {invalid_actor_module, grid, 42},
        hls_topology:normalize(Spec#{actors := Actors#{grid := 42}})
    ).

%% Checks indexed tuple actor ids normalize and emit without mangling.
-spec indexed_tuple_actor_ids_normalize_and_emit_without_mangling_test() -> ok.
indexed_tuple_actor_ids_normalize_and_emit_without_mangling_test() ->
    Id = {grid, 17, {tile, 2, 3}},
    Spec = rename_actor_id(hls_routing_topology_fixture:topology(), grid, Id),
    Plan = hls_topology:normalize(Spec),
    ?assert(lists:member(Id, [maps:get(id, Actor)
        || Actor <- maps:get(actors, Plan)])),
    Profile = (hls_routing_topology_fixture:profile())#{
        name := indexed_grid_topology
    },
    Generated = iolist_to_binary(xls_topology_dslx:emit(Plan, Profile)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "Actor {grid,17,{tile,2,3}} uses hls_grid_cell_fixture"
    >>)),
    ?assertNotEqual(nomatch, binary:match(
        Generated,
        <<"spawn hls_grid_cell_fixture::Service(">>
    )).

%% Checks route sources are checked and total.
-spec route_sources_are_checked_and_total_test() -> ok.
route_sources_are_checked_and_total_test() ->
    Spec = hls_routing_topology_fixture:topology(),
    [First | Rest] = maps:get(routes, Spec),
    ?assertError(
        {unknown_actor_output, grid, up},
        hls_topology:normalize(Spec#{
            routes := [{{grid, up}, [{actor, grid}]} | Rest]
        })
    ),
    ?assertError(
        {unrouted_outputs, [{grid, north}]},
        hls_topology:normalize(Spec#{routes := Rest})
    ),
    ?assertError(
        {duplicate_route_sources, [{grid, north}]},
        hls_topology:normalize(Spec#{routes := [First, First | Rest]})
    ).

%% Checks route recipients are checked and unique.
-spec route_recipients_are_checked_and_unique_test() -> ok.
route_recipients_are_checked_and_unique_test() ->
    Spec = hls_routing_topology_fixture:topology(),
    Source = {query, grid},
    ?assertError(
        {unknown_actor, missing, {route_recipient, Source}},
        hls_topology:normalize(replace_route(
            Spec,
            Source,
            {Source, buffered, [{actor, missing}, {actor, grid}]}
        ))
    ),
    ?assertError(
        {empty_route, Source},
        hls_topology:normalize(replace_route(Spec, Source, {Source, []}))
    ),
    ?assertError(
        {duplicate_route_recipients, Source, [{actor, grid}]},
        hls_topology:normalize(replace_route(
            Spec,
            Source,
            {Source, buffered, [{actor, grid}, {actor, grid}]}
        ))
    ).

%% Checks fanout delivery is explicit.
-spec fanout_delivery_is_explicit_test() -> ok.
fanout_delivery_is_explicit_test() ->
    Spec = hls_routing_topology_fixture:topology(),
    Source = {query, grid},
    ?assertError(
        {fanout_delivery_required, Source},
        hls_topology:normalize(replace_route(
            Spec,
            Source,
            {Source, [{actor, grid}, {external, announcement}]}
        ))
    ),
    ?assertError(
        {invalid_fanout_delivery, Source, accidental},
        hls_topology:normalize(replace_route(
            Spec,
            Source,
            {Source, accidental, [
                {actor, grid},
                {external, announcement}
            ]}
        ))
    ).

%% Checks startup targets are known and unique.
-spec startup_targets_are_known_and_unique_test() -> ok.
startup_targets_are_known_and_unique_test() ->
    Spec = hls_routing_topology_fixture:topology(),
    ?assertError(
        {unknown_actor, missing, startup},
        hls_topology:normalize(Spec#{startup := [{missing, [config]}]})
    ),
    ?assertError(
        {duplicate_startup_targets, [data]},
        hls_topology:normalize(Spec#{startup := [
            {data, [first]},
            {data, [second]}
        ]})
    ).

%% Checks live runtime identity is rejected.
-spec live_runtime_identity_is_rejected_test() -> ok.
live_runtime_identity_is_rejected_test() ->
    Spec = hls_routing_topology_fixture:topology(),
    ?assertError(
        {live_topology_value, pid},
        hls_topology:normalize(Spec#{startup := [{data, [self()]}]})
    ),
    ?assertError(
        {live_topology_value, reference},
        hls_topology:normalize(Spec#{startup := [{data, [make_ref()]}]})
    ).

%% Checks actor output abi order is preserved.
-spec actor_output_abi_order_is_preserved_test() -> ok.
actor_output_abi_order_is_preserved_test() ->
    Plan = hls_topology:from_module(hls_routing_topology_fixture),
    Grid = hd([
        Actor
        || Actor <- maps:get(actors, Plan),
           maps:get(id, Actor) =:= grid
    ]),
    ?assertEqual(
        [north, east, west, south, query, result, status],
        maps:get(outputs, Grid)
    ).

%% Checks incompatible actor route schema is rejected.
-spec incompatible_actor_route_schema_is_rejected_test() -> ok.
incompatible_actor_route_schema_is_rejected_test() ->
    Spec = hls_routing_topology_fixture:topology(),
    Source = {grid, query},
    ?assertError(
        {incompatible_route_schemas,
            Source,
            {actor, data},
            [request],
            [config, query]},
        hls_topology:normalize(replace_route(
            Spec,
            Source,
            {Source, [{actor, data}]}
        ))
    ).

%% Checks incompatible actor route layout is rejected.
-spec incompatible_actor_route_layout_is_rejected_test() -> ok.
incompatible_actor_route_layout_is_rejected_test() ->
    SourceFields = [#{
        name => value,
        type => {hls_type, hls_nums, u32, []}
    }],
    DestinationFields = [#{
        name => value,
        type => {hls_type, hls_nums, u64, []}
    }],
    ?assertError(
        {incompatible_route_schema_layout,
            {source, out},
            {actor, destination},
            message,
            SourceFields,
            DestinationFields},
        hls_topology:normalize(layout_fixture_topology())
    ).

%% Checks incompatible external route schema is rejected.
-spec incompatible_external_route_schema_is_rejected_test() -> ok.
incompatible_external_route_schema_is_rejected_test() ->
    Spec = hls_routing_topology_fixture:topology(),
    ?assertError(
        {incompatible_route_schemas,
            {query, grid},
            {external, announcement},
            [report],
            [sample]},
        hls_topology:normalize(Spec#{
            externals := [
                {announcement, out, [sample]},
                {data_measurements, out, [measurement]},
                {result_events, out, [result, status]}
            ]
        })
    ).

%% Checks incompatible startup schema is rejected.
-spec incompatible_startup_schema_is_rejected_test() -> ok.
incompatible_startup_schema_is_rejected_test() ->
    Spec = hls_routing_topology_fixture:topology(),
    ?assertError(
        {incompatible_startup_schema,
            data,
            0,
            request,
            [config, query]},
        hls_topology:normalize(Spec#{
            startup := [{data, [{request, 0}]}]
        })
    ).

%% Checks generated topology is deterministic.
-spec generated_topology_is_deterministic_test() -> ok.
generated_topology_is_deterministic_test() ->
    Spec = hls_routing_topology_fixture:topology(),
    Reordered = Spec#{
        externals := lists:reverse(maps:get(externals, Spec)),
        routes := lists:reverse(maps:get(routes, Spec)),
        startup := lists:reverse(maps:get(startup, Spec))
    },
    Profile = hls_routing_topology_fixture:profile(),
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
        hls_routing_topology_fixture:to_dslx()
    )).

%% Checks generated topology has expected physical shape.
-spec generated_topology_has_expected_physical_shape_test() -> ok.
generated_topology_has_expected_physical_shape_test() ->
    Generated = iolist_to_binary(hls_routing_topology_fixture:to_dslx()),
    ?assertEqual(3, count(Generated, <<"::Service(">>)),
    ?assertEqual(3, count(Generated, <<"proc ActorIngress">>)),
    ?assertEqual(3, count(Generated, <<"spawn ActorIngress">>)),
    ?assertEqual(3, count(Generated, <<"proc ActorRouter">>)),
    ?assertEqual(3, count(Generated, <<"spawn ActorRouter">>)),
    ?assertEqual(1, count(Generated, <<"::Egress, u32:3>">>)),
    ?assertEqual(2, count(Generated, <<"::Egress, u32:4>">>)),
    %% All four aliased source ports select one ordered send to query.
    ?assertEqual(1, count(Generated, <<
        "effect.port == hls_data_cell_fixture::OutputPort::NORTH || "
        "effect.port == hls_data_cell_fixture::OutputPort::EAST || "
        "effect.port == hls_data_cell_fixture::OutputPort::WEST || "
        "effect.port == hls_data_cell_fixture::OutputPort::SOUTH"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated,
        <<"uN[96]:0x000000000000000400000001">>)),
    ?assertNotEqual(nomatch, binary:match(Generated,
        <<"uN[96]:0x000000000000000400000002">>)),
    ?assertNotEqual(nomatch, binary:match(Generated,
        <<"axis::pack(u8:12, u32:0x00000003)">>)).

%% Checks generated topology uses explicit actor egress depth.
-spec generated_topology_uses_explicit_actor_egress_depth_test() -> ok.
generated_topology_uses_explicit_actor_egress_depth_test() ->
    Plan = hls_topology:from_module(hls_routing_topology_fixture),
    Profile = hls_routing_topology_fixture:profile(),
    lists:foreach(
        fun(Depth) ->
            Generated = iolist_to_binary(xls_topology_dslx:emit(
                Plan,
                Profile#{actor_egress_depth := Depth}
            )),
            Needle = iolist_to_binary([
                "::Egress, u32:", integer_to_list(Depth), ">"
            ]),
            ?assertEqual(3, count(Generated, Needle))
        end,
        [0, 1]
    ).

%% Checks generated startup preserves per actor message order.
-spec generated_startup_preserves_per_actor_message_order_test() -> ok.
generated_startup_preserves_per_actor_message_order_test() ->
    Spec = hls_routing_topology_fixture:topology(),
    Plan = hls_topology:normalize(Spec#{startup := [
        {data, [
            {config, 1, 2, 3, 4},
            {config, 5, 6, 7, 8}
        ]}
    ]}),
    Generated = iolist_to_binary(xls_topology_dslx:emit(
        Plan,
        hls_routing_topology_fixture:profile()
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

%% Checks generated startup and routed receive both require admission.
-spec generated_startup_and_routed_receive_both_require_admission_test() -> ok.
generated_startup_and_routed_receive_both_require_admission_test() ->
    Generated = iolist_to_binary(hls_routing_topology_fixture:to_dslx()),
    [_Preamble | Procs] = binary:split(Generated, <<"proc ActorIngress">>, [global]),
    ?assertEqual(3, length(Procs)),
    lists:foreach(fun(Proc) ->
        {Admission, _} = binary:match(Proc, <<"recv(join(), admission_in)">>),
        {Startup, _} = binary:match(Proc, <<"} else if state.2 < u32:1 {">>),
        {Routed, _} = binary:match(Proc, <<"frame_in[candidate]">>),
        ?assert(Admission < Startup),
        ?assert(Startup < Routed)
    end, Procs).

%% Checks dslx backend rejects unpacked startup data.
-spec dslx_backend_rejects_unpacked_startup_data_test() -> ok.
dslx_backend_rejects_unpacked_startup_data_test() ->
    Spec = hls_routing_topology_fixture:topology(),
    Plan = hls_topology:normalize(Spec#{startup := [
        {data, [not_a_record]}
    ]}),
    ?assertError(
        {invalid_startup_message, data, 0, not_a_record},
        xls_topology_dslx:emit(
            Plan,
            hls_routing_topology_fixture:profile()
        )
    ).

%% Checks dslx backend rejects out of range startup fields.
-spec dslx_backend_rejects_out_of_range_startup_fields_test() -> ok.
dslx_backend_rejects_out_of_range_startup_fields_test() ->
    Spec = hls_routing_topology_fixture:topology(),
    lists:foreach(fun(Message) ->
        Plan = hls_topology:normalize(Spec#{startup := [{data, [Message]}]}),
        ?assertError({cannot_pack_startup_message, data, 0, error, badarg},
            xls_topology_dslx:emit(Plan, hls_routing_topology_fixture:profile()))
    end, [{config, -1, 0, 0, 0},
        {config, 0, 1 bsl 32, 0, 0},
        {config, 0, 0, 65536, 0}]).

%% Checks dslx backend rejects removed alias escape hatch.
-spec dslx_backend_rejects_removed_alias_escape_hatch_test() -> ok.
dslx_backend_rejects_removed_alias_escape_hatch_test() ->
    Plan = hls_topology:from_module(hls_routing_topology_fixture),
    Profile = hls_routing_topology_fixture:profile(),
    ?assertError(
        {invalid_dslx_profile_keys, [], [aliased_port_order]},
        xls_topology_dslx:emit(
            Plan,
            Profile#{aliased_port_order => may_reorder}
        )
    ).

%% Checks dslx backend rejects channel depth wider than u32.
-spec dslx_backend_rejects_channel_depth_wider_than_u32_test() -> ok.
dslx_backend_rejects_channel_depth_wider_than_u32_test() ->
    Plan = hls_topology:from_module(hls_routing_topology_fixture),
    Profile = hls_routing_topology_fixture:profile(),
    ?assertError(
        {invalid_dslx_channel_depth, 16#100000000},
        xls_topology_dslx:emit(
            Plan,
            Profile#{channel_depth := 16#100000000}
        )
    ).

%% Checks dslx backend rejects invalid actor egress depth.
-spec dslx_backend_rejects_invalid_actor_egress_depth_test() -> ok.
dslx_backend_rejects_invalid_actor_egress_depth_test() ->
    Plan = hls_topology:from_module(hls_routing_topology_fixture),
    Profile = hls_routing_topology_fixture:profile(),
    lists:foreach(
        fun(Value) ->
            ?assertError(
                {egress_depth, Value},
                xls_topology_dslx:emit(
                    Plan,
                    Profile#{actor_egress_depth := Value}
                )
            )
        end,
        [-1, 16#100000000, auto]
    ).

%% Checks dslx backend rejects unimplemented route tag remap.
-spec dslx_backend_rejects_unimplemented_route_tag_remap_test() -> ok.
dslx_backend_rejects_unimplemented_route_tag_remap_test() ->
    Plan = hls_topology:normalize(reordered_fixture_topology()),
    ?assertError(
        {unsupported_dslx_route_tag_remap,
            {source, out},
            {actor, destination},
            message,
            3,
            4},
        xls_topology_dslx:emit(Plan, fixture_profile(selector_fixture))
    ).

%% Checks dslx backend rejects incoherent external schema encoding.
-spec dslx_backend_rejects_incoherent_external_schema_encoding_test() -> ok.
dslx_backend_rejects_incoherent_external_schema_encoding_test() ->
    Plan = hls_topology:normalize(external_encoding_fixture_topology()),
    try xls_topology_dslx:emit(
        Plan,
        fixture_profile(external_encoding_fixture)
    ) of
        _ -> ?assert(false)
    catch
        error:{incompatible_dslx_external_schema_encoding,
                shared, message, _Existing, _New} -> ok
    end.

%% Checks dslx backend rejects ambiguous external selector.
-spec dslx_backend_rejects_ambiguous_external_selector_test() -> ok.
dslx_backend_rejects_ambiguous_external_selector_test() ->
    Plan = hls_topology:normalize(external_selector_fixture_topology()),
    try xls_topology_dslx:emit(
        Plan,
        fixture_profile(external_selector_fixture)
    ) of
        _ -> ?assert(false)
    catch
        error:{ambiguous_dslx_external_selector,
                shared, 3, _ExistingSchema, _NewSchema} -> ok
    end.

%% Checks dslx backend accepts nonaliased graph.
-spec dslx_backend_accepts_nonaliased_graph_test() -> ok.
dslx_backend_accepts_nonaliased_graph_test() ->
    Plan = hls_topology:normalize(nonaliased_grid_pair()),
    Profile = (hls_routing_topology_fixture:profile())#{
        name := nonaliased_grid_pair
    },
    Generated = iolist_to_binary(xls_topology_dslx:emit(Plan, Profile)),
    ?assertEqual(1, count(Generated, <<"spawn hls_grid_cell_fixture::Service(">>)),
    ?assertEqual(
        1,
        count(Generated, <<"spawn hls_query_cell_fixture::Service(">>)
    ),
    ?assertEqual(
        nomatch,
        binary:match(Generated, <<"Aliased-port lanes permitted">>)
    ).

%% Checks dslx backend rejects stale cached lanes.
-spec dslx_backend_rejects_stale_cached_lanes_test() -> ok.
dslx_backend_rejects_stale_cached_lanes_test() ->
    Plan = hls_topology:from_module(hls_routing_topology_fixture),
    [First | Rest] = maps:get(routes, Plan),
    Changed = First#{recipients := [{actor, grid}]},
    try xls_topology_dslx:emit(
        Plan#{routes := [Changed | Rest]},
        hls_routing_topology_fixture:profile()
    ) of
        _ -> ?assert(false)
    catch
        error:{inconsistent_dslx_plan_lanes, _Realized, _Cached} -> ok
    end.

%% Checks dslx backend supports aliased external lane.
-spec dslx_backend_supports_aliased_external_lane_test() -> ok.
dslx_backend_supports_aliased_external_lane_test() ->
    Spec = hls_routing_topology_fixture:topology(),
    Routes = [
        case Route of
            {{grid, north}, _} ->
                {{grid, north}, [{external, announcement}]};
            {{grid, east}, _} ->
                {{grid, east}, [{external, announcement}]};
            _ -> Route
        end
        || Route <- maps:get(routes, Spec)
    ],
    Plan = hls_topology:normalize(Spec#{
        externals := [
            {announcement, out, [
                move,
                sample,
                delta,
                report
            ]},
            {data_measurements, out, [measurement]},
            {result_events, out, [result, status]}
        ],
        routes := Routes
    }),
    Generated = iolist_to_binary(xls_topology_dslx:emit(
        Plan,
        hls_routing_topology_fixture:profile()
    )),
    ?assertEqual(
        [east, north],
        maps:get(source_ports, lane(Plan, grid, {external, announcement}))
    ),
    ?assertNotEqual(nomatch, binary:match(Generated, <<"proc ActorRouter">>)).

%% Checks dslx backend requires identifier external names.
-spec dslx_backend_requires_identifier_external_names_test() -> ok.
dslx_backend_requires_identifier_external_names_test() ->
    Spec = hls_routing_topology_fixture:topology(),
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
    Plan = hls_topology:normalize(Spec#{
        externals := [
            {ExternalId, out, [report]},
            {data_measurements, out, [measurement]},
            {result_events, out, [result, status]}
        ],
        routes := Routes
    }),
    ?assertError(
        {invalid_dslx_identifier, external_id, ExternalId},
        xls_topology_dslx:emit(
            Plan,
            hls_routing_topology_fixture:profile()
        )
    ).

%% Checks dslx backend rejects startup target with initial effects.
-spec dslx_backend_rejects_startup_target_with_initial_effects_test() -> ok.
dslx_backend_rejects_startup_target_with_initial_effects_test() ->
    Plan = hls_topology:normalize(#{
        version => 1,
        ingresses => [],
        actors => #{source => hls_topology_source_fixture},
        families => #{},
        externals => [{out, out, [message]}],
        routes => [{{source, out}, [{external, out}]}],
        route_relations => [],
        startup => [{source, [{message, 0}]}]
    }),
    try xls_topology_dslx:emit(
        Plan,
        fixture_profile(initial_effect_startup)
    ) of
        _ -> ?assert(false)
    catch
        error:{startup_target_has_initial_effects,
                source, hls_topology_source_fixture, Effects} ->
            ?assertMatch([_ | _], Effects)
    end.

%% Checks dslx backend supports startup only actor.
-spec dslx_backend_supports_startup_only_actor_test() -> ok.
dslx_backend_supports_startup_only_actor_test() ->
    Spec = hls_routing_topology_fixture:topology(),
    Actors = maps:get(actors, Spec),
    Directions = [north, east, west, south],
    Routes = [
        case Route of
            {Source = {query, Port}, _Recipients} ->
                case lists:member(Port, Directions) of
                    true -> {Source, [{actor, data2}]};
                    false -> Route
                end;
            _ -> Route
        end
        || Route <- maps:get(routes, Spec)
    ],
    Data2Routes = [
        {{data2, Port}, [{actor, query}]}
        || Port <- Directions
    ] ++ [
        {{data2, measurement}, [{external, data_measurements}]}
    ],
    [DataStartup] = [
        Messages
        || {data, Messages} <- maps:get(startup, Spec)
    ],
    Plan = hls_topology:normalize(Spec#{
        actors := Actors#{data2 => hls_data_cell_fixture},
        routes := Routes ++ Data2Routes,
        startup := maps:get(startup, Spec) ++ [{data2, DataStartup}]
    }),
    Generated = iolist_to_binary(xls_topology_dslx:emit(
        Plan, hls_routing_topology_fixture:profile())),
    ?assertEqual(4, count(Generated, <<"::Service(">>)),
    ?assertNotEqual(nomatch, binary:match(Generated,
        <<"spawn ActorIngress0(actor_0_req_p, actor_0_admit_c)">>)).

%% Checks dslx backend rejects unimplemented coupled fanout.
-spec dslx_backend_rejects_unimplemented_coupled_fanout_test() -> ok.
dslx_backend_rejects_unimplemented_coupled_fanout_test() ->
    Plan = hls_topology:from_module(hls_routing_topology_fixture),
    Source = {query, grid},
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
            hls_routing_topology_fixture:profile()
        )
    ).

%% Checks dslx backend rejects other unimplemented fanout modes.
-spec dslx_backend_rejects_other_unimplemented_fanout_modes_test_() -> [term()].
dslx_backend_rejects_other_unimplemented_fanout_modes_test_() ->
    [
        {atom_to_list(Delivery), fun() ->
            Plan = hls_topology:from_module(hls_routing_topology_fixture),
            Source = {query, grid},
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
                    hls_routing_topology_fixture:profile()
                )
            )
        end}
        || Delivery <- [buffered, best_effort]
    ].

%% Finds the one normalized route selected by source or output port.
-spec route(map() | [map()], term()) -> map().
route(Plan, Source) ->
    hd([
        Route
        || Route <- maps:get(routes, Plan),
           maps:get(source, Route) =:= Source
    ]).

%% Finds the normalized source/destination lane.
-spec lane(map(), term(), term()) -> map().
lane(Plan, Source, Destination) ->
    hd([
        Lane
        || Lane <- maps:get(lanes, Plan),
           maps:get(source, Lane) =:= Source,
           maps:get(destination, Lane) =:= Destination
    ]).

%% Replaces one raw route while preserving unrelated routes.
-spec replace_route(map(), term(), tuple()) -> map().
replace_route(Spec, Source, Replacement) ->
    Spec#{routes := [
        case Route of
            {Source, _Recipients} -> Replacement;
            {Source, _Delivery, _Recipients} -> Replacement;
            _ -> Route
        end
        || Route <- maps:get(routes, Spec)
    ]}.

%% Builds the minimal topology needed by this validation scenario.
-spec nonaliased_grid_pair() -> hls_topology:spec().
nonaliased_grid_pair() ->
    Directions = [north, east, west, south],
    GridExternalIds = #{
        north => grid_north,
        east => grid_east,
        west => grid_west,
        south => grid_south
    },
    QueryExternalIds = #{
        north => query_north,
        east => query_east,
        west => query_west,
        south => query_south
    },
    GridExternals = [
        {maps:get(Port, GridExternalIds), out, [delta, move, sample]}
        || Port <- Directions
    ],
    QueryExternals = [
        {maps:get(Port, QueryExternalIds), out, [query]}
        || Port <- Directions
    ],
    #{
        version => 1,
        ingresses => [],
        actors => #{
            grid => hls_grid_cell_fixture,
            query => hls_query_cell_fixture
        },
        families => #{},
        externals =>
            GridExternals ++ QueryExternals ++
            [
                {result_events, out, [result, status]},
                {announcement, out, [report]}
            ],
        routes =>
            [
                {{grid, Port}, [{external, maps:get(Port, GridExternalIds)}]}
                || Port <- Directions
            ] ++
            [
                {{grid, query}, [{actor, query}]},
                {{grid, result}, [{external, result_events}]},
                {{grid, status}, [{external, result_events}]}
            ] ++
            [
                {{query, Port}, [
                    {external, maps:get(Port, QueryExternalIds)}
                ]}
                || Port <- Directions
            ] ++
            [
                {{query, grid}, queued, [
                    {actor, grid},
                    {external, announcement}
                ]}
            ],
        route_relations => [],
        startup => []
    }.

%% Builds the minimal topology needed by this validation scenario.
-spec layout_fixture_topology() -> hls_topology:spec().
layout_fixture_topology() ->
    #{
        version => 1,
        ingresses => [],
        actors => #{
            source => hls_topology_source_fixture,
            destination => hls_topology_layout_fixture
        },
        families => #{},
        externals => [{sink, out, [message]}],
        routes => [
            {{source, out}, [{actor, destination}]},
            {{destination, out}, [{external, sink}]}
        ],
        route_relations => [],
        startup => []
    }.

%% Builds the minimal topology needed by this validation scenario.
-spec reordered_fixture_topology() -> hls_topology:spec().
reordered_fixture_topology() ->
    #{
        version => 1,
        ingresses => [],
        actors => #{
            source => hls_topology_source_fixture,
            destination => hls_topology_reordered_fixture
        },
        families => #{},
        externals => [
            {message_sink, out, [message]},
            {padding_sink, out, [padding]}
        ],
        routes => [
            {{source, out}, [{actor, destination}]},
            {{destination, message_out}, [{external, message_sink}]},
            {{destination, padding_out}, [{external, padding_sink}]}
        ],
        route_relations => [],
        startup => []
    }.

%% Builds the minimal topology needed by this validation scenario.
-spec external_encoding_fixture_topology() -> hls_topology:spec().
external_encoding_fixture_topology() ->
    #{
        version => 1,
        ingresses => [],
        actors => #{
            source => hls_topology_source_fixture,
            reordered => hls_topology_reordered_fixture
        },
        families => #{},
        externals => [
            {shared, out, [message]},
            {padding_sink, out, [padding]}
        ],
        routes => [
            {{source, out}, [{external, shared}]},
            {{reordered, message_out}, [{external, shared}]},
            {{reordered, padding_out}, [{external, padding_sink}]}
        ],
        route_relations => [],
        startup => []
    }.

%% Builds the minimal topology needed by this validation scenario.
-spec external_selector_fixture_topology() -> hls_topology:spec().
external_selector_fixture_topology() ->
    #{
        version => 1,
        ingresses => [],
        actors => #{
            source => hls_topology_source_fixture,
            reordered => hls_topology_reordered_fixture
        },
        families => #{},
        externals => [
            {shared, out, [message, padding]},
            {message_sink, out, [message]}
        ],
        routes => [
            {{source, out}, [{external, shared}]},
            {{reordered, message_out}, [{external, message_sink}]},
            {{reordered, padding_out}, [{external, shared}]}
        ],
        route_relations => [],
        startup => []
    }.

%% Selects the explicit queue policy for a structural witness.
-spec fixture_profile(atom()) -> xls_topology_dslx:profile().
fixture_profile(Name) ->
    #{
        name => Name,
        channel_depth => 1,
        actor_egress_depth => burst
    }.

%% Renames an exact actor and each of its references.
-spec rename_actor_id(map(), term(), term()) -> map().
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

%% Renames source and recipient actor identities in one route.
-spec rename_route_actor(tuple(), term(), term()) -> tuple().
rename_route_actor({Source, Recipients}, OldId, NewId) ->
    {rename_source(Source, OldId, NewId),
        [rename_recipient(Recipient, OldId, NewId)
            || Recipient <- Recipients]};
rename_route_actor({Source, Delivery, Recipients}, OldId, NewId) ->
    {rename_source(Source, OldId, NewId), Delivery,
        [rename_recipient(Recipient, OldId, NewId)
            || Recipient <- Recipients]}.

%% Renames only the actor component of a route source.
-spec rename_source(tuple(), term(), term()) -> tuple().
rename_source({Id, Port}, OldId, NewId) ->
    {rename_id(Id, OldId, NewId), Port}.

%% Renames an actor recipient while retaining external boundaries.
-spec rename_recipient(tuple(), term(), term()) -> tuple().
rename_recipient({actor, Id}, OldId, NewId) ->
    {actor, rename_id(Id, OldId, NewId)};
rename_recipient(Recipient = {external, _Id}, _OldId, _NewId) ->
    Recipient.

%% Substitutes one exact identity and leaves other terms intact.
-spec rename_id(term(), term(), term()) -> term().
rename_id(OldId, OldId, NewId) -> NewId;
rename_id(Id, _OldId, _NewId) -> Id.

%% Counts exact generated fragments for structural assertions.
-spec count(binary(), binary()) -> non_neg_integer().
count(Binary, Pattern) -> length(binary:matches(Binary, Pattern)).
