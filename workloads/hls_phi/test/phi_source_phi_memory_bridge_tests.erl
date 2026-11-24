-module(phi_source_phi_memory_bridge_tests).

-include_lib("eunit/include/eunit.hrl").

-define(DEBUG_TIMEOUT, 600000).
-define(SMOKE_CUTOFF_STEP, 16).
-define(SMOKE_RUNNER_TIMEOUT, 30000).
-define(SMOKE_TEST_TIMEOUT, 60).

%% Attach to caller-prepared simulator FIFOs only when its stage is explicitly selected.
-spec simulated_rtl_test_() -> [] | {setup, fun(() -> {pid(), pid() | undefined, pid() | undefined, pid()}), fun(({pid(), pid() | undefined, pid() | undefined, pid()}) -> ok), fun(({pid(), pid() | undefined, pid() | undefined, pid()}) -> {timeout, pos_integer(), {pos_integer(), fun(() -> ok)}})}.
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

%% Start independent application/debug brokers and the bounded experiment runner.
-spec start(file:filename(), phi_memory_experiment:options(), pos_integer()) -> {pid(), pid() | undefined, pid() | undefined, pid()}.
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

%% Omit debug attachment only when explicitly disabled by the witness environment.
-spec start_debug(file:filename()) -> {pid(), pid()} | {undefined, undefined}.
start_debug(SimDir) ->
    case os:getenv("ERL_HLS_PHI_DEBUG") of
        "0" ->
            {undefined, undefined};
        _ ->
            start_debug_fabric(SimDir)
    end.

%% Attach the framed debug client to the prepared gateway endpoints.
-spec start_debug_fabric(file:filename()) -> {pid(), pid()}.
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

%% Select the retained D3 CPU oracle or the bounded noise-free one-cell smoke fixture.
-spec fixture() -> {smoke | demo, phi_memory_experiment:options(), {ok, phi_memory_experiment:witness()} | {error, term()}, pos_integer(), pos_integer()}.
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

%% Load the explicitly selected CPU witness envelope, rejecting missing or invalid input.
-spec cpu_witness() -> {demo, phi_memory_experiment:options(), {ok, phi_memory_experiment:witness()} | {error, term()}, pos_integer(), pos_integer()}.
cpu_witness() ->
    Path = case os:getenv("ERL_HLS_PHI_CPU_WITNESS") of
        false -> error(missing_cpu_witness);
        Value -> Value
    end,
    {ok, [Envelope]} = file:consult(Path),
    {ok, Options, Expected} =
        phi_memory_demo:decode_witness_envelope(Envelope),
    {demo, Options, Expected, 600000, 660}.

%% Check the selected oracle; a smoke run must report no anticommuting data cells.
-spec verify(smoke | demo, {ok, phi_memory_experiment:witness()} | {error, term()}) -> ok.
verify(demo, Actual) ->
    phi_memory_demo:verify(Actual);
verify(smoke, {ok, #{data_anticommutations := DataAnticommutations}}) ->
    case [Coordinate || {Coordinate, 1} <- DataAnticommutations] of
        [] -> ok;
        Anticommuting -> error({anticommuting_smoke, Anticommuting})
    end;
verify(smoke, Result) ->
    error({smoke_result, Result}).

%% Inspect the gateway only when debug attachment was enabled.
-spec maybe_verify_debug(pid() | undefined, phi_memory_experiment:options()) -> ok.
maybe_verify_debug(undefined, _Options) ->
    ok;
maybe_verify_debug(Client, #{distance := Distance}) ->
    Debug = {boundary, Client, {phi_memory_gateway, host_stream}},
    verify_debug(Debug, phi_memory_boundary:contract(Distance)).

%% Require active gateway traffic and lossless trace records at the same observation scope.
-spec verify_debug({boundary, pid(), {phi_memory_gateway, host_stream}}, map()) -> ok.
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

%% Require each retained frame trace to use a declared boundary route and selector.
-spec verify_trace_headers([map()], map()) -> ok.
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

%% Retain the selected counters and trace summary only at an explicit output path.
-spec maybe_write_debug_metrics(map(), map()) -> ok | {error, file:posix()}.
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

%% Retire clients before their brokers after the simulation witness.
-spec stop({pid(), pid() | undefined, pid() | undefined, pid()}) -> ok.
stop({AppFabric, DebugFabric, Debug, Runner}) ->
    stop_if_alive(hls_debug, Debug),
    stop_if_alive(phi_memory_runner, Runner),
    stop_if_alive(hls_fabric, DebugFabric),
    stop_if_alive(hls_fabric, AppFabric).

%% Skip disabled or terminated processes during witness cleanup.
-spec stop_if_alive(module(), pid() | undefined) -> ok.
stop_if_alive(_Module, undefined) ->
    ok;
stop_if_alive(Module, Pid) ->
    case is_process_alive(Pid) of
        true -> Module:stop(Pid);
        false -> ok
    end.
