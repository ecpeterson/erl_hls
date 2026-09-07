-module(phi_decoder_profile_topology_tests).

-include_lib("eunit/include/eunit.hrl").

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

global_effect_window_remains_the_default_test() ->
    Generated = iolist_to_binary(
        phi_decoder_profile_topology_dslx:to_dslx()
    ),
    ?assertEqual(1, count(Generated, <<
        "spawn effect_window::Arbiter<u32:8>"
    >>)),
    ?assertEqual(0, count(Generated, <<"Effect-window domain">>)).

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
    JoinedCycles = schedulers([
        {0, [1]},
        {1, [0, 2]},
        {2, [3]},
        {3, [2]}
    ]),
    ?assertEqual(
        [[0, 1, 2, 3]],
        xls_topology_effect_windows:partition(JoinedCycles, weak_components)
    ),
    DisconnectedCycles = schedulers([
        {0, [1]},
        {1, [0]},
        {2, [3]},
        {3, [2]}
    ]),
    ?assertEqual(
        [[0, 1], [2, 3]],
        xls_topology_effect_windows:partition(
            DisconnectedCycles, weak_components
        )
    ).

generated_profile_and_ram_shell_are_width_driven_test() ->
    #{groups := Groups} = phi_decoder_profile_topology_dslx:scheduler_plan(),
    ExpectedRamCount = 2 * length(Groups),
    Generated = iolist_to_binary(
        phi_decoder_profile_topology_dslx:to_dslx()
    ),
    Wrapper = phi_decoder_profile_top_v:to_verilog(),
    assert_contains(Generated, <<"import phi_syndrome_replay_cell;">>),
    assert_contains(Generated, <<"import phi_halo_cell;">>),
    ?assertEqual(nomatch, binary:match(Generated, <<"phenom_data_cell">>)),
    ?assertEqual(nomatch, binary:match(Generated, <<"phenom_syndrome_cell">>)),
    ?assertEqual(
        ExpectedRamCount,
        count(Wrapper, <<"hls_1r1w_ram #(.WIDTH(">>)
    ),
    assert_contains(Wrapper, <<".scheduler_7_state_rd_addr(">>),
    ?assertEqual(nomatch, binary:match(Wrapper, <<"_reduction_rd_addr">>)),
    ?assertEqual(nomatch, binary:match(Wrapper, <<"@SCHEDULER_">>)).

assert_contains(Binary, Pattern) ->
    ?assertNotEqual(nomatch, binary:match(Binary, Pattern)).

count(Binary, Pattern) ->
    length(binary:matches(Binary, Pattern)).

schedulers(Edges) ->
    [#{
        index => Source,
        destinations => [#{index => Destination}
            || Destination <- Destinations]
    } || {Source, Destinations} <- Edges].
