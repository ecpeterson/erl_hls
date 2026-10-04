-module(hls_gather_debug_tests).
-moduledoc "Checks metadata-only indexed gather inspection on CPU and the shared collection observation word.".
-include_lib("eunit/include/eunit.hrl").

%% Partial elements never appear in an inspection, and observing progress cannot consume them.
-spec cpu_partial_gather_test() -> ok.
cpu_partial_gather_test() ->
    {ok, Pid} = hls_statem:start_link(hls_statem_gather_fixture, #{capacity => 3, mask => 5},
        [{mailbox_capacity, 8}, {outputs, #{out => self()}}]),
    Target = {hls_statem, Pid},
    try
        ?assertEqual({gather, idle}, hls_debug:info(Target, gather)),
        {capabilities, #{info := Fields}} = hls_debug:info(Target, capabilities),
        ?assert(lists:member(gather, Fields)),
        hls_statem:cast(Pid, open),
        hls_statem:cast(Pid, {value, items, 7, 2, private_element}),
        {gather, Progress} = hls_debug:info(Target, gather),
        ?assertMatch(#{status := open, phase := collecting, name := items, key := 7,
            capacity := 3, expected := 5, seen := 4, population := {members, [0, 2]},
            remaining := 1, received := 1, missing_members := [0], failure := none}, Progress),
        ?assertNot(maps:is_key(values, Progress)),
        ?assertNot(lists:member(private_element, maps:values(Progress))),
        ?assertEqual({gather, Progress}, hls_debug:info(Target, gather)),
        ?assertEqual({reduction, idle}, hls_debug:info(Target, reduction)),
        hls_statem:cast(Pid, {value, items, 7, 0, first_element}),
        ?assertEqual({gather, idle}, hls_debug:info(Target, gather))
    after
        hls_statem:stop(Pid), flush_casts()
    end.

%% Site identity selects one logical collection while preserving scalar observation semantics.
-spec mixed_collection_word_test() -> ok.
mixed_collection_word_test() ->
    ?assert(lists:member(gather, hls_topology_debug:actor_fields(resource()))),
    Values = #{status => 1, site => 1, key => 27, remaining => 1, expected => 5, seen => 4},
    ?assertMatch({ok, #{reduction := idle, gather := #{status := open,
        name := <<"items">>, phase := <<"collecting">>, key := 27,
        population := {members, [0, 2]}, received := 1, missing_members := [0]}}}, sample(Values)),
    ?assertMatch({ok, #{gather := idle, reduction := #{status := open,
        name := <<"sum">>, population := {members, [0, 2]}, remaining := 1}}}, sample(Values#{site := 0})),
    ?assertMatch({ok, #{gather := idle, reduction := idle}}, sample(#{status => 0})),
    ?assertMatch({ok, #{gather := undefined, reduction := undefined}},
        hls_topology_debug:decode_observation(<<0:32/little, 10:64/little, 0:128>>, resource())).

%% Zero membership is a completed gather, never an open or completed scalar reduction.
-spec empty_gather_and_invalid_progress_test() -> ok.
empty_gather_and_invalid_progress_test() ->
    Empty = #{status => 2, site => 1, remaining => 0, expected => 0, seen => 0},
    ?assertMatch({ok, #{reduction := idle, gather := #{status := complete,
        population := {members, []}, received := 0, remaining := 0, missing_members := []}}}, sample(Empty)),
    lists:foreach(fun(Bad) ->
        ?assertEqual({error, invalid_reduction_observation}, sample(Bad))
    end, [Empty#{site := 0}, Empty#{status := 1}, Empty#{remaining := 1},
        Empty#{seen := 1}, Empty#{expected := 1},
        #{status => 1, site => 1, remaining => 1, expected => 5, seen => 2}]),
    ?assertMatch({ok, #{gather := #{status := complete, received := 2,
        missing_members := []}}}, sample(Empty#{expected := 5, seen := 5})).

%% The test covers the actual compact query region with two site identities and six member slots.
-spec fields() -> #{atom() => {non_neg_integer(), pos_integer()}}.
fields() -> #{status => {56, 2}, site => {58, 1}, key => {59, 32},
    remaining => {91, 3}, failure => {94, 16}, expected => {110, 6}, seen => {116, 6}}.

%% A scalar site without a kind marker remains compatible with existing manifests.
-spec resource() -> map().
resource() ->
    Population = #{<<"mode">> => <<"members">>, <<"runtime_mask">> => true, <<"size">> => 6},
    #{<<"id">> => 0, <<"kind">> => <<"actor">>, <<"width">> => 122,
        <<"phases">> => [<<"collecting">>], <<"failures">> => #{},
        <<"reduction">> => #{<<"fields">> => maps:from_list([
            {atom_to_binary(Name), #{<<"observation_offset">> => Offset, <<"width">> => Width}}
            || {Name, {Offset, Width}} <- maps:to_list(fields())]),
            <<"sites">> => [
                #{<<"id">> => 0, <<"name">> => <<"sum">>, <<"phase">> => <<"collecting">>,
                    <<"population">> => Population},
                #{<<"id">> => 1, <<"name">> => <<"items">>, <<"phase">> => <<"collecting">>,
                    <<"kind">> => <<"gather">>, <<"population">> => Population}]}}.

%% Encode named observations independently of the decoder and include a valid actor header.
-spec sample(#{atom() => non_neg_integer()}) -> {ok, map()} | {error, term()}.
sample(Fields) ->
    Value = maps:fold(fun(Name, N, Bits) ->
        {Offset, _Width} = maps:get(Name, fields()), Bits bor (N bsl Offset)
    end, 1 bsl 25, Fields),
    hls_topology_debug:decode_observation(<<0:32/little, 10:64/little, Value:128/little>>, resource()).

%% Remove only this actor's ordinary output casts after teardown.
-spec flush_casts() -> ok.
flush_casts() -> receive {'$gen_cast', _} -> flush_casts() after 0 -> ok end.
