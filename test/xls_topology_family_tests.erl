-module(xls_topology_family_tests).

-include_lib("eunit/include/eunit.hrl").

generated_family_topology_is_compact_test() ->
    Generated = generated(phi_torus_topology:topology(2, 2)),
    ?assertEqual(1, count(Generated, <<"spawn FamilyNode<">>)),
    ?assertEqual(1, count(Generated, <<"spawn phi_halo_cell::Service(">>)),
    ?assertEqual(4, count(Generated,
        <<"chan<axis::Frame, u32:0>[TORUS_HEIGHT][TORUS_WIDTH]">>
    )),
    ?assertEqual(4, count(Generated, <<"unroll_for! (">>)),
    ?assertEqual(1, count(Generated, <<"proc FamilyIngress<">>)),
    ?assertEqual(1, count(Generated, <<"spawn FamilyIngress<">>)),
    ?assertEqual(0, count(Generated, <<"spawn axis::FrameMux2(">>)),
    ?assertEqual(0, count(Generated, <<"spawn axis::ReservedFrame(">>)),
    ?assertEqual(nomatch, binary:match(Generated, <<"actor_0">>)),
    ?assertEqual(nomatch, binary:match(Generated, <<"{phi,0,0}">>)).

generated_two_by_two_router_preserves_alias_lanes_test() ->
    Generated = generated(phi_torus_topology:topology(2, 2)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "OutputPort::NORTH => true,\n"
        "      phi_halo_cell::OutputPort::SOUTH => true,\n"
        "      _ => false,"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "OutputPort::EAST => true,\n"
        "      phi_halo_cell::OutputPort::WEST => true,\n"
        "      _ => false,"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "let lane_2_tok = send_if(\n"
        "      tok, lane_2_out, lane_2_selected, egress.frame);"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "lane_2_c[x][(y + TORUS_HEIGHT - u32:1) % TORUS_HEIGHT]"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "lane_3_c[(x + TORUS_WIDTH - u32:1) % TORUS_WIDTH][y]"
    >>)).

generated_external_merge_uses_static_channel_sites_test() ->
    Generated = generated(phi_torus_topology:topology(3, 3)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "frame_in[candidate],\n          selected,"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "cursor == candidate"
    >>)),
    ?assertEqual(nomatch, binary:match(Generated, <<"frame_in[cursor]">>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "spawn FrameArrayMux<GRID_HEIGHT>(frame_in[x], column_p[x])"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "spawn FrameArrayMux<GRID_WIDTH>(column_c, frame_out)"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "spawn FrameGridMux<TORUS_WIDTH, TORUS_HEIGHT>("
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "frame_in: chan<axis::Frame>[GRID_HEIGHT][GRID_WIDTH] in"
    >>)),
    ?assertEqual(nomatch, binary:match(Generated, <<
        "chan<axis::Frame>[GRID_WIDTH][GRID_HEIGHT]"
    >>)).

generated_external_merges_distinct_source_families_test() ->
    Generated = generated(shared_external_topology()),
    ?assertEqual(2, count(Generated, <<"spawn FamilyNode">>)),
    ?assertEqual(4, count(Generated, <<
        "spawn FrameGridMux<TORUS_WIDTH, TORUS_HEIGHT>("
    >>)),
    ?assertEqual(2, count(Generated, <<
        "chan<axis::Frame, CHANNEL_DEPTH>[u32:2]"
    >>)),
    ?assertEqual(2, count(Generated, <<"spawn FrameArrayMux<u32:2>(">>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "external_0_lanes_p[u32:0]"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "external_0_lanes_p[u32:1]"
    >>)).

family_backend_rejects_external_without_a_lane_test() ->
    Spec = phi_torus_topology:topology(2, 2),
    Plan = hls_topology:normalize(Spec#{
        externals := maps:get(externals, Spec) ++ [
            {orphan, out, [phenom_request]}
        ]
    }),
    ?assertError(
        {external_lanes, orphan, 0},
        xls_topology_dslx:emit(
            Plan,
            phi_torus_topology_dslx:profile()
        )
    ).

rectangular_torus_wires_all_inverse_translations_test() ->
    Generated = generated(phi_torus_topology:topology(3, 4)),
    ExpectedInputs = [
        <<"lane_2_c[(x + u32:1) % TORUS_WIDTH][y]">>,
        <<"lane_3_c[x][(y + u32:1) % TORUS_HEIGHT]">>,
        <<"lane_4_c[x][(y + TORUS_HEIGHT - u32:1) % TORUS_HEIGHT]">>,
        <<"lane_5_c[(x + TORUS_WIDTH - u32:1) % TORUS_WIDTH][y]">>
    ],
    lists:foreach(
        fun(Input) ->
            ?assertNotEqual(nomatch, binary:match(Generated, Input))
        end,
        ExpectedInputs
    ).

