-module(hls_partition_reduction_tests).
-include_lib("eunit/include/eunit.hrl").

%% D2 aliases opposite ports; each destination must still collect all four contributions.
-spec aliased_partition_test() -> ok.
aliased_partition_test() ->
    {Plan, Shared} = fixture(),
    Offloaded = hls_partition_reduction:attach(Plan, Shared,
        #{phi_x => source_fragments, phi_z => source_fragments}),
    ?assertEqual(Shared, maps:without([reduction_plan, reduction_inputs], Offloaded)),
    Requirements = hls_partition_reduction:requirements(Offloaded),
    ?assertEqual(#{shared_service => aggregate_only}, maps:get(phi_halo_cell, Requirements)),
    ?assertEqual(#{shared_service => ordinary}, maps:get(phenom_data_cell, Requirements)),
    Inputs = maps:values(maps:get(reduction_inputs, Offloaded)),
    ?assertEqual(8, length(Inputs)),
    lists:foreach(fun(Lanes) ->
        ?assertEqual(4, lists:sum([N || #{multiplicity := N} <- Lanes])),
        ?assertEqual([2, 2], [N || #{multiplicity := N} <- Lanes]),
        ?assertEqual([local, remote], lists:usort([K || #{kind := K} <- Lanes]))
    end, Inputs),
    Source = iolist_to_binary(hls_partition_dslx:emit(Offloaded, 0,
        #{name => reduction_partition_test, channel_depth => 1, actor_egress_depth => burst})),
    ?assertNotEqual(nomatch, binary:match(Source, <<"::reduction_aggregate_batch<u32:4>">>)),
    ?assertNotEqual(nomatch, binary:match(Source, <<"spawn hls_reduction_fragments::Split<u32:2>">>)),
    ?assertNotEqual(nomatch, binary:match(Source, <<"::ReductionAggregateRequest">>)),
    ?assertEqual(nomatch, binary:match(Source, <<"::phi_halo_cell_ReductionAggregateRequest">>)).

%% Unaliased reductions retain their storage budget on the original ordered lanes.
-spec unaliased_partition_test() -> ok.
unaliased_partition_test() ->
    {Plan, Placement, _} = hls_phi_memory_fixture:fixture(d3),
    Shared = hls_partition_schedule:shared_by_module(hls_partition:normalize(Plan, Placement), 4),
    Offloaded = hls_partition_reduction:attach(Plan, Shared,
        #{phi_x => source_fragments, phi_z => source_fragments}),
    Inputs = lists:append(maps:values(maps:get(reduction_inputs, Offloaded))),
    ?assert(lists:all(fun(#{multiplicity := N}) -> N =:= 1 end, Inputs)),
    ?assertEqual([local, remote], lists:usort([K || #{kind := K} <- Inputs])),
    lists:foreach(fun(#{id := Id}) ->
        ?assertEqual(3, hls_partition_reduction:queue_extra(Id, Offloaded))
    end, Inputs),
    Source = iolist_to_binary(hls_partition_dslx:emit(Offloaded, 0,
        #{name => direct_reduction_test, channel_depth => 1, actor_egress_depth => burst})),
    ?assertEqual(nomatch, binary:match(Source, <<"spawn hls_reduction_fragments::Split">>)),
    ?assertNotEqual(nomatch, binary:match(Source, <<"::reduction_aggregate_batch<u32:4>">>)),
    Local = hls_partition:device(Offloaded, 0),
    lists:foreach(fun(#{id := Id, destination := {actor, Actor}}) ->
        Expected = case maps:is_key(Actor, maps:get(reduction_inputs, Local)) of
            true -> 3;
            false -> 0
        end,
        ?assertEqual(Expected, hls_partition_reduction:queue_extra(Id, Local))
    end, maps:get(rx_lanes, Local)),
    ?assertEqual(0, hls_partition_reduction:queue_extra(1000000, Offloaded)).

%% One compiled module cannot receive contributions through two different hardware ABIs.
-spec mixed_artifact_rejected_test() -> ok.
mixed_artifact_rejected_test() ->
    {Plan, Shared} = fixture(),
    ?assertException(error, {source_fragment_module_artifact_conflict, _, _},
        hls_partition_reduction:attach(Plan, Shared, #{phi_x => source_fragments})).

%% Changing physical groups must not change the globally proved contribution lanes.
-spec replication_preserves_contributors_test_() -> {timeout, pos_integer(), fun(() -> ok)}.
replication_preserves_contributors_test_() ->
    %% Three source-provider/layout passes take about six seconds on native macOS.
    {timeout, 15, fun replication_preserves_contributors/0}.

%% Exercise the same complete proof at each supported scheduler replication.
-spec replication_preserves_contributors() -> ok.
replication_preserves_contributors() ->
    {Plan, Shared} = fixture(),
    Direct = maps:remove(schedulers, Shared),
    Plans = [hls_partition_reduction:attach(Plan,
        hls_partition_schedule:shared_by_module(Direct, 4, #{phi_halo_cell => Limit}),
        #{phi_x => source_fragments, phi_z => source_fragments}) || Limit <- [4, 2, 1]],
    ?assertEqual(1, length(lists:usort([maps:get(reduction_inputs, P) || P <- Plans]))).

%% A complete noisy board pair provides actual phi membership and route metadata.
-spec fixture() -> {hls_topology:plan(), map()}.
fixture() ->
    {Plan, Placement, _} = hls_phi_memory_fixture:fixture(board_memory),
    {Plan, hls_partition_schedule:shared_by_module(hls_partition:normalize(Plan, Placement), 4)}.
