-module(xls_topology_family_tests).

-include_lib("eunit/include/eunit.hrl").

%% Checks generated family topology is compact.
-spec generated_family_topology_is_compact_test() -> ok.
generated_family_topology_is_compact_test() ->
    Generated = generated(hls_grid_topology_fixture:topology(2, 2)),
    ?assertEqual(1, count(Generated, <<"spawn FamilyNode<">>)),
    ?assertEqual(1, count(Generated, <<"spawn hls_grid_cell_fixture::Service(">>)),
    ?assertEqual(4, count(Generated,
        <<"chan<axis::Frame, u32:0>[TORUS_HEIGHT][TORUS_WIDTH]">>
    )),
    ?assertEqual(2, count(Generated, <<"unroll_for! (">>)),
    ?assertEqual(1, count(Generated, <<"proc FamilyIngress<">>)),
    ?assertEqual(1, count(Generated, <<"spawn FamilyIngress<">>)),
    ?assertEqual(0, count(Generated, <<"spawn axis::FrameMux2(">>)),
    ?assertEqual(0, count(Generated, <<"spawn axis::ReservedFrame(">>)),
    ?assertEqual(nomatch, binary:match(Generated, <<"actor_0">>)),
    ?assertEqual(nomatch, binary:match(Generated, <<"{grid,0,0}">>)).

%% Checks generated two by two router preserves alias lanes.
-spec generated_two_by_two_router_preserves_alias_lanes_test() -> ok.
generated_two_by_two_router_preserves_alias_lanes_test() ->
    Generated = generated(hls_grid_topology_fixture:topology(2, 2)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "OutputPort::NORTH => true,\n"
        "      hls_grid_cell_fixture::OutputPort::SOUTH => true,\n"
        "      _ => false,"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "OutputPort::EAST => true,\n"
        "      hls_grid_cell_fixture::OutputPort::WEST => true,\n"
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

%% Checks generated external merge uses shared transport.
-spec generated_external_merge_uses_shared_transport_test() -> ok.
generated_external_merge_uses_shared_transport_test() ->
    Generated = generated(hls_grid_topology_fixture:topology(3, 3)),
    ?assertNotEqual(nomatch, binary:match(Generated,
        <<"import frame_transport;">>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "spawn frame_transport::FrameGridMux<"
        "TORUS_WIDTH, TORUS_HEIGHT, CHANNEL_DEPTH>("
    >>)).

%% Checks generated external merges distinct source families.
-spec generated_external_merges_distinct_source_families_test() -> ok.
generated_external_merges_distinct_source_families_test() ->
    Generated = generated(shared_external_topology()),
    ?assertEqual(2, count(Generated, <<"spawn FamilyNode">>)),
    ?assertEqual(4, count(Generated, <<
        "spawn frame_transport::FrameGridMux<TORUS_WIDTH, TORUS_HEIGHT, CHANNEL_DEPTH>("
    >>)),
    ?assertEqual(2, count(Generated, <<
        "chan<axis::Frame, CHANNEL_DEPTH>[u32:2]"
    >>)),
    ?assertEqual(2, count(Generated, <<"spawn frame_transport::FrameArrayMux<u32:2>(">>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "external_0_lanes_p[u32:0]"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "external_0_lanes_p[u32:1]"
    >>)).

%% Checks family backend rejects external without a lane.
-spec family_backend_rejects_external_without_a_lane_test() -> ok.
family_backend_rejects_external_without_a_lane_test() ->
    Spec = hls_grid_topology_fixture:topology(2, 2),
    Plan = hls_topology:normalize(Spec#{
        externals := maps:get(externals, Spec) ++ [
            {orphan, out, [request]}
        ]
    }),
    ?assertError(
        {external_lanes, orphan, 0},
        xls_topology_dslx:emit(
            Plan,
            hls_grid_topology_fixture:profile()
        )
    ).

