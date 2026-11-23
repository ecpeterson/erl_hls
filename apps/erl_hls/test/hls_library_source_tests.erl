-module(hls_library_source_tests).
-moduledoc "Installed source lookup survives release relocation without consulting original BEAM source paths.".
-include_lib("eunit/include/eunit.hrl").

%% Loading a moved package must use its new source tree even when BEAM metadata names a deleted build path.
-spec relocated_library_source_test() -> ok.
relocated_library_source_test() ->
    Root = filename:absname(filename:join(["_build", "library-source-tests",
        binary_to_list(binary:encode_hex(crypto:strong_rand_bytes(12), lowercase))])),
    Original = filename:join([Root, "original", "hls_library_fixture-0.1.0"]),
    Relocated = filename:join([Root, "installed", "hls_library_fixture-0.1.0"]),
    Source = filename:join([Original, "src", "nested", "hls_library_fixture.erl"]),
    Beam = filename:join([Original, "ebin", "hls_library_fixture.beam"]),
    Ebin = filename:join(Relocated, "ebin"),
    Paths = code:get_path(),
    try
        ok = filelib:ensure_dir(Source),
        ok = filelib:ensure_dir(Beam),
        ok = file:write_file(Source,
            "-module(hls_library_fixture).\n-export([value/0]).\nvalue() -> 7.\n"),
        {ok, hls_library_fixture, Binary} = compile:noenv_file(Source, [binary, debug_info]),
        ok = file:write_file(Beam, Binary),
        ok = file:write_file(filename:join(Original, "ebin/hls_library_fixture.app"),
            "{application,hls_library_fixture,[{vsn,\"0.1.0\"},{modules,[hls_library_fixture]}]}.\n"),
        ok = filelib:ensure_dir(Relocated),
        ok = file:rename(Original, Relocated),
        true = code:add_patha(Ebin),
        {module, hls_library_fixture} = code:load_abs(filename:join(Ebin, "hls_library_fixture")),
        ?assertEqual(Source, proplists:get_value(source, hls_library_fixture:module_info(compile))),
        ?assertNot(filelib:is_regular(Source)),
        Expected = filename:join([Relocated, "src", "nested", "hls_library_fixture.erl"]),
        ?assertEqual(Expected, hls_source:library_file(hls_library_fixture, "nested/hls_library_fixture.erl")),
        {ok, Forms} = hls_source:parse_file(Expected),
        ?assertEqual(hls_library_fixture, hls_source:find_attribute(Forms, module)),
        ok = file:delete(Expected),
        ?assertException(error, {hls_diagnostic, #{stage := source, code := library_source_missing}},
            hls_source:library_file(hls_library_fixture, "nested/hls_library_fixture.erl"))
    after
        true = code:set_path(Paths),
        _ = code:purge(hls_library_fixture),
        _ = code:delete(hls_library_fixture),
        _ = code:purge(hls_library_fixture),
        _ = file:del_dir_r(Root)
    end.

%% Library lookup must neither escape its source tree lexically nor guess missing installations.
-spec invalid_or_missing_library_test() -> ok.
invalid_or_missing_library_test() ->
    lists:foreach(fun(Path) ->
        ?assertError({invalid_library_source, Path}, hls_source:library_file(erl_hls, Path))
    end, ["", ".", "../outside.erl", "nested/../outside.erl", "/absolute.erl"]),
    ?assertException(error, {hls_diagnostic, #{stage := source, code := library_unavailable}},
        hls_source:library_file(hls_absent_source_fixture, "absent.erl")).

%% The actual finite controller is compiled from the installed runtime package, including its own header.
-spec packaged_lifecycle_source_compiles_test() -> ok.
packaged_lifecycle_source_compiles_test() ->
    Source = hls_source:library_file(hls_runtime, "runtime/hls_domain_lifecycle.erl"),
    Artifact = xls_parse:to_artifact(Source, #{frame_payload_words => 10}),
    ?assert(byte_size(xls_emitted:bytes(Artifact)) > 0).
