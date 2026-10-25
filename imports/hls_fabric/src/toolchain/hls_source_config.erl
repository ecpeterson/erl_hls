-module(hls_source_config).
-moduledoc "Source-build configuration contracts and trusted terms-file loading. Each builder owns validation of its selected configuration; read/1 does not turn an arbitrary map into a checked config.".
-export([read/1]).
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


-doc "Consults exactly one map from a trusted Erlang terms file. Source and include paths remain relative to the caller's working directory; this function neither changes directory nor evaluates constructors.".
-spec read(file:filename()) -> map().
read(Filename) ->
    case file:consult(Filename) of
        {ok, [Config]} when is_map(Config) -> Config;
        {ok, _} -> error({invalid_source_config, Filename});
        {error, Reason} -> error({source_config, Filename, Reason})
    end.