%% Checks rectangular torus wires all inverse translations.
-spec rectangular_torus_wires_all_inverse_translations_test() -> ok.
rectangular_torus_wires_all_inverse_translations_test() ->
    Generated = generated(hls_grid_topology_fixture:topology(3, 4)),
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

%% Checks five and fifty wide tori have the same generated route structure.
-spec five_and_fifty_wide_tori_have_the_same_generated_route_structure_test() -> ok.
five_and_fifty_wide_tori_have_the_same_generated_route_structure_test() ->
    %% Instance constants are still enumerated by the v0 startup model. Strip
    %% them here to isolate the compact family and route representation.
    SmallSpec = hls_grid_topology_fixture:topology(5, 5),
    LargeSpec = hls_grid_topology_fixture:topology(50, 50),
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

%% Checks generated grid torus startup is per coordinate.
-spec generated_grid_torus_startup_is_per_coordinate_test() -> ok.
generated_grid_torus_startup_is_per_coordinate_test() ->
    Generated = generated(hls_grid_topology_fixture:topology()),
    ?assertEqual(6, count(Generated, <<") => axis::pack(">>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "join(), frame_out, family_0_startup(X, Y));"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "spawn FamilyNode<x, y>("
    >>)).

%% Checks family backend rejects out of range startup fields.
-spec family_backend_rejects_out_of_range_startup_fields_test() -> ok.
family_backend_rejects_out_of_range_startup_fields_test() ->
    Spec = hls_grid_topology_fixture:topology(1, 1),
    lists:foreach(fun(Seed) ->
        ?assertError(badarg, generated(Spec#{startup := [
            {{grid, 0, 0}, [{seed, Seed}]}
        ]}))
    end, [-1, 1 bsl 32]).

%% Checks family backend rejects cross family selector remap.
-spec family_backend_rejects_cross_family_selector_remap_test() -> ok.
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

%% Checks family backend rejects incompatible external schema.
-spec family_backend_rejects_incompatible_external_schema_test() -> ok.
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

%% Checks family backend rejects ambiguous external selector.
-spec family_backend_rejects_ambiguous_external_selector_test() -> ok.
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

