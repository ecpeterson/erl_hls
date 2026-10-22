#!/usr/bin/env escript
%%! +S 2:2
-mode(compile).
%% Fresh source compilation and checked boundary rejection precede network emission.
-spec main([string()]) -> ok.
main([Config,Output]) ->
    {ok,[Settings]}=file:consult(Config),
    #{actors:=Actors,links:=Links}=hls_protocol_network:write(Settings,Output),
    io:format("NETWORK_EMITTED ~p actors ~p links; application admission pending~n",[Actors,Links]);
main(_) -> io:format(standard_error,"Usage: emit_protocol_network.escript CONFIG FRESH_OUTPUT~n",[]),halt(2).
