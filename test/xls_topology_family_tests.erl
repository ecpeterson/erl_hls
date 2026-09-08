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
    ?assertEqual(6, count(Generated, <<"proc SchedulerRouter">>)),
    ?assertEqual(6, count(Generated, <<"spawn SchedulerRouter">>)),
    ?assertEqual(6, count(Generated, <<"::SharedService<">>)),
    ?assertEqual(0, count(Generated, <<"::EffectWindowAdapter(">>)),
    ?assertEqual(1, count(Generated, <<
        "spawn effect_window::Arbiter<"
    >>)),
    ?assertEqual(30, count(Generated, <<"::ScheduledEffects">>)),
    %% Ordinary routers still render two effect lookups each; the two joined
    %% reduction routers additionally materialize their four-frame prefixes.
    ?assertEqual(20, count(Generated, <<"::scheduled_effect(">>)),
    ?assertEqual(1, count(Generated, <<"struct Phi_xReductionBatch {">>)),
    ?assertEqual(1, count(Generated, <<"struct Phi_zReductionBatch {">>)),
    ?assertEqual(1, count(Generated, <<"proc Phi_xReductionPlane {">>)),
    ?assertEqual(1, count(Generated, <<"proc Phi_zReductionPlane {">>)),
    ?assertEqual(1, count(Generated, <<"spawn Phi_xReductionPlane(">>)),
    ?assertEqual(1, count(Generated, <<"spawn Phi_zReductionPlane(">>)),
    %% Each captured route owns a source-indexed depth-two edge queue.  A
    %% destination consumes the four inverse-route heads with one aggregate
    %% fold rather than updating a destination-wide combinational crossbar.
    ?assertEqual(1, count(Generated, <<
        "struct Phi_xReductionFragmentQueue {"
    >>)),
    ?assertEqual(1, count(Generated, <<
        "struct Phi_zReductionFragmentQueue {"
    >>)),
    ?assertEqual(2, count(Generated, <<
        "  current_valid: u1,\n"
        "  current: axis::Frame,\n"
        "  lookahead_valid: u1,\n"
        "  lookahead: axis::Frame,"
    >>)),
    ?assertEqual(8, count(Generated, <<
        ": Phi_xReductionFragmentQueue[u32:9]"
    >>) + count(Generated, <<
        ": Phi_zReductionFragmentQueue[u32:9]"
    >>)),
    ?assertEqual(2, count(Generated, <<
        "::reduction_aggregate_batch<u32:4>(frames)"
    >>)),
    %% Aggregate retirement and batch intake are independent handshakes in
    %% one plane activation. Admission is atomic across all four banks; a
    %% single holding slot preserves a batch if its
    %% four atomic edge-queue writes cannot yet proceed.
    ?assertEqual(2, count(Generated, <<
        "let ready_slots = ["
    >>)),
    ?assertEqual(2, count(Generated, <<
        "let (input_tok, received, incoming) ="
    >>)),
    ?assertEqual(2, count(Generated, <<
        "pending_valid: u1"
    >>)),
    ?assertEqual(2, count(Generated, <<
        "let work_valid = state.pending_valid || received;"
    >>)),
    ?assertEqual(2, count(Generated, <<
        "let _done = join(output_tok, input_tok);"
    >>)),
    ?assertEqual(2, count(Generated, <<
        "let can_insert = work_valid && source_valid && capacity_0 &&"
    >>)),
    ?assertEqual(6, count(Generated, <<
        "let last = batch_valid && if reduction_batch {"
    >>)),
    ?assertEqual(6, count(Generated, <<
        "routed_tok, credit_out, forward_credit"
    >>)),
    %% The source-fragment batch is the sole carrier for the four reduction
    %% routes.  Pruning their ordinary producer ports leaves each phi shard
    %% with only syndrome input plus its returned egress credit.
    ?assertEqual(2, count(Generated, <<
        "phi_halo_cell::SharedService<\n"
        "      u32:9, u32:2, u32:9"
    >>)),
    lists:foreach(
        fun(Port) ->
            Needle = iolist_to_binary([
                "phi_halo_cell::OutputPort::", Port, " => grant_tok"
            ]),
            ?assertEqual(2, count(Generated, Needle))
        end,
        ["NORTH", "EAST", "WEST", "SOUTH"]
    ),
    %% SharedService mode is selected when each actor module is generated,
    %% rather than retained as a topology-time generic which forces XLS to
    %% elaborate every dormant reduction path.
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
    %% Small reduction receptacles live inside the phi scheduler, rather than
    %% adding a third external RAM boundary per reducing scheduler.
    ?assertEqual(0, count(Generated, <<"::ReductionRamReadReq> out">>)),
    ?assertEqual(0, count(Generated, <<"::ReductionRamReadResp> in">>)),
    ?assertEqual(0, count(Generated, <<"::ReductionRamWriteReq> out">>)),
    ?assertEqual(0, count(Generated, <<"::ReductionRamWriteResp> in">>)),
    ?assertEqual(1, count(Generated, <<"spawn FrameArrayMux<u32:2>(">>)),
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

