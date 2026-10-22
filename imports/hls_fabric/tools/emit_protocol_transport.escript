#!/usr/bin/env escript
%%! +S 2:2
-mode(compile).
%% Explicit trusted build configuration supplies current sources and a topology constructor.
-spec main([string()]) -> ok.
main([Config, Output]) ->
    {ok, [Settings]} = file:consult(Config),
    #{fabric := #{sources := Sources, links := Links}} = hls_protocol_transport:write(Settings, Output),
    io:format("TRANSPORT_EMITTED ~p actors ~p links; application admission pending~n", [length(Sources), length(Links)]);
main(_) -> io:format(standard_error, "Usage: emit_protocol_transport.escript CONFIG FRESH_OUTPUT~n", []), halt(2).
