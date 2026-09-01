-module(phi_memory_bridge_tests).

-include_lib("eunit/include/eunit.hrl").

-define(RUNNER_TIMEOUT, 120000).

simulated_rtl_test_() ->
    case os:getenv("ERL_HLS_PHI_SIM_DIR") of
        false ->
            [];
        SimDir ->
            {setup,
                fun() -> start(SimDir) end,
                fun stop/1,
                fun({_Fabric, Runner}) ->
                    {timeout, 180, ?_assertEqual(
                        {ok, 0},
                        phi_memory_runner:await(Runner)
                    )}
                end}
    end.

start(SimDir) ->
    WritePath = filename:join(SimDir, "app_tx"),
    ReadPath = filename:join(SimDir, "app_rx"),
    {ok, Fabric} = hls_fabric:start_link(WritePath, ReadPath),
    Options = #{
        distance => 1,
        %% The synthesized actors are already advancing while the host route
        %% is installed. Arm a future round, as the cutoff protocol requires.
        first_quiet_step => 16,
        line_y => 0,
        measurement => z,
        request_id => 16#504849
    },
    {ok, Runner} = phi_memory_runner:start_link(
        Fabric,
        Options,
        ?RUNNER_TIMEOUT
    ),
    {Fabric, Runner}.

stop({Fabric, Runner}) ->
    stop_if_alive(phi_memory_runner, Runner),
    stop_if_alive(hls_fabric, Fabric).

stop_if_alive(Module, Pid) ->
    case is_process_alive(Pid) of
        true -> Module:stop(Pid);
        false -> ok
    end.