generated_one_shard_topology_retains_single_external_lanes_test() ->
    Generated = iolist_to_binary(
        phi_noise_topology_dslx:to_dslx(3, 16#80000000, 1)
    ),
    ?assertEqual(3, count(Generated, <<"::SharedService<">>)),
    ?assertEqual(0, count(Generated, <<"proc FrameArrayMux">>)),
    ?assertEqual(0, count(Generated, <<"spawn FrameArrayMux">>)),
    ?assertEqual(1, count(Generated,
        <<"proc SchedulerAggregateArrayMux">>)),
    ?assertEqual(1, count(Generated,
        <<"spawn SchedulerAggregateArrayMux">>)).

generated_multi_plane_scheduler_arbitrates_typed_aggregates_test() ->
    Generated = iolist_to_binary(
        phi_noise_topology_dslx:to_dslx(3, 16#80000000, 1)
    ),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "aggregate_in: chan<phi_halo_cell::"
        "ReductionAggregateRequest>[u32:2] in"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "chan<phi_halo_cell::ReductionAggregateRequest, "
        "u32:0>[u32:2](\"scheduler_1_aggregate_sources\")"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "scheduler_1_aggregate_sources_c, scheduler_1_aggregate_p"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "spawn Phi_xReductionPlane(\n"
        "      phi_x_reduction_batch_c,\n"
        "      scheduler_1_aggregate_sources_p[u32:0])"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "spawn Phi_zReductionPlane(\n"
        "      phi_z_reduction_batch_c,\n"
        "      scheduler_1_aggregate_sources_p[u32:1])"
    >>)),
    %% Selection starts at the cursor and advances after each successful
    %% transfer; empty planes are bypassed rather than consuming turns.
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "let unwrapped = state.cursor + offset;"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "let take = !choice.0 && available[candidate];"
    >>)).

generated_single_plane_scheduler_keeps_direct_aggregate_channel_test() ->
    Generated = iolist_to_binary(phi_noise_topology_dslx:to_dslx()),
    ?assertEqual(0, count(Generated,
        <<"proc SchedulerAggregateArrayMux">>)),
    ?assertEqual(0, count(Generated, <<"_aggregate_sources_">>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "spawn Phi_xReductionPlane(\n"
        "      phi_x_reduction_batch_c,\n"
        "      scheduler_2_aggregate_p)"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "spawn Phi_zReductionPlane(\n"
        "      phi_z_reduction_batch_c,\n"
        "      scheduler_3_aggregate_p)"
    >>)).

