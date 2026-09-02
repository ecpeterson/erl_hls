-module(phi_memory_bridge_tests).

-include_lib("eunit/include/eunit.hrl").

-define(RUNNER_TIMEOUT, 120000).
-define(DEBUG_TIMEOUT, 120000).

simulated_rtl_test_() ->
    case os:getenv("ERL_HLS_PHI_SIM_DIR") of
        false ->
            [];
        SimDir ->
            {Mode, Options, Expected, RunnerTimeout, TestTimeout} = fixture(),
            {setup,
                fun() -> start(SimDir, Options, RunnerTimeout) end,
                fun stop/1,
                fun({_AppFabric, _DebugFabric, Debug, Runner}) ->
                    {timeout, TestTimeout, ?_test(begin
                        Actual = phi_memory_runner:await(Runner),
                        ok = verify(Mode, Actual),
                        ?assertEqual(Expected, Actual),
                        ok = maybe_verify_debug(Debug)
                    end)}
                end}
    end.

start(SimDir, Options, RunnerTimeout) ->
    WritePath = filename:join(SimDir, "app_tx"),
    ReadPath = filename:join(SimDir, "app_rx"),
    {ok, AppFabric} = hls_fabric:start_link(WritePath, ReadPath),
    {DebugFabric, Debug} = start_debug(SimDir),
    {ok, Runner} = phi_memory_runner:start_link(
        AppFabric,
        Options,
        RunnerTimeout
    ),
    {AppFabric, DebugFabric, Debug, Runner}.

start_debug(SimDir) ->
    case os:getenv("ERL_HLS_PHI_DEBUG") of
        "0" ->
            {undefined, undefined};
        _ ->
            start_debug_fabric(SimDir)
    end.

start_debug_fabric(SimDir) ->
    DebugWritePath = filename:join(SimDir, "debug_tx"),
    DebugReadPath = filename:join(SimDir, "debug_rx"),
    {ok, DebugFabric} = hls_fabric:start_link(
        DebugWritePath, DebugReadPath
    ),
    {ok, Debug} = hls_debug:start_link(
        phi_memory_gateway, {fabric, DebugFabric, 1}
    ),
    {DebugFabric, Debug}.

fixture() ->
    case os:getenv("ERL_HLS_PHI_DEMO") of
        "d3" ->
            cpu_witness();
        _ ->
            Options = #{
                distance => 1,
                %% The synthesized actors advance while ERTS installs routes.
                first_quiet_step => 16,
                line_y => 0,
                measurement => z,
                request_id => 16#504849
            },
            Expected = {ok, #{
                closeout_step => 16,
                corrections => [],
                measurement => z,
                data_anticommutations => [{{0, 0}, 0}, {{0, 1}, 0}],
                row => #{y => 0, parity => 0}
            }},
            {smoke, Options, Expected, ?RUNNER_TIMEOUT, 180}
    end.

cpu_witness() ->
    Path = case os:getenv("ERL_HLS_PHI_CPU_WITNESS") of
        false -> error(missing_cpu_witness);
        Value -> Value
    end,
    {ok, [Envelope]} = file:consult(Path),
    {ok, Options, Expected} =
        phi_memory_demo:decode_witness_envelope(Envelope),
    {demo, Options, Expected, 600000, 660}.

verify(demo, Actual) ->
    phi_memory_demo:verify(Actual);
verify(smoke, {ok, #{data_anticommutations := DataAnticommutations}}) ->
    case [Coordinate || {Coordinate, 1} <- DataAnticommutations] of
        [] -> ok;
        Anticommuting -> error({anticommuting_smoke, Anticommuting})
    end;
verify(smoke, Result) ->
    error({smoke_result, Result}).

maybe_verify_debug(undefined) ->
    ok;
maybe_verify_debug(Debug) ->
    verify_debug(Debug).

verify_debug(Debug) ->
    {ok, Counters} = hls_debug:get_counters(Debug, ?DEBUG_TIMEOUT),
    ?assertEqual(4, maps:get(version, Counters)),
    ?assert(maps:get(cycles, Counters) > 0),
    ?assert(maps:get(app_rx_beats, Counters) > 0),
    ?assert(maps:get(app_rx_frames, Counters) > 0),
    ?assert(maps:get(app_tx_beats, Counters) > 0),
    ?assert(maps:get(app_tx_frames, Counters) > 0),
    {ok, Trace} = hls_debug:get_trace(Debug, ?DEBUG_TIMEOUT),
    ?assertEqual(1, maps:get(version, Trace)),
    ?assertEqual(2, maps:get(record_words, Trace)),
    ?assertEqual(0, maps:get(observation_drops, Trace)),
    ?assert(maps:get(count, Trace) > 0),
    ?assert(lists:any(
        fun(#{kind := Kind}) -> Kind =:= application_rx end,
        maps:get(events, Trace)
    )),
    ?assert(lists:any(
        fun(#{kind := Kind}) -> Kind =:= application_tx end,
        maps:get(events, Trace)
    )),
    ok.

stop({AppFabric, DebugFabric, Debug, Runner}) ->
    stop_if_alive(hls_debug, Debug),
    stop_if_alive(phi_memory_runner, Runner),
    stop_if_alive(hls_fabric, DebugFabric),
    stop_if_alive(hls_fabric, AppFabric).

stop_if_alive(_Module, undefined) ->
    ok;
stop_if_alive(Module, Pid) ->
    case is_process_alive(Pid) of
        true -> Module:stop(Pid);
        false -> ok
    end.
