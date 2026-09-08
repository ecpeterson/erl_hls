-module(xls_topology_source_fragment_dslx_tests).

-include_lib("eunit/include/eunit.hrl").

source_fragment_profile_is_deterministic_and_opt_in_test() ->
    Plan = hls_topology:normalize(closed_topology()),
    Base = profile(single_groups()),
    Ordinary = iolist_to_binary(xls_topology_dslx:emit(Plan, Base)),
    ExplicitOrdinary = iolist_to_binary(xls_topology_dslx:emit(
        Plan, Base#{reduction_placements => #{}}
    )),
    SelectedProfile = Base#{
        reduction_placements => #{reducer => source_fragments}
    },
    First = iolist_to_binary(xls_topology_dslx:emit(
        Plan, SelectedProfile
    )),
    Second = iolist_to_binary(xls_topology_dslx:emit(
        Plan, SelectedProfile
    )),
    ?assertEqual(Ordinary, ExplicitOrdinary),
    ?assertEqual(First, Second),
    ?assertEqual(0, count(Ordinary, <<"ReductionPlane">>)),
    ?assertEqual(1, count(First, <<"proc ReducerReductionPlane {">>)),
    ?assertEqual(1, count(First, <<"struct ReducerReductionBatch {">>)).

artifact_requirements_follow_the_selected_profile_test() ->
    Plan = hls_topology:normalize(closed_topology()),
    Base = profile(single_groups()),
    ?assertEqual(
        #{
            hls_topology_source_fragment_fixture => #{
                shared_service => ordinary
            },
            hls_topology_source_fixture => #{shared_service => ordinary}
        },
        xls_topology_dslx:artifact_requirements(Plan, Base)
    ),
    ?assertEqual(
        #{
            hls_topology_source_fragment_fixture => #{
                shared_service => aggregate_only
            },
            hls_topology_source_fixture => #{shared_service => ordinary}
        },
        xls_topology_dslx:artifact_requirements(
            Plan,
            Base#{reduction_placements => #{reducer => source_fragments}}
        )
    ).

source_fragment_router_captures_only_the_proved_prefix_test() ->
    Generated = selected(),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "let reduction_prefix = hls_topology_source_fragment_fixture::"
        "scheduled_reduction_prefix(scheduled);"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "let reduction_batch = batch_valid && index == u8:0 &&\n"
        "      reduction_prefix.0;"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "let effect_0 = hls_topology_source_fragment_fixture::"
        "scheduled_effect(scheduled, u8:0).0;"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "let effect_1 = hls_topology_source_fragment_fixture::"
        "scheduled_effect(scheduled, u8:1).0;"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "frames: [effect_0.frame, effect_1.frame]"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "index: index + if reduction_batch { u8:2 } "
        "else { u8:1 }"
    >>)),
    ?assertEqual(0, count(Generated, <<"OutputPort::NORTH => send(">>)),
    ?assertEqual(0, count(Generated, <<"OutputPort::SOUTH => send(">>)),
    ?assertEqual(1, count(Generated, <<"OutputPort::NORTH => grant_tok">>)),
    ?assertEqual(1, count(Generated, <<"OutputPort::SOUTH => grant_tok">>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "OutputPort::REPORT => send("
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "let release_tok = send_if(\n"
        "      credit_tok, window_release_out, release, u1:1);"
    >>)).

source_fragment_plane_uses_inverse_depth_two_queues_test() ->
    Generated = selected(),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "current_valid: u1,\n"
        "  current: axis::Frame,\n"
        "  lookahead_valid: u1,\n"
        "  lookahead: axis::Frame"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "bank_0: ReducerReductionFragmentQueue[u32:9]"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "bank_1: ReducerReductionFragmentQueue[u32:9]"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "Fragment 0 (north) uses inverse fragment 1 at offset [0, 1]."
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "Fragment 1 (south) uses inverse fragment 0 at offset [0, -1]."
    >>)),
    %% At destination [0,0], north's inverse source is [0,1] and south's
    %% inverse source is [0,2] in the planner's x-major linearization.
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "state.open_tokens[u32:0] && state.bank_0[u32:1].current_valid"
        " && state.bank_1[u32:2].current_valid"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "let after_pop_0 = reducer_reduction_fragment_after_pop("
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "let capacity_0 = !after_pop_0.lookahead_valid;"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "let can_insert = work_valid && source_valid && capacity_0"
        " && capacity_1;"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "pending_valid: work_valid && !can_insert"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "let (input_tok, received, incoming) ="
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "let _done = join(output_tok, input_tok);"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "let open_tokens_after_output = if output_ready"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "::reduction_aggregate_batch<u32:2>(frames);"
    >>)).

source_fragment_plane_wires_the_aggregate_endpoint_last_test() ->
    Generated = selected(),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "chan<hls_topology_source_fragment_fixture::"
        "ReductionAggregateRequest, u32:0>"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "ReductionAggregateRequest {\n"
        "            slot: u32:0,\n"
        "            aggregate,"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "scheduler_0_mailbox_write_resp_in,\n"
        "      scheduler_0_aggregate_c);"
    >>)),
    ?assertEqual(0, count(Generated, <<"SchedulerAggregateArrayMux">>)).

