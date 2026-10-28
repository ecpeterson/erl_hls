-module(hls_partition_tile_tests).
-include_lib("eunit/include/eunit.hrl").

%% All eighteen wraps have identical logic; seeds and global filter points remain distinct.
-spec congruence_test_() -> tuple().
congruence_test_() -> {timeout, 120, fun congruence/0}.

%% Exercise actual application routes, both reduction planes and all global seam positions.
-spec congruence() -> ok.
congruence() ->
    {Plan, Placement, _} = hls_phi_memory_fixture:fixture(mesh_memory),
    Raw = hls_partition:normalize(Plan, Placement),
    Scheduled = hls_partition_schedule:shared_by_module(Raw, 12, #{phi_halo_cell => 2}),
    Reduced = hls_partition_reduction:attach(Plan, Scheduled, #{phi_x => source_fragments, phi_z => source_fragments}),
    {Roles, Peers} = hls_phi_board_geometry:tile_roles(6),
    P = hls_partition_tile:schedule(hls_partition_tile:prepare(Reduced, Roles, Peers), 12, #{phi_halo_cell => 2}),
    %% Protocol binding validation has its own tests; only varying constants matter here.
    Deployment = #{devices => maps:from_list([{D, #{identity => <<D:256>>, host => D+1,
        control => 7, local => hls_partition:device(P, D)}} || D <- lists:seq(0, 17)])},
    Graphs = [iolist_to_binary(hls_partition_dslx:emit(P, D, #{name => tile_graph, channel_depth => 1, actor_egress_depth => burst})) || D <- lists:seq(0, 17)],
    Tops = [iolist_to_binary(xls_partition_application:emit(Deployment, D, tile_graph)) || D <- lists:seq(0, 17)],
    ?assertEqual(1, length(lists:usort(Graphs))),
    ?assertEqual(1, length(lists:usort(Tops))),
    Original = maps:from_list([{Id, Frames} || #{identity := Id, startup := Frames} <- maps:get(actors, Raw)]),
    ?assertEqual(Original, maps:from_list([{Id, Frames} || #{identity := Id, startup := Frames} <- maps:get(actors, P)])),
    Configs = [begin
        L = #{schedulers := Groups, links := Links} = hls_partition:device(P, D),
        %% Equal emitted slot wiring covers all boards; check the public layout at both seams.
        case lists:member(D, [0, 1, 17]) of
            true ->
                {Physical, Specs} = hls_partition_tile:planning(L),
                #{groups := Planned} = hls_scheduler_plan:normalize(Physical, Specs),
                ?assertEqual([[{I, S} || #{index := I, slot := S} <- A] || #{actors := A} <- Groups],
                    [[{I, S} || #{id := I, base_slot := S} <- A] || #{members := A} <- Planned]);
            false -> ok
        end,
        lists:foreach(fun(#{peer := Peer, tx_lanes := Tx, rx_lanes := Rx}) ->
            Remote = hls_partition:device(P, Peer),
            ?assertEqual(lists:seq(0, length(Tx)-1), [W || #{wire_id := W} <- Tx]),
            ?assertEqual(lists:sort(Tx), lists:sort([L0 || L0 = #{source_device := S} <- maps:get(rx_lanes, Remote), S =:= D])),
            ?assertEqual(lists:sort(Rx), lists:sort([L0 || L0 = #{destination_device := T} <- maps:get(tx_lanes, Remote), T =:= D]))
        end, Links),
        hls_partition_tile:constants(L, maps:get(D, maps:get(devices, Deployment)))
    end || D <- lists:seq(0, 17)],
    ?assertEqual(18, length(lists:usort(Configs))),
    [A | _] = maps:get(actors, Raw),
    Id = maps:get(identity, A),
    ?assertException(error, _, hls_partition_tile:prepare(Reduced, maps:remove(Id, Roles), Peers)),
    ?assertException(error, _, hls_partition_tile:prepare(Reduced, Roles, maps:map(fun(_, _) -> 0 end, Peers))),
    ?assertError({aliased_tile_neighbors, 4}, hls_phi_board_geometry:tile_roles(4)),
    ok.