five_and_fifty_wide_tori_have_the_same_generated_route_structure_test() ->
    %% Instance constants are still enumerated by the v0 startup model. Strip
    %% them here to isolate the compact family and route representation.
    SmallSpec = phi_torus_topology:topology(5, 5),
    LargeSpec = phi_torus_topology:topology(50, 50),
    Small = generated(SmallSpec#{startup := []}),
    Large = generated(LargeSpec#{startup := []}),
    ?assertEqual(
        scrub_dimensions(Small, <<"5">>),
        scrub_dimensions(Large, <<"50">>)
    ),
    ?assertEqual(1, count(Large, <<"spawn FamilyNode(">>)),
    ?assertEqual(6, count(Large,
        <<"chan<axis::Frame, u32:0>[TORUS_HEIGHT][TORUS_WIDTH]">>
    )).

generated_family_topology_matches_checked_in_artifact_test() ->
    {ok, Expected} = file:read_file(
        "src/examples/phi_decoder/phi_torus_topology.x"
    ),
    ?assertEqual(
        Expected,
        iolist_to_binary(phi_torus_topology_dslx:to_dslx())
    ).

generated_multi_family_topology_retains_compact_structure_test() ->
    Generated = iolist_to_binary(phi_noise_topology_dslx:to_dslx()),
    ?assertEqual(3, count(Generated, <<"proc SchedulerRouter">>)),
    ?assertEqual(3, count(Generated, <<"spawn SchedulerRouter">>)),
    ?assertEqual(3, count(Generated, <<"::SharedService<">>)),
    ?assertEqual(6, count(Generated, <<
        "ScheduledRequest, CHANNEL_DEPTH"
    >>)),
    ?assertEqual(0, count(Generated, <<"FamilyRouter">>)),
    ?assertEqual(0, count(Generated, <<"FamilyIngress">>)),
    ?assertEqual(0, count(Generated, <<"FamilyNode">>)),
    ?assertEqual(0, count(Generated, <<"chan<axis::Frame, u32:0>">>)),
    ?assertEqual(0, count(Generated, <<"spawn axis::FrameMux2(">>)),
    ?assertEqual(0, count(Generated, <<"spawn axis::ReservedFrame(">>)),
    ?assertEqual(1, count(Generated, <<"proc ControlDispatcher">>)),
    ?assertEqual(1, count(Generated, <<"spawn ControlDispatcher">>)),
    %% Each RAM request appears in Top's member and config lists and once more
    %% in SchedulerGrid's config list.
    ?assertEqual(9, count(Generated, <<"::MachineRamReq> out">>)),
    ?assertEqual(9, count(Generated, <<"::MailboxRamReq> out">>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "state.packet.target == u2:0"
    >>)),
    assert_ingress_selector(Generated, phenom_data_cell, pauli_query),
    assert_ingress_selector(Generated, phenom_data_cell, pauli_update),
    assert_ingress_selector(Generated, phenom_data_cell, noise_cutoff),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "control_router_in: chan<hls_spatial_router::SpatialFrame> in"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "hls_spatial_router::contains(\n"
        "            state.packet.rectangle, address_x, address_y)"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "proc SchedulerGrid {"
    >>)).

generated_family_topology_uses_explicit_actor_egress_depth_test() ->
    Plan = hls_topology:normalize(phi_noise_topology:topology()),
    Profile = maps:remove(
        scheduler_groups,
        phi_noise_topology_dslx:profile()
    ),
    lists:foreach(
        fun(Depth) ->
            Generated = iolist_to_binary(xls_topology_dslx:emit(
                Plan,
                Profile#{actor_egress_depth := Depth}
            )),
            Needle = iolist_to_binary([
                "::Egress, u32:", integer_to_list(Depth), ">"
            ]),
            ?assertEqual(6, count(Generated, Needle))
        end,
        [0, 1]
    ).

generated_family_startup_precedes_routed_input_test() ->
    Generated = iolist_to_binary(phi_noise_topology_dslx:to_dslx()),
    ?assertEqual(36, count(Generated, <<"frame: axis::pack(u8:6,">>)),
    ?assertEqual(18, count(Generated, <<"frame: axis::pack(u8:12,">>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<"uN[96]:0x">>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "proc SchedulerStartup0 {"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "spawn SchedulerStartup0(scheduler_0_startup_p);"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "let _done = send_if(join(), request_out, active, request);"
    >>)),
    ?assertEqual(0, count(Generated, <<"admission_in">>)).