one_plane_spans_all_selected_family_shards_test() ->
    Plan = hls_topology:normalize(closed_topology()),
    Groups = #{
        reducer_even => group([
            {family, reducer, {interleaved, 0, 2}}
        ]),
        reducer_odd => group([
            {family, reducer, {interleaved, 1, 2}}
        ]),
        source => group([{family, source}])
    },
    Generated = iolist_to_binary(xls_topology_dslx:emit(
        Plan,
        (profile(Groups))#{
            reduction_placements => #{reducer => source_fragments}
        }
    )),
    ?assertEqual(1, count(Generated, <<"proc ReducerReductionPlane {">>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "batch_in: chan<ReducerReductionBatch>[u32:2] in"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "aggregate_out_0: chan<hls_topology_source_fragment_fixture::"
        "ReductionAggregateRequest> out"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "aggregate_out_1: chan<hls_topology_source_fragment_fixture::"
        "ReductionAggregateRequest> out"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "reducer_reduction_batch_c,\n"
        "      scheduler_0_aggregate_p,\n"
        "      scheduler_1_aggregate_p"
    >>)).

source_fragment_plane_is_one_effect_window_hyperedge_test() ->
    Plan = hls_topology:normalize(closed_topology()),
    Groups = #{
        reducer_even => group([
            {family, reducer, {interleaved, 0, 2}}
        ]),
        reducer_odd => group([
            {family, reducer, {interleaved, 1, 2}}
        ]),
        source => group([{family, source}])
    },
    Generated = iolist_to_binary(xls_topology_dslx:emit(
        Plan,
        (profile(Groups))#{
            effect_window_partition => weak_components,
            reduction_placements => #{reducer => source_fragments}
        }
    )),
    ?assertEqual(1, count(Generated, <<
        "spawn effect_window::Arbiter<u32:2>"
    >>)),
    ?assertEqual(1, count(Generated, <<
        "spawn effect_window::Arbiter<u32:1>"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "Effect-window domain 0: schedulers 0, 1."
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "Effect-window domain 1: schedulers 2."
    >>)).

multiple_planes_share_one_scheduler_through_a_fair_typed_mux_test() ->
    Plan = hls_topology:normalize(dual_topology()),
    Profile = (profile(#{combined => group([
        {family, reducer_a},
        {family, reducer_b}
    ])}))#{
        reduction_placements => #{
            reducer_a => source_fragments,
            reducer_b => source_fragments
        }
    },
    Generated = iolist_to_binary(xls_topology_dslx:emit(Plan, Profile)),
    ?assertEqual(1, count(Generated, <<
        "proc SchedulerAggregateArrayMux0 {"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "valid: u1[u32:2]"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "let unwrapped = state.cursor + offset;"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "scheduler_0_aggregate_sources_c, scheduler_0_aggregate_p"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "reducer_a_reduction_batch_c,\n"
        "      scheduler_0_aggregate_sources_p[u32:0]"
    >>)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<
        "reducer_b_reduction_batch_c,\n"
        "      scheduler_0_aggregate_sources_p[u32:1]"
    >>)).

family_profile_rejects_a_non_map_reduction_placement_test() ->
    Plan = hls_topology:normalize(closed_topology()),
    ?assertError(
        {reduction_placements, [reducer]},
        xls_topology_dslx:emit(
            Plan,
            (profile(single_groups()))#{
                reduction_placements => [reducer]
            }
        )
    ).

selected() ->
    Plan = hls_topology:normalize(closed_topology()),
    Profile = (profile(single_groups()))#{
        reduction_placements => #{reducer => source_fragments}
    },
    iolist_to_binary(xls_topology_dslx:emit(Plan, Profile)).

profile(Groups) ->
    #{
        name => source_fragment_topology,
        channel_depth => 1,
        actor_egress_depth => burst,
        scheduler_groups => Groups
    }.

single_groups() ->
    #{
        reducer => group([{family, reducer}]),
        source => group([{family, source}])
    }.

group(Members) ->
    #{
        members => Members,
        state_storage => block_ram,
        mailbox_storage => block_ram
    }.

closed_topology() ->
    #{
        version => 1,
        ingresses => [],
        actors => #{},
        families => #{
            reducer => #{
                module => hls_topology_source_fragment_fixture,
                shape => [3, 3]
            },
            source => #{
                module => hls_topology_source_fixture,
                shape => [3, 3]
            }
        },
        externals => [
            {messages, out, [message]},
            {reports, out, [notice]}
        ],
        routes => [],
        route_relations => reducer_relations(reducer) ++ [
            {{source, out}, [{external, messages}]}
        ],
        startup => []
    }.

dual_topology() ->
    #{
        version => 1,
        ingresses => [],
        actors => #{},
        families => maps:from_list([
            {Family, #{
                module => hls_topology_source_fragment_fixture,
                shape => [3, 3]
            }}
            || Family <- [reducer_a, reducer_b]
        ]),
        externals => [{reports, out, [notice]}],
        routes => [],
        route_relations => lists:append([
            reducer_relations(Family)
            || Family <- [reducer_a, reducer_b]
        ]),
        startup => []
    }.

reducer_relations(Family) ->
    [
        {{Family, north}, [
            {family, Family, {translate, [0, -1], wrap}}
        ]},
        {{Family, south}, [
            {family, Family, {translate, [0, 1], wrap}}
        ]},
        {{Family, report}, [{external, reports}]}
    ].

count(Binary, Pattern) ->
    length(binary:matches(Binary, Pattern)).
