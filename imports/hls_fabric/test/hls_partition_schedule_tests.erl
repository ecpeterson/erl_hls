-module(hls_partition_schedule_tests).
-include_lib("eunit/include/eunit.hrl").

%% The full application shares compatible families without moving actors or their routes.
-spec coalesced_layout_test() -> ok.
coalesced_layout_test() ->
    {Plan, Placement, _} = hls_phi_memory_fixture:fixture(),
    Direct = #{actors := Actors, lanes := Lanes} = hls_partition:normalize(Plan, Placement),
    P = #{schedulers := Groups} = hls_partition_schedule:shared_by_module(Direct, 12),
    ?assertEqual(Actors, maps:get(actors, P)),
    ?assertEqual(Lanes, maps:get(lanes, P)),
    ?assertEqual(6, length(Groups)),
    lists:foreach(fun(Device) ->
        #{schedulers := Local} = hls_partition:device(P, Device),
        ?assertEqual([0, 1, 2], [I || #{index := I} <- Local]),
        Expected = case Device of 0 -> 6; 1 -> 12 end,
        lists:foreach(fun(#{slot_count := Count, actors := Members}) ->
            ?assertEqual(Expected, Count),
            ?assertEqual(lists:seq(0, Count-1), [S || #{slot := S} <- Members]),
            ?assertEqual(2, length(lists:usort([F || #{identity := {family, F, _}} <- Members])))
        end, Local)
    end, [0, 1]),
    ?assertEqual(P#{actors := lists:reverse(Actors)},
        hls_partition_schedule:shared_by_module(Direct#{actors := lists:reverse(Actors)}, 12)).

%% A nondivisible bucket uses balanced groups, respects the cap, and never crosses devices.
-spec bounded_grouping_test() -> ok.
bounded_grouping_test() ->
    {Direct = #{actors := [Actor | _] = Actors}, _} = fixture(),
    Extra = Actor#{identity := {actor, extra}},
    P = hls_partition_schedule:shared_by_module(Direct#{actors := [Extra | Actors]}, 2),
    #{schedulers := Groups} = P,
    ?assertEqual([1, 2, 2], lists:sort([N || #{slot_count := N} <- Groups])),
    ?assertEqual(lists:sort([Id || #{identity := Id} <- [Extra | Actors]]),
        lists:sort([Id || #{actors := Members} <- Groups, #{identity := Id} <- Members])),
    ?assertEqual(5, length(maps:get(schedulers,
        hls_partition_schedule:shared_by_module(Direct#{actors := [Extra | Actors]}, 1)))),
    lists:foreach(fun(#{device := Device, module := Module, actors := Members}) ->
        ?assert(lists:all(fun(#{device := D, module := M}) ->
            D =:= Device andalso M =:= Module end, Members))
    end, Groups).

%% Replicating phi execution leaves the other groups, all routes and all identities unchanged.
-spec module_capacity_test() -> ok.
module_capacity_test() ->
    {Plan, Placement, _} = hls_phi_memory_fixture:fixture(board_memory),
    Direct = hls_partition:normalize(Plan, Placement),
    Base = hls_partition_schedule:shared_by_module(Direct, 4),
    Other = fun(P) -> [G || G = #{module := M} <- maps:get(schedulers, P), M =/= phi_halo_cell] end,
    lists:foreach(fun(Limit) ->
        Split = hls_partition_schedule:shared_by_module(Direct, 4, #{phi_halo_cell => Limit}),
        ?assertEqual(Other(Base), Other(Split)),
        ?assertEqual(Direct, maps:remove(schedulers, Split)),
        lists:foreach(fun(Device) ->
            #{schedulers := Local} = hls_partition:device(Split, Device),
            ?assertEqual(lists:duplicate(4 div Limit, Limit),
                [N || #{module := phi_halo_cell, slot_count := N} <- Local])
        end, maps:get(devices, Direct))
    end, [4, 2, 1]),
    ?assertError({unknown_scheduler_modules, [misspelled]},
        hls_partition_schedule:shared_by_module(Direct, 4, #{misspelled => 1})),
    ?assertError({invalid_scheduler_capacity, phi_halo_cell, 0},
        hls_partition_schedule:shared_by_module(Direct, 4, #{phi_halo_cell => 0})).

%% RAM grouping preserves application routes, actor identities and dense local storage slots.
-spec shared_layout_test() -> ok.
shared_layout_test() ->
    {Direct, Specs} = fixture(),
    P = hls_partition_schedule:shared(Direct, Specs),
    ?assertEqual(maps:get(lanes, Direct), maps:get(lanes, P)),
    ?assertEqual(maps:get(actors, Direct), maps:get(actors, P)),
    #{schedulers := [G], tx_lanes := Tx, rx_lanes := Rx} = hls_partition:device(P, a),
    ?assertEqual(2, maps:get(slot_count, G)),
    ?assertEqual([0, 1], [S || #{slot := S} <- maps:get(actors, G)]),
    ?assertEqual([0, 1], [W || #{wire_id := W} <- Tx]),
    ?assertEqual([0, 1], [W || #{wire_id := W} <- Rx]),
    ?assertEqual([], [S || #{kind := window, signal := S} <- Tx]),
    ?assertEqual([], [S || #{kind := window, signal := S} <- Rx]),
    ok.

%% Every received signal/data lane has exactly one opposite transmitter with the same wire ID.
-spec paired_lanes_test() -> ok.
paired_lanes_test() ->
    {Direct, Specs} = fixture(),
    P = hls_partition_schedule:shared(Direct, Specs),
    A = hls_partition:device(P, a), B = hls_partition:device(P, b),
    ?assertEqual(maps:get(tx_lanes, A), maps:get(rx_lanes, B)),
    ?assertEqual(maps:get(tx_lanes, B), maps:get(rx_lanes, A)).

%% Map and member insertion order cannot change the physical deployment or its fingerprint.
-spec canonical_groups_test() -> ok.
canonical_groups_test() ->
    {Direct, Specs} = fixture(),
    Reverse = maps:from_list([{G, lists:reverse(Ids)} || {G, Ids} <- lists:reverse(maps:to_list(Specs))]),
    ?assertEqual(hls_partition_schedule:shared(Direct, Specs), hls_partition_schedule:shared(Direct, Reverse)).

%% A physical RAM executor cannot own actors on both devices or silently omit an actor.
-spec invalid_ownership_test() -> ok.
invalid_ownership_test() ->
    {P, Specs} = fixture(),
    [A | _] = maps:get(a, Specs), [B | _] = maps:get(b, Specs),
    ?assertException(error, {partition_scheduler_devices, _, [a, b]},
        hls_partition_schedule:shared(P, #{mixed => [A, B], rest =>
            (maps:get(a, Specs) ++ maps:get(b, Specs)) -- [A, B]})),
    ?assertException(error, {partition_unscheduled, [_ | _]},
        hls_partition_schedule:shared(P, maps:remove(b, Specs))).

%% Startup is loaded before RUN, so a too-large prefix cannot wait for normal consumption.
-spec startup_capacity_test() -> ok.
startup_capacity_test() ->
    {P = #{actors := [A = #{identity := Id, mailbox_capacity := Capacity} | Rest]}, Specs} = fixture(),
    Frame = #{selector => 0, payload => <<>>},
    Full = A#{startup := lists:duplicate(Capacity, Frame)},
    ?assertMatch(#{schedulers := _}, hls_partition_schedule:shared(P#{actors := [Full | Rest]}, Specs)),
    TooMany = Capacity+1,
    Overflow = A#{startup := lists:duplicate(TooMany, Frame)},
    ?assertError({partition_startup_capacity, Id, TooMany, Capacity},
        hls_partition_schedule:shared(P#{actors := [Overflow | Rest]}, Specs)).

%% The existing typed request ABI has a dedicated credit receptacle outside actor request queues.
-spec generated_bindings_test() -> ok.
generated_bindings_test() ->
    {P, Specs} = fixture(),
    Shared = hls_partition_schedule:shared(P, Specs),
    Profile = #{name => shared_test, channel_depth => 1, actor_egress_depth => burst},
    Owner = iolist_to_binary(hls_partition_dslx:emit(Shared, a, Profile)),
    Peer = iolist_to_binary(hls_partition_dslx:emit(Shared, b, Profile)),
    ?assertEqual(nomatch, binary:match(Owner, <<"effect_window::Arbiter">>)),
    ?assertEqual(nomatch, binary:match(Peer, <<"effect_window::Arbiter">>)),
    ?assertNotEqual(nomatch, binary:match(Peer, <<"::SharedService<u32:2, u32:4, u32:0, u32:0, true>">>)),
    ?assertNotEqual(nomatch, binary:match(Peer, <<"hls_partition_fixture_ActorOutboxBank<u32:2>">>)),
    ?assertNotEqual(nomatch, binary:match(Peer, <<"scheduler_0_mailbox_debug_out">>)),
    ?assertEqual(nomatch, binary:match(Peer, <<"spawn axis::ReservedFrame">>)).

%% Two columns exercise aliased fanout, one module and two local slots per device.
-spec fixture() -> {map(), map()}.
fixture() ->
    Plan = hls_topology:normalize(#{version => 1, actors => #{},
        families => #{cells => #{module => hls_partition_fixture, shape => [2, 2]}},
        ingresses => [], externals => [{reports, out, [work]}], routes => [], startup => [],
        route_relations => [{{cells, left}, [{family, cells, {translate, [1, 0], wrap}}]},
            {{cells, right}, [{family, cells, {translate, [1, 0], wrap}}]},
            {{cells, report}, [{external, reports}]}]}),
    A = [{family, cells, [0, Y]} || Y <- [0, 1]], B = [{family, cells, [1, Y]} || Y <- [0, 1]],
    Placement = maps:from_list([{Id, a} || Id <- A] ++ [{Id, b} || Id <- B]),
    {hls_partition:normalize(Plan, Placement), #{a => A, b => B}}.
