#!/usr/bin/env escript
%%! +S 2:2
-mode(compile).
%% Fresh source compilation binds external declarations before boundary generation.
-spec main([string()]) -> ok.
main([Config,Output]) ->
    {ok,[Settings]}=file:consult(Config),
    #{actors:=Actors,externals:=Externals}=hls_protocol_bridge:write(Settings,Output),
    io:format("BRIDGE_EMITTED ~p actors ~p endpoints; application admission pending~n",[Actors,length(Externals)]);
main(_) -> io:format(standard_error,"Usage: emit_protocol_bridge.escript CONFIG FRESH_OUTPUT~n",[]),halt(2).
