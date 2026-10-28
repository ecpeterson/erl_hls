-module(hls_compile).
-moduledoc """
Standalone actor-to-bundle API used by hls_compile_cli and build clients. Lowers through xls_parse, retains the xls_emitted failure codebook and publishes source/support with hls_artifact_bundle. It runs no external tools; placement and deployment belong to clients.
""".
%% Standalone actor bundle emission.
-export([actor/3]).

%% Shared compiler-support snapshot and configuration.
-export([support/2, support/3, configure_support/2, support_layout/1]).
%% Shared type contracts.
-export_type([options/0, support_layout/0]).

-doc "Actor preprocessing, direct observation, extra DSLX import trees and the optional external pipeline length (default two) and ordinary payload capacity (default three words). No external tools run during emission.".
-type options() :: #{
    source_options => [hls_source:option()],
    direct_actor_debug => boolean(),
    dslx_path => [file:filename()],
    pipeline_stages => pos_integer(),
    frame_payload_words => hls_frame_layout:words()
}.

-doc "Lowers one supported actor into a fresh portable DSLX bundle using xls_parse:to_artifact/2. Caller include paths/macros/features pass unchanged to hls_source; the compiler include directory is appended. Retains a hashed failure-codebook sidecar. Records a Top proc with module hls_actor and an explicit XLS unit-delay pipeline recipe, not a timing claim. Unknown options and nonpositive stage counts fail; partial output is retained. Original source paths in request.erl are descriptive, not a portable source-recompilation recipe.".
-spec actor(file:filename(), options(), file:filename()) -> map().
actor(Source, Options, Output) ->
    case
        maps:keys(Options) --
            [source_options, direct_actor_debug, dslx_path, pipeline_stages, frame_payload_words]
    of
        [] ->
            ok;
        Keys ->
            hls_diagnostic:raise(
                arguments,
                unknown_compile_options,
                <<"Unknown actor compilation options">>,
                #{options => Keys}
            )
    end,
    Layout = hls_frame_layout:new(maps:get(frame_payload_words, Options, 3)),
    Stages = maps:get(pipeline_stages, Options, 2),
    case is_integer(Stages) andalso Stages > 0 of
        true ->
            ok;
        false ->
            hls_diagnostic:raise(
                arguments,
                pipeline_stages,
                <<"Pipeline stage count must be a positive integer">>,
                #{option => pipeline_stages, value => Stages}
            )
    end,
    SourceOptions =
        maps:get(source_options, Options, []) ++
            [{i, filename:join(code:lib_dir(erl_hls), "include")}],
    Emitted = xls_parse:to_artifact(Source, #{
        source_options => SourceOptions,
        direct_actor_debug => maps:get(direct_actor_debug, Options, false),
        frame_payload_words => hls_frame_layout:payload_words(Layout)
    }),
    Dslx = xls_emitted:bytes(Emitted),
    Directory = hls_artifact_bundle:open(Output),
    ok = file:write_file(filename:join(Directory, "actor.x"), Dslx, [exclusive]),
    ok = file:write_file(
        filename:join(Directory, "actor.x.json"),
        json:encode(#{
            dslx_sha256 => string:lowercase(binary:encode_hex(crypto:hash(sha256, Dslx))),
            failure_sites => xls_emitted:sites(Emitted)
        }),
        [exclusive]
    ),
    ok = file:write_file(
        filename:join(Directory, "request.erl"),
        io_lib:format("~tp.~n", [#{source => Source, options => Options}]),
        [exclusive]
    ),
    Imports = support(Directory, maps:get(dslx_path, Options, []), Layout),
    Unit = #{
        role => <<".">>,
        directory => <<".">>,
        source => <<"actor.x">>,
        top => <<"Top">>,
        module => <<"hls_actor">>,
        output => <<"actor.v">>,
        dslx_path => [<<".">> | Imports],
        codegen_flags => [
            iolist_to_binary(["--pipeline_stages=", integer_to_list(Stages)]),
            <<"--delay_model=unit">>,
            <<"--flop_inputs=false">>,
            <<"--flop_outputs=true">>,
            <<"--use_system_verilog=false">>,
            <<"--reset=reset">>,
            <<"--fifo_module=">>
        ],
        rtl => [<<"actor.v">>]
    },
    hls_artifact_bundle:finish(Directory, [Unit], #{
        kind => actor, frame_abi => hls_frame_layout:descriptor(Layout)
    }).

-doc "Snapshots this compiler's DSLX/RTL support and extra DSLX trees into an open bundle; returns existing relative import directories. Additional imports must exist. Fabric clients may add their own libraries and schedules separately.".
-spec support(file:filename(), [file:filename()]) -> [binary()].
support(Output, Imports) -> support(Output, Imports, hls_frame_layout:default()).

-doc "Snapshots support with one checked ordinary-frame ABI. Only the bundle copy of frame_config.x is selected; installed compiler files are unchanged. All units in the bundle must use the same layout.".
-spec support(file:filename(), [file:filename()], hls_frame_layout:layout()) -> [binary()].
support(Output, Imports, Layout) ->
    #{libraries := Libraries, imports := Paths} = support_layout(Imports),
    hls_artifact_bundle:snapshot(Output, Libraries),
    ok = configure_support(Output, Layout),
    Paths.

-doc "Selects the ordinary-frame layout in a newly copied support tree before the bundle manifest is frozen. Requires the copied frame_config.x; never call on a published bundle or installed library. Debug, hash and explicit FrameN envelope widths are unchanged.".
-spec configure_support(file:filename(), hls_frame_layout:layout()) -> ok.
configure_support(Output, Layout) ->
    case filelib:is_file(filename:join(Output, "source-build.json")) of
        true -> error({published_bundle, Output});
        false -> ok
    end,
    Path = filename:join([Output, "support", "compiler", "xls", "lib", "frame_config.x"]),
    {ok, _} = file:read_file_info(Path),
    ok = file:write_file(Path, hls_frame_layout:config_dslx(Layout)).

-doc "Compiler and caller-owned support trees with their emitted import directories, without writing files. Library sources are absolute; imports are bundle-relative.".
-type support_layout() :: #{libraries := [hls_artifact_bundle:library()], imports := [binary()]}.

-doc "Plans the same support snapshot used by support/2 without opening an output directory. Missing extra import trees fail; optional compiler import subdirectories are included only when present in the source tree.".
-spec support_layout([file:filename()]) -> support_layout().
support_layout(Imports) ->
    Priv = code:priv_dir(erl_hls),
    Extra = [
        {filename:absname(Source), "support/import" ++ integer_to_list(I), [".x"]}
     || {I, Source} <- lists:enumerate(0, Imports)
    ],
    Libraries = [
        {filename:join(Priv, "xls"), "support/compiler/xls", [".x"]},
        {filename:join(Priv, "rtl"), "support/compiler/rtl", [".v", ".sv"]}
        | Extra
    ],
    lists:foreach(fun({Source, _, _}) -> {ok, _} = file:list_dir(Source) end, Libraries),
    Candidates =
        [
            {filename:join([Priv, "xls", "lib"]), "support/compiler/xls/lib"},
            {filename:join([Priv, "xls", "fabric"]), "support/compiler/xls/fabric"}
        ] ++
            [{Source, Target} || {Source, Target, _} <- Extra],
    #{
        libraries => Libraries,
        imports => [
            unicode:characters_to_binary(Target)
         || {Source, Target} <- Candidates, filelib:is_dir(Source)
        ]
    }.
