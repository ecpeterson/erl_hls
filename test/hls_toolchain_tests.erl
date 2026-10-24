-module(hls_toolchain_tests).
-moduledoc "Compiler frontend option handling and artifact-boundary rejection tests.".
-include_lib("eunit/include/eunit.hrl").

%% Preprocessing flags repeat in source order; unknown and duplicate scalar flags fail.
-spec cli_options_test() -> ok.
cli_options_test() ->
    Spec = [{"-I", includes, repeat}, {"--output", output, value}, {"--debug", debug, flag}],
    ?assertEqual(#{includes => ["a", "b"], output => "out", debug => true},
        hls_cli:options(["-I", "a", "--output", "out", "-I", "b", "--debug"], Spec)),
    ?assertError({duplicate_option, "--output"}, hls_cli:options(["--output", "a", "--output", "b"], Spec)),
    ?assertError({missing_option_value, "-I"}, hls_cli:options(["-I", "--output"], Spec)),
    ?assertError({unknown_option, "--fabric"}, hls_cli:options(["--fabric"], Spec)),
    ?assertError({missing_option, output}, hls_compile_cli:run(["emit", "missing.erl"])),
    ?assertError({invalid_define, "X=not valid"},
        hls_compile_cli:run(["emit", "missing.erl", "--output", "unused", "-D", "X=not valid"])),
    ?assertError({pipeline_stages, 0}, hls_compile:actor("missing.erl", #{pipeline_stages => 0}, "unused")),
    ?assertError({unknown_compile_options, [placement]}, hls_compile:actor("missing.erl", #{placement => board}, "unused")),
    ok.

%% Manifest clients cannot escape the bundle or overwrite another unit's intermediates.
-spec bundle_rejection_test() -> ok.
bundle_rejection_test() ->
    ?assertError({nonrelative_bundle_path, "../outside"},
        hls_artifact_bundle:snapshot("unused", [{"unused", "../outside", [".x"]}])),
    ?assertError(duplicate_unit_directory,
        hls_artifact_bundle:finish("unused", [#{directory => <<".">>}, #{directory => <<".">>}], #{})),
    ok.