generated_phi_family_shards_use_static_destination_tables_test() ->
    lists:foreach(
        fun(ShardCount) ->
            Generated = iolist_to_binary(
                phi_noise_topology_dslx:to_dslx(
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

generated_phi_routes_mark_sender_addressed_reductions_test() ->
    Generated = iolist_to_binary(
        phi_noise_topology_dslx:to_dslx(
            3, 16#80000000, {phi_shards, 3}
        )
    ),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "direct_reduction: phi_halo_cell::"
        "direct_reduction_candidate(effect.frame)"
    >>)),
    ?assertEqual(nomatch, binary:match(Generated, <<
        "direct_reduction: phenom_data_cell::"
    >>)),
    ?assertEqual(nomatch, binary:match(Generated, <<
        "direct_reduction: phenom_syndrome_cell::"
    >>)).

generated_family_topology_uses_explicit_actor_egress_depth_test() ->
    Plan = hls_topology:normalize(phi_noise_topology:topology()),
    Profile = (maps:remove(
        scheduler_groups,
        phi_noise_topology_dslx:profile()
    ))#{reduction_transport := ordinary},
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
    ?assertEqual(36, count(Generated, <<"::Tag::PHENOM_CONFIG as u8">>)),
    ?assertEqual(18, count(Generated, <<"::Tag::PHI_CONFIG as u8">>)),
    ?assertEqual(36, count(Generated, <<"::Phenomconfig {">>)),
    ?assertEqual(18, count(Generated, <<"::Phiconfig {">>)),
    ?assertEqual(0, count(Generated, <<"uN[96]:0x">>)),
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

family_backend_rejects_invalid_effect_window_partition_test() ->
    Plan = hls_topology:normalize(phi_noise_topology:topology(1)),
    Profile = phi_noise_topology_dslx:profile(),
    ?assertError(
        {effect_window_partition, strongly_connected_components},
        xls_topology_dslx:emit(
            Plan,
            Profile#{
                effect_window_partition => strongly_connected_components
            }
        )
    ).

family_backend_rejects_invalid_reduction_transport_test() ->
    Plan = hls_topology:normalize(phi_noise_topology:topology(1)),
    Profile = phi_noise_topology_dslx:profile(),
    ?assertError(
        {reduction_transport, speculative},
        xls_topology_dslx:emit(
            Plan,
            Profile#{reduction_transport => speculative}
        )
    ).

source_fragment_transport_rejects_captured_port_after_prefix_test() ->
    Plan = hls_topology:normalize(
        source_fragment_captured_port_topology()
    ),
    ?assertError(
        {source_fragment_captured_port_outside_prefix,
            reducer, reporting, 0, north, notice},
        xls_topology_dslx:emit(
            Plan,
            source_fragment_profile([reducer])
        )
    ).

source_fragment_transport_rejects_ordinary_contribution_route_test() ->
    Plan = hls_topology:normalize(
        source_fragment_ordinary_contributor_topology()
    ),
    ?assertError(
        {source_fragment_ordinary_contribution_route,
            reducer, {source, out}, [message]},
        xls_topology_dslx:emit(
            Plan,
            source_fragment_profile([reducer, source])
        )
    ).

source_fragment_transport_rejects_contribution_ingress_test() ->
    Plan = hls_topology:normalize(
        source_fragment_contribution_ingress_topology()
    ),
    ?assertError(
        {source_fragment_contribution_ingress,
            reducer, contributions, values, [message]},
        xls_topology_dslx:emit(
            Plan,
            source_fragment_profile([reducer, source])
        )
    ).

source_fragment_transport_rejects_contribution_startup_test() ->
    Plan = hls_topology:normalize(
        source_fragment_contribution_startup_topology()
    ),
    ?assertError(
        {source_fragment_contribution_startup,
            reducer, [0, 0], message},
        xls_topology_dslx:emit(
            Plan,
            source_fragment_profile([reducer, source])
        )
    ).

source_fragment_transport_rejects_direct_reducer_test() ->
    Plan = hls_topology:normalize(
        source_fragment_closed_topology()
    ),
    ?assertError(
        {source_fragment_requires_scheduler, reducer},
        xls_topology_dslx:emit(
            Plan,
            source_fragment_profile([source])
        )
    ).

