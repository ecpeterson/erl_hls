-module(regsvc_cpu_tests).

-include_lib("eunit/include/eunit.hrl").

%% TODO: Parameterize this scenario over CPU and simulated-PL setup once an
%% Erlang-to-Icarus bridge is available.
cpu_reference_test_() ->
    {setup,
        fun() ->
            {ok, Pid} = regsvc:start_link(),
            Pid
        end,
        fun(Pid) ->
            regsvc:stop(Pid)
        end,
        fun(Pid) ->
            [
                ?_assertEqual(16#12345678, regsvc:ping(Pid, 16#12345678)),
                ?_assertEqual(ok, regsvc:set(Pid, 0, 2, 16#ffffffff)),
                ?_assertEqual(2, regsvc:get(Pid, 0)),
                ?_assertEqual(ok, regsvc:set(Pid, 0, 1, 1)),
                ?_assertEqual(3, regsvc:get(Pid, 0)),
                ?_assertEqual(ok, regsvc:set(Pid, 1, 4, 16#ffffffff)),
                ?_assertEqual([3, 4, 0], regsvc:bulk_get(Pid, 0, 3))
            ]
        end}.
