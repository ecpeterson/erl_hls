-module(hls_scheduler_plan_tests).

-include_lib("eunit/include/eunit.hrl").

%% Checks phi profile groups homogeneous families.
-spec phi_profile_groups_homogeneous_families_test() -> 'ok'.
phi_profile_groups_homogeneous_families_test() ->
    #{groups := Groups, direct_members := []} =
        phi_shared_noise_topology_dslx:scheduler_plan(),
    ?assertEqual(
        [data_even, data_odd, phi_x, phi_z, syndrome_x, syndrome_z],
        [maps:get(id, Group) || Group <- Groups]
    ),
    assert_group(
        group(phi_x, Groups),
        phi_halo_cell,
        9,
        [{family, phi_x, 0}]
    ),
    assert_group(
        group(syndrome_z, Groups),
        phenom_syndrome_cell,
        9,
        [{family, syndrome_z, 0}]
    ),
    assert_group(
        group(data_even, Groups),
        phenom_data_cell,
        9,
        [{family, data_even, 0}]
    ).

%% Checks one shard profile retains module level groups.
-spec one_shard_profile_retains_module_level_groups_test() -> 'ok'.
one_shard_profile_retains_module_level_groups_test() ->
    #{groups := Groups, direct_members := []} =
        phi_shared_noise_topology_dslx:scheduler_plan(1),
    ?assertEqual([data, phi, syndrome], [
        maps:get(id, Group) || Group <- Groups
    ]),
    assert_group(
        group(phi, Groups),
        phi_halo_cell,
        18,
        [{family, phi_x, 0}, {family, phi_z, 9}]
    ),
    assert_group(
        group(syndrome, Groups),
        phenom_syndrome_cell,
        18,
        [{family, syndrome_x, 0}, {family, syndrome_z, 9}]
    ),
    assert_group(
        group(data, Groups),
        phenom_data_cell,
        18,
        [{family, data_even, 0}, {family, data_odd, 9}]
    ).

%% Checks interleaved phi shards cover each family once.
-spec interleaved_phi_shards_cover_each_family_once_test() -> 'ok'.
interleaved_phi_shards_cover_each_family_once_test() ->
    lists:foreach(
        fun(ShardCount) ->
            #{groups := Groups, direct_members := []} =
                phi_shared_noise_topology_dslx:scheduler_plan(
                    {phi_shards, ShardCount}
                ),
            PhiX = [Member
                || Group <- Groups,
                   Member = #{kind := family, id := phi_x} <-
                       maps:get(members, Group)],
            ?assertEqual(ShardCount, length(PhiX)),
            Coordinates = lists:sort(lists:append([
                [maps:get(coordinates, Instance)
                    || Instance <- maps:get(instances, Member)]
                || Member <- PhiX
            ])),
            ?assertEqual(
                [[X, Y] || X <- lists:seq(0, 2), Y <- lists:seq(0, 2)],
                Coordinates
            ),
            ?assertEqual(9, lists:sum([
                maps:get(instance_count, Member) || Member <- PhiX
            ]))
        end,
        [1, 2, 3]
    ).

%% Checks incomplete family partition is rejected.
-spec incomplete_family_partition_is_rejected_test() -> 'ok'.
incomplete_family_partition_is_rejected_test() ->
    Topology = hls_topology:from_module(phi_noise_topology),
    ?assertError(
        {incomplete_partition, {family, phi_x}, 2, [0]},
        hls_scheduler_plan:normalize(Topology, #{
            only_half => group_spec([
                {family, phi_x, {interleaved, 0, 2}}
            ])
        })
    ).

%% Checks ungrouped members keep direct realization.
-spec ungrouped_members_keep_direct_realization_test() -> 'ok'.
ungrouped_members_keep_direct_realization_test() ->
    Topology = hls_topology:from_module(phi_noise_topology),
    #{groups := [_], direct_members := Direct} =
        hls_scheduler_plan:normalize(Topology, #{
            phi => group_spec([{family, phi_x}, {family, phi_z}])
        }),
    ?assertEqual(
        [
            {family, data_even},
            {family, data_odd},
            {family, syndrome_x},
            {family, syndrome_z}
        ],
        Direct
    ).

%% Supplied compiler summaries must cover and exactly project to the retained core catalog.
-spec supplied_interfaces_match_core_catalog_test() -> ok.
supplied_interfaces_match_core_catalog_test() ->
    Topology = hls_topology:from_module(phi_noise_topology),
    Layout = hls_frame_layout:default(),
    Interfaces = hls_scheduler_plan:interfaces(Topology, Layout),
    Scheduler = hls_scheduler_plan:normalize(Topology, #{}, Layout, Interfaces),
    ?assertEqual(Interfaces, maps:get(interfaces, Scheduler)),
    [Module | _] = maps:keys(Interfaces),
    ?assertError(
        {compiler_process_interface_catalog, [Module], []},
        hls_scheduler_plan:normalize(
            Topology, #{}, Layout, maps:remove(Module, Interfaces)
        )
    ),
    ProcessInterfaces = hls_logical_topology:interfaces(Topology),
    ProcessInterface = maps:get(Module, ProcessInterfaces),
    Mismatch = Topology#{interfaces := ProcessInterfaces#{
        Module := ProcessInterface#{mailbox_capacity := 999}
    }},
    ?assertException(
        error,
        {compiler_process_interface_mismatch, Module, _, _},
        hls_scheduler_plan:normalize(Mismatch, #{}, Layout, Interfaces)
    ).

%% Checks heterogeneous group is rejected.
-spec heterogeneous_group_is_rejected_test() -> 'ok'.
heterogeneous_group_is_rejected_test() ->
    Topology = hls_topology:from_module(phi_noise_topology),
    ?assertError(
        {heterogeneous_group, mixed,
            [phenom_syndrome_cell, phi_halo_cell]},
        hls_scheduler_plan:normalize(Topology, #{
            mixed => group_spec([
                {family, phi_x},
                {family, syndrome_x}
            ])
        })
    ).

