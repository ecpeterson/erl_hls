-module(phi_memory_gateway_dslx_tests).

-include_lib("eunit/include/eunit.hrl").

checked_gateway_matches_generator_test() ->
    {ok, Checked} = file:read_file(
        "src/examples/phi_decoder/phi_memory_gateway.x"
    ),
    ?assertEqual(
        Checked,
        iolist_to_binary(phi_memory_gateway_dslx:to_dslx())
    ).

generated_gateway_ends_with_newline_test() ->
    ?assertEqual($\n, binary:last(generated(3))).

default_gateway_keeps_topology_as_an_import_test() ->
    Generated = generated(3),
    ?assertNotEqual(
        nomatch,
        binary:match(Generated, <<"import phi_noise_topology;">>)
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(Generated, <<"spawn phi_noise_topology::Top(">>)
    ),
    ?assertEqual(nomatch, binary:match(Generated, <<"proc FamilyGrid<">>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<"const WIDTH = u16:3;">>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<"const HEIGHT = u16:3;">>)).

smoke_gateway_imports_distance_one_staging_topology_test() ->
    Generated = generated(1),
    ?assertMatch(<<"// phi_memory_gateway_smoke.x\n", _/binary>>, Generated),
    ?assertNotEqual(
        nomatch,
        binary:match(Generated, <<"import phi_noise_topology_smoke;">>)
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(Generated, <<"spawn phi_noise_topology_smoke::Top(">>)
    ),
    ?assertNotEqual(nomatch, binary:match(Generated, <<"const WIDTH = u16:1;">>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<"const HEIGHT = u16:1;">>)).

boundary_contract_is_explicit_test() ->
    Generated = generated(3),
    assert_contains(Generated, <<"type BoundaryFrame = axis::FrameN<">>),
    assert_contains(Generated, <<"header.flags == BOUNDARY_VERSION">>),
    assert_contains(Generated, <<"header.txid == u8:0">>),
    assert_contains(Generated, <<"OP_NOISE_CUTOFF => header.payload_words == u8:3">>),
    assert_contains(Generated, <<"OP_PAULI_UPDATE => header.payload_words == u8:3">>),
    assert_contains(Generated, <<"OP_PAULI_QUERY => header.payload_words == u8:4">>),
    assert_contains(Generated, <<"x0: frame.payload[0:16] as u16">>),
    assert_contains(Generated, <<"y1: frame.payload[48:64] as u16">>),
    assert_contains(Generated, <<"payload: frame.payload[64:128] as bits[96]">>),
    assert_contains(Generated, <<"bounds.x1 < WIDTH && bounds.y1 < DATA_HEIGHT">>),
    assert_contains(Generated, <<"frame.payload[64:96] as u32 <= u32:3">>),
    assert_contains(Generated, <<"frame.payload[96:128] as u32 <= u32:3">>).

first_valid_command_arms_topology_egress_test() ->
    Generated = generated(3),
    assert_contains(Generated, <<"send_if(tok, arm_out, valid && !armed">>),
    assert_contains(Generated, <<"send_if(\n      arm_tok, spatial_out, valid">>),
    assert_contains(Generated, <<
        "proc EgressGate {\n  frame_in: chan<RoutedFrame> in;"
    >>),
    assert_contains(Generated, <<"if armed {\n      let (tok, frame) = recv(join(), frame_in);">>),
    assert_contains(Generated, <<"spawn SpatialIngress(boundary_frames_c, control_p, arm_p)">>),
    assert_contains(Generated, <<"chan<RoutedFrame, u32:1>(\"pre_gate\")">>),
    assert_contains(Generated, <<"spawn FrameMux(topology_outputs_c, pre_gate_p)">>),
    assert_contains(Generated, <<"spawn EgressGate(pre_gate_c, egress_p, arm_c)">>),
    assert_contains(Generated, <<"chan<axis::Frame, u32:0>[u32:5](\"topology_outputs\")">>),
    ?assertEqual(nomatch, binary:match(Generated, <<"FrameMux {\n  arm_in:">>)).

same_channel_operations_have_one_syntactic_site_test() ->
    Generated = generated(3),
    assert_contains(Generated, <<
        "let (tok, routed) = recv_if(\n      join(), frame_in, !state.active"
    >>),
    ?assertEqual(
        nomatch,
        binary:match(Generated, <<"let (tok, state2) = if state.active">>)
    ),
    assert_contains(Generated, <<
        "let (beat, next_state) = if state2.route_pending {"
    >>),
    ?assertEqual(
        1,
        count(Generated, <<"let _done = send(tok, routed_out, beat);">>)
    ),
    ?assertEqual(
        nomatch,
        binary:match(Generated, <<"send(tok, routed_out, axis::Beat">>)
    ),
    {ok, Axis} = file:read_file("priv/xls/lib/axis.x"),
    assert_contains(Axis, <<
        "let (frame, valid, next_state) = if !state.active {"
    >>),
    ?assertEqual(
        1,
        count(Axis, <<"send_if(tok, instr_out, valid, frame)">>)
    ).

egress_contract_is_explicit_test() ->
    Generated = generated(3),
    lists:foreach(
        fun(Endpoint) -> assert_contains(Generated, Endpoint) end,
        [
            <<"const DATA_MEASUREMENTS_ENDPOINT = u16:2;">>,
            <<"const X_ANNOUNCEMENTS_ENDPOINT = u16:3;">>,
            <<"const X_DECODER_EVENTS_ENDPOINT = u16:4;">>,
            <<"const Z_ANNOUNCEMENTS_ENDPOINT = u16:5;">>,
            <<"const Z_DECODER_EVENTS_ENDPOINT = u16:6;">>
        ]
    ),
    assert_contains(Generated, <<"cursor == candidate">>),
    assert_contains(Generated, <<"cursor == u32:4 { u32:0 }">>),
    assert_contains(Generated, <<"word: route_word(state2.source, HOST_ENDPOINT)">>),
    assert_contains(Generated, <<"flags: BOUNDARY_VERSION">>),
    assert_contains(Generated, <<"txid: u8:0">>).

unsupported_distance_is_rejected_test() ->
    ?assertError(badarg, phi_memory_gateway_dslx:to_dslx(2)).

generated(Distance) ->
    iolist_to_binary(phi_memory_gateway_dslx:to_dslx(Distance)).

assert_contains(Haystack, Needle) ->
    ?assertNotEqual(nomatch, binary:match(Haystack, Needle)).

count(Haystack, Needle) ->
    length(binary:matches(Haystack, Needle)).
