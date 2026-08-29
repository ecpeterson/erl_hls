-module(regsvc_cpu_tests).

-include_lib("eunit/include/eunit.hrl").

cpu_reference_test_() ->
    target_test_(fun regsvc:start_link/0, fun scenario_/1).

guarded_cast_clause_cpu_test_() ->
    target_test_(
        fun regsvc:start_link/0,
        fun guarded_cast_clause_scenario_/1
    ).

ordered_call_clause_cpu_test_() ->
    target_test_(
        fun regsvc:start_link/0,
        fun ordered_call_clause_scenario_/1
    ).

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
                    {ok, AppFabric} = xls_fabric:start_link(
                        WritePath, ReadPath
                    ),
                    {ok, DebugFabric} = xls_fabric:start_link(
                        DebugWritePath, DebugReadPath
                    ),
                    {ok, PidOne} = xls_gs:start_link(regsvc, [], [
                        {fabric, AppFabric, 1}
                    ]),
                    {ok, PidTwo} = xls_gs:start_link(regsvc, [], [
                        {fabric, AppFabric, 2}
                    ]),
                    {ok, DebugPidOne} = xls_debug:start_link(
                        regsvc, {fabric, DebugFabric, 1}
                    ),
                    {ok, DebugPidTwo} = xls_debug:start_link(
                        regsvc, {fabric, DebugFabric, 2}
                    ),
                    {
                        AppFabric,
                        DebugFabric,
                        PidOne,
                        PidTwo,
                        DebugPidOne,
                        DebugPidTwo
                    }
                end,
                fun({
                    AppFabric,
                    DebugFabric,
                    PidOne,
                    PidTwo,
                    DebugPidOne,
                    DebugPidTwo
                }) ->
                    xls_debug:stop(DebugPidTwo),
                    xls_debug:stop(DebugPidOne),
                    regsvc:stop(PidTwo),
                    regsvc:stop(PidOne),
                    xls_fabric:stop(DebugFabric),
                    xls_fabric:stop(AppFabric)
                end,
                fun({
                    _AppFabric,
                    _DebugFabric,
                    PidOne,
                    PidTwo,
                    DebugPidOne,
                    DebugPidTwo
                }) ->
                    scenario_(PidOne) ++
                        debug_scenario_(PidOne, DebugPidOne) ++
                        routed_pair_scenario_(PidOne, PidTwo) ++
                        routed_debug_scenario_(DebugPidTwo) ++
                        rtl_error_scenario_(PidOne)
                end}
    end.

target_test_(Start, Scenario) ->
    {setup,
        fun() ->
            {ok, Pid} = Start(),
            Pid
        end,
        fun(Pid) ->
            regsvc:stop(Pid)
        end,
        fun(Pid) -> Scenario(Pid) end}.

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

debug_scenario_(Pid, DebugPid) ->
    [
        ?_test(begin
            {ok, Counters} = xls_debug:get_counters(DebugPid),
            ?assertEqual(4, maps:get(version, Counters)),
            ?assert(maps:get(cycles, Counters) > 0),
            ?assertEqual(21, maps:get(app_rx_beats, Counters)),
            ?assertEqual(7, maps:get(app_rx_frames, Counters)),
            ?assertEqual(10, maps:get(app_tx_beats, Counters)),
            ?assertEqual(4, maps:get(app_tx_frames, Counters)),
            ?assertEqual(0, maps:get(app_rx_stall_cycles, Counters)),
            %% Egress polling phase is host/VPI-scheduling dependent here. The
            %% cycle-controlled RTL test checks routed TX stalls while it
            %% deliberately blocks the shared application output.
            ?assert(maps:get(app_tx_stall_cycles, Counters) =< 4)
        end),
        ?_test(begin
            {ok, Trace} = xls_debug:get_trace(DebugPid),
            Events = maps:get(events, Trace),
            ?assertEqual(1, maps:get(version, Trace)),
            ?assertEqual(2, maps:get(record_words, Trace)),
            ?assertEqual(11, maps:get(count, Trace)),
            ?assertEqual(11, length(Events)),
            ?assertEqual(0, maps:get(dropped, Trace)),
            ?assertEqual(0, maps:get(observation_drops, Trace)),
            ?assertEqual([
                {application_rx, 0, 5},
                {application_tx, 0, 7},
                {application_rx, 1, 3},
                {application_rx, 2, 4},
                {application_tx, 2, 8},
                {application_rx, 3, 3},
                {application_rx, 4, 4},
                {application_tx, 4, 8},
                {application_rx, 5, 3},
                {application_rx, 6, 6},
                {application_tx, 6, 9}
            ], [
                {
                    maps:get(kind, Event),
                    maps:get(tx_id, Event),
                    maps:get(op, Event)
                }
                || Event <- Events
            ]),
            ?assert(lists:all(
                fun(Event) -> maps:get(cycle, Event) > 0 end,
                Events
            )),
            Cycles = [maps:get(cycle, Event) || Event <- Events],
            ?assertEqual(Cycles, lists:sort(Cycles))
        end),
        ?_test(begin
            {ok, Trace} = xls_debug:get_trace(DebugPid),
            ?assertEqual(0, maps:get(count, Trace)),
            ?assertEqual(0, maps:get(dropped, Trace)),
            ?assertEqual(0, maps:get(observation_drops, Trace)),
            ?assertEqual([], maps:get(events, Trace))
        end),
        ?_test(begin
            lists:foreach(
                fun(Value) ->
                    ?assertEqual(Value, regsvc:ping(Pid, Value))
                end,
                lists:seq(1, 33)
            ),
            {ok, Trace} = xls_debug:get_trace(DebugPid),
            Events = maps:get(events, Trace),
            ?assertEqual(64, maps:get(count, Trace)),
            ?assertEqual(64, length(Events)),
            ?assertEqual(2, maps:get(dropped, Trace)),
            ?assertEqual(0, maps:get(observation_drops, Trace)),
            ?assertEqual(lists:flatmap(
                fun(TxID) ->
                    [
                        {application_rx, TxID, 5},
                        {application_tx, TxID, 7}
                    ]
                end,
                lists:seq(7, 38)
            ), [
                {
                    maps:get(kind, Event),
                    maps:get(tx_id, Event),
                    maps:get(op, Event)
                }
                || Event <- Events
            ])
        end),
        ?_test(begin
            {ok, Trace} = xls_debug:get_trace(DebugPid),
            ?assertEqual(0, maps:get(count, Trace)),
            ?assertEqual(0, maps:get(dropped, Trace)),
            ?assertEqual(0, maps:get(observation_drops, Trace)),
            ?assertEqual([], maps:get(events, Trace))
        end)
    ].

