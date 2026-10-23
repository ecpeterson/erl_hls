#!/usr/bin/env escript
%%! +S 2:2
-mode(compile).
%% Trusted config sources are freshly compiled before host/hardware bindings are emitted.
-spec main([string()]) -> ok.
main([Config,Output]) ->
    {ok,[Settings]}=file:consult(Config),
    #{devices:=Devices}=hls_protocol_application:write(Settings,Output),
    io:format("APPLICATION_EMITTED ~p devices; capacity/progress admission pending~n",[map_size(Devices)]);
main(_) -> io:format(standard_error,"Usage: emit_protocol_application.escript CONFIG FRESH_OUTPUT~n",[]),halt(2).
