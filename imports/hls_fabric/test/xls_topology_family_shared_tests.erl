-module(xls_topology_family_shared_tests).

-include_lib("eunit/include/eunit.hrl").


%% Checks generated multi family topology retains compact structure.
-spec generated_multi_family_topology_retains_compact_structure_test() -> 'ok'.
generated_multi_family_topology_retains_compact_structure_test() ->
    Generated = iolist_to_binary(phi_shared_noise_topology_dslx:to_dslx()),
    ?assertEqual(6, count(Generated, <<"proc SchedulerRouter">>)),
    ?assertEqual(6, count(Generated, <<"spawn SchedulerRouter">>)),
    ?assertEqual(6, count(Generated, <<"::SharedService<">>)),
    ?assertEqual(0, count(Generated, <<"::EffectWindowAdapter(">>)),
    ?assertEqual(1, count(Generated, <<
        "spawn effect_window::Arbiter<"
    >>)),
    ?assertEqual(30, count(Generated, <<"::ScheduledEffects">>)),
    %% Each router decodes incoming index zero and its next retained effect;
    %% the two phi reduction routers also decode their four-frame prefixes.
    ?assertEqual(20, count(Generated, <<"::scheduled_effect(">>)),
    ?assertEqual(6, count(Generated, <<"let state_effect_info = state.head;">>)),
    ?assertEqual(6, count(Generated, <<"let effect_info = if state.control.active { state.head }">>)),
    ?assertEqual(6, count(Generated, <<"::scheduled_effect(incoming, u8:0);">>)),
    ?assertEqual(6, count(Generated, <<"scheduled: incoming, head: incoming_effect_info">>)),
    ?assertEqual(6, count(Generated, <<"::scheduled_effect(scheduled, next_index)">>)),
    ?assertEqual(0, count(Generated, <<"::scheduled_effect(state.scheduled, state.index)">>)),
    ?assertEqual(1, count(Generated, <<"proc Phi_xReductionPlane {">>)),
    ?assertEqual(1, count(Generated, <<"proc Phi_zReductionPlane {">>)),
    ?assertEqual(4, count(Generated, <<
        "let last = batch_valid && effect_info.2"
    >>)),
    ?assertEqual(2, count(Generated, <<
        "let last = batch_valid && if reduction_batch {"
    >>)),
    ?assertEqual(6, count(Generated, <<
        "routed_tok, credit_out, forward_credit"
    >>)),
    ?assertEqual(1, count(Generated, <<"fn scheduler_0_address(">>)),
    ?assertEqual(1, count(Generated, <<"fn scheduler_1_address(">>)),
    ?assertEqual(1, count(Generated, <<"fn scheduler_2_address(">>)),
    ?assertEqual(1, count(Generated, <<"fn scheduler_0_slot(">>)),
    ?assertEqual(1, count(Generated, <<"fn scheduler_1_slot(">>)),
    ?assertEqual(1, count(Generated, <<"fn scheduler_2_slot(">>)),
    ?assertEqual(1, count(Generated, <<"fn scheduler_3_address(">>)),
    ?assertEqual(1, count(Generated, <<"fn scheduler_4_address(">>)),
    ?assertEqual(1, count(Generated, <<"fn scheduler_5_address(">>)),
    ?assertEqual(1, count(Generated, <<"fn scheduler_3_slot(">>)),
    ?assertEqual(1, count(Generated, <<"fn scheduler_4_slot(">>)),
    ?assertEqual(1, count(Generated, <<"fn scheduler_5_slot(">>)),
    ?assertEqual(12, count(Generated, <<
        "ScheduledRequest, CHANNEL_DEPTH"
    >>)),
    ?assertEqual(0, count(Generated, <<"FamilyRouter">>)),
    ?assertEqual(0, count(Generated, <<"FamilyIngress">>)),
    ?assertEqual(0, count(Generated, <<"FamilyNode">>)),
    ?assertEqual(0, count(Generated, <<"chan<axis::Frame, u32:0>">>)),
    ?assertEqual(0, count(Generated, <<"spawn axis::FrameMux2(">>)),
    ?assertEqual(0, count(Generated, <<"spawn axis::ReservedFrame(">>)),
    ?assertEqual(0, count(Generated, <<" / HEIGHT">>)),
    ?assertEqual(0, count(Generated, <<" % HEIGHT">>)),
    ?assertEqual(0, count(Generated, <<" % WIDTH">>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "match address.family as FamilyId"
    >>)),
    ?assertEqual(1, count(Generated, <<"proc ControlDispatcher">>)),
    ?assertEqual(1, count(Generated, <<"spawn ControlDispatcher">>)),
    %% Each RAM channel appears in Top's member and config lists and once more
    %% in SchedulerGrid's config list.  Independent read and write ports let
    %% the shared scheduler overlap the younger read with the older commit.
    ?assertEqual(18, count(Generated, <<"::MachineRamReadReq> out">>)),
    ?assertEqual(18, count(Generated, <<"::MachineRamReadResp> in">>)),
    ?assertEqual(18, count(Generated, <<"::MachineRamWriteReq> out">>)),
    ?assertEqual(18, count(Generated, <<"::MachineRamWriteResp> in">>)),
    ?assertEqual(18, count(Generated, <<"::MailboxRamReadReq> out">>)),
    ?assertEqual(18, count(Generated, <<"::MailboxRamReadResp> in">>)),
    ?assertEqual(18, count(Generated, <<"::MailboxRamWriteReq> out">>)),
    ?assertEqual(18, count(Generated, <<"::MailboxRamWriteResp> in">>)),
    ?assertEqual(1, count(Generated, <<"spawn frame_transport::FrameArrayMux<u32:2>(">>)),
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

