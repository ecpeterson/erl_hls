-module(hls_source_config).
-moduledoc "Source-build configuration contracts and trusted terms-file loading. The public build boundary validates input shape here; source-owning passes check semantic constraints. File loading alone does not produce a checked config.".
-export([read/1, validate/2]).
-export_type([config/0, source/0, transport/0, network/0, boundary/0, application/0,
    bridge/0, deployment/0, mixed/0, placement_options/0, network_options/0,
    bridge_options/0, source_file/0, topology/0, activation/0, inspection/0,
    role/0, limits/0, endpoint/0, device/0]).

%% Erlang map types have no extension syntax; these fragments give shared input
%% fields one owner while keeping every exported per-kind map closed.
-define(SOURCE_FIELDS,
    sources := [source_file(), ...], topology := topology(), actor_limit := 1..65536,
    protocol_model => hls_protocol_model:request(), dslx_path => [file:filename()]).
-define(PLACEMENT_FIELDS,
    native_actors => [hls_protocol_topology:id(), ...],
    arithmetic_groups => [[hls_protocol_topology:id(), ...]]).
-define(NETWORK_FIELDS, activation => activation(), inspection => inspection(), control => rectangle).
-define(BRIDGE_FIELDS,
    native_actors := [hls_protocol_topology:id(), ...], host := endpoint(), service := endpoint(),
    control := rectangle, arithmetic_groups => [[hls_protocol_topology:id(), ...]],
    activation => explicit_start, inspection => none).

-doc "One declared Erlang source and its ordinary compiler options, including include paths and macros. Paths are relative to the build caller.".
-type source_file() :: {file:filename(), [hls_source:compiler_option()]}.

-doc "A trusted topology constructor invoked after the declared sources are loaded. Arguments are application-owned Erlang values.".
-type topology() :: {module(), atom(), [term()]}.

-doc "Network startup policy; framed application and bridge builders require explicit_start.".
-type activation() :: automatic | explicit_start.

-doc "Passive process inspection or no inspection. Partitioned bridges currently require none.".
-type inspection() :: none | process.

-doc "A nonzero 16-bit host or service endpoint; each bridge requires different host and service values.".
-type endpoint() :: 1..65535.

-doc "An application-chosen device identity used as a map key and retained in deployment bindings; it is not a host endpoint or process identifier.".
-type device() :: term().

-doc "Fresh source inputs shared by every build kind. Optional provider options belong to hls_protocol_model; dslx_path is consumed only by source-bundle packaging.".
-type source() :: #{?SOURCE_FIELDS}.

-doc "Native placement and optional scalar-completion groups. Native IDs must be a unique nonempty proper subset; groups must have two or three disjoint compatible native members.".
-type placement_options() :: #{?PLACEMENT_FIELDS}.

-doc "Options for an existing network or boundary placement; omitted modes select automatic activation and no inspection.".
-type network_options() :: #{activation => activation(), inspection => inspection()}.

-doc "Options for an existing framed placement. Rectangle control is required; explicit activation and no inspection are the supported defaults.".
-type bridge_options() :: #{host := endpoint(), service := endpoint(), control := rectangle,
    activation => explicit_start, inspection => none}.

-doc "Source transport inputs with optional native placement and scalar-completion sharing. This stage does not connect actor clocks or frame a deployment.".
-type transport() :: #{?SOURCE_FIELDS, ?PLACEMENT_FIELDS}.

-doc "Connected source-network inputs. The optional rectangle selection can be carried through a shared outer configuration; control schemas still come from source. Inspection with native_actors is rejected.".
-type network() :: #{?SOURCE_FIELDS, ?PLACEMENT_FIELDS, ?NETWORK_FIELDS}.

-doc "External-stream arbitration uses the same source, placement and mode inputs as the connected network.".
-type boundary() :: network().

-doc "One whole native application and its framed host endpoint. Native partition selection is unsupported; source control must be a rectangle and activation must be explicit.".
-type application() :: #{?SOURCE_FIELDS, device := device(), host := endpoint(),
    arithmetic_groups => [[hls_protocol_topology:id(), ...]],
    control => rectangle, activation => explicit_start, inspection => inspection()}.

-doc "One native actor partition with framed crossings and host/service endpoints. Crossing, control and external-stream requirements are validated against the selected source graph.".
-type bridge() :: #{?SOURCE_FIELDS, ?BRIDGE_FIELDS}.

-doc "One device's exact native ownership and distinct return endpoints. The deployment must cover all actors once and use distinct endpoint pairs.".
-type role() :: #{native_actors := [hls_protocol_topology:id(), ...],
    host := endpoint(), service := endpoint()}.

