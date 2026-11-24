-module(phi_memory_bridge_tests).

-include_lib("eunit/include/eunit.hrl").

-define(DEBUG_TIMEOUT, 600000).
-define(SMOKE_CUTOFF_STEP, 16).
-define(SMOKE_RUNNER_TIMEOUT, 30000).
-define(SMOKE_TEST_TIMEOUT, 60).

%% Checks simulated rtl.
-spec simulated_rtl_test_() -> [] | {setup, fun(() -> tuple()), fun((tuple()) -> ok), fun((tuple()) -> tuple())}.
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
                        ok = maybe_verify_debug(Debug, Options)
                    end)}
                end}
    end.

%% Starts the fixture's host clients against the selected transport.
-spec start(string(),term(),30000 | 600000) -> {term(),term(),term(),term()}.
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

%% Starts a routed debug client on the fixture's existing transport.
-spec start_debug(string()) -> {term(),term()}.
start_debug(SimDir) ->
    case os:getenv("ERL_HLS_PHI_DEBUG") of
        "0" ->
            {undefined, undefined};
        _ ->
            start_debug_fabric(SimDir)
    end.

%% Opens the fixture's debug stream through a dedicated broker.
-spec start_debug_fabric(string()) -> {term(),term()}.
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

%% Builds the selected test topology and its matching execution profile.
-spec fixture() -> {'demo',term(),term(),600000,660} | {'smoke',map(),{'ok',map()},30000,60}.
fixture() ->
    case os:getenv("ERL_HLS_PHI_DEMO") of
        "d3" ->
            cpu_witness();
        _ ->
            Options = #{
                distance => 1,
                %% The reset-released topology can buffer several rounds
                %% before this ingress arrives. Keep the cutoff beyond that
                %% bounded startup lead.
                first_quiet_step => ?SMOKE_CUTOFF_STEP,
                line_y => 0,
                measurement => z,
                request_id => 16#504849
            },
            Expected = {ok, #{
                closeout_step => ?SMOKE_CUTOFF_STEP,
                corrections => [],
                measurement => z,
                data_anticommutations => [{{0, 0}, 0}, {{0, 1}, 0}],
                row => #{y => 0, parity => 0}
            }},
            {smoke, Options, Expected,
                ?SMOKE_RUNNER_TIMEOUT, ?SMOKE_TEST_TIMEOUT}
    end.

%% Runs the native memory experiment to obtain expected correction and measurement results.
-spec cpu_witness() -> {'demo',term(),term(),600000,660}.
cpu_witness() ->
    Path = case os:getenv("ERL_HLS_PHI_CPU_WITNESS") of
        false -> error(missing_cpu_witness);
        Value -> Value
    end,
    {ok, [Envelope]} = file:consult(Path),
    {ok, Options, Expected} =
        phi_memory_demo:decode_witness_envelope(Envelope),
    {demo, Options, Expected, 600000, 660}.

%% Compares the hardware experiment result with the native witness.
-spec verify(demo | smoke, {ok, phi_memory_experiment:witness()} | {error, term()}) -> ok | {error, term()}.
verify(demo, Actual) ->
    phi_memory_demo:verify(Actual);
