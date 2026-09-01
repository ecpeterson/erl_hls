-module(phi_memory_bridge_tests).

-include_lib("eunit/include/eunit.hrl").

-define(RUNNER_TIMEOUT, 120000).

simulated_rtl_test_() ->
    case os:getenv("ERL_HLS_PHI_SIM_DIR") of
        false ->
            [];
        SimDir ->
            {Options, Expected, RunnerTimeout, TestTimeout} = fixture(),
            {setup,
                fun() -> start(SimDir, Options, RunnerTimeout) end,
                fun stop/1,
                fun({_Fabric, Runner}) ->
                    {timeout, TestTimeout, ?_assertEqual(
                        Expected,
                        phi_memory_runner:await(Runner)
                    )}
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
            #{options := Options, expected := Expected} =
                phi_memory_demo:fixture(),
            {Options, Expected, 600000, 660};
        _ ->
            Options = #{
                distance => 1,
                %% The synthesized actors advance while ERTS installs routes.
                first_quiet_step => 16,
                line_y => 0,
                measurement => z,
                request_id => 16#504849
            },
            {Options, {ok, 0}, ?RUNNER_TIMEOUT, 180}
    end.

stop({Fabric, Runner}) ->
    stop_if_alive(phi_memory_runner, Runner),
    stop_if_alive(hls_fabric, Fabric).

stop_if_alive(Module, Pid) ->
    case is_process_alive(Pid) of
        true -> Module:stop(Pid);
        false -> ok
    end.
