-module(hls_compile_topology).
-moduledoc "Packages dedicated actor topologies for hls_compile and hlsc. Loads declared Erlang sources, normalizes the logical graph, applies XLS topology requirements, and freezes a portable bundle. The application owns its topology callback; this module owns compilation and packaging, not device transport or recovery.".
%% Public build entry point and configuration contract.
-export([write/2]).
-export_type([config/0, source/0]).

-doc "One source file and its ordered preprocessing options. Declare dependencies before consumers; helper/provider modules may accompany actors and the topology module.".
-type source() :: {file:filename(), [hls_source:option()]}.
-doc "Trusted Erlang build configuration. Sources and the topology callback execute in the compiler VM. File configurations resolve source/include/import paths beside that file; maps use the caller's directory. Profile selects dedicated actor buffering and frame width; pipeline_stages defaults to two with the unit delay model.".
-type config() :: #{
    sources := [source(), ...],
    topology := module(),
    profile := xls_topology_dslx:profile(),
    pipeline_stages => pos_integer(),
    dslx_path => [file:filename()]
}.

-doc "Compiles a trusted configuration map or single-term file into a fresh source bundle. Every actor and topology module must be declared; duplicate modules and missing sources fail before publication. Loads BEAM modules into the caller VM, so use a build process rather than a live application. Source and support files must remain stable during this call. Partial output is retained on write errors; XLS execution and board deployment are separate.".
-spec write(config() | file:filename(), file:filename()) -> map().
write(File, Output) when is_list(File) ->
    case file:consult(File) of
        {ok, [Config]} ->
            write_config(Config, filename:dirname(filename:absname(File)), Output);
        Other ->
            fail(config_file, <<"Expected one topology build configuration">>, #{
                file => File, result => Other
            })
    end;
write(Config, Output) ->
    write_config(Config, filename:absname("."), Output).

%% Loaded source/context pairs are reused by interface analysis and lowering.
-type loaded() :: #{module() => {file:filename(), hls_source:context()}}.

%% Validate shape before executing application source; backend owners validate profile semantics.
-spec write_config(config(), file:filename(), file:filename()) -> map().
write_config(Config, Base, Output) ->
    #{sources := Sources, topology := Topology, profile := Profile0} = validate(Config),
    Profile = xls_topology_profile:normalize(Profile0),
    #{name := Name, frame_payload_words := Words} = Profile,
    Stages = maps:get(pipeline_stages, Config, 2),
    case is_integer(Stages) andalso Stages > 0 of
        true ->
            ok;
        false ->
            fail(pipeline_stages, <<"Pipeline stage count must be a positive integer">>, #{
                value => Stages
            })
    end,
    Imports = [filename:absname(Path, Base) || Path <- maps:get(dslx_path, Config, [])],
    _ = hls_compile:support_layout(Imports),
    Loaded = lists:foldl(fun(Source, Acc) -> load(Source, Base, Acc) end, #{}, Sources),
    _ = declared(Topology, Loaded),
    Plan = hls_topology:from_module(Topology),
    Requirements = xls_topology_dslx:artifact_requirements(Plan, Profile),
    Artifacts = maps:map(
        fun(Module, Options) ->
            {File, Context} = declared(Module, Loaded),
            xls_parse:to_artifact(File, Options#{source_options => Context})
        end,
        Requirements
    ),
    Graph = xls_topology_dslx:emit(Plan, Profile),
    Directory = hls_artifact_bundle:open(Output),
    %% Actor names live under actors/ so a legal actor called topology cannot overwrite the graph.
    ActorDirectory = filename:join(Directory, "actors"),
    maps:foreach(
        fun(Module, Artifact) -> write_actor(Module, Artifact, ActorDirectory) end, Artifacts
    ),
    ok = file:write_file(filename:join(Directory, "topology.x"), Graph, [exclusive]),
    Layout = hls_frame_layout:new(Words),
    Support = hls_compile:support(Directory, Imports, Layout),
    Rtl = unicode:characters_to_binary(Name ++ ".v"),
    Unit = #{
        role => <<".">>,
        directory => <<".">>,
        source => <<"topology.x">>,
        top => <<"Top">>,
        module => unicode:characters_to_binary(Name),
        output => Rtl,
        dslx_path => [<<"actors">>, <<".">> | Support],
        codegen_flags => [
            iolist_to_binary(["--pipeline_stages=", integer_to_list(Stages)]),
            <<"--delay_model=unit">>,
            <<"--worst_case_throughput=1">>,
            <<"--flop_inputs=false">>,
            <<"--flop_outputs=true">>,
            <<"--use_system_verilog=false">>,
            <<"--reset=reset">>,
            <<"--fifo_module=">>
        ],
        rtl => [Rtl]
    },
    hls_artifact_bundle:finish(Directory, [Unit], #{
        kind => topology,
        profile => Profile,
        frame_abi => hls_frame_layout:descriptor(Layout)
    }).

