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
            target_test_(fun() ->
                xls_gs:start_link(regsvc, [], [
                    {transport, WritePath, ReadPath}
                ])
            end)
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
