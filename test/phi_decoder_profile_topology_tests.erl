-module(phi_decoder_profile_topology_tests).

-include_lib("eunit/include/eunit.hrl").

rectangular_profile_preserves_the_remaining_plane_test() ->
    Both = phi_decoder_profile_topology:topology(#{shape => [2, 3]}),
    Single = phi_decoder_profile_topology:topology(#{shape => [2, 3], planes => [z]}),
    ?assertEqual([phi_z, syndrome_z], lists:sort(maps:keys(maps:get(families, Single)))),
    ?assertEqual([Entry || Entry = {{Family, _, _}, _} <- maps:get(startup, Both),
        lists:member(Family, [phi_z, syndrome_z])], maps:get(startup, Single)),
    Plan = hls_topology:normalize(Single),
    Routes = hls_topology:routes_for_instance(Plan, phi_z, [0, 0]),
    ?assertMatch([#{recipients := [{actor, {phi_z, 0, 2}}]}],
        [R || R = #{source := {_, north}} <- Routes]),
    #{groups := Groups} = phi_decoder_profile_topology_dslx:scheduler_plan(
        #{shape => [2, 3], planes => [z], shards => 2}),
    ?assertEqual([6, 3, 3], [maps:get(slot_count, G) || G <- Groups]).

profile_configuration_rejects_invalid_populations_test() ->
    [?assertException(error, _, phi_decoder_profile:normalize(Options)) || Options <- [
        #{shape => [0, 2]}, #{shape => [2, 1.5]}, #{shape => [51, 1]},
        #{planes => []}, #{planes => [x, x]}, #{planes => [y]},
        #{shape => [2, 1], shards => 3}, #{shards => 0}, #{shard => 2}]],
    ?assertEqual(#{shape => [1, 1], shards => 1, planes => [x, z]},
        phi_decoder_profile:normalize(#{shape => [1, 1], planes => [z, x]})).

single_plane_artifacts_have_no_inactive_schedulers_test() ->
    Config = #{shape => [2, 2], planes => [x], shards => 2},
    Generated = iolist_to_binary(phi_decoder_profile_topology_dslx:to_dslx(Config)),
    Wrapper = phi_decoder_profile_top_v:to_verilog(Config),
    ?assertEqual(nomatch, binary:match(Generated, <<"phi_z">>)),
    ?assertEqual(nomatch, binary:match(Wrapper, <<"._z_decoder_events_out">>)),
    ?assertEqual(6, count(Wrapper, <<"hls_1r1w_ram #(.WIDTH(">>)),
    assert_contains(Wrapper, <<"assign z_decoder_event_valid = 1'b0;">>),
    assert_contains(Wrapper, <<"profile_phi_state_reads = {31'd0, scheduler_1_state_rd_en} + {31'd0, scheduler_2_state_rd_en};">>),
    ?assertMatch(#{phi_actor_count := 4, source_actor_count := 4,
        scheduler_count := 3}, phi_decoder_profile:manifest(Config)).

profile_replaces_the_physical_source_network_test() ->
    Plan = hls_topology:from_module(phi_decoder_profile_topology),
    Families = maps:get(families, Plan),
    ?assertEqual(
        [phi_x, phi_z, syndrome_x, syndrome_z],
        lists:sort([maps:get(id, Family) || Family <- Families])
    ),
    ?assertEqual([], maps:get(ingresses, Plan)),
    ?assertEqual(
        [x_decoder_events, z_decoder_events],
        [maps:get(id, External) || External <- maps:get(externals, Plan)]
    ),
    ?assertEqual(16, length(maps:get(route_relations, Plan))).

three_shards_keep_source_and_decoder_counters_separate_test() ->
    #{groups := Groups, direct_members := []} =
        phi_decoder_profile_topology_dslx:scheduler_plan(),
    ?assertEqual(8, length(Groups)),
    ?assertEqual(
        [phi_syndrome_replay_cell, phi_syndrome_replay_cell],
        [maps:get(module, Group) || Group <- lists:sublist(Groups, 2)]
    ),
    ?assertEqual(
        [9, 9, 3, 3, 3, 3, 3, 3],
        [maps:get(slot_count, Group) || Group <- Groups]
    ).

source_fragment_profile_specializes_only_the_phi_actor_test() ->
    Plan = hls_topology:from_module(phi_decoder_profile_topology),
    ?assertEqual(
        #{
            phi_halo_cell => #{shared_service => aggregate_only},
            phi_syndrome_replay_cell => #{shared_service => ordinary}
        },
        xls_topology_dslx:artifact_requirements(
            Plan,
            phi_decoder_profile_topology_dslx:profile()
        )
    ).

global_effect_window_remains_the_default_test() ->
    Generated = iolist_to_binary(
        phi_decoder_profile_topology_dslx:to_dslx()
    ),
    ?assertEqual(1, count(Generated, <<
        "spawn effect_window::Arbiter<u32:8>"
    >>)),
    ?assertEqual(0, count(Generated, <<"Effect-window domain">>)).

source_fragment_plane_uses_inverse_route_edge_queues_test() ->
    Generated = iolist_to_binary(
        phi_decoder_profile_topology_dslx:to_dslx()
    ),
    assert_contains(Generated, <<"proc Phi_xReductionPlane {">>),
    assert_contains(Generated, <<"proc Phi_zReductionPlane {">>),
    ?assertEqual(8, count(Generated, <<": frame_queue::Queue[u32:9]">>)),    ?assertEqual(2, count(Generated, <<
        "::reduction_aggregate_batch<u32:4>(frames)"
    >>)),
    ?assertEqual(6, count(Generated, <<
        "let reduction_batch = batch_valid && index == u8:0"
    >>)).

weak_component_effect_windows_follow_the_disconnected_planes_test() ->
    Plan = hls_topology:from_module(phi_decoder_profile_topology),
    Profile = (phi_decoder_profile_topology_dslx:profile())#{
        effect_window_partition => weak_components
    },
    Generated = iolist_to_binary(xls_topology_dslx:emit(Plan, Profile)),
    ?assertEqual(2, count(Generated, <<
        "spawn effect_window::Arbiter<u32:4>"
    >>)),
    assert_contains(Generated, <<
        "Effect-window domain 0: schedulers 0, 2, 3, 4."
    >>),
    assert_contains(Generated, <<
        "Effect-window domain 1: schedulers 1, 5, 6, 7."
    >>),
    ?assertEqual(4, count(Generated, <<
        "effect_window_domain_0_request_p[u32:"
    >>)),
    ?assertEqual(4, count(Generated, <<
        "effect_window_domain_1_request_p[u32:"
    >>)),
    ?assertEqual(4, count(Generated, <<
        "effect_window_domain_0_grant_c[u32:"
    >>)),
    ?assertEqual(4, count(Generated, <<
        "effect_window_domain_1_grant_c[u32:"
    >>)),
    ?assertEqual(4, count(Generated, <<
        "effect_window_domain_0_release_p[u32:"
    >>)),
    ?assertEqual(4, count(Generated, <<
        "effect_window_domain_1_release_p[u32:"
    >>)).

effect_window_domains_are_weak_not_strong_components_test() ->
    %% A one-way dependency joins two directed cycles: SCC partitioning would
    %% incorrectly allow both sides to retain independent effect windows.
    JoinedCycles = dependencies([
        {0, [1]},
        {1, [0, 2]},
        {2, [3]},
        {3, [2]}
    ]),
    ?assertEqual(
        [[0, 1, 2, 3]],
        xls_topology_effect_windows:partition([0, 1, 2, 3], weak_components, JoinedCycles)
    ),
    DisconnectedCycles = dependencies([
        {0, [1]},
        {1, [0]},
        {2, [3]},
        {3, [2]}
    ]),
    ?assertEqual(
        [[0, 1], [2, 3]],
        xls_topology_effect_windows:partition(
            [0, 1, 2, 3], weak_components, DisconnectedCycles
        )
    ),
    %% A bounded manager incident to both otherwise-disconnected components
    %% is an undirected hyperedge for ownership, without becoming a router
    %% destination in either scheduler's generated wiring.
    ?assertEqual(
        [[0, 1, 2, 3]],
        xls_topology_effect_windows:partition(
            [0, 1, 2, 3], weak_components, DisconnectedCycles ++ [[1, 2]]
        )
    ).

generated_profile_and_ram_shell_are_width_driven_test() ->
    Generated = iolist_to_binary(
        phi_decoder_profile_topology_dslx:to_dslx()
    ),
    Wrapper = phi_decoder_profile_top_v:to_verilog(),
    assert_contains(Generated, <<"import phi_syndrome_replay_cell;">>),
    assert_contains(Generated, <<"import phi_halo_cell;">>),
    ?assertEqual(nomatch, binary:match(Generated, <<"phenom_data_cell">>)),
    ?assertEqual(nomatch, binary:match(Generated, <<"phenom_syndrome_cell">>)),
    ?assertEqual(16, count(Wrapper, <<"hls_1r1w_ram #(.WIDTH(">>)),
    assert_contains(Wrapper, <<".scheduler_7_state_rd_addr(">>),
    ?assertEqual(nomatch, binary:match(Wrapper, <<"@SCHEDULER_">>)).

assert_contains(Binary, Pattern) ->
    ?assertNotEqual(nomatch, binary:match(Binary, Pattern)).

count(Binary, Pattern) ->
    length(binary:matches(Binary, Pattern)).

dependencies(Edges) ->
    [[Source, Destination] || {Source, Destinations} <- Edges, Destination <- Destinations].