%% Keep configuration fields closed; ordinary source options are validated by hls_source.
-spec validate(term()) -> config().
validate(#{sources := [_ | _] = Sources, topology := Topology, profile := Profile} = Config) when
    is_atom(Topology), is_map(Profile)
->
    case maps:keys(Config) -- [sources, topology, profile, pipeline_stages, dslx_path] of
        [] -> ok;
        Keys -> fail(unknown_options, <<"Unknown topology build fields">>, #{fields => Keys})
    end,
    lists:foreach(
        fun
            ({File, Options}) when is_list(File), File =/= [], is_list(Options) -> ok;
            (Value) ->
                fail(source, <<"Expected {source filename, preprocessing options}">>, #{
                    value => Value
                })
        end,
        Sources
    ),
    case maps:get(dslx_path, Config, []) of
        Paths when is_list(Paths) ->
            lists:foreach(
                fun
                    (Path) when is_list(Path), Path =/= [] -> ok;
                    (Value) ->
                        fail(import_path, <<"Expected a DSLX import directory">>, #{value => Value})
                end,
                Paths
            );
        Value ->
            fail(import_path, <<"Expected a list of DSLX import directories">>, #{value => Value})
    end,
    Config;
validate(Config) ->
    fail(config, <<"Topology build requires sources, topology module and profile">>, #{
        value => Config
    }).

%% Retain the same captured preprocessing context for BEAM/interface analysis and DSLX lowering.
-spec load(source(), file:filename(), loaded()) -> loaded().
load({File0, Options0}, Base, Loaded) ->
    File = filename:absname(File0, Base),
    Options = [
        case Option of
            {i, Path} -> {i, filename:absname(Path, Base)};
            _ -> Option
        end
     || Option <- Options0
    ],
    {ok, Forms} = hls_source:parse_file(File, Options),
    Module = hls_source:find_attribute(Forms, module),
    case maps:is_key(Module, Loaded) of
        true ->
            fail(duplicate_module, <<"A module is declared by more than one source">>, #{
                module => Module
            });
        false ->
            ok
    end,
    case
        compile:noenv_forms(beam_forms(Forms), [
            binary, debug_info, return_errors, return_warnings, {source, File}
        ])
    of
        {ok, Module, Bytes, _Warnings} ->
            {module, Module} = code:load_binary(Module, File, Bytes),
            Loaded#{Module => {File, hls_source:from_forms(Forms, [])}};
        {error, Errors, Warnings} ->
            fail(source_compile, <<"Erlang source compilation failed">>, #{
                source => File, errors => Errors, warnings => Warnings
            })
    end.

%% Source analysis appends its captured context after functions; erl_lint requires attributes first.
-spec beam_forms([hls_source:form()]) -> [hls_source:form()].
beam_forms(Forms) ->
    Context = hls_source:capture(Forms, []),
    lists:flatmap(
        fun
            ({attribute, _, module, _} = Module) -> [Module | Context];
            ({attribute, _, hls_source_context, _}) -> [];
            (Form) -> [Form]
        end,
        Forms
    ).

%% A preloaded module cannot silently substitute for an undeclared actor source.
-spec declared(module(), loaded()) -> {file:filename(), hls_source:context()}.
declared(Module, Loaded) ->
    case maps:find(Module, Loaded) of
        {ok, Source} ->
            Source;
        error ->
            fail(missing_source, <<"Topology module or actor has no declared source">>, #{
                module => Module
            })
    end.

%% Runtime failure metadata stays adjacent to the exact annotated actor bytes.
-spec write_actor(module(), xls_emitted:artifact(), file:filename()) -> ok.
write_actor(Module, Artifact, Directory) ->
    File = filename:join(Directory, atom_to_list(Module) ++ ".x"),
    ok = xls_emitted:write(Artifact, File),
    file:write_file(
        File ++ ".json",
        json:encode(#{
            dslx_sha256 => binary:encode_hex(
                crypto:hash(sha256, xls_emitted:bytes(Artifact)), lowercase
            ),
            failure_sites => xls_emitted:sites(Artifact)
        }),
        [exclusive]
    ).

%% Build-shape failures retain values for the shared text/JSON diagnostic boundary.
-spec fail(atom(), binary(), map()) -> no_return().
fail(Code, Message, Context) -> hls_diagnostic:raise(topology_build, Code, Message, Context).
