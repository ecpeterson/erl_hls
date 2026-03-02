-module(demo).
-export([main/1]).

main(Module) ->
    {ok, PID} = Module:start_link(),
    fp64_fmac:reset(PID),
    lists:foreach(
        fun({A, B}) ->
            Acc = fp64_fmac:fmac(PID, A, B),
            io:format("~p, ~p -> ~p~n", [A, B, Acc])
        end,
        [{1.0, 2.0}, {2.0, 3.0}, {3.0, 4.0}]
    ),
    Module:stop(PID).
