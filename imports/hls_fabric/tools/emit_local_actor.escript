#!/usr/bin/env escript
%%! +S 2:2
-mode(compile).

%% Only source options enter the compiler; no saved artifact or callback subset is accepted.
-spec main([string()]) -> ok.
main([Source, OptionsFile, Output]) ->
    {ok, [Options]} = file:consult(OptionsFile),
    Summary = hls_local_actor:write(Source, Options, Output),
    io:format("~s~n", [json:encode(maps:without([source_plan], Summary))]);
main(_) ->
    io:format(standard_error, "Usage: emit_local_actor.escript SOURCE OPTIONS FRESH_OUTPUT.x~n", []),
    halt(2).
