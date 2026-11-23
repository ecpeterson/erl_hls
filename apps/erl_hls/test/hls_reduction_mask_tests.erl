-module(hls_reduction_mask_tests).
-moduledoc "Bounded runtime participant-set checks for actor reductions.".
-include_lib("eunit/include/eunit.hrl").
-export([reduce/3]).

%% Each nonempty six-bit set has exactly its selected numeric contributors.
-spec all_small_member_sets_test() -> ok.
all_small_member_sets_test() ->
    lists:foreach(fun(Mask) ->
        Members = [I || I <- lists:seq(0, 5), Mask band (1 bsl I) =/= 0],
        {ok, R0} = hls_reduction:open(parity, epoch, {members_mask, 6, Mask},
            {commutative_monoid, 0}),
        ?assertMatch(#{population := {members, Members}, received := 0}, hls_reduction:info(R0)),
        Result = lists:foldl(fun(Member, {pending, R}) ->
            hls_reduction:contribute(?MODULE, parity, epoch, Member, 1 bsl Member, R)
        end, {pending, R0}, lists:reverse(Members)),
        ?assertEqual({complete, {reduction_complete, parity, epoch, Mask}}, Result)
    end, lists:seq(1, 63)).

%% Bounds, numeric shape and nonemptiness are checked before installing a window.
-spec invalid_mask_test() -> ok.
invalid_mask_test() ->
    lists:foreach(fun({Width, Mask}) ->
        ?assertEqual({error, invalid_population}, hls_reduction:open(parity, epoch,
            {members_mask, Width, Mask}, {commutative_monoid, 0}))
    end, [{0, 1}, {256, 1}, {6, 0}, {6, -1}, {6, 64}, {6, 1.0}, {6, false}, {1.0, 1}]).

%% Rejections retain both the member budget and the accumulated value.
-spec rejected_members_test() -> ok.
rejected_members_test() ->
    {ok, R0} = hls_reduction:open(parity, epoch, {members_mask, 6, 33}, {commutative_monoid, 0}),
    ?assertEqual({error, {unexpected_member, 1}},
        hls_reduction:contribute(?MODULE, parity, epoch, 1, 2, R0)),
    {pending, R1} = hls_reduction:contribute(?MODULE, parity, epoch, 5, 32, R0),
    ?assertEqual({error, {duplicate_member, 5}},
        hls_reduction:contribute(?MODULE, parity, epoch, 5, 32, R1)),
    ?assertEqual(mismatch, hls_reduction:contribute(?MODULE, parity, next_epoch, 0, 1, R1)),
    ?assertEqual({complete, {reduction_complete, parity, epoch, 33}},
        hls_reduction:contribute(?MODULE, parity, epoch, 0, 1, R1)).

-doc "Combines independent bounded parity contributions.".
-spec reduce(parity | poison, non_neg_integer(), non_neg_integer()) -> non_neg_integer().
reduce(parity, A, B) -> A bxor B;
reduce(poison, _A, _B) ->
    put(mask_reduce_calls, get(mask_reduce_calls) + 1),
    error(mask_fold_failure).

%% The declared mask follows ordinary mailbox postponement and completion ordering on ERTS.
-spec actor_member_mask_test() -> ok.
actor_member_mask_test() ->
    Module = hls_statem_mask_reduction_fixture,
    {ok, Module, Binary} = compile:file("test_data/hls_statem_mask_reduction_fixture.erl", [binary]),
    {module, Module} = code:load_binary(Module, "mask_fixture", Binary),
    {ok, Pid} = hls_statem:start_link(Module, [], [{mailbox_capacity, 8}, {outputs, #{out => self()}}]),
    try
        ok = hls_statem:cast(Pid, {piece, 7, 5, 32}),
        ?assertMatch(#{phase := idle, postponed := 1}, hls_statem:info(Pid)),
        ok = hls_statem:cast(Pid, {begin_set, 7, 33}),
        ?assertMatch(#{phase := collecting, reduction := #{remaining := 1}}, hls_statem:info(Pid)),
        ok = hls_statem:cast(Pid, {piece, 7, 0, 1}),
        receive {'$gen_cast', {result, 33}} -> ok after 1000 -> error(missing_mask_result) end,
        ?assertMatch(#{phase := complete, reduction := idle}, hls_statem:info(Pid))
    after
        hls_statem:stop(Pid)
    end.

%% A failed fold keeps its exact missing-member obligations and never evaluates another fold.
-spec poisoned_window_drains_selected_members_test() -> ok.
poisoned_window_drains_selected_members_test() ->
    put(mask_reduce_calls, 0),
    try
        {ok, R0} = hls_reduction:open(poison, 16#ffffffff, {members_mask, 6, 37},
            {commutative_monoid, 0}),
        {pending, R1} = hls_reduction:contribute(?MODULE, poison, 16#ffffffff, 0, 1, R0),
        ?assertMatch(#{remaining := 2, failure := #{reason := mask_fold_failure}}, hls_reduction:info(R1)),
        ?assertEqual({error, {unexpected_member, 1}},
            hls_reduction:contribute(?MODULE, poison, 16#ffffffff, 1, 2, R1)),
        {pending, R2} = hls_reduction:contribute(?MODULE, poison, 16#ffffffff, 5, 32, R1),
        ?assertMatch(#{remaining := 1}, hls_reduction:info(R2)),
        ?assertEqual(mismatch, hls_reduction:contribute(?MODULE, poison, 0, 2, 4, R2)),
        ?assertError(mask_fold_failure,
            hls_reduction:contribute(?MODULE, poison, 16#ffffffff, 2, 4, R2)),
        ?assertEqual(1, get(mask_reduce_calls))
    after erase(mask_reduce_calls) end.

%% Capacity bounds the numeric identity, not the number of low-index members selected.
-spec maximum_capacity_sparse_mask_test() -> ok.
maximum_capacity_sparse_mask_test() ->
    Mask = (1 bsl 254) bor 1,
    {ok, R0} = hls_reduction:open(parity, 0, {members_mask, 255, Mask}, {commutative_monoid, 0}),
    ?assertMatch(#{population := {members, [0, 254]}, remaining := 2}, hls_reduction:info(R0)),
    {pending, R1} = hls_reduction:contribute(?MODULE, parity, 0, 254, 32, R0),
    ?assertEqual({complete, {reduction_complete, parity, 0, 33}},
        hls_reduction:contribute(?MODULE, parity, 0, 0, 1, R1)).

%% Sparse masks are decoded by numeric member identity, not by rank within the active subset.
-spec hardware_membership_observation_test() -> ok.
hardware_membership_observation_test() ->
    Reduction = maps:get(reductions, xls_parse:actor_artifact(
        "test_data/hls_statem_mask_reduction_fixture.erl", [])),
    {Resource, Fields} = debug_resource(Reduction),
    Values = #{status => 1, site => 0, key => 7, remaining => 1, failure => 0,
        expected => 33, seen => 32},
    {ok, #{reduction := Progress}} = debug_sample(Values, Resource, Fields),
    ?assertMatch(#{population := {members, [0, 5]}, received := 1, remaining := 1,
        arrived_members := [5], missing_members := [0]}, Progress),
    lists:foreach(fun(Bad) ->
        ?assertEqual({error, invalid_reduction_observation}, debug_sample(Bad, Resource, Fields))
    end, [Values#{seen := 2}, Values#{remaining := 3}, Values#{expected := 0}]).

%% A bounded query that cannot carry a wide mask never mistakes capacity for the selected population.
-spec wide_mask_observation_test() -> ok.
wide_mask_observation_test() ->
    Reduction = maps:get(reductions, xls_parse:actor_artifact(
        "test_data/hls_statem_mask_reduction_fixture.erl", [])),
    [Site] = maps:get(sites, Reduction),
    Wide = Reduction#{sites := [Site#{population := #{mode => members, size => 255,
        members => lists:seq(0, 254), runtime_mask => true}}]},
    {Resource, Fields} = debug_resource(Wide),
    ?assertNot(maps:is_key(expected, Fields)),
    {ok, #{reduction := Progress}} = debug_sample(#{status => 1, site => 0,
        key => 7, remaining => 1, failure => 0}, Resource, Fields),
    ?assertMatch(#{population := {members_mask, 255, unavailable},
        received := undefined, remaining := 1}, Progress).

%% Build the same public descriptor used by the generated dedicated-actor observation port.
-spec debug_resource(map()) -> {map(), map()}.
debug_resource(Reduction) ->
    #{reduction := Metadata = #{width := Width, fields := Fields}} = xls_actor_observation:layout(Reduction),
    Sites = [maps:with([id, phase, name, population], S) || S <- maps:get(sites, Reduction)],
    Resource = #{id => 0, kind => actor, width => 56 + Width, phases => [collecting], failures => #{},
        reduction => Metadata#{sites => Sites}},
    {json:decode(iolist_to_binary(json:encode(Resource))), Fields}.

%% Encode a coherent wire sample without reaching through the implementation's opaque reducer record.
-spec debug_sample(map(), map(), map()) -> {ok, map()} | {error, term()}.
debug_sample(Values, Resource, Fields) ->
    Value = maps:fold(fun(Name, N, Acc) ->
        #{observation_offset := Offset} = maps:get(Name, Fields), Acc bor (N bsl Offset)
    end, 1 bsl 25, Values),
    hls_topology_debug:decode_observation(<<0:32/little, 9:64/little, Value:128/little>>, Resource).

%% Fixed sites sharing storage with a runtime site still use declaration-order member bits.
-spec mixed_site_observation_test() -> ok.
mixed_site_observation_test() ->
    Reduction = maps:get(reductions, xls_parse:actor_artifact(
        "test_data/hls_statem_mask_reduction_fixture.erl", [])),
    [Site] = maps:get(sites, Reduction),
    Fixed = Site#{id := 1, population := #{mode => members, size => 2, members => [10, 40]}},
    {Resource, Fields} = debug_resource(Reduction#{sites := [Site, Fixed]}),
    Values = #{status => 1, site => 1, key => 7, remaining => 1, failure => 0,
        expected => 3, seen => 2},
    ?assertMatch({ok, #{reduction := #{population := {members, [10, 40]},
        arrived_members := [40], missing_members := [10]}}}, debug_sample(Values, Resource, Fields)),
    ?assertEqual({error, invalid_reduction_observation},
        debug_sample(Values#{expected := 2}, Resource, Fields)).

%% Early collection is distinct from a completed empty population, and requires manifest authorization.
-spec early_collection_observation_test() -> ok.
early_collection_observation_test() ->
    Reduction = maps:get(reductions, xls_parse:actor_artifact(
        "test_data/hls_statem_mask_reduction_fixture.erl", [])),
    {Resource, Fields} = debug_resource(Reduction),
    EarlyResource = Resource#{<<"reduction">> := (maps:get(<<"reduction">>, Resource))#{<<"early_collection">> => true}},
    Values = #{status => 1, site => 0, key => 7, remaining => 0, failure => 0, expected => 0, seen => 32},
    ?assertEqual({error, invalid_reduction_observation}, debug_sample(Values, Resource, Fields)),
    ?assertMatch({ok, #{reduction := #{status := early, key := 7, population := {members_mask, 6, pending},
        remaining := undefined, received := 1, arrived_members := [5], missing_members := undefined}}},
        debug_sample(Values, EarlyResource, Fields)),
    Uninitialized = maps:fold(fun(Name, N, Acc) ->
        #{observation_offset := Offset} = maps:get(Name, Fields), Acc bor (N bsl Offset)
    end, 0, Values),
    ?assertMatch({ok, #{initialized := false, reduction := undefined}},
        hls_topology_debug:decode_observation(<<0:32/little, 9:64/little, Uninitialized:128/little>>, EarlyResource)),
    ?assertEqual({error, invalid_reduction_observation}, debug_sample(Values#{seen := 0}, EarlyResource, Fields)),
    ?assertEqual({error, invalid_reduction_observation}, debug_sample(Values#{expected := 33}, EarlyResource, Fields)).
