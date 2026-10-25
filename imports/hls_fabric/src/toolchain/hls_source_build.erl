-module(hls_source_build).
-moduledoc "Source-only HLS build boundary. Packages generated DSLX and its libraries for independently invoked external tools.".
-export([plan/2, descriptor/1, write/2, write/3]).
-export_type([kind/0, plan/0, descriptor/0, manifest/0]).

-doc "The supported source-derived hardware boundaries; selection is explicit and does not change application semantics.".
-type kind() :: transport | network | boundary | application | bridge | deployment | mixed.

%% Each selected stage retains its own checked constructor result, never a universal input map.
-type stage_plan() :: hls_protocol_transport:build() | hls_protocol_network:plan() |
    hls_protocol_boundary:plan() | hls_protocol_application:plan() | hls_protocol_bridge:plan() |
    hls_protocol_deployment:plan() | hls_protocol_mixed:plan().
%% Packaging retains the original config for inspection, but does not rerun it during write.
-record(plan, {kind :: kind(), config :: hls_source_config:config(), stage :: stage_plan()}).

-doc "One complete checked source composition selected by plan/2. Keep it unchanged in process with its source codecs loaded. Provider/support files are read during packaging, so this is not a saved or hermetic external-tool input.".
-opaque plan() :: #plan{}.

-doc "The selected kind, its read-only static builder descriptor and provider import paths. Generated-byte identities, support snapshots and external-tool schedules belong to the written bundle.".
-type descriptor() ::
    #{kind := transport, build := hls_protocol_transport:descriptor(), dslx_path := [file:filename()]} |
    #{kind := network, build := hls_protocol_network:descriptor(), dslx_path := [file:filename()]} |
    #{kind := boundary, build := hls_protocol_boundary:descriptor(), dslx_path := [file:filename()]} |
    #{kind := application, build := hls_protocol_application:descriptor(), dslx_path := [file:filename()]} |
    #{kind := bridge, build := hls_protocol_bridge:descriptor(), dslx_path := [file:filename()]} |
    #{kind := deployment, build := hls_protocol_deployment:descriptor(), dslx_path := [file:filename()]} |
    #{kind := mixed, build := hls_protocol_mixed:descriptor(), dslx_path := [file:filename()]}.

