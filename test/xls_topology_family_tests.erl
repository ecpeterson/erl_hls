-module(xls_topology_family_tests).

-include_lib("eunit/include/eunit.hrl").

generated_family_topology_is_compact_test() ->
    Generated = generated(phi_torus_topology:topology(2, 2)),
    ?assertEqual(1, count(Generated, <<"spawn FamilyNode(">>)),
    ?assertEqual(1, count(Generated, <<"spawn phi_halo_cell::Service(">>)),
    ?assertEqual(4, count(Generated,
        <<"chan<axis::Frame, u32:0>[TORUS_HEIGHT][TORUS_WIDTH]">>
    )),
    ?assertEqual(4, count(Generated, <<"unroll_for! (">>)),
    ?assertEqual(1, count(Generated, <<"proc FamilyIngress {">>)),
    ?assertEqual(1, count(Generated, <<"spawn FamilyIngress(">>)),
    ?assertEqual(0, count(Generated, <<"spawn axis::FrameMux2(">>)),
    ?assertEqual(0, count(Generated, <<"spawn axis::ReservedFrame(">>)),
    ?assertEqual(nomatch, binary:match(Generated, <<"actor_0">>)),
    ?assertEqual(nomatch, binary:match(Generated, <<"{phi,0,0}">>)).

generated_two_by_two_router_preserves_alias_lanes_test() ->
    Generated = generated(phi_torus_topology:topology(2, 2)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "OutputPort::NORTH => send(tok, lane_2_out, egress.frame),\n"
        "      phi_halo_cell::OutputPort::EAST => send(tok, lane_3_out, "
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "OutputPort::WEST => send(tok, lane_3_out, egress.frame),\n"
        "      phi_halo_cell::OutputPort::SOUTH => send(tok, lane_2_out, "
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

five_and_fifty_wide_tori_have_the_same_generated_structure_test() ->
    Small = generated(phi_torus_topology:topology(5, 5)),
    Large = generated(phi_torus_topology:topology(50, 50)),
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
    ?assertEqual(6, count(Generated, <<"proc FamilyRouter">>)),
    ?assertEqual(6, count(Generated, <<"proc FamilyIngress">>)),
    ?assertEqual(6, count(Generated, <<"proc FamilyNode">>)),
    ?assertEqual(6, count(Generated, <<"spawn FamilyIngress">>)),
    ?assertEqual(6, count(Generated, <<"spawn FamilyNode">>)),
    ?assertEqual(32, count(Generated, <<
        "chan<axis::Frame, u32:0>[TORUS_HEIGHT][TORUS_WIDTH]"
    >>)),
    %% The 32 lane arrays use per-coordinate router output registers as their
    %% holding slots. The six actor request queues and reusable external
    %% grid-column queue remain explicit; ingress itself adds no Frame queue.
    ?assertEqual(7, count(Generated, <<
        "chan<axis::Frame, CHANNEL_DEPTH>"
    >>)),
    ?assertEqual(4, count(Generated, <<"fn family_">>)),
    ?assertEqual(0, count(Generated, <<"StartupPrefix">>)),
    ?assertEqual(0, count(Generated, <<"spawn axis::FrameMux2(">>)),
    ?assertEqual(0, count(Generated, <<"spawn axis::ReservedFrame(">>)),
    ?assertEqual(2, count(Generated, <<
        "let branch_0_tok = send(tok"
    >>)),
    ?assertEqual(4, count(Generated, <<
        "spawn FrameGridMux<TORUS_WIDTH, TORUS_HEIGHT>("
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "proc FamilyGrid<TORUS_WIDTH: u32, TORUS_HEIGHT: u32>"
    >>)).

generated_family_startup_precedes_routed_input_test() ->
    Generated = iolist_to_binary(phi_noise_topology_dslx:to_dslx()),
    ?assertEqual(36, count(Generated, <<") => axis::pack(u8:6,">>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<"uN[96]:0x">>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "if !state.1 {\n"
        "      let (_tok, _credit) = recv(join(), admission_in);\n"
        "      (state.0, u1:1, state.2)\n"
        "    } else if !state.2 {\n"
        "      let _tok = send(\n"
        "        join(), frame_out, family_0_startup(X, Y));\n"
        "      (state.0, u1:0, u1:1)"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "spawn FamilyIngress0<X, Y>("
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "let _done = send_if(tok_"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "spawn FamilyNode0<x, y>("
    >>)),
    ?assertEqual(nomatch, binary:match(Generated, <<
        "startup_frame: axis::Frame"
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
            #{name => selector_remap_topology, channel_depth => 1}
        )
    ).

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
    Plan = hls_topology:normalize(phi_torus_topology:topology(TooWide, 1)),
    ?assertError(
        {unsupported_dslx_family_dimensions,
            phi,
            [TooWide, 1],
            16#ffffffff},
        xls_topology_dslx:emit(Plan, phi_torus_topology_dslx:profile())
    ).

generated(Spec) ->
    iolist_to_binary(xls_topology_dslx:emit(
        hls_topology:normalize(Spec),
        phi_torus_topology_dslx:profile()
    )).

selector_remap_topology() ->
    #{
        version => 1,
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
