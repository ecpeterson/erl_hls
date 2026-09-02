-module(phi_memory_bridge_tests).

-include_lib("eunit/include/eunit.hrl").

-define(RUNNER_TIMEOUT, 120000).

simulated_rtl_test_() ->
    case os:getenv("ERL_HLS_PHI_SIM_DIR") of
        false ->
            [];
        SimDir ->
            {Mode, Options, Expected, RunnerTimeout, TestTimeout} = fixture(),
            {setup,
                fun() -> start(SimDir, Options, RunnerTimeout) end,
                fun stop/1,
                fun({_Fabric, Runner}) ->
                    {timeout, TestTimeout, ?_test(begin
                        Actual = phi_memory_runner:await(Runner),
                        ok = verify(Mode, Actual),
                        ?assertEqual(Expected, Actual)
                    end)}
                end}
    end.

start(SimDir, Options, RunnerTimeout) ->
    WritePath = filename:join(SimDir, "app_tx"),
    ReadPath = filename:join(SimDir, "app_rx"),
    {ok, Fabric} = hls_fabric:start_link(WritePath, ReadPath),
    {ok, Runner} = phi_memory_runner:start_link(
        Fabric,
        Options,
        RunnerTimeout
    ),
    {Fabric, Runner}.

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

stop({Fabric, Runner}) ->
    stop_if_alive(phi_memory_runner, Runner),
    stop_if_alive(hls_fabric, Fabric).

stop_if_alive(Module, Pid) ->
    case is_process_alive(Pid) of
        true -> Module:stop(Pid);
        false -> ok
    end.
