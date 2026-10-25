-module(xls_parse).
-moduledoc """
Compiles supported Erlang actors to XLS or exposes their checked semantics.

hls_source owns preprocessing and form queries; hls_actor_source owns actor
metadata. xls_gs_immediate/xls_gs_deferred render servers and xls_statem_lower
lowers state machines. Shared callback expression lowering is xls_clause_lower.
See docs/actor-compilation.md for these internal boundaries and docs/control-flow.md
for the supported source semantics.
""".
-export([actor_artifact/2, actor_interface/1, actor_interface/2, to_xls/1, to_xls/2]).

-doc "Transpiles an Erlang actor into a dedicated XLS service.".
-spec to_xls(file:filename()) -> iolist().
to_xls(Filename) -> to_xls(Filename, #{}).

-doc "Transpiles an actor with preprocessing and optional direct-actor observations.".
-spec to_xls(file:filename(), #{source_options => [hls_source:option()] | hls_source:context(),
    direct_actor_debug => boolean()}) -> iolist().
to_xls(Filename, Options0) ->
    Options = validate_xls_options(Options0),
    {ok, Forms} = hls_source:parse_file(Filename, maps:get(source_options, Options)),
    case hls_source:find_optional_attribute(Forms, hls_phases) of
        none ->
            case maps:get(direct_actor_debug, Options) of
                true -> error(direct_actor_debug_requires_hls_statem);
                false -> server(Filename, Forms)
            end;
        {ok, Phases} -> xls_statem_lower:lower(Filename, Forms, Phases,
            maps:with([direct_actor_debug], Options))
    end.

-doc "Returns validated state-machine callback semantics for a backend, using explicit source context.".
-spec actor_artifact(file:filename(), [hls_source:option()] | hls_source:context()) -> xls_actor_codegen:spec().
actor_artifact(Filename, SourceOptions) ->
    {ok, Forms} = hls_source:parse_file(Filename, SourceOptions),
    case hls_source:find_optional_attribute(Forms, hls_phases) of
        {ok, Phases} -> xls_statem_lower:artifact(Filename, Forms, Phases);
        none -> error({unsupported_actor_artifact, Filename, hls_gs})
    end.

%% Reject physical execution options at the dedicated-service boundary.
-doc "Validates source and dedicated-actor options; rejects unknown physical settings.".
-spec validate_xls_options(map()) -> map().
validate_xls_options(Options) when is_map(Options) ->
    case maps:keys(Options) -- [source_options, direct_actor_debug] of
        [] -> #{direct_actor_debug => xls_actor_observation:enabled(Options),
            source_options => maps:get(source_options, Options, [])};
        Keys -> error({invalid_xls_options, Keys})
    end;
validate_xls_options(Options) -> error({invalid_xls_options, Options}).

-spec actor_interface(file:filename()) -> map().
-doc "Returns the include-expanded interface inferred for one hls_statem file.".
actor_interface(Filename) ->
    actor_interface(Filename, []).

-spec actor_interface(file:filename(), [hls_source:option()] |
    hls_source:context()) -> map().
-doc "Infers an interface using explicit preprocessing options or a captured context.".
actor_interface(Filename, SourceOptions) ->
    {ok, Forms} = hls_source:parse_file(Filename, SourceOptions),
    case hls_source:find_optional_attribute(Forms, hls_phases) of
        {ok, PhaseNames} ->
            xls_statem_lower:interface(Forms, PhaseNames);
        none ->
            error({unsupported_hls_actor_interface, Filename, hls_gs})
    end.

%% Select the server emitter after checking its callback contract.
-spec server(file:filename(), [hls_source:form()]) -> iolist().
server(Filename, Forms) ->
    case hls_service_contract:call_arity(Forms) of
        3 -> xls_gs_deferred:emit(Filename, Forms);
        2 -> xls_gs_immediate:emit(Filename, Forms)
    end.
