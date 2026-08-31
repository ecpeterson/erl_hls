-module(xls_topology_family_tests).

-include_lib("eunit/include/eunit.hrl").

generated_family_topology_is_compact_test() ->
    Generated = generated(phi_torus_topology:topology(2, 2)),
    ?assertEqual(1, count(Generated, <<"spawn FamilyNode(">>)),
    ?assertEqual(1, count(Generated, <<"spawn phi_halo_cell::Service(">>)),
    ?assertEqual(3, count(Generated,
        <<"chan<axis::Frame, CHANNEL_DEPTH>[TORUS_HEIGHT][TORUS_WIDTH]">>
    )),
    ?assertEqual(4, count(Generated, <<"unroll_for! (">>)),
    ?assertEqual(nomatch, binary:match(Generated, <<"actor_0">>)),
    ?assertEqual(nomatch, binary:match(Generated, <<"{phi,0,0}">>)).

generated_two_by_two_router_preserves_alias_lanes_test() ->
    Generated = generated(phi_torus_topology:topology(2, 2)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "OutputPort::NORTH => send(tok, lane_1_out, egress.frame),\n"
        "      phi_halo_cell::OutputPort::EAST => send(tok, lane_2_out, "
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "OutputPort::WEST => send(tok, lane_2_out, egress.frame),\n"
        "      phi_halo_cell::OutputPort::SOUTH => send(tok, lane_1_out, "
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "lane_1_c[x][(y + TORUS_HEIGHT - u32:1) % TORUS_HEIGHT]"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "lane_2_c[(x + TORUS_WIDTH - u32:1) % TORUS_WIDTH][y]"
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
        <<"lane_1_c[(x + u32:1) % TORUS_WIDTH][y]">>,
        <<"lane_2_c[x][(y + u32:1) % TORUS_HEIGHT]">>,
        <<"lane_3_c[x][(y + TORUS_HEIGHT - u32:1) % TORUS_HEIGHT]">>,
        <<"lane_4_c[(x + TORUS_WIDTH - u32:1) % TORUS_WIDTH][y]">>
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
    ?assertEqual(5, count(Large,
        <<"chan<axis::Frame, CHANNEL_DEPTH>[TORUS_HEIGHT][TORUS_WIDTH]">>
    )).

generated_family_topology_matches_checked_in_artifact_test() ->
    {ok, Expected} = file:read_file(
        "src/examples/phi_decoder/phi_torus_topology.x"
    ),
    ?assertEqual(
        Expected,
        iolist_to_binary(phi_torus_topology_dslx:to_dslx())
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