source_fragment_transport_rejects_ordinary_self_route_test() ->
    Plan = hls_topology:normalize(
        source_fragment_ordinary_self_route_topology()
    ),
    ?assertError(
        {source_fragment_ordinary_self_route, reducer, report},
        xls_topology_dslx:emit(
            Plan,
            source_fragment_profile([reducer, source])
        )
    ).

source_fragment_transport_allows_external_report_route_test() ->
    Plan = hls_topology:normalize(source_fragment_closed_topology()),
    Generated = iolist_to_binary(xls_topology_dslx:emit(
        Plan,
        source_fragment_profile([reducer, source])
    )),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "reports_out: chan<axis::Frame> out"
    >>)).

source_fragment_transport_rejects_non_inverse_closed_routes_test() ->
    Spec = phi_noise_topology:topology(3),
    Relations = [
        case Relation of
            {{phi_x, north}, _Recipients} ->
                %% Remove north's inverse without violating the more general
                %% joined-prefix requirement that every contribution follows
                %% one direct, wrapped self-family translation.
                {{phi_x, north}, [
                    {family, phi_x, {translate, [0, 0], wrap}}
                ]};
            _ ->
                Relation
        end
        || Relation <- maps:get(route_relations, Spec)
    ],
    Plan = hls_topology:normalize(Spec#{route_relations := Relations}),
    try xls_topology_dslx:emit(
            Plan,
            phi_noise_topology_dslx:profile()
        ) of
        _ -> ?assert(false)
    catch
        error:{source_fragment_routes_not_inverse_closed,
                phi_x, Offset, Inverse, Offsets} ->
            ?assertEqual({0, 1}, Offset),
            ?assertEqual({0, 2}, Inverse),
            ?assertEqual([{0, 0}, {1, 0}, {2, 0}, {0, 1}], Offsets)
    end.

family_backend_rejects_invalid_joined_fold_width_test() ->
    Plan = hls_topology:normalize(phi_noise_topology:topology(1)),
    Profile = phi_noise_topology_dslx:profile(),
    ?assertError(
        {reduction_transport, {joined, 0}},
        xls_topology_dslx:emit(
            Plan,
            Profile#{reduction_transport => {joined, 0}}
        )
    ),
    ?assertError(
        {joined_reduction_fold_lanes, phi_x, 4, 5},
        xls_topology_dslx:emit(
            Plan,
            Profile#{reduction_transport => {joined, 5}}
        )
    ).

shared_service_modes_follow_physical_reduction_transport_test() ->
    Plan = hls_topology:normalize(phi_noise_topology:topology(1)),
    Profile = phi_noise_topology_dslx:profile(),
    ?assertEqual(
        #{
            phenom_data_cell => ordinary,
            phenom_syndrome_cell => ordinary,
            phi_halo_cell => aggregate_only
        },
        xls_topology_dslx:shared_service_modes(Plan, Profile)
    ),
    ?assertEqual(
        #{
            phenom_data_cell => ordinary,
            phenom_syndrome_cell => ordinary,
            phi_halo_cell => joined
        },
        xls_topology_dslx:shared_service_modes(
            Plan,
            Profile#{reduction_transport => joined}
        )
    ),
    ?assertEqual(
        #{
            phenom_data_cell => ordinary,
            phenom_syndrome_cell => ordinary,
            phi_halo_cell => ordinary
        },
        xls_topology_dslx:shared_service_modes(
            Plan,
            Profile#{reduction_transport => ordinary}
        )
    ).

