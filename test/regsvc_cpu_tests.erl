-module(regsvc_cpu_tests).

-include_lib("eunit/include/eunit.hrl").

cpu_reference_test_() ->
    target_test_(fun regsvc:start_link/0).

simulated_rtl_test_() ->
    case os:getenv("ERL_XLS_SIM_DIR") of
        false ->
            [];
        SimDir ->
            WritePath = filename:join(SimDir, "app_tx"),
            ReadPath = filename:join(SimDir, "app_rx"),
            DebugWritePath = filename:join(SimDir, "debug_tx"),
            DebugReadPath = filename:join(SimDir, "debug_rx"),
            {setup,
                fun() ->
                    {ok, Pid} = xls_gs:start_link(regsvc, [], [
                        {transport, WritePath, ReadPath}
                    ]),
                    {ok, DebugPid} = xls_debug:start_link(
                        regsvc, DebugWritePath, DebugReadPath
                    ),
                    {Pid, DebugPid}
                end,
                fun({Pid, DebugPid}) ->
                    xls_debug:stop(DebugPid),
                    regsvc:stop(Pid)
                end,
                fun({Pid, DebugPid}) ->
                    scenario_(Pid) ++ debug_scenario_(DebugPid)
                end}
    end.

target_test_(Start) ->
    {setup,
        fun() ->
            {ok, Pid} = Start(),
            Pid
        end,
        fun(Pid) ->
            regsvc:stop(Pid)
        end,
        fun(Pid) -> scenario_(Pid) end}.

scenario_(Pid) ->
    [
        ?_assertEqual(16#12345678, regsvc:ping(Pid, 16#12345678)),
        ?_assertEqual(ok, regsvc:set(Pid, 0, 2, 16#ffffffff)),
        ?_assertEqual(2, regsvc:get(Pid, 0)),
        ?_assertEqual(ok, regsvc:set(Pid, 0, 1, 1)),
        ?_assertEqual(3, regsvc:get(Pid, 0)),
        ?_assertEqual(ok, regsvc:set(Pid, 1, 4, 16#ffffffff)),
        ?_assertEqual([3, 4, 0], regsvc:bulk_get(Pid, 0, 3))
    ].

debug_scenario_(DebugPid) ->
    [
        ?_test(begin
            {ok, Counters} = xls_debug:get_counters(DebugPid),
            ?assertEqual(2, maps:get(version, Counters)),
            ?assert(maps:get(cycles, Counters) > 0),
            ?assertEqual(21, maps:get(app_rx_beats, Counters)),
            ?assertEqual(7, maps:get(app_rx_frames, Counters)),
            ?assertEqual(10, maps:get(app_tx_beats, Counters)),
            ?assertEqual(4, maps:get(app_tx_frames, Counters)),
            ?assertEqual(0, maps:get(app_rx_stall_cycles, Counters)),
            ?assertEqual(0, maps:get(app_tx_stall_cycles, Counters))
        end),
        ?_test(begin
            {ok, {state, Registers}} = xls_debug:get_state(DebugPid),
            ?assertEqual([3, 4 | lists:duplicate(14, 0)], Registers)
        end)
    ].