verify(smoke, {ok, #{data_anticommutations := DataAnticommutations}}) ->
    case [Coordinate || {Coordinate, 1} <- DataAnticommutations] of
        [] -> ok;
        Anticommuting -> error({anticommuting_smoke, Anticommuting})
    end;
verify(smoke, Result) ->
    error({smoke_result, Result}).

%% Checks debug evidence when the fixture exposes a debug transport.
-spec maybe_verify_debug(term(),term()) -> 'ok'.
maybe_verify_debug(undefined, _Options) ->
    ok;
maybe_verify_debug(Client, #{distance := Distance}) ->
    Debug = {boundary, Client, {phi_memory_gateway, host_stream}},
    verify_debug(Debug, phi_memory_boundary:contract(Distance)).

%% Requires populated counters and correctly framed trace responses.
-spec verify_debug({'boundary',term(),{'phi_memory_gateway','host_stream'}},map()) -> 'ok'.
verify_debug(Debug, Contract) ->
    {scope, Scope} = hls_debug:info(Debug, scope),
    {ok, Counters} = hls_debug:get_counters(Debug, ?DEBUG_TIMEOUT),
    ?assertEqual(Scope, maps:get(scope, Counters)),
    io:format("PHI_DEBUG_COUNTERS: ~p~n", [Counters]),
    ?assertEqual(5, maps:get(version, Counters)),
    ?assert(maps:get(cycles, Counters) > 0),
    ?assert(maps:get(app_rx_beats, Counters) > 0),
    ?assert(maps:get(app_rx_frames, Counters) > 0),
    ?assert(maps:get(app_tx_beats, Counters) > 0),
    ?assert(maps:get(app_tx_frames, Counters) > 0),
    {ok, Trace} = hls_debug:get_trace(Debug, ?DEBUG_TIMEOUT),
    ?assertEqual(Scope, maps:get(scope, Trace)),
    ?assertEqual(2, maps:get(version, Trace)),
    ?assertEqual(3, maps:get(record_words, Trace)),
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
    ok = verify_trace_headers(maps:get(events, Trace), Contract),
    ok = maybe_write_debug_metrics(Counters, Trace),
    ok.

%% Checks the observed request and response header identities.
-spec verify_trace_headers([any()],map()) -> 'ok'.
verify_trace_headers(Events, Contract = #{
    host_endpoint := Host,
    ingress := #{targets := Targets},
    outputs := Outputs
}) ->
    ControlRoute = phi_memory_wire:control_route(Contract),
    Allowed = [
        {application_rx, ControlRoute, Selector}
        || #{schemas := Schemas} <- Targets,
           #{selector := Selector} <- Schemas
    ] ++ [
        {application_tx, {Endpoint, Host}, Selector}
        || #{endpoint := Endpoint, schemas := Schemas} <- Outputs,
           #{selector := Selector} <- Schemas
    ],
    lists:foreach(fun(#{kind := Kind, route := Route, op := Op,
                       tx_id := TxID, observation_gap := Gap}) ->
        ?assert(lists:member({Kind, Route, Op}, Allowed)),
        ?assertEqual(0, TxID),
        ?assertEqual(false, Gap)
    end, Events).

%% Retains debug metrics when an output directory is configured.
-spec maybe_write_debug_metrics(term(),map()) -> 'ok' | {'error',atom()}.
maybe_write_debug_metrics(Counters, Trace) ->
    case os:getenv("ERL_HLS_PHI_DEBUG_METRICS") of
        false ->
            ok;
        Path ->
            TraceSummary = maps:with(
                [version, count, dropped, observation_drops, events],
                Trace
            ),
            Metrics = #{counters => Counters, trace => TraceSummary},
            file:write_file(Path, io_lib:format("~p.~n", [Metrics]))
    end.

%% Closes fixture clients and transport processes after verification.
-spec stop({'undefined' | pid(),'undefined' | pid(),'undefined' | pid(),'undefined' | pid()}) -> any().
stop({AppFabric, DebugFabric, Debug, Runner}) ->
    stop_if_alive(hls_debug, Debug),
    stop_if_alive(phi_memory_runner, Runner),
    stop_if_alive(hls_fabric, DebugFabric),
    stop_if_alive(hls_fabric, AppFabric).

%% Closes a surviving fixture process with the supplied stop function.
-spec stop_if_alive('hls_debug' | 'hls_fabric' | 'phi_memory_runner','undefined' | pid()) -> any().
stop_if_alive(_Module, undefined) ->
    ok;
stop_if_alive(Module, Pid) ->
    case is_process_alive(Pid) of
        true -> Module:stop(Pid);
        false -> ok
    end.