ordinary_reduction_transport_omits_aggregate_endpoints_test() ->
    Plan = hls_topology:normalize(phi_noise_topology:topology(1)),
    Profile = phi_noise_topology_dslx:profile(),
    Generated = iolist_to_binary(xls_topology_dslx:emit(
        Plan,
        Profile#{reduction_transport => ordinary}
    )),
    %% Mode-specialized actor artifacts no longer expose an aggregate input
    %% when this transport is disabled, so the topology needs neither a
    %% never-sending producer nor a dormant aggregate channel.
    ?assertEqual(0, count(Generated, <<"proc SchedulerAggregateIdle">>)),
    ?assertEqual(0, count(Generated, <<"spawn SchedulerAggregateIdle">>)),
    ?assertEqual(0, count(Generated, <<"ReductionAggregateRequest">>)),
    ?assertEqual(0, count(Generated, <<"ReductionPlane {">>)).

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

source_fragment_captured_port_topology() ->
    #{
        version => 1,
        ingresses => [],
        actors => #{},
        families => #{
            reducer => #{
                module => hls_topology_source_fragment_port_fixture,
                shape => [2, 2]
            }
        },
        externals => [{reports, out, [notice]}],
        routes => [],
        route_relations => [
            {{reducer, north}, [
                {family, reducer, {translate, [0, -1], wrap}}
            ]},
            {{reducer, south}, [
                {family, reducer, {translate, [0, 1], wrap}}
            ]},
            {{reducer, report}, [{external, reports}]}
        ],
        startup => []
    }.

source_fragment_ordinary_contributor_topology() ->
    Spec = source_fragment_closed_topology(),
    Spec#{route_relations := [
        case Relation of
            {{source, out}, _Recipients} ->
                {{source, out}, queued, [
                    {family, reducer, {translate, [0, 0], wrap}},
                    {external, messages}
                ]};
            _ ->
                Relation
        end
        || Relation <- maps:get(route_relations, Spec)
    ]}.

source_fragment_contribution_ingress_topology() ->
    Spec = source_fragment_closed_topology(),
    Spec#{ingresses := [
        {contributions, {rectangle, [2, 2]}, [
            {values, [message], [
                {family, reducer, {embed, [1, 1], [0, 0]}}
            ]}
        ]}
    ]}.

source_fragment_contribution_startup_topology() ->
    Spec = source_fragment_closed_topology(),
    Spec#{startup := [
        {{reducer, X, Y}, [{message, 0}]}
        || X <- lists:seq(0, 1),
           Y <- lists:seq(0, 1)
    ]}.

source_fragment_ordinary_self_route_topology() ->
    Spec = source_fragment_closed_topology(),
    Spec#{route_relations := [
        case Relation of
            {{reducer, report}, _Recipients} ->
                {{reducer, report}, [
                    {family, reducer, {translate, [0, 0], wrap}}
                ]};
            _ ->
                Relation
        end
        || Relation <- maps:get(route_relations, Spec)
    ]}.

source_fragment_closed_topology() ->
    #{
        version => 1,
        ingresses => [],
        actors => #{},
        families => #{
            reducer => #{
                module => hls_topology_source_fragment_fixture,
                shape => [2, 2]
            },
            source => #{
                module => hls_topology_source_fixture,
                shape => [2, 2]
            }
        },
        externals => [
            {messages, out, [message]},
            {reports, out, [notice]}
        ],
        routes => [],
        route_relations => [
            {{reducer, north}, [
                {family, reducer, {translate, [0, -1], wrap}}
            ]},
            {{reducer, south}, [
                {family, reducer, {translate, [0, 1], wrap}}
            ]},
            {{reducer, report}, [{external, reports}]},
            {{source, out}, [{external, messages}]}
        ],
        startup => []
    }.

source_fragment_profile(Families) ->
    #{
        name => source_fragment_validation,
        channel_depth => 1,
        actor_egress_depth => burst,
        reduction_transport => source_fragments,
        scheduler_groups => maps:from_list([
            {Family, #{
                members => [{family, Family}],
                state_storage => block_ram,
                mailbox_storage => block_ram
            }}
            || Family <- Families
        ])
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
