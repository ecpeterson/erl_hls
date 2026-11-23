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