generated_phi_torus_startup_is_per_coordinate_test() ->
    Generated = generated(phi_torus_topology:topology()),
    ?assertEqual(6, count(Generated, <<") => axis::pack(">>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "join(), frame_out, family_0_startup(X, Y));"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "spawn FamilyNode<x, y>("
    >>)).

family_backend_rejects_partial_family_startup_test() ->
    Plan = hls_topology:normalize(phi_noise_topology:topology(2)),
    [_First | Rest] = maps:get(startup, Plan),
    ?assertError(
        {incomplete_family_startup, data_even, 4, 3},
        xls_topology_dslx:emit(
            Plan#{startup := Rest},
            phi_noise_topology_dslx:profile()
        )
    ).

family_backend_rejects_invalid_actor_egress_depth_test() ->
    Plan = hls_topology:normalize(phi_noise_topology:topology(1)),
    Profile = phi_noise_topology_dslx:profile(),
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

family_backend_rejects_cross_family_selector_remap_test() ->
    Plan = hls_topology:normalize(selector_remap_topology()),
    Recipient = {family, source, {translate, [0, 0], wrap}},
    ?assertError(
        {unsupported_route_tag_remap,
            {destination, message_out},
            Recipient,
            message,
            4,
            3},
        xls_topology_dslx:emit(
            Plan,
            #{
                name => selector_remap_topology,
                channel_depth => 1,
                actor_egress_depth => burst
            }
        )
    ).

family_backend_rejects_incompatible_external_schema_test() ->
    Plan = hls_topology:normalize(external_schema_topology()),
    try xls_topology_dslx:emit(
            Plan,
            #{
                name => external_schema_topology,
                channel_depth => 1,
                actor_egress_depth => burst
            }
        ) of
        _ -> ?assert(false)
    catch
        error:{external_schema, shared, message, _Existing, _New} -> ok
    end.

family_backend_rejects_ambiguous_external_selector_test() ->
    Plan = hls_topology:normalize(external_selector_topology()),
    try xls_topology_dslx:emit(
            Plan,
            #{
                name => external_selector_topology,
                channel_depth => 1,
                actor_egress_depth => burst
            }
        ) of
        _ -> ?assert(false)
    catch
        error:{external_selector, shared, 3, _Existing, _New} -> ok
    end.

family_backend_rejects_route_fanout_test() ->
    Spec = phi_torus_topology:topology(3, 3),
    Source = {phi, north},
    Relations = [
        case Relation of
            {Source, _Recipients} ->
                {Source, coupled, [
                    {family, phi, {translate, [0, -1], wrap}},
                    {family, phi, {translate, [0, 1], wrap}}
                ]};
            _ -> Relation
        end
        || Relation <- maps:get(route_relations, Spec)
    ],
    Plan = hls_topology:normalize(Spec#{route_relations := Relations}),
    ?assertError(
        {unsupported_route,
            {phi, north},
            coupled,
            [
                {family, phi, {translate, [0, -1], wrap}},
                {family, phi, {translate, [0, 1], wrap}}
            ]},
        xls_topology_dslx:emit(Plan, phi_torus_topology_dslx:profile())
    ).

family_backend_rejects_stale_lane_cache_test() ->
    Plan = hls_topology:normalize(phi_torus_topology:topology(3, 4)),
    Cached = maps:get(lane_relations, Plan),
    Reversed = lists:reverse(Cached),
    try xls_topology_dslx:emit(
            Plan#{lane_relations := Reversed},
            phi_torus_topology_dslx:profile()
        ) of
        _ -> ?assert(false)
    catch
        error:{inconsistent_dslx_family_plan_lanes, Expected, Actual} ->
            ?assertEqual(Cached, Expected),
            ?assertEqual(Reversed, Actual)
    end.

family_backend_rejects_headless_plan_test() ->
    Plan = hls_topology:from_module(phi_torus_topology),
    ?assertError(
        {unsupported_dslx_family_external_count, 0},
        xls_topology_dslx:emit(
            Plan#{externals := []},
            phi_torus_topology_dslx:profile()
        )
    ).

family_backend_rejects_dimensions_wider_than_dslx_u32_test() ->
    TooWide = 16#100000000,
    Spec = phi_torus_topology:topology(1, 1),
    Families = maps:get(families, Spec),
    Plan = hls_topology:normalize(Spec#{
        families := Families#{phi := #{
            module => phi_halo_cell,
            shape => [TooWide, 1]
        }},
        startup := []
    }),
    ?assertError(
        {unsupported_dslx_family_dimensions,
            phi,
            [TooWide, 1],
            16#ffffffff},
        xls_topology_dslx:emit(Plan, phi_torus_topology_dslx:profile())
    ).

rectangle_ingress_accepts_the_full_u16_coordinate_extent_test() ->
    Plan0 = hls_topology:normalize(phi_noise_topology:topology(1)),
    [Ingress0] = maps:get(ingresses, Plan0),
    Plan = Plan0#{ingresses := [Ingress0#{shape := [16#10000, 2]}]},
    Generated = iolist_to_binary(xls_topology_dslx:emit(
        Plan,
        phi_noise_topology_dslx:profile()
    )),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "control_router_in: chan<hls_spatial_router::SpatialFrame> in"
    >>)).