-doc "Positive deployment queue bounds; events must be at least two and crossings must cover every checked cross-role route.".
-type limits() :: #{crossings := pos_integer(), commands := pos_integer(), events := pos_integer()}.

-doc "A complete multi-device source deployment. At least two disjoint roles are required; all roles share source, control, retirement and reset policy.".
-type deployment() :: #{?SOURCE_FIELDS, devices := #{device() => role()}, limits := limits(),
    control := rectangle, activation => explicit_start, inspection => none,
    arithmetic_groups => [[hls_protocol_topology:id(), ...]]}.

-doc "A framed native partition whose complementary source actors run in BEAM. Uses bridge inputs; each host output must have one recipient and no BEAM-to-BEAM route.".
-type mixed() :: bridge().

-doc "The closed union of supported source-build maps. Select the intended kind before validation; the union does not certify that source, placement or capability constraints hold.".
-type config() :: transport() | network() | boundary() | application() | bridge() | deployment() | mixed().


-doc "Consults exactly one map from a trusted Erlang terms file. Reports syntax errors with the filename and line. Source/include paths remain relative to the caller; loading neither changes directory nor executes constructors.".
-spec read(file:filename()) -> map().
read(Filename) ->
    Context = #{config_file => unicode:characters_to_binary(filename:absname(Filename))},
    case file:consult(Filename) of
        {ok, [Config]} when is_map(Config) -> Config;
        {ok, _} -> hls_diagnostic:raise(configuration, invalid_config_file,
            <<"Configuration must contain exactly one Erlang map.">>, Context);
        {error, {Line, Module, Reason}} ->
            hls_diagnostic:raise(configuration, config_syntax,
                unicode:characters_to_binary(Module:format_error(Reason)), Context#{line => Line});
        {error, Reason} -> hls_diagnostic:raise(configuration, config_read,
            unicode:characters_to_binary(file:format_error(Reason)), Context)
    end.

-doc "Checks the selected build kind's required/optional fields and scalar bounds before source compilation. Reports exact nested key paths; constructors and provider options remain trusted application values. Does not establish ownership, source compatibility or protocol progress.".
-spec validate(hls_source_build:kind(), term()) -> config().
validate(Kind, Config) ->
    {Required, Optional} = fields(Kind),
    object(Config, Required, Optional, []),
    lists:foreach(fun({Key, Value}) -> field(Key, Value, [Key]) end, lists:sort(maps:to_list(Config))),
    Config.

%% Keep allowed keys next to their owning public types; do not accept misspelled or ignored options.
-spec fields(hls_source_build:kind()) -> {[atom()], [atom()]}.
fields(Kind) ->
    Source = [sources, topology, actor_limit],
    Optional = [protocol_model, dslx_path, arithmetic_groups],
    case Kind of
        transport -> {Source, Optional ++ [native_actors]};
        K when K =:= network; K =:= boundary ->
            {Source, Optional ++ [native_actors, activation, inspection, control]};
        application -> {Source ++ [device, host], Optional ++ [control, activation, inspection]};
        K when K =:= bridge; K =:= mixed ->
            {Source ++ [native_actors, host, service, control], Optional ++ [activation, inspection]};
        deployment -> {Source ++ [devices, limits, control], Optional ++ [activation, inspection]}
    end.

%% Check maps before destructuring so malformed terms get configuration errors, not badmap.
-spec object(term(), [atom()], [atom()], [term()]) -> ok.
object(Value, Required, Optional, Path) ->
    need(is_map(Value), Path, <<"map">>, Value),
    lists:foreach(fun(Key) ->
        case maps:is_key(Key, Value) of
            true -> ok;
            false -> hls_diagnostic:raise(configuration, missing_config_field,
                <<"Required configuration field is missing.">>, #{field => Path ++ [Key]})
        end
    end, Required),
    case maps:keys(Value) -- (Required ++ Optional) of
        [] -> ok;
        Unknown -> hls_diagnostic:raise(configuration, unknown_config_fields,
            <<"Configuration contains unsupported fields.">>, #{field => Path, value => lists:sort(Unknown)})
    end.

%% Values cross an untyped terms-file/API boundary here; semantic checks stay with the owning pass.
-spec field(atom(), term(), [term()]) -> ok.
field(sources, Value, Path) ->
    need(proper_list(Value) andalso Value =/= [], Path, <<"nonempty list of {filename, compiler_options}">>, Value),
    lists:foreach(fun({Index, Source}) ->
        case Source of
            {File, Options} ->
                need(proper_list(Options), Path ++ [Index], <<"compiler option list">>, Options),
                need(filename(File), Path ++ [Index], <<"filename">>, File);
            _ -> invalid(Path ++ [Index], <<"{filename, compiler_options}">>, Source)
        end
    end, lists:enumerate(0, Value));
field(topology, Value, Path) ->
    Valid = case Value of
        {Module, Function, Arguments} when is_atom(Module), is_atom(Function) -> proper_list(Arguments);
        _ -> false
    end,
    need(Valid, Path, <<"{module, function, argument_list}">>, Value);
field(actor_limit, Value, Path) ->
    need(is_integer(Value) andalso Value >= 1 andalso Value =< 65536, Path, <<"integer in 1..65536">>, Value);
field(dslx_path, Value, Path) ->
    need(proper_list(Value), Path, <<"list of import directories">>, Value),
    lists:foreach(fun({Index, File}) ->
        need(filename(File), Path ++ [Index], <<"filename">>, File)
    end, lists:enumerate(0, Value));
field(protocol_model, Value, Path) ->
    Valid = case Value of none -> true; {Module, _} when is_atom(Module) -> true; _ -> false end,
    need(Valid, Path, <<"none or {provider_module, options}">>, Value);
field(native_actors, Value, Path) ->
    need(proper_list(Value) andalso Value =/= [], Path, <<"nonempty list of actor IDs">>, Value);
field(arithmetic_groups, Value, Path) ->
    need(proper_list(Value), Path, <<"list of actor groups">>, Value),
    lists:foreach(fun({Index, Group}) ->
        need(proper_list(Group) andalso Group =/= [], Path ++ [Index], <<"nonempty list of actor IDs">>, Group)
    end, lists:enumerate(0, Value));
field(Key, Value, Path) when Key =:= host; Key =:= service ->
    need(is_integer(Value) andalso Value > 0 andalso Value < 65536, Path, <<"integer in 1..65535">>, Value);
field(activation, Value, Path) ->
    need(Value =:= automatic orelse Value =:= explicit_start, Path, <<"automatic or explicit_start">>, Value);
field(inspection, Value, Path) ->
    need(Value =:= none orelse Value =:= process, Path, <<"none or process">>, Value);
field(control, Value, Path) -> need(Value =:= rectangle, Path, <<"rectangle">>, Value);
field(device, _, _) -> ok;
field(devices, Value, Path) ->
    need(is_map(Value) andalso map_size(Value) >= 2, Path, <<"map with at least two device roles">>, Value),
    lists:foreach(fun({Device, Role}) ->
        RolePath = Path ++ [Device],
        hls_diagnostic:with_context(#{role => Device}, fun() ->
            object(Role, [native_actors, host, service], [], RolePath),
            lists:foreach(fun({Key, V}) -> field(Key, V, RolePath ++ [Key]) end, lists:sort(maps:to_list(Role)))
        end)
    end, lists:sort(maps:to_list(Value)));
field(limits, Value, Path) ->
    object(Value, [crossings, commands, events], [], Path),
    lists:foreach(fun({Key, V}) ->
        Min = case Key of events -> 2; _ -> 1 end,
        need(is_integer(V) andalso V >= Min, Path ++ [Key],
            iolist_to_binary(["integer >= ", integer_to_list(Min)]), V)
    end, lists:sort(maps:to_list(Value))).

%% List-shaped input must have a proper tail before enumeration or constructor application.
-spec proper_list(term()) -> boolean().
proper_list([]) -> true;
proper_list([_ | Rest]) -> proper_list(Rest);
proper_list(_) -> false.

%% Erlang filenames are text; arbitrary binaries and improper lists must not reach file APIs.
-spec filename(term()) -> boolean().
filename(Value) when is_binary(Value) ->
    case unicode:characters_to_binary(Value) of
        Text when is_binary(Text), byte_size(Text) > 0 -> binary:match(Text, <<0>>) =:= nomatch;
        _ -> false
    end;
filename([_ | _] = Value) -> filename_characters(Value);
filename(_) -> false.

%% File APIs need a flat Unicode charlist; reject nested iodata, improper tails and NUL.
-spec filename_characters(term()) -> boolean().
filename_characters([]) -> true;
filename_characters([Char | Rest]) when is_integer(Char), Char > 0, Char =< 16#10ffff,
        (Char < 16#d800 orelse Char > 16#dfff) -> filename_characters(Rest);
filename_characters(_) -> false.

%% This helper is used only at the untyped configuration boundary, never to mask compiler bugs.
-spec need(boolean(), [term()], binary(), term()) -> ok.
need(true, _, _, _) -> ok;
need(false, Path, Expected, Value) -> invalid(Path, Expected, Value).

%% Known invalid alternatives use no_return directly; checks returning ok retain boolean guards.
-spec invalid([term()], binary(), term()) -> no_return().
invalid(Path, Expected, Value) ->
    hls_diagnostic:raise(configuration, invalid_config_field,
        <<"Configuration field has an invalid value.">>, #{field => Path, expected => Expected, value => Value}).
