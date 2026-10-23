#!/usr/bin/env escript
%%! +S 2:2
-mode(compile).
%% Source compilation binds the native bridge and complementary BEAM actors together.
-spec main([string()]) -> ok.
main([Config,Output]) ->
    {ok,[Settings]}=file:consult(Config),
    #{actors:=Actors}=hls_protocol_mixed:write(Settings,Output),
    io:format("MIXED_EMITTED ~p BEAM actors; application admission pending~n",[map_size(Actors)]);
main(_) -> io:format(standard_error,"Usage: emit_protocol_mixed.escript CONFIG FRESH_OUTPUT~n",[]),halt(2).