-doc "The compiler-owned source bundle format with this builder's kind metadata. Unit schedules use hls_artifact_bundle's shared contract; inputs bind every packaged file and RTL lists are grouped by role.".
-type manifest() :: #{version := 1, metadata := #{kind := kind()},
    units := [hls_artifact_bundle:unit()], rtl := #{binary() => [binary()]},
    inputs := [#{file := binary(), sha256 := binary()}], eligible := false, native_measured := false}.

-doc "Checks a source composition without rendering or creating an output directory. Accepts a trusted config map or filename and validates optional dslx_path directories before source preparation. The selected builder owns placement, layout and host-binding checks; trusted source constructors may have effects. Paths are relative to the caller.".
-spec plan(transport, hls_source_config:transport() | file:filename()) -> plan();
    (network, hls_source_config:network() | file:filename()) -> plan();
    (boundary, hls_source_config:boundary() | file:filename()) -> plan();
    (application, hls_source_config:application() | file:filename()) -> plan();
    (bridge, hls_source_config:bridge() | file:filename()) -> plan();
    (deployment, hls_source_config:deployment() | file:filename()) -> plan();
    (mixed, hls_source_config:mixed() | file:filename()) -> plan().
plan(Kind, Config) when is_map(Config) ->
    _ = builder(Kind),
    lists:foreach(fun import_directory/1, maps:get(dslx_path, Config, [])),
    #plan{kind = Kind, config = Config, stage = stage_plan(Kind, maps:remove(dslx_path, Config))};
plan(Kind, Filename) -> plan(Kind, hls_source_config:read(Filename)).

-doc "Returns the complete static composition and provider import locations. Inspect this value without an output directory; the descriptor grants neither artifact freshness after mutation nor device admission.".
-spec descriptor(plan()) -> descriptor().
descriptor(#plan{kind = Kind, config = Config, stage = Stage}) ->
    Builder = builder(Kind),
    #{kind => Kind, build => Builder:descriptor(Stage), dslx_path => maps:get(dslx_path, Config, [])}.

-doc "Plans the selected source boundary, then writes and packages it with write/2. A config filename is consulted as one trusted map; existing output is never replaced. XLS, simulation, synthesis and timing remain separate.".
-spec write(transport, hls_source_config:transport() | file:filename(), file:filename()) -> manifest();
    (network, hls_source_config:network() | file:filename(), file:filename()) -> manifest();
    (boundary, hls_source_config:boundary() | file:filename(), file:filename()) -> manifest();
    (application, hls_source_config:application() | file:filename(), file:filename()) -> manifest();
    (bridge, hls_source_config:bridge() | file:filename(), file:filename()) -> manifest();
    (deployment, hls_source_config:deployment() | file:filename(), file:filename()) -> manifest();
    (mixed, hls_source_config:mixed() | file:filename(), file:filename()) -> manifest().
write(Kind, Config, Output) -> write(plan(Kind, Config), Output).

-doc "Renders a retained checked composition into a fresh directory without recompiling source or repeating layout/host checks. Copies provider and resolved compiler/fabric support trees, records config.erl and writes source-build.json with relative input hashes, entry points, schedules and RTL lists. Packaging reads support files at write time; I/O failures retain partial output. The resulting manifest is a trusted build record, not executable commands or admission.".
-spec write(plan(), file:filename()) -> manifest().
write(#plan{kind = Kind, config = Config, stage = Stage}, Output) ->
    Builder = builder(Kind),
    Imports = maps:get(dslx_path, Config, []),
    Directory = filename:absname(Output),
    case file:read_link_info(Directory) of
        {error, enoent} -> ok;
        {ok, _} -> error({source_output_exists, Directory});
        {error, Reason} -> error({source_output, Directory, Reason})
    end,
    Result = hls_generated_files:write(Builder:emit(Stage), Directory),
    ok = file:write_file(filename:join(Directory, "config.erl"), io_lib:format("~tp.~n", [Config]), [exclusive]),
    Support = support(Directory, Imports),
    Roles = case Kind of
        deployment -> [{bridge, Name} || Name <- lists:sort(maps:values(maps:get(directories, Result)))];
        _ -> [{Kind, "."}]
    end,
    Units = lists:append([units(K, Role, Config, Support) || {K, Role} <- Roles]),
    hls_artifact_bundle:finish(Directory, Units, #{kind => Kind}).

%% Low-level compositions share the ordinary source planner; complete application builders own theirs.
-spec stage_plan(kind(), hls_source_config:config()) -> stage_plan().
stage_plan(network, Config) ->
    hls_protocol_network:plan(hls_protocol_transport:plan(Config), maps:with([activation, inspection], Config));
stage_plan(boundary, Config) ->
    hls_protocol_boundary:plan(hls_protocol_transport:plan(Config), maps:with([activation, inspection], Config));
stage_plan(bridge, Config = #{native_actors := _}) ->
    hls_protocol_bridge:plan(hls_protocol_transport:plan(Config),
        maps:with([host, service, control, activation, inspection], Config));
stage_plan(Kind, Config) when Kind =:= transport; Kind =:= application; Kind =:= deployment; Kind =:= mixed ->
    Builder = builder(Kind), Builder:plan(Config).

%% Choose only known emitters, before creating any output.
-spec builder(kind()) -> module().
builder(transport) -> hls_protocol_transport;
builder(network) -> hls_protocol_network;
builder(boundary) -> hls_protocol_boundary;
builder(application) -> hls_protocol_application;
builder(bridge) -> hls_protocol_bridge;
builder(deployment) -> hls_protocol_deployment;
builder(mixed) -> hls_protocol_mixed;
builder(Other) -> error({unknown_source_builder, Other}).

%% Missing user import directories must not silently produce an incomplete bundle.
-spec import_directory(file:filename()) -> ok.
import_directory(Path) ->
    case filelib:is_dir(Path) of true -> ok; false -> error({missing_dslx_directory, Path}) end.

%% Snapshot support inputs so external compilation needs neither this checkout nor rebar.
-spec support(file:filename(), [file:filename()]) -> [string()].
support(Output, Imports) ->
    CompilerPaths = hls_compile:support(Output, Imports),
    Fabric = code:priv_dir(hls_fabric),
    hls_artifact_bundle:snapshot(Output,
        [{filename:join(Fabric, "xls"), "support/fabric/xls", [".x"]},
         {filename:join(Fabric, "rtl"), "support/fabric/rtl", [".v", ".sv"]}]),
    Paths = ["support/fabric/xls/lib", "support/fabric/xls/fabric"],
    [P || P <- Paths, filelib:is_dir(filename:join(Output, P))] ++
        [unicode:characters_to_list(P) || P <- CompilerPaths].

%% Schedules describe existing clock owners, not target-frequency optimization requests.
-spec units(kind(), string(), hls_source_config:config(), [string()]) -> [hls_artifact_bundle:unit()].
units(application, Role, Config, Support) ->
    Boundary = units(boundary, Role, Config, Support),
    Debug = case maps:get(inspection, Config, none) of
        none -> [];
        process -> ["support/compiler/rtl/debug/" ++ Name
            || Name <- ["hls_debug_route.v", "hls_debug_frame_rx.v", "hls_topology_debug.v"]]
    end,
    Gateway = unit(Role, "application", "gateway.x", "Top", "application_gateway", "gateway.v",
        [join(Role, "application"), "support/fabric/xls" | Support],
        ["--pipeline_stages=2", "--delay_model=unit", "--flop_inputs=false", "--flop_outputs=true",
         "--use_system_verilog=false", "--reset=reset", "--fifo_module="],
        [join(Role, "application/protocol_application_top.sv"), "support/fabric/rtl/hls_partition_activation.sv"] ++ Debug),
    Boundary ++ [Gateway];
units(mixed, Role, Config, Support) -> units(bridge, Role, Config, Support);
units(Kind, Role, _, Support) ->
    {Stage, File, Top, Module, Adapter, ImportDirs} = case Kind of
        transport -> {"dslx", "transport.x", "protocol_clock", "protocol_fabric_core", "protocol_fabric.sv", ["dslx"]};
        network -> {"network", "network.x", "network_clock", "protocol_network_core", "protocol_network.sv", ["network", "actors", "dslx"]};
        boundary -> {"boundary", "boundary.x", "boundary_clock", "protocol_boundary_core", "protocol_boundary.sv", ["network", "actors", "dslx"]};
        bridge -> {"bridge", "bridge.x", "bridge_clock", "protocol_bridge_core", "protocol_bridge_top.sv", ["boundary", "network", "actors", "dslx"]}
    end,
    [unit(Role, Stage, File, Top, Module, "core.v", [join(Role, P) || P <- ImportDirs] ++ Support,
        ["--pipeline_stages=1", "--delay_model=unit", "--flop_inputs=false", "--flop_outputs=false",
         "--use_system_verilog=false", "--reset=reset"], [join(Role, filename:join(Stage, Adapter))])].

%% Relative paths make emitted bundles movable before invoking any external tool.
-spec unit(string(), string(), string(), string(), string(), string(), [string()], [string()], [string()]) -> hls_artifact_bundle:unit().
unit(Role, Stage, Source, Top, Module, Product, Imports, Flags, Rtl) ->
    Directory = join(Role, Stage), Output = filename:join(Directory, Product),
    #{role => text(Role), directory => text(Directory), source => text(filename:join(Directory, Source)),
      top => text(Top), module => text(Module), output => text(Output),
      dslx_path => [text(P) || P <- Imports], codegen_flags => [text(F) || F <- Flags],
      rtl => [text(P) || P <- [Output | Rtl]]}.

%% Avoid redundant ./ prefixes in manifest identities.
-spec join(string(), string()) -> string().
join(".", Path) -> Path;
join(Directory, Path) -> filename:join(Directory, Path).

%% JSON strings are UTF-8 binaries, not Erlang character lists.
-spec text(string()) -> binary().
text(Value) -> unicode:characters_to_binary(Value).