rectangle_ingress_rejects_an_extent_beyond_u16_coordinates_test() ->
    Plan0 = hls_topology:normalize(phi_noise_topology:topology(1)),
    [Ingress0] = maps:get(ingresses, Plan0),
    Plan = Plan0#{ingresses := [Ingress0#{shape := [16#10001, 2]}]},
    ?assertError(
        {ingress_shape, [16#10001, 2], 16#10000},
        xls_topology_dslx:emit(
            Plan,
            phi_noise_topology_dslx:profile()
        )
    ).

generated(Spec) ->
    iolist_to_binary(xls_topology_dslx:emit(
        hls_topology:normalize(Spec),
        phi_torus_topology_dslx:profile()
    )).

assert_ingress_selector(Generated, Module, Schema) ->
    Selector = Module:pack_tag(Schema),
    Needle = iolist_to_binary([
        "state.packet.frame.header.op == u8:", integer_to_list(Selector)
    ]),
    ?assertNotEqual(nomatch, binary:match(Generated, Needle)).

selector_remap_topology() ->
    #{
        version => 1,
        ingresses => [],
        actors => #{},
        families => #{
            source => #{
                module => hls_topology_source_fixture,
                shape => [1, 1]
            },
            destination => #{
                module => hls_topology_reordered_fixture,
                shape => [1, 1]
            }
        },
        externals => [{padding, out, [padding]}],
        routes => [],
        route_relations => [
            {{source, out}, [
                {family, destination, {translate, [0, 0], wrap}}
            ]},
            {{destination, message_out}, [
                {family, source, {translate, [0, 0], wrap}}
            ]},
            {{destination, padding_out}, [{external, padding}]}
        ],
        startup => []
    }.

shared_external_topology() ->
    #{
        version => 1,
        ingresses => [],
        actors => #{},
        families => #{
            left => #{module => phi_halo_cell, shape => [2, 2]},
            right => #{module => phi_halo_cell, shape => [2, 2]}
        },
        externals => [
            {syndrome_requests, out, [phenom_request]},
            {decoder_events, out, [phi_correction, phi_status]}
        ],
        routes => [],
        route_relations =>
            shared_external_relations(left) ++
                shared_external_relations(right),
        startup => []
    }.

shared_external_relations(Family) ->
    [
        {{Family, north}, [
            {family, Family, {translate, [0, -1], wrap}}
        ]},
        {{Family, east}, [
            {family, Family, {translate, [1, 0], wrap}}
        ]},
        {{Family, west}, [
            {family, Family, {translate, [-1, 0], wrap}}
        ]},
        {{Family, south}, [
            {family, Family, {translate, [0, 1], wrap}}
        ]},
        {{Family, syndrome}, [{external, syndrome_requests}]},
        {{Family, correction}, [{external, decoder_events}]},
        {{Family, status}, [{external, decoder_events}]}
    ].

external_schema_topology() ->
    external_fixture_topology(
        [{shared, out, [message]}, {padding, out, [padding]}],
        [
            {{source, out}, [{external, shared}]},
            {{destination, message_out}, [{external, shared}]},
            {{destination, padding_out}, [{external, padding}]}
        ]
    ).

external_selector_topology() ->
    external_fixture_topology(
        [{shared, out, [message, padding]}, {message, out, [message]}],
        [
            {{source, out}, [{external, shared}]},
            {{destination, message_out}, [{external, message}]},
            {{destination, padding_out}, [{external, shared}]}
        ]
    ).

external_fixture_topology(Externals, Relations) ->
    #{
        version => 1,
        ingresses => [],
        actors => #{},
        families => #{
            source => #{
                module => hls_topology_source_fixture,
                shape => [1, 1]
            },
            destination => #{
                module => hls_topology_reordered_fixture,
                shape => [1, 1]
            }
        },
        externals => Externals,
        routes => [],
        route_relations => Relations,
        startup => []
    }.

scrub_dimensions(Generated, Value) ->
    Width = <<"const WIDTH = u32:", Value/binary, ";">>,
    Height = <<"const HEIGHT = u32:", Value/binary, ";">>,
    binary:replace(
        binary:replace(Generated, Width, <<"const WIDTH = u32:N;">>),
        Height,
        <<"const HEIGHT = u32:N;">>
    ).

count(Binary, Pattern) ->
    length(binary:matches(Binary, Pattern)).
