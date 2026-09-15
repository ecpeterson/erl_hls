-module(hls_reduction_debug_tests).
-include_lib("eunit/include/eunit.hrl").

cpu_partial_reduction_test_() ->
    [?_test(cpu_partial(Mode, Fault)) || Mode <- [count, members], Fault <- [false, true]].

cpu_partial(Mode, Fault) ->
    {ok, Pid} = hls_statem:start_link(hls_statem_reduction_fixture, [],
        [{mailbox_capacity, 8}, {outputs, #{out => self()}}]),
    unlink(Pid),
    Ref = monitor(process, Pid),
    Target = {hls_statem, Pid},
    try
        ?assertEqual({reduction, idle}, hls_debug:info(Target, reduction)),
        {Begin, Phase, Population, Count} = case Mode of
            count -> {begin_count, counting, {count, 2}, 2};
            members -> {begin_members, collecting_members, {members, [0, 1, 2, 3]}, 4}
        end,
        hls_statem:cast(Pid, {Begin, 16#fedcba98}),
        Value = case Fault of true -> invalid_number; false -> 7 end,
        contribute(Pid, Mode, 0, Value),
        {reduction, Snapshot} = hls_debug:info(Target, reduction),
        ?assertMatch(#{status := open, name := sum, key := 16#fedcba98,
            phase := Phase, population := Population, received := 1}, Snapshot),
        ?assertEqual(Count-1, maps:get(remaining, Snapshot)),
        ?assertEqual(case Fault of true -> #{class => error, reason => badarith}; false -> none end,
            maps:get(failure, Snapshot)),
        %% Inspection neither consumes contributions nor closes a failed window.
        ?assertEqual({reduction, Snapshot}, hls_debug:info(Target, reduction)),
        lists:foreach(fun(I) -> contribute(Pid, Mode, I, 1) end, lists:seq(1, Count-1)),
        case Fault of
            true -> receive {'DOWN', Ref, process, Pid, {badarith, _}} -> ok
                after 1000 -> error(failure_not_released) end;
            false ->
                receive {'$gen_cast', {observation, 1, Total, 0, 1}} -> ?assertEqual(7+Count-1, Total)
                after 1000 -> error(no_completion) end,
                ?assertEqual({reduction, idle}, hls_debug:info(Target, reduction))
        end
    after
        case is_process_alive(Pid) of true -> hls_statem:stop(Pid); false -> ok end,
        demonitor(Ref, [flush])
    end.

contribute(Pid, count, _Member, Value) -> hls_statem:cast(Pid, {count, 16#fedcba98, Value});
contribute(Pid, members, Member, Value) -> hls_statem:cast(Pid, {member, 16#fedcba98, Member, Value}).

hardware_reduction_decode_test() ->
    #{<<"banks">> := [Bank]} = hls_actor_debug_dslx:projection(reduction),
    #{<<"reduction">> := Reduction = #{<<"width">> := Width, <<"fields">> := Fields},
        <<"failures">> := Failures, <<"phases">> := Phases} = Bank,
    R = #{<<"id">> => 0, <<"kind">> => <<"actor">>, <<"width">> => 56+Width,
        <<"reduction">> => Reduction, <<"failures">> => Failures, <<"phases">> => Phases},
    [{Code, _} | _] = [{binary_to_integer(C), O} || {C, O = #{<<"kind">> := <<"badarith">>}} <- maps:to_list(Failures)],
    Pack = fun(Values) -> maps:fold(fun(K, V, Acc) ->
        #{<<"observation_offset">> := Offset} = maps:get(K, Fields), Acc bor (V bsl Offset)
    end, 0, Values) end,
    Decode = fun(Initialized, Values) ->
        Value = Initialized bor Pack(Values),
        hls_topology_debug:decode_observation(<<0:32/little, 99:64/little, Value:128/little>>, R)
    end,
    Open = #{<<"status">> => 1, <<"site">> => 0, <<"key">> => 16#fedcba98,
        <<"remaining">> => 1, <<"failure">> => Code},
    ?assertMatch({ok, #{failed := false, reduction := #{status := open, name := <<"sum">>,
        phase := <<"gathering">>, key := 16#fedcba98, population := {count, 3},
        remaining := 1, received := 2, failure := #{kind := <<"badarith">>}}}}, Decode(1 bsl 25, Open)),
    ?assertMatch({ok, #{reduction := #{failure := none}}}, Decode(1 bsl 25, Open#{<<"failure">> := 0})),
    ?assertMatch({ok, #{reduction := idle}}, Decode(1 bsl 25, #{})),
    ?assertMatch({ok, #{reduction := undefined}}, Decode(0, #{})),
    ?assertMatch({ok, #{reduction := #{status := complete, remaining := 0}}},
        Decode(1 bsl 25, Open#{<<"status">> := 2, <<"remaining">> := 0})),
    lists:foreach(fun(Invalid) ->
        ?assertEqual({error, invalid_reduction_observation}, Decode(1 bsl 25, Invalid))
    end, [Open#{<<"status">> := 3}, Open#{<<"site">> := 1}, Open#{<<"remaining">> := 0},
        Open#{<<"status">> := 2}, Open#{<<"failure">> := 65535}]),
    ?assertEqual({error, invalid_reduction_observation}, Decode(0, Open)).

projection_checks_reduction_layout_and_sites_test() ->
    {Plan, Specs} = hls_actor_debug_dslx:fixture(reduction),
    Projection = #{<<"banks">> := [Bank]} = hls_actor_debug_dslx:projection(reduction),
    #{<<"reduction">> := R = #{<<"fields">> := Fields, <<"sites">> := [Site]}} = Bank,
    Key = maps:get(<<"key">>, Fields),
    lists:foreach(fun(Bad) ->
        ?assertError(actor_projection_mismatch, xls_scheduler_debug:validate(Plan, Specs,
            Projection#{<<"banks">> := [Bank#{<<"reduction">> := Bad}]}))
    end, [R#{<<"fields">> := Fields#{<<"key">> := Key#{<<"offset">> := 0}}},
        R#{<<"sites">> := [Site#{<<"name">> := <<"other_reducer">>}]}, R#{<<"width">> := 54}]).