rtl_error_scenario_(Pid) ->
    [
        ?_test(begin
            ok = regsvc:set(Pid, 16, 16#ffffffff, 0),
            ?assertEqual(3, regsvc:get(Pid, 0))
        end),
        ?_assertEqual([], regsvc:bulk_get(Pid, 16, 0)),
        ?_assertEqual(
            {error, {remote_error, function_clause}},
            gen_server:call(Pid, {bulk_get, 16, 1})
        ),
        ?_assertEqual(
            {error, {remote_error, function_clause}},
            gen_server:call(Pid, {get, 16})
        ),
        ?_assertEqual(
            {error, {remote_error, function_clause}},
            gen_server:call(Pid, {ack, 0})
        ),
        ?_assertEqual(0, regsvc:get(Pid, 0))
    ].

guarded_cast_clause_scenario_(Pid) ->
    [
        ?_test(begin
            ok = regsvc:set(Pid, 16, 16#ffffffff, 0),
            ?assertEqual(0, regsvc:get(Pid, 0))
        end)
    ].

ordered_call_clause_scenario_(Pid) ->
    [
        ?_assertEqual([], regsvc:bulk_get(Pid, 16, 0))
    ].

routed_pair_scenario_(PidOne, PidTwo) ->
    [
        ?_assertEqual(ok, regsvc:set(PidTwo, 0, 16#22, 16#ffffffff)),
        ?_assertEqual(16#22, regsvc:get(PidTwo, 0)),
        ?_assertEqual(3, regsvc:get(PidOne, 0)),
        ?_test(begin
            Parent = self(),
            spawn(fun() ->
                Parent ! {endpoint_one, regsvc:ping(PidOne, 16#11111111)}
            end),
            spawn(fun() ->
                Parent ! {endpoint_two, regsvc:ping(PidTwo, 16#22222222)}
            end),
            ?assertEqual(
                {endpoint_one, 16#11111111},
                receive ReplyOne = {endpoint_one, _} -> ReplyOne end
            ),
            ?assertEqual(
                {endpoint_two, 16#22222222},
                receive ReplyTwo = {endpoint_two, _} -> ReplyTwo end
            )
        end)
    ].

routed_debug_scenario_(DebugPid) ->
    [
        ?_test(begin
            {ok, Counters} = xls_debug:get_counters(DebugPid),
            ?assertEqual(4, maps:get(version, Counters)),
            ?assertEqual(8, maps:get(app_rx_beats, Counters)),
            ?assertEqual(3, maps:get(app_rx_frames, Counters)),
            ?assertEqual(4, maps:get(app_tx_beats, Counters)),
            ?assertEqual(2, maps:get(app_tx_frames, Counters)),
            ?assert(maps:get(app_tx_stall_cycles, Counters) =< 2)
        end)
    ].
