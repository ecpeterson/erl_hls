-module(xls_parse).
-moduledoc "File-level compiler facade used by build tools and backend consumers. hls_source preprocesses Erlang forms; xls_statem_lower checks state machines and xls_gs_immediate/xls_gs_deferred compile server contracts. actor_artifact exposes a checked semantic spec, whereas to_artifact returns final DSLX plus failure metadata. XLS conversion, optimization and RTL generation happen outside this Erlang backend.".
%% Compile dedicated services to final artifacts or bytes.
-export([to_artifact/1, to_artifact/2, to_xls/1, to_xls/2]).
%% Expose checked state-machine semantics to other execution backends.
-export([actor_artifact/2, actor_artifact/3]).
%% Infer public actor interfaces without rendering an execution body.
-export([actor_interface/1, actor_interface/2, actor_interface/3]).

-doc "Transpiles an Erlang actor into a dedicated XLS service.".
-spec to_xls(file:filename()) -> iolist().
to_xls(Filename) -> to_xls(Filename, #{}).

-doc "Transpiles an actor with preprocessing and optional direct-actor observations.".
-spec to_xls(file:filename(), #{
    source_options => [hls_source:option()] | hls_source:context(),
    direct_actor_debug => boolean(),
    frame_payload_words => hls_frame_layout:words()
}) -> iolist().
to_xls(Filename, Options) -> [xls_emitted:bytes(to_artifact(Filename, Options))].

-doc "Compiles an actor to final DSLX with its allocated failure codebook and consistency seal.".
-spec to_artifact(file:filename()) -> xls_emitted:artifact().
to_artifact(Filename) -> to_artifact(Filename, #{}).

-doc "Compiles with explicit preprocessing, frame capacity and optional direct observations; preserves failure metadata for debug consumers.".
-spec to_artifact(file:filename(), #{
    source_options => [hls_source:option()] | hls_source:context(),
    direct_actor_debug => boolean(),
    frame_payload_words => hls_frame_layout:words()
}) -> xls_emitted:artifact().
to_artifact(Filename, Options0) ->
    Options = validate_xls_options(Options0),
    {ok, Forms} = hls_source:parse_file(Filename, maps:get(source_options, Options)),
    case hls_source:find_optional_attribute(Forms, hls_phases) of
        none ->
            case maps:get(direct_actor_debug, Options) of
                true -> error(direct_actor_debug_requires_hls_statem);
                false -> server(Filename, Forms, maps:get(frame_layout, Options))
            end;
        {ok, Phases} ->
            Spec = xls_statem_lower:artifact(
                Filename, Forms, Phases, maps:get(frame_layout, Options)
            ),
            xls_statem_codegen:artifact(Spec#{
                direct_actor_debug => maps:get(direct_actor_debug, Options)
            })
    end.

-doc "Returns validated state-machine callback semantics for a backend, using explicit source context.".
-spec actor_artifact(file:filename(), [hls_source:option()] | hls_source:context()) ->
    xls_actor_codegen:spec().
actor_artifact(Filename, SourceOptions) ->
    actor_artifact(Filename, SourceOptions, hls_frame_layout:default()).

-doc "Returns checked state-machine semantics under the explicit ordinary-frame capacity.".
-spec actor_artifact(
    file:filename(),
    [hls_source:option()] | hls_source:context(),
    hls_frame_layout:layout()
) -> xls_actor_codegen:spec().
actor_artifact(Filename, SourceOptions, Layout) ->
    {ok, Forms} = hls_source:parse_file(Filename, SourceOptions),
    case hls_source:find_optional_attribute(Forms, hls_phases) of
        {ok, Phases} -> xls_statem_lower:artifact(Filename, Forms, Phases, Layout);
        none -> error({unsupported_actor_artifact, Filename, hls_gs})
    end.

%% Reject physical execution options at the dedicated-service boundary.
-doc "Validates source and dedicated-actor options; rejects unknown physical settings.".
-spec validate_xls_options(map()) -> map().
validate_xls_options(Options) when is_map(Options) ->
    case maps:keys(Options) -- [source_options, direct_actor_debug, frame_payload_words] of
        [] ->
            #{
                frame_layout => hls_frame_layout:new(maps:get(frame_payload_words, Options, 3)),
                direct_actor_debug => xls_actor_observation:enabled(Options),
                source_options => maps:get(source_options, Options, [])
            };
        Keys ->
            error({invalid_xls_options, Keys})
    end;
validate_xls_options(Options) ->
    error({invalid_xls_options, Options}).

-spec actor_interface(file:filename()) -> map().
-doc "Returns the include-expanded interface inferred for one hls_statem file.".
actor_interface(Filename) ->
    actor_interface(Filename, []).

-spec actor_interface(
    file:filename(),
    [hls_source:option()]
    | hls_source:context()
) -> map().
-doc "Infers an interface using explicit preprocessing options or a captured context.".
actor_interface(Filename, SourceOptions) ->
    {ok, Forms} = hls_source:parse_file(Filename, SourceOptions),
    case hls_source:find_optional_attribute(Forms, hls_phases) of
        {ok, PhaseNames} ->
            xls_statem_lower:interface(Forms, PhaseNames);
        none ->
            error({unsupported_hls_actor_interface, Filename, hls_gs})
    end.

-doc "Infers an interface and checks every public schema against an explicit ordinary-frame capacity.".
-spec actor_interface(
    file:filename(),
    [hls_source:option()] | hls_source:context(),
    hls_frame_layout:layout()
) -> map().
actor_interface(Filename, SourceOptions, Layout) ->
    {ok, Forms} = hls_source:parse_file(Filename, SourceOptions),
    case hls_source:find_optional_attribute(Forms, hls_phases) of
        {ok, Phases} -> xls_statem_lower:interface(Forms, Phases, Layout);
        none -> error({unsupported_hls_actor_interface, Filename, hls_gs})
    end.

%% Select the server emitter after checking its callback contract.
-spec server(file:filename(), [hls_source:form()], hls_frame_layout:layout()) ->
    xls_emitted:artifact().
server(Filename, Forms, Layout) ->
    case hls_service_contract:call_arity(Forms) of
        3 -> xls_gs_deferred:artifact(Filename, Forms, Layout);
        2 -> xls_gs_immediate:artifact(Filename, Forms, Layout)
    end.
