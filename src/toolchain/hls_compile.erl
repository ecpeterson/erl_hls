-module(hls_compile).
-moduledoc "Standalone actor compilation and compiler support libraries. Placement and deployment belong to clients.".
-export([actor/3, support/2, support_layout/1]).
-export_type([options/0, support_layout/0]).

-doc "Actor preprocessing, direct observation, extra DSLX import trees and the optional external pipeline length (default two). No external tools run during emission.".
-type options() :: #{source_options => [hls_source:option()], direct_actor_debug => boolean(),
    dslx_path => [file:filename()], pipeline_stages => pos_integer()}.

-doc "Lowers one supported actor into a fresh portable DSLX bundle using xls_parse:to_xls/2. Caller include paths/macros/features pass unchanged to hls_source; the compiler include directory is appended. Records a Top proc with module hls_actor and an explicit XLS unit-delay pipeline recipe, not a timing claim. Unknown options and nonpositive stage counts fail; partial output is retained. Original source paths in request.erl are descriptive, not a portable source-recompilation recipe.".
-spec actor(file:filename(), options(), file:filename()) -> map().
actor(Source, Options, Output) ->
    case maps:keys(Options) -- [source_options, direct_actor_debug, dslx_path, pipeline_stages] of
        [] -> ok;
        Keys -> hls_diagnostic:raise(arguments, unknown_compile_options,
            <<"Unknown actor compilation options">>, #{options => Keys})
    end,
    Stages = maps:get(pipeline_stages, Options, 2),
    case is_integer(Stages) andalso Stages > 0 of
        true -> ok;
        false -> hls_diagnostic:raise(arguments, pipeline_stages,
            <<"Pipeline stage count must be a positive integer">>, #{option => pipeline_stages, value => Stages})
    end,
    SourceOptions = maps:get(source_options, Options, []) ++
        [{i, filename:join(code:lib_dir(erl_hls), "include")}],
    Dslx = xls_parse:to_xls(Source, #{source_options => SourceOptions,
        direct_actor_debug => maps:get(direct_actor_debug, Options, false)}),
    Directory = hls_artifact_bundle:open(Output),
    ok = file:write_file(filename:join(Directory, "actor.x"), Dslx, [exclusive]),
    ok = file:write_file(filename:join(Directory, "request.erl"),
        io_lib:format("~tp.~n", [#{source => Source, options => Options}]), [exclusive]),
    Imports = support(Directory, maps:get(dslx_path, Options, [])),
    Unit = #{role => <<".">>, directory => <<".">>, source => <<"actor.x">>, top => <<"Top">>,
        module => <<"hls_actor">>, output => <<"actor.v">>, dslx_path => [<<".">> | Imports],
        codegen_flags => [iolist_to_binary(["--pipeline_stages=", integer_to_list(Stages)]),
            <<"--delay_model=unit">>, <<"--flop_inputs=false">>, <<"--flop_outputs=true">>,
            <<"--use_system_verilog=false">>, <<"--reset=reset">>, <<"--fifo_module=">>],
        rtl => [<<"actor.v">>]},
    hls_artifact_bundle:finish(Directory, [Unit], #{kind => actor}).

-doc "Snapshots this compiler's DSLX/RTL support and extra DSLX trees into an open bundle; returns existing relative import directories. Additional imports must exist. Fabric clients may add their own libraries and schedules separately.".
-spec support(file:filename(), [file:filename()]) -> [binary()].
support(Output, Imports) ->
    #{libraries := Libraries, imports := Paths} = support_layout(Imports),
    hls_artifact_bundle:snapshot(Output, Libraries),
    Paths.

-doc "Compiler and caller-owned support trees with their emitted import directories, without writing files. Library sources are absolute; imports are bundle-relative.".
-type support_layout() :: #{libraries := [hls_artifact_bundle:library()], imports := [binary()]}.

-doc "Plans the same support snapshot used by support/2 without opening an output directory. Missing extra import trees fail; optional compiler import subdirectories are included only when present in the source tree.".
-spec support_layout([file:filename()]) -> support_layout().
support_layout(Imports) ->
    Priv = code:priv_dir(erl_hls),
    Extra = [{filename:absname(Source), "support/import" ++ integer_to_list(I), [".x"]}
        || {I, Source} <- lists:enumerate(0, Imports)],
    Libraries = [{filename:join(Priv, "xls"), "support/compiler/xls", [".x"]},
        {filename:join(Priv, "rtl"), "support/compiler/rtl", [".v", ".sv"]} | Extra],
    lists:foreach(fun({Source, _, _}) -> {ok, _} = file:list_dir(Source) end, Libraries),
    Candidates = [{filename:join([Priv, "xls", "lib"]), "support/compiler/xls/lib"},
        {filename:join([Priv, "xls", "fabric"]), "support/compiler/xls/fabric"}] ++
        [{Source, Target} || {Source, Target, _} <- Extra],
    #{libraries => Libraries, imports => [unicode:characters_to_binary(Target)
        || {Source, Target} <- Candidates, filelib:is_dir(Source)]}.