%% Checks generated one shard topology retains single external lanes.
-spec generated_one_shard_topology_retains_single_external_lanes_test() -> 'ok'.
generated_one_shard_topology_retains_single_external_lanes_test() ->
    Generated = iolist_to_binary(
        phi_shared_noise_topology_dslx:to_dslx(3, 16#80000000, 1)
    ),
    ?assertEqual(3, count(Generated, <<"::SharedService<">>)),
    ?assertEqual(0, count(Generated, <<"proc FrameArrayMux">>)),
    ?assertEqual(0, count(Generated, <<"spawn frame_transport::FrameArrayMux">>)).

%% Checks generated phi family shards use static destination tables.
-spec generated_phi_family_shards_use_static_destination_tables_test() -> 'ok'.
generated_phi_family_shards_use_static_destination_tables_test() ->
    lists:foreach(
        fun(ShardCount) ->
            Generated = iolist_to_binary(
                phi_shared_noise_topology_dslx:to_dslx(
                    3, 16#80000000, {phi_shards, ShardCount}
                )
            ),
            SchedulerCount = 4 + 2 * ShardCount,
            ?assertEqual(SchedulerCount,
                count(Generated, <<"::SharedService<">>)),
            ?assertEqual(1, count(Generated,
                <<"fn phi_x_destination(">>)),
            ?assertEqual(1, count(Generated,
                <<"fn phi_z_destination(">>)),
            ?assertEqual(0, count(Generated, <<" / HEIGHT">>)),
            ?assertEqual(0, count(Generated, <<" % HEIGHT">>)),
            ?assertEqual(0, count(Generated, <<" % WIDTH">>))
        end,
        [2, 3]
    ).

%% Checks generated family topology uses explicit actor egress depth.
-spec generated_family_topology_uses_explicit_actor_egress_depth_test() -> 'ok'.
generated_family_topology_uses_explicit_actor_egress_depth_test() ->
    Plan = hls_topology:normalize(phi_noise_topology:topology()),
    Profile = maps:remove(
        reduction_placements,
        maps:remove(
            scheduler_groups,
            phi_shared_noise_topology_dslx:profile()
        )
    ),
    lists:foreach(
        fun(Depth) ->
            Generated = iolist_to_binary(xls_shared_topology_dslx:emit(
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

%% Checks generated family startup precedes routed input.
-spec generated_family_startup_precedes_routed_input_test() -> 'ok'.
generated_family_startup_precedes_routed_input_test() ->
    Generated = iolist_to_binary(phi_shared_noise_topology_dslx:to_dslx()),
    ?assertEqual(36, count(Generated, <<"::Tag::PHENOM_CONFIG as u8">>)),
    ?assertEqual(18, count(Generated, <<"::Tag::PHI_CONFIG as u8">>)),
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

%% Checks family backend rejects partial family startup.
-spec family_backend_rejects_partial_family_startup_test() -> 'ok'.
family_backend_rejects_partial_family_startup_test() ->
    Plan = hls_topology:normalize(phi_noise_topology:topology(2)),
    [_First | Rest] = maps:get(startup, Plan),
    ?assertError(
        {incomplete_family_startup, data_even, 4, 3},
        xls_shared_topology_dslx:emit(
            Plan#{startup := Rest},
            phi_shared_noise_topology_dslx:profile()
        )
    ).

%% Checks family backend rejects invalid actor egress depth.
-spec family_backend_rejects_invalid_actor_egress_depth_test() -> 'ok'.
family_backend_rejects_invalid_actor_egress_depth_test() ->
    Plan = hls_topology:normalize(phi_noise_topology:topology(1)),
    Profile = phi_shared_noise_topology_dslx:profile(),
    lists:foreach(
        fun(Value) ->
            ?assertError(
                {egress_depth, Value},
                xls_shared_topology_dslx:emit(
                    Plan,
                    Profile#{actor_egress_depth := Value}
                )
            )
        end,
        [-1, 16#100000000, auto]
    ).

%% Checks family backend rejects invalid effect window partition.
-spec family_backend_rejects_invalid_effect_window_partition_test() -> 'ok'.
family_backend_rejects_invalid_effect_window_partition_test() ->
    Plan = hls_topology:normalize(phi_noise_topology:topology(1)),
    Profile = phi_shared_noise_topology_dslx:profile(),
    ?assertError(
        {effect_window_partition, strongly_connected_components},
        xls_shared_topology_dslx:emit(
            Plan,
            Profile#{
                effect_window_partition => strongly_connected_components
            }
        )
    ).

%% Checks rectangle ingress accepts the full u16 coordinate extent.
-spec rectangle_ingress_accepts_the_full_u16_coordinate_extent_test() -> 'ok'.
rectangle_ingress_accepts_the_full_u16_coordinate_extent_test() ->
    Plan0 = hls_topology:normalize(phi_noise_topology:topology(1)),
    [Ingress0] = maps:get(ingresses, Plan0),
    Plan = Plan0#{ingresses := [Ingress0#{shape := [16#10000, 2]}]},
    Generated = iolist_to_binary(xls_shared_topology_dslx:emit(
        Plan,
        phi_shared_noise_topology_dslx:profile()
    )),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "control_router_in: chan<hls_spatial_router::SpatialFrame> in"
    >>)).

%% Checks rectangle ingress rejects an extent beyond u16 coordinates.
-spec rectangle_ingress_rejects_an_extent_beyond_u16_coordinates_test() -> 'ok'.
rectangle_ingress_rejects_an_extent_beyond_u16_coordinates_test() ->
    Plan0 = hls_topology:normalize(phi_noise_topology:topology(1)),
    [Ingress0] = maps:get(ingresses, Plan0),
    Plan = Plan0#{ingresses := [Ingress0#{shape := [16#10001, 2]}]},
    ?assertError(
        {ingress_shape, [16#10001, 2], 16#10000},
        xls_shared_topology_dslx:emit(
            Plan,
            phi_shared_noise_topology_dslx:profile()
        )
    ).

%% Checks control selectors against the fixture's logical family mapping.
-spec assert_ingress_selector(binary(),'phenom_data_cell','noise_cutoff' | 'pauli_query' | 'pauli_update') -> 'ok'.
assert_ingress_selector(Generated, Module, Schema) ->
    Selector = Module:pack_tag(Schema),
    Needle = iolist_to_binary([
        "state.packet.frame.header.op == u8:", integer_to_list(Selector)
    ]),
    ?assertNotEqual(nomatch, binary:match(Generated, Needle)).

%% Counts nonoverlapping occurrences of a generated structural marker.
-spec count(binary(),nonempty_binary()) -> non_neg_integer().
count(Binary, Pattern) ->
    length(binary:matches(Binary, Pattern)).
