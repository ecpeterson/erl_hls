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

with_source(Test) ->
    Directory = filename:absname(filename:join(["_build", "source-tests",
        integer_to_list(erlang:unique_integer([positive, monotonic]))])),
    Path = filename:join([Directory, "src", "hls_source_context_fixture.erl"]),
    Config = filename:join([Directory, "headers", "config.hrl"]),
    ok = filelib:ensure_dir(Path),
    ok = filelib:ensure_dir(Config),
    {ok, _} = file:copy("test_data/hls_source_context_fixture.erl", Path),
    ok = file:write_file(Config, "-include(\"layout.hrl\").\n"),
    ok = file:write_file(filename:join(filename:dirname(Config), "layout.hrl"),
        "-ifdef(WIDE).\n-define(WORD_TYPE, u64).\n-else.\n"
        "-define(WORD_TYPE, u32).\n-endif.\n"),
    try Test(Path, Directory)
    after
        _ = code:purge(?MODULE_UNDER_TEST),
        _ = code:delete(?MODULE_UNDER_TEST),
        _ = code:purge(?MODULE_UNDER_TEST),
        ok = file:del_dir_r(Directory)
    end.
