-module(phi_source_xls_topology_family_tests).

-include_lib("eunit/include/eunit.hrl").

%% Checks generated family topology is compact for the retained Phi application.
-spec generated_family_topology_is_compact_test() -> ok.
generated_family_topology_is_compact_test() ->
    Generated = generated(phi_torus_topology:topology(2, 2)),
    ?assertEqual(1, count(Generated, <<"spawn FamilyNode<">>)),
    ?assertEqual(1, count(Generated, <<"spawn phi_halo_cell::Service(">>)),
    ?assertEqual(4, count(Generated,
        <<"chan<axis::Frame, u32:0>[TORUS_HEIGHT][TORUS_WIDTH]">>
    )),
    ?assertEqual(2, count(Generated, <<"unroll_for! (">>)),
    ?assertEqual(1, count(Generated, <<"proc FamilyIngress<">>)),
    ?assertEqual(1, count(Generated, <<"spawn FamilyIngress<">>)),
    ?assertEqual(0, count(Generated, <<"spawn axis::FrameMux2(">>)),
    ?assertEqual(0, count(Generated, <<"spawn axis::ReservedFrame(">>)),
    ?assertEqual(nomatch, binary:match(Generated, <<"actor_0">>)),
    ?assertEqual(nomatch, binary:match(Generated, <<"{phi,0,0}">>)).

%% Checks generated two by two router preserves alias lanes for the retained Phi application.
-spec generated_two_by_two_router_preserves_alias_lanes_test() -> ok.
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

%% Checks generated external merge uses shared transport for the retained Phi application.
-spec generated_external_merge_uses_shared_transport_test() -> ok.
generated_external_merge_uses_shared_transport_test() ->
    Generated = generated(phi_torus_topology:topology(3, 3)),
    ?assertNotEqual(nomatch, binary:match(Generated,
        <<"import frame_transport;">>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "spawn frame_transport::FrameGridMux<"
        "TORUS_WIDTH, TORUS_HEIGHT, CHANNEL_DEPTH>("
    >>)).

%% Checks generated external merges distinct source families for the retained Phi application.
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

%% Checks rectangular torus wires all inverse translations for the retained Phi application.
-spec rectangular_torus_wires_all_inverse_translations_test() -> ok.
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

%% Checks five and fifty wide tori have the same generated route structure for the retained Phi application.
-spec five_and_fifty_wide_tori_have_the_same_generated_route_structure_test() -> ok.
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

%% Checks generated family topology matches checked in artifact for the retained Phi application.
-spec generated_family_topology_matches_checked_in_artifact_test() -> ok.
generated_family_topology_matches_checked_in_artifact_test() ->
    {ok, Expected} = file:read_file(
        "apps/hls_phi/src/phi_torus_topology.x"
    ),
    ?assertEqual(
        Expected,
        iolist_to_binary(phi_torus_topology_dslx:to_dslx())
    ).

%% Checks generated phi torus startup is per coordinate for the retained Phi application.
-spec generated_phi_torus_startup_is_per_coordinate_test() -> ok.
generated_phi_torus_startup_is_per_coordinate_test() ->
    Generated = generated(phi_torus_topology:topology()),
    ?assertEqual(6, count(Generated, <<") => axis::pack(">>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "join(), frame_out, family_0_startup(X, Y));"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "spawn FamilyNode<x, y>("
    >>)).

%% Emits a checked Phi family with its maintained deployment profile.
-spec generated(hls_topology:spec()) -> binary().
generated(Spec) ->
    iolist_to_binary(xls_topology_dslx:emit(
        hls_topology:normalize(Spec),
        phi_torus_topology_dslx:profile()
    )).

%% Builds two Phi families sharing the same declared host boundaries.
-spec shared_external_topology() -> hls_topology:spec().
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

%% Retains the seven Phi output relations for one family.
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
        {{Family, syndrome}, [{external, syndrome_requests}]},
        {{Family, correction}, [{external, decoder_events}]},
        {{Family, status}, [{external, decoder_events}]}
    ].

%% Removes only dimension literals to compare compact application route structure.
-spec scrub_dimensions(binary(), binary()) -> binary().
scrub_dimensions(Generated, Value) ->
    Width = <<"const WIDTH = u32:", Value/binary, ";">>,
    Height = <<"const HEIGHT = u32:", Value/binary, ";">>,
    binary:replace(
        binary:replace(Generated, Width, <<"const WIDTH = u32:N;">>),
        Height,
        <<"const HEIGHT = u32:N;">>
    ).

%% Counts exact fragments in the generated application source.
-spec count(binary(), binary()) -> non_neg_integer().
count(Binary, Pattern) ->
    length(binary:matches(Binary, Pattern)).
