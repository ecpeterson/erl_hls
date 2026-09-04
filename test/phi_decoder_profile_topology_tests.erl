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
