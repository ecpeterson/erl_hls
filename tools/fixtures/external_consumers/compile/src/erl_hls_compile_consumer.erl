-module(erl_hls_compile_consumer).
-moduledoc "Exercises the installed compiler release without starting deployed execution.".

-export([witness/0]).

-doc "Emits one portable actor bundle and proves that no runtime service was started.".
-spec witness() -> ok.
witness() ->
    false = started(hls_runtime),
    undefined = whereis(hls_runtime_sup),
    false = code:is_loaded(hls_runtime_app),
    Output = filename:absname("external-compile-output"),
    ok = remove(Output),
    try
        Manifest = hls_compile:actor("src/erl_hls_compile_actor.erl", #{}, Output),
        actor = maps:get(kind, maps:get(metadata, Manifest)),
        true = filelib:is_regular(filename:join(Output, "source-build.json")),
        false = started(hls_runtime),
        undefined = whereis(hls_runtime_sup),
        false = code:is_loaded(hls_runtime_app),
        ok
    after
        ok = remove(Output)
    end.

%% Application presence on the code path is not application startup.
-spec started(atom()) -> boolean().
started(Application) ->
    lists:keymember(Application, 1, application:which_applications()).

%% Keep the witness repeatable after either a prior success or interrupted run.
-spec remove(file:filename()) -> ok.
remove(Path) ->
    case file:del_dir_r(Path) of
        ok -> ok;
        {error, enoent} -> ok
    end.
