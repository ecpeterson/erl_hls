-module(hls_source_build).
-moduledoc "Source-only HLS build boundary. Packages generated DSLX and its libraries for independently invoked external tools.".
-export([write/3]).
-export_type([kind/0]).

-doc "The supported source-derived hardware boundaries; selection is explicit and does not change application semantics.".
-type kind() :: transport | network | boundary | application | bridge | deployment | mixed.

-doc "Calls the selected source builder with a trusted configuration map or filename and a fresh output directory. A filename is consulted as one map and follows the same build path. Optional dslx_path lists provider import directories; all .x files in those directories and the resolved applications' DSLX/RTL support trees are copied into the output. Writes source-build.json with relative input hashes, entry points, required schedules and RTL lists. Config paths are relative to the caller's working directory. The manifest is a trusted build record, not executable commands or admission; XLS, simulation, synthesis and timing remain separate. Partial output is retained on failure; existing output is never replaced.".
-spec write(kind(), map() | file:filename(), file:filename()) -> map().
write(Kind, Config, Output) when is_map(Config) ->
    Builder = builder(Kind),
    Imports = maps:get(dslx_path, Config, []),
    lists:foreach(fun import_directory/1, Imports),
    Directory = filename:absname(Output),
    case file:read_link_info(Directory) of
        {error, enoent} -> ok;
        {ok, _} -> error({source_output_exists, Directory});
        {error, Reason} -> error({source_output, Directory, Reason})
    end,
    Result = Builder:write(maps:remove(dslx_path, Config), Directory),
    ok = file:write_file(filename:join(Directory, "config.erl"), io_lib:format("~tp.~n", [Config]), [exclusive]),
    Support = support(Directory, Imports),
    Roles = case Kind of
        deployment -> [{bridge, Name} || Name <- lists:sort(maps:values(maps:get(directories, Result)))];
        _ -> [{Kind, "."}]
    end,
    Units = lists:append([units(K, Role, Config, Support) || {K, Role} <- Roles]),
    hls_artifact_bundle:finish(Directory, Units, #{kind => Kind});
write(Kind, Filename, Output) -> write(Kind, hls_source_config:read(Filename), Output).

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
-spec units(kind(), string(), map(), [string()]) -> [hls_artifact_bundle:unit()].
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
