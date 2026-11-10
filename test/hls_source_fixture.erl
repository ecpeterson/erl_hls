-module(hls_source_fixture).
-export([options/1, compile_actor/2, with_source/1]).

-define(MODULE_UNDER_TEST, hls_source_context_fixture).

options(Directory) ->
    [{i, filename:join(Directory, "headers")}, {d, 'INITIAL', 7}].

compile_actor(Path, Options) ->
    _ = code:purge(?MODULE_UNDER_TEST),
    _ = code:delete(?MODULE_UNDER_TEST),
    {ok, ?MODULE_UNDER_TEST, Binary} = compile:noenv_file(Path,
        [binary, debug_info, report_errors | Options]),
    {module, ?MODULE_UNDER_TEST} = code:load_binary(?MODULE_UNDER_TEST, Path, Binary).

-doc "Runs a serial source-context test in an isolated scratch tree; working directory and code path are VM-global. Restores the working directory and code path, unloads the fixture and removes its tree on normal return or exception. Interrupted VMs leave unique trees that cannot collide with later runs.".
-spec with_source(fun((file:filename(), file:filename()) -> Result)) -> Result.
with_source(Test) ->
    {ok, Cwd} = file:get_cwd(),
    Paths = code:get_path(),
    true = code:set_path([filename:absname(Path) || Path <- Paths]),
    Root = filename:absname(filename:join(["_build", "source-tests",
        binary_to_list(binary:encode_hex(crypto:strong_rand_bytes(12), lowercase))])),
    Directory = filename:join(Root, "source"),
    Path = filename:join([Directory, "src", "hls_source_context_fixture.erl"]),
    Config = filename:join([Directory, "headers", "config.hrl"]),
    try
        ok = filelib:ensure_dir(Path),
        ok = filelib:ensure_dir(Config),
        {ok, _} = file:copy("test_data/hls_source_context_fixture.erl", Path),
        ok = file:write_file(Config, "-include(\"layout.hrl\").\n"),
        ok = file:write_file(filename:join(filename:dirname(Config), "layout.hrl"),
            "-ifdef(WIDE).\n-define(WORD_TYPE, u64).\n-else.\n"
            "-define(WORD_TYPE, u32).\n-endif.\n"),
        Test(Path, Directory)
    after
        ok = file:set_cwd(Cwd),
        true = code:set_path(Paths),
        _ = code:purge(?MODULE_UNDER_TEST),
        _ = code:delete(?MODULE_UNDER_TEST),
        _ = code:purge(?MODULE_UNDER_TEST),
        _ = file:del_dir_r(Root)
    end.
