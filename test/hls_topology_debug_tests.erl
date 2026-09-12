-module(hls_topology_debug_tests).
-include_lib("eunit/include/eunit.hrl").

actor_observation_test() ->
    R = #{<<"id">> => 7, <<"kind">> => <<"actor">>, <<"width">> => 11,
        <<"phases">> => [<<"boot">>, <<"active">>]},
    Decode = fun(V) -> hls_topology_debug:decode_observation(<<7:32/little, 99:64/little, V:32/little>>, R) end,
    ?assertMatch({ok, #{initialized := false, phase := undefined, failed := undefined}}, Decode(0)),
    ?assertMatch({ok, #{initialized := true, phase := <<"active">>, failed := true,
        enter_pending := false, cycle := 99}}, Decode(1024+512+1)),
    ?assertMatch({ok, #{phase := <<"boot">>, failed := false, enter_pending := true}}, Decode(1024+256)),
    ?assertEqual({error, invalid_resource_value}, Decode(1)),
    ?assertEqual({error, invalid_resource_value}, Decode(1024+2)),
    ?assertMatch({error, _}, Decode(2048)).

info_geometry_test() ->
    ?assertMatch({ok, #{schema := 2, channels := 3, queues := 2, actors := 4}},
        hls_topology_debug:decode_info(<<2:32/little, 9:32/little, 3:32/little, 2:32/little, 4:32/little, 0:256>>)),
    ?assertMatch({error, _}, hls_topology_debug:decode_info(
        <<2:32/little, 9:32/little, 3:32/little, 2:32/little, 5:32/little, 0:256>>)).

observation_test() ->
    R = #{<<"id">> => 4, <<"kind">> => <<"fifo">>, <<"width">> => 2, <<"capacity">> => 2},
    ?assertMatch({ok, #{occupancy := 2, free_slots := 0, cycle := 99}},
        hls_topology_debug:decode_observation(<<4:32/little, 99:64/little, 2:32/little>>, R)),
    ?assertMatch({error, invalid_resource_value},
        hls_topology_debug:decode_observation(<<4:32/little, 99:64/little, 3:32/little>>, R)),
    ?assertMatch({error, _},
        hls_topology_debug:decode_observation(<<5:32/little, 99:64/little, 2:32/little>>, R)),
    ?assertMatch({error, _},
        hls_topology_debug:decode_observation(<<4:32/little, 99:64/little, 4:32/little>>, R)).

fingerprint_test() ->
    %% Python json.dumps(..., sort_keys=True, ensure_ascii=False, separators=(",", ":")).
    M = #{<<"z">> => [1, true], <<"a">> => <<"phi", 16#cf, 16#86>>},
    Canonical = <<"{\"a\":\"phi", 16#cf, 16#86, "\",\"z\":[1,true]}">>,
    Hash = string:lowercase(binary:encode_hex(crypto:hash(sha256, Canonical))),
    ?assertEqual(Hash, hls_topology_debug:manifest_fingerprint(M#{<<"fingerprint">> => <<"ignored">>})).

iterative_sink_test() ->
    M = fixture(),
    Q = query_fun(#{0 => 1, 1 => 1, 2 => 1, 3 => 3, 4 => 1}, #{}),
    {ok, R} = hls_topology_wait:inspect_waits(M, Q, [0], #{}),
    ?assertEqual([0, 1, 2], lists:sort(maps:get(reobserved_blocked, R))),
    %% Unrelated progressing channel 3 is never queried.
    ?assertEqual([0, 1, 2, 4], lists:usort([Id || #{id := Id} <- maps:get(observations, R)])),
    ?assert(lists:any(fun(#{kind := K}) -> K =:= external_sink end, maps:get(edges, R))),
    ?assertEqual([], maps:get(candidate_cycles, R)),
    ?assertNot(maps:get(truncated, R)).

transient_and_budget_test() ->
    M = fixture(),
    {ok, R} = hls_topology_wait:inspect_waits(M, query_fun(#{0 => 1, 1 => 1, 2 => 1, 4 => 1}, #{2 => 3}), [0], #{}),
    ?assertEqual([2], maps:get(changed_resources, R)),
    ?assertNot(lists:member(2, maps:get(reobserved_blocked, R))),
    {ok, Bounded} = hls_topology_wait:inspect_waits(M, query_fun(#{0 => 1, 1 => 1, 2 => 1, 4 => 1}, #{}), [0], #{max_queries => 2}),
    ?assert(maps:get(truncated, Bounded)),
    ?assertEqual(2, length(maps:get(observations, Bounded))).

cycle_and_clock_test() ->
    M = fixture(),
    [P0, P1, P2, P3] = maps:get(<<"probes">>, M),
    Cyclic = M#{<<"probes">> := [P0, P1, P2#{<<"endpoints">> := [endpoint(<<"actor">>, <<"producer">>),
        endpoint(<<"source">>, <<"consumer">>)]}, P3]},
    {ok, R} = hls_topology_wait:inspect_waits(Cyclic, query_fun(#{0 => 1, 1 => 1, 2 => 1, 4 => 1}, #{}), [0], #{}),
    ?assertEqual([[0, 1, 2]], maps:get(candidate_cycles, R)),
    ?assertEqual({error, observation_clock_regressed}, hls_topology_wait:inspect_waits(M,
        fun(Id) -> {ok, #{id => Id, cycle => 0, value => 1}} end, [0], #{})),
    ?assertEqual({error, disconnected}, hls_topology_wait:inspect_waits(M,
        fun(_) -> {error, disconnected} end, [0], #{})),
    ?assertEqual({error, {unknown_resources, [99]}}, hls_topology_wait:inspect_waits(M,
        fun(_) -> error(unexpected_query) end, [99], #{})).

ambiguous_and_internal_wait_test() ->
    M = fixture(),
    [P0 | Rest] = maps:get(<<"probes">>, M),
    {ok, R} = hls_topology_wait:inspect_waits(M#{<<"probes">> := [P0#{<<"constant_handshake">> := true} | Rest]},
        query_fun(#{0 => 1}, #{}), [0], #{}),
    ?assertMatch([#{kind := ambiguous}], maps:get(edges, R)),
    {ok, Internal} = hls_topology_wait:inspect_waits(M, query_fun(#{0 => 1, 1 => 1, 2 => 0, 4 => 1}, #{}), [0], #{}),
    ?assertEqual([], maps:get(candidate_cycles, Internal)),
    ?assertNot(lists:any(fun(#{kind := K}) -> K =:= external_sink end, maps:get(edges, Internal))).

query_fun(First, Changes) ->
    Ref = make_ref(),
    put(Ref, {0, #{}}),
    fun(Id) ->
        {Cycle, Seen} = get(Ref),
        Value = case maps:is_key(Id, Seen) of
            true -> maps:get(Id, Changes, maps:get(Id, First));
            false -> maps:get(Id, First)
        end,
        put(Ref, {Cycle+10, Seen#{Id => true}}),
        {ok, #{id => Id, cycle => Cycle, value => Value}}
    end.

endpoint(Path, Role) -> #{<<"path">> => [Path], <<"role">> => Role}.
channel(Id, Source, Sink) ->
    #{<<"id">> => Id, <<"constant_handshake">> => false,
      <<"endpoints">> => [endpoint(Source, <<"producer">>), endpoint(Sink, <<"consumer">>)]}.
fixture() ->
    P2 = (channel(2, <<"actor">>, <<"sink">>))#{<<"endpoints">> := [endpoint(<<"actor">>, <<"producer">>),
        #{<<"role">> => <<"consumer">>, <<"external">> => true, <<"port">> => <<"sink">>}]},
    #{<<"fingerprint">> => <<"fixture">>,
      <<"probes">> => [channel(0, <<"source">>, <<"queue">>), channel(1, <<"queue">>, <<"actor">>), P2,
        channel(3, <<"other">>, <<"unrelated">>)],
      <<"resources">> => [#{<<"id">> => Id, <<"kind">> => <<"channel">>} || Id <- lists:seq(0, 3)] ++
        [#{<<"id">> => 4, <<"kind">> => <<"fifo">>, <<"path">> => [<<"queue">>], <<"push">> => 0, <<"pop">> => 1}]}.
