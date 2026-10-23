#!/usr/bin/env escript
%%! +S 2:2
-mode(compile).
%% Fresh compilation derives all role boundaries and source-bound application codecs.
-spec main([string()]) -> ok.
main([Config,Output]) ->
    {ok,[Settings]}=file:consult(Config),
    #{devices:=Devices}=hls_protocol_deployment:write(Settings,Output),
    io:format("DEPLOYMENT_EMITTED ~p devices; application admission pending~n",[map_size(Devices)]);
main(_) -> io:format(standard_error,"Usage: emit_protocol_deployment.escript CONFIG FRESH_OUTPUT~n",[]),halt(2).
