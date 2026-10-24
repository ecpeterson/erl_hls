-module(hls_compile).
-moduledoc "Standalone actor compilation and compiler support libraries. Placement and deployment belong to clients.".
-export([actor/3, support/2]).
-export_type([options/0]).

-doc "Actor preprocessing, direct observation, extra DSLX import trees and the optional external pipeline length (default two). No external tools run during emission.".
-type options() :: #{source_options => [hls_source:option()], direct_actor_debug => boolean(),
    dslx_path => [file:filename()], pipeline_stages => pos_integer()}.

-doc "Lowers one supported actor into a fresh portable DSLX bundle using xls_parse:to_xls/2. Caller include paths/macros/features pass unchanged to hls_source; the compiler include directory is appended. Records a Top proc with module hls_actor and an explicit XLS unit-delay pipeline recipe, not a timing claim. Unknown options and nonpositive stage counts fail; partial output is retained. Original source paths in request.erl are descriptive, not a portable source-recompilation recipe.".
-spec actor(file:filename(), options(), file:filename()) -> map().
actor(Source, Options, Output) ->
    case maps:keys(Options) -- [source_options, direct_actor_debug, dslx_path, pipeline_stages] of
        [] -> ok;
        Keys -> error({unknown_compile_options, Keys})
    end,
    Stages = maps:get(pipeline_stages, Options, 2),
    case is_integer(Stages) andalso Stages > 0 of
        true -> ok;
        false -> error({pipeline_stages, Stages})
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
    Priv = code:priv_dir(erl_hls),
    Extra = [{Source, "support/import" ++ integer_to_list(I), [".x"]}
        || {I, Source} <- lists:enumerate(0, Imports)],
    hls_artifact_bundle:snapshot(Output,
        [{filename:join(Priv, "xls"), "support/compiler/xls", [".x"]},
         {filename:join(Priv, "rtl"), "support/compiler/rtl", [".v", ".sv"]} | Extra]),
    Paths = ["support/compiler/xls/lib", "support/compiler/xls/fabric"] ++
        [Target || {_, Target, _} <- Extra],
    [unicode:characters_to_binary(P) || P <- Paths, filelib:is_dir(filename:join(Output, P))].
