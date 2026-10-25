-module(hls_toolchain_tests).
-moduledoc "Compiler frontend option handling and artifact-boundary rejection tests.".
-include_lib("eunit/include/eunit.hrl").

%% Values and aliases override in command order; additive options retain every entry and flags are idempotent.
-spec cli_options_test() -> ok.
cli_options_test() ->
    Spec = [{"-I", includes, repeat}, {"--output", output, value}, {"-o", output, value}, {"--debug", debug, flag}],
    ?assertEqual(#{includes => ["a", "b"], output => "out", debug => true},
        hls_cli:options(["-I", "a", "--output", "out", "-I", "b", "--debug"], Spec)),
    ?assertEqual(#{includes => ["a", "b", "a"], output => "last", debug => true},
        hls_cli:options(["--output", "first", "-I", "a", "--debug", "-o", "second",
            "-I", "b", "--output", "last", "--debug", "-I", "a"], Spec)),
    ?assertEqual(#{output => "last"}, hls_cli:options(["--output", "first", "-o", "last"], Spec)),
    ?assertError({hls_diagnostic, #{code := missing_option_value}},
        hls_cli:options(["--output", "first", "--output"], Spec)),
    ?assertError({hls_diagnostic, #{code := missing_option_value, context := #{option := <<"-I">>}}}, hls_cli:options(["-I", "--output"], Spec)),
    ?assertError({hls_diagnostic, #{code := unknown_option, context := #{option := <<"--fabric">>}}}, hls_cli:options(["--fabric"], Spec)),
    ?assertError({hls_diagnostic, #{code := missing_option, context := #{option := output}}}, hls_compile_cli:run(["emit", "missing.erl"])),
    ?assertError({hls_diagnostic, #{code := invalid_define, context := #{value := <<"X=not valid">>}}},
        hls_compile_cli:run(["emit", "missing.erl", "--output", "unused", "-D", "X=not valid"])),
    ?assertError({hls_diagnostic, #{code := pipeline_stages, context := #{value := 0}}}, hls_compile:actor("missing.erl", #{pipeline_stages => 0}, "unused")),
    ?assertError({hls_diagnostic, #{code := unknown_compile_options, context := #{options := [placement]}}}, hls_compile:actor("missing.erl", #{placement => board}, "unused")),
    ?assertError({hls_diagnostic, #{code := invalid_integer, context := #{option := stages, value := <<"bad">>}}},
        hls_cli:integer(stages, "bad")),
    ?assertError({hls_diagnostic, #{code := unknown_command, context := #{arguments := [<<"bad">>]}}},
        hls_compile_cli:run(["bad"])),
    ok.

%% Manifest clients cannot escape the bundle or overwrite another unit's intermediates.
-spec bundle_rejection_test() -> ok.
bundle_rejection_test() ->
    ?assertError({nonrelative_bundle_path, "../outside"},
        hls_artifact_bundle:snapshot("unused", [{"unused", "../outside", [".x"]}])),
    ?assertError(duplicate_unit_directory,
        hls_artifact_bundle:finish("unused", [#{directory => <<".">>}, #{directory => <<".">>}], #{})),
    ok.

%% Planned import paths remain valid when a support subdirectory has no selected source files.
-spec empty_support_import_test() -> ok.
empty_support_import_test() ->
    Root = filename:join("_build", "support-layout-" ++ integer_to_list(erlang:unique_integer([positive]))),
    Source = filename:join(Root, "source"),
    Output = filename:join(Root, "output"),
    try
        ok = filelib:ensure_dir(filename:join([Source, "empty", "placeholder"])),
        ok = filelib:ensure_dir(filename:join([Source, "filtered", "ignored.txt"])),
        ok = file:write_file(filename:join([Source, "filtered", "ignored.txt"]), <<"not DSLX">>),
        ok = file:write_file(filename:join(Source, "entry.x"), <<"pub fn main() -> u1 { u1:0 }">>),
        ok = hls_artifact_bundle:snapshot(Output, [{Source, "support/import", [".x"]}]),
        ?assert(filelib:is_dir(filename:join([Output, "support/import/empty"]))),
        ?assert(filelib:is_dir(filename:join([Output, "support/import/filtered"]))),
        ?assertNot(filelib:is_file(filename:join([Output, "support/import/filtered/ignored.txt"]))),
        Unit = #{role => <<".">>, directory => <<".">>, source => <<"support/import/entry.x">>,
            top => <<"main">>, module => <<"entry">>, output => <<"entry.v">>,
            dslx_path => [<<"support/import/empty">>, <<"support/import/filtered">>],
            codegen_flags => [], rtl => [<<"entry.v">>]},
        #{inputs := Inputs} = hls_artifact_bundle:finish(Output, [Unit], #{}),
        ?assertMatch([#{file := <<"support/import/entry.x">>}], Inputs)
    after
        ok = file:del_dir_r(Root)
    end.