%% Checks one member cannot belong to two schedulers.
-spec one_member_cannot_belong_to_two_schedulers_test() -> 'ok'.
one_member_cannot_belong_to_two_schedulers_test() ->
    Topology = hls_topology:from_module(phi_noise_topology),
    ?assertError(
        {duplicate, members, [{family, phi_x}]},
        hls_scheduler_plan:normalize(Topology, #{
            first => group_spec([{family, phi_x}]),
            second => group_spec([{family, phi_x}])
        })
    ).

%% Checks unknown member is rejected.
-spec unknown_member_is_rejected_test() -> 'ok'.
unknown_member_is_rejected_test() ->
    Topology = hls_topology:from_module(phi_noise_topology),
    ?assertError(
        {unknown_member, {family, missing}},
        hls_scheduler_plan:normalize(Topology, #{
            phi => group_spec([{family, missing}])
        })
    ).

%% Checks storage binding is required and checked.
-spec storage_binding_is_required_and_checked_test() -> 'ok'.
storage_binding_is_required_and_checked_test() ->
    Topology = hls_topology:from_module(phi_noise_topology),
    ?assertError(
        {scheduler_group_keys, phi, [mailbox_storage], []},
        hls_scheduler_plan:normalize(Topology, #{
            phi => #{
                members => [{family, phi_x}],
                state_storage => block_ram
            }
        })
    ),
    ?assertError(
        {storage, phi, state, automatic},
        hls_scheduler_plan:normalize(Topology, #{
            phi => (group_spec([{family, phi_x}]))#{
                state_storage := automatic
            }
        })
    ).

%% Checks exact actors can share when their artifacts match.
-spec exact_actors_can_share_when_their_artifacts_match_test() -> 'ok'.
exact_actors_can_share_when_their_artifacts_match_test() ->
    Topology = hls_topology:normalize(#{
        version => 1,
        actors => #{phi_a => hls_partition_fixture, phi_b => hls_partition_fixture},
        families => #{},
        externals => [{reports, out, [work]}],
        ingresses => [],
        routes => [
            {{Actor, Port}, [{external, reports}]}
         || Actor <- [phi_a, phi_b], Port <- [left, right, report]
        ],
        route_relations => [],
        startup => []
    }),
    #{groups := [Group], direct_members := []} =
        hls_scheduler_plan:normalize(Topology, #{
            phi => group_spec([{actor, phi_a}, {actor, phi_b}])
        }),
    ?assertEqual(hls_partition_fixture, maps:get(module, Group)),
    ?assertEqual(2, maps:get(slot_count, Group)).

%% Builds a homogeneous storage policy for the requested fixture members.
-spec group_spec([{'actor','phi_a' | 'phi_b'} | {'family','missing' | 'phi_x' | 'phi_z' | 'syndrome_x'} | {'family','phi_x',{term(),term(),term()}},...]) -> map().
group_spec(Members) ->
    #{
        members => Members,
        state_storage => block_ram,
        mailbox_storage => block_ram
    }.

%% Assigns the selected fixture members to one shared executor.
-spec group('data' | 'data_even' | 'phi' | 'phi_x' | 'syndrome' | 'syndrome_z',[any()]) -> map().
group(Id, Groups) ->
    hd([Group || Group = #{id := GroupId} <- Groups, GroupId =:= Id]).

%% Checks dense slot assignment and memory layout for one normalized group.
-spec assert_group(map(),'phenom_data_cell' | 'phenom_syndrome_cell' | 'phi_halo_cell',9 | 18,[{'family','data_even' | 'data_odd' | 'phi_x' | 'phi_z' | 'syndrome_x' | 'syndrome_z',0 | 9},...]) -> 'ok'.
assert_group(Group, Module, SlotCount, ExpectedMembers) ->
    ?assertEqual(Module, maps:get(module, Group)),
    ?assertEqual(SlotCount, maps:get(slot_count, Group)),
    ?assertEqual(5, maps:get(mailbox_capacity, Group)),
    ?assert(maps:get(width, maps:get(state, Group)) > 0),
    Interface = hls_actor_interface:from_module(Module),
    ?assertEqual(
        hls_actor_interface:reduction_storage_width(Interface),
        maps:get(reduction_storage_width, Group)
    ),
    ?assertEqual(round_robin, maps:get(selection, Group)),
    ?assertEqual(resumable, maps:get(effect_progress, Group)),
    ?assertEqual(none, maps:get(reservation, Group)),
    ?assertEqual(yield, maps:get(blocked, Group)),
    ?assertEqual(block_ram, maps:get(state_storage, Group)),
    ?assertEqual(block_ram, maps:get(mailbox_storage, Group)),
    ?assertEqual(ExpectedMembers, [
        {Kind, Id, Base}
        || #{kind := Kind, id := Id, base_slot := Base} <-
               maps:get(members, Group)
    ]).
