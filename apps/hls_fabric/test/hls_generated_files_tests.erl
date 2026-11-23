-module(hls_generated_files_tests).
-moduledoc "Checks generated file composition, explicit output boundaries and trusted term configuration without compiling source or invoking external tools.".
-include_lib("eunit/include/eunit.hrl").

%% Composing child trees preserves bytes and rejects collisions, including equal content.
-spec composition_test() -> ok.
composition_test() ->
    Actor = #{"actor.x" => [<<"pub ">>, "fn tick() {}\n"]},
    Files = hls_generated_files:merge([hls_generated_files:prefix("actors", Actor),
        #{"manifest.json" => <<"{}">>}]),
    ?assertEqual([<<"pub ">>, "fn tick() {}\n"], maps:get("actors/actor.x", Files)),
    ?assertEqual(<<"{}">>, maps:get("manifest.json", Files)),
    ?assertError({duplicate_generated_path, "actor.x"}, hls_generated_files:merge([Actor, Actor])),
    ?assertError({invalid_generated_path, "../actors"}, hls_generated_files:prefix("../actors", Actor)),
    ?assertError({invalid_generated_path, "./actor.x"},
        hls_generated_files:merge([#{"./actor.x" => <<>>}])),
    ok.

%% Hashes bind logical bytes regardless of how generators assemble their iodata.
-spec byte_hash_test() -> ok.
byte_hash_test() ->
    Expected = <<"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad">>,
    ?assertEqual(Expected, hls_generated_files:hash(<<"abc">>)),
    ?assertEqual(Expected, hls_generated_files:hash(["a", [<<"b">>, $c]])),
    ok.

%% A fresh root receives all nested files and returns the retained descriptor unchanged.
-spec fresh_output_test() -> ok.
fresh_output_test() ->
    Root = fresh("output"), Directory = filename:join(Root, "generated"),
    Result = #{identity => <<1, 2>>, plan => checked},
    Output = #{result => Result, files => #{"actors/a.x" => ["first", <<"\n">>],
        "manifest.json" => <<"{}">>}},
    ?assertEqual(false, filelib:is_dir(Directory)),
    ?assertEqual(Result, hls_generated_files:write(Output, Directory)),
    ?assertEqual({ok, <<"first\n">>}, file:read_file(filename:join(Directory, "actors/a.x"))),
    ?assertEqual({ok, <<"{}">>}, file:read_file(filename:join(Directory, "manifest.json"))),
    ?assertError({generated_output_exists, Directory}, hls_generated_files:write(Output, Directory)),
    ?assertEqual({ok, <<"first\n">>}, file:read_file(filename:join(Directory, "actors/a.x"))),
    ok.

%% Existing directories accept additional files but existing bytes cannot be replaced.
-spec existing_output_test() -> ok.
existing_output_test() ->
    Root = fresh("existing"), Path = filename:join(Root, "nested/a.x"),
    ?assertEqual(written, hls_generated_files:write_into(
        #{result => written, files => #{"nested/a.x" => <<"original">>}}, Root)),
    ?assertError({badmatch, {error, eexist}}, hls_generated_files:write_into(
        #{result => replaced, files => #{"nested/a.x" => <<"replacement">>}}, Root)),
    ?assertEqual({ok, <<"original">>}, file:read_file(Path)),
    Absent = filename:join(Root, "absent"),
    ?assertEqual(nothing, hls_generated_files:write_into(#{result => nothing, files => #{}}, Absent)),
    ?assertEqual(false, filelib:is_dir(Absent)),
    ok.

%% Invalid paths are rejected across the whole set before creating output or writing a valid sibling.
-spec invalid_paths_test() -> ok.
invalid_paths_test() ->
    Root = fresh("paths"), Directory = filename:join(Root, "generated"),
    Invalid = ["", "/absolute", "../escape", "a/../escape", "./a", "a/./b", "a//b", "a/", [$a, 0, $b]],
    lists:foreach(fun(Path) ->
        Output = #{result => invalid, files => #{"valid.x" => <<"must not write">>, Path => <<>>}},
        ?assertError({invalid_generated_path, Path}, hls_generated_files:write(Output, Directory)),
        ?assertEqual(false, filelib:is_dir(Directory)),
        ?assertError({invalid_generated_path, Path}, hls_generated_files:write_into(Output, Root)),
        ?assertEqual(false, filelib:is_file(filename:join(Root, "valid.x")))
    end, Invalid),
    ok.

%% Invalid iodata is rejected before output even when valid filenames sort before it.
-spec invalid_bytes_test() -> ok.
invalid_bytes_test() ->
    Root = fresh("bytes"), Directory = filename:join(Root, "generated"),
    Output = #{result => invalid, files => #{"a.x" => <<"must not write">>, "z.x" => [not_a_byte]}},
    ?assertError(badarg, hls_generated_files:write(Output, Directory)),
    ?assertEqual(false, filelib:is_dir(Directory)),
    ?assertError(badarg, hls_generated_files:write_into(Output, Root)),
    ?assertEqual(false, filelib:is_file(filename:join(Root, "a.x"))),
    ok.

%% Consulting a trusted map preserves relative source paths and the caller's working directory.
-spec config_map_test() -> ok.
config_map_test() ->
    Root = fresh("config"), Path = filename:join(Root, "build.config"),
    Config = #{sources => [{"src/actor.erl", [{i, "include"}]}], options => #{native_actors => [left]}},
    ok = file:write_file(Path, io_lib:format("~tp.~n", [Config]), [exclusive]),
    {ok, Before} = file:get_cwd(),
    ?assertEqual(Config, hls_source_config:read(Path)),
    ?assertEqual({ok, Before}, file:get_cwd()),
    ok.

%% A configuration file must contain exactly one map; consultation errors retain their reason.
-spec invalid_config_test() -> ok.
invalid_config_test() ->
    Root = fresh("bad-config"),
    lists:foreach(fun({Name, Bytes}) ->
        Path = filename:join(Root, Name),
        ok = file:write_file(Path, Bytes, [exclusive]),
        ?assertException(error, {hls_diagnostic, #{code := invalid_config_file}}, hls_source_config:read(Path))
    end, [{"empty.config", <<>>}, {"atom.config", <<"config.\n">>},
        {"multiple.config", <<"#{}.\n#{}.\n">>}]),
    Missing = filename:join(Root, "missing.config"),
    ?assertException(error, {hls_diagnostic, #{code := config_read}}, hls_source_config:read(Missing)),
    ok.

%% Each test keeps its tiny outputs beneath a unique disposable build directory.
-spec fresh(string()) -> file:filename().
fresh(Name) ->
    Root = filename:join("_build", "generated-files-" ++ Name ++ "-" ++
        integer_to_list(erlang:unique_integer([positive, monotonic])) ++ "-" ++
        integer_to_list(erlang:system_time(nanosecond))),
    ok = filelib:ensure_dir(filename:join(Root, "placeholder")),
    Root.