%% Checks family backend rejects route fanout.
-spec family_backend_rejects_route_fanout_test() -> ok.
family_backend_rejects_route_fanout_test() ->
    Spec = hls_grid_topology_fixture:topology(3, 3),
    Source = {grid, north},
    Relations = [
        case Relation of
            {Source, _Recipients} ->
                {Source, coupled, [
                    {family, grid, {translate, [0, -1], wrap}},
                    {family, grid, {translate, [0, 1], wrap}}
                ]};
            _ -> Relation
        end
        || Relation <- maps:get(route_relations, Spec)
    ],
    Plan = hls_topology:normalize(Spec#{route_relations := Relations}),
    ?assertError(
        {unsupported_route,
            {grid, north},
            coupled,
            [
                {family, grid, {translate, [0, -1], wrap}},
                {family, grid, {translate, [0, 1], wrap}}
            ]},
        xls_topology_dslx:emit(Plan, hls_grid_topology_fixture:profile())
    ).

%% Checks family backend rejects stale lane cache.
-spec family_backend_rejects_stale_lane_cache_test() -> ok.
family_backend_rejects_stale_lane_cache_test() ->
    Plan = hls_topology:normalize(hls_grid_topology_fixture:topology(3, 4)),
    Cached = maps:get(lane_relations, Plan),
    Reversed = lists:reverse(Cached),
    try xls_topology_dslx:emit(
            Plan#{lane_relations := Reversed},
            hls_grid_topology_fixture:profile()
        ) of
        _ -> ?assert(false)
    catch
        error:{inconsistent_dslx_family_plan_lanes, Expected, Actual} ->
            ?assertEqual(Cached, Expected),
            ?assertEqual(Reversed, Actual)
    end.

%% Checks family backend rejects headless plan.
-spec family_backend_rejects_headless_plan_test() -> ok.
family_backend_rejects_headless_plan_test() ->
    Plan = hls_topology:from_module(hls_grid_topology_fixture),
    ?assertError(
        {unsupported_dslx_family_external_count, 0},
        xls_topology_dslx:emit(
            Plan#{externals := []},
            hls_grid_topology_fixture:profile()
        )
    ).

%% Checks family backend rejects dimensions wider than dslx u32.
-spec family_backend_rejects_dimensions_wider_than_dslx_u32_test() -> ok.
family_backend_rejects_dimensions_wider_than_dslx_u32_test() ->
    TooWide = 16#100000000,
    Spec = hls_grid_topology_fixture:topology(1, 1),
    Families = maps:get(families, Spec),
    Plan = hls_topology:normalize(Spec#{
        families := Families#{grid := #{
            module => hls_grid_cell_fixture,
            shape => [TooWide, 1]
        }},
        startup := []
    }),
    ?assertError(
        {unsupported_dslx_family_dimensions,
            grid,
            [TooWide, 1],
            16#ffffffff},
        xls_topology_dslx:emit(Plan, hls_grid_topology_fixture:profile())
    ).

%% Renders one checked family with the fixed test profile.
-spec generated(hls_topology:spec()) -> binary().
generated(Spec) ->
    iolist_to_binary(xls_topology_dslx:emit(
        hls_topology:normalize(Spec),
        hls_grid_topology_fixture:profile()
    )).

%% Builds the minimal topology needed by this validation scenario.
-spec selector_remap_topology() -> hls_topology:spec().
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

%% Builds the minimal topology needed by this validation scenario.
-spec shared_external_topology() -> hls_topology:spec().
shared_external_topology() ->
    #{
        version => 1,
        ingresses => [],
        actors => #{},
        families => #{
            left => #{module => hls_grid_cell_fixture, shape => [2, 2]},
            right => #{module => hls_grid_cell_fixture, shape => [2, 2]}
        },
        externals => [
            {request_events, out, [request]},
            {result_events, out, [result, status]}
        ],
        routes => [],
        route_relations =>
            shared_external_relations(left) ++
                shared_external_relations(right),
        startup => []
    }.

%% Builds compact cardinal routes and two shared output boundaries.
-spec shared_external_relations(atom()) -> [tuple()].
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
        {{Family, query}, [{external, request_events}]},
        {{Family, result}, [{external, result_events}]},
        {{Family, status}, [{external, result_events}]}
    ].

%% Builds the minimal topology needed by this validation scenario.
-spec external_schema_topology() -> hls_topology:spec().
external_schema_topology() ->
    external_fixture_topology(
        [{shared, out, [message]}, {padding, out, [padding]}],
        [
            {{source, out}, [{external, shared}]},
            {{destination, message_out}, [{external, shared}]},
            {{destination, padding_out}, [{external, padding}]}
        ]
    ).

%% Builds the minimal topology needed by this validation scenario.
-spec external_selector_topology() -> hls_topology:spec().
external_selector_topology() ->
    external_fixture_topology(
        [{shared, out, [message, padding]}, {message, out, [message]}],
        [
            {{source, out}, [{external, shared}]},
            {{destination, message_out}, [{external, message}]},
            {{destination, padding_out}, [{external, shared}]}
        ]
    ).

%% Builds two minimal families with the requested external route contract.
-spec external_fixture_topology([tuple()], [tuple()]) -> hls_topology:spec().
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

%% Removes only dimension literals when comparing compact route structure.
-spec scrub_dimensions(binary(), binary()) -> binary().
scrub_dimensions(Generated, Value) ->
    Width = <<"const WIDTH = u32:", Value/binary, ";">>,
    Height = <<"const HEIGHT = u32:", Value/binary, ";">>,
    binary:replace(
        binary:replace(Generated, Width, <<"const WIDTH = u32:N;">>),
        Height,
        <<"const HEIGHT = u32:N;">>
    ).

%% Counts exact generated fragments for structural assertions.
-spec count(binary(), binary()) -> non_neg_integer().
count(Binary, Pattern) ->
    length(binary:matches(Binary, Pattern)).
