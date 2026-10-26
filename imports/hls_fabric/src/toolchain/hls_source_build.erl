-module(hls_source_build).
-moduledoc "Source-only HLS build boundary. Packages generated DSLX and its libraries for independently invoked external tools.".
-export([plan/2, descriptor/1, inspect/2, write/2, write/3]).
-export_type([kind/0, plan/0, descriptor/0, manifest/0, inspection_stage/0, inspection/0]).

-doc "The supported source-derived hardware boundaries; selection is explicit and does not change application semantics.".
-type kind() :: transport | network | boundary | application | bridge | deployment | mixed.

%% Each selected stage retains its own checked constructor result, never a universal input map.
-type stage_plan() :: hls_protocol_transport:build() | hls_protocol_network:plan() |
    hls_protocol_boundary:plan() | hls_protocol_application:plan() | hls_protocol_bridge:plan() |
    hls_protocol_deployment:plan() | hls_protocol_mixed:plan().
%% Packaging retains the original config for inspection, but does not rerun it during write.
-record(plan, {kind :: kind(), config :: hls_source_config:config(), stage :: stage_plan(),
    cwd :: file:filename(), libraries :: [hls_artifact_bundle:library()],
    units :: [hls_artifact_bundle:unit()], profile :: hls_build_profile:profile()}).

-doc "Read-only views of a checked build. Views inspect retained source and layout data; none resumes a build from serialized data.".
-type inspection_stage() :: summary | configuration | source | topology | placement | composition | schedule | profile.

-doc "A versioned inspection report. Data is an Erlang term; hls_diagnostic:json_value/1 preserves non-JSON shapes using explicit tags for display, never as executable plan input.".
-type inspection() :: #{version := 1, kind := kind(), stage := inspection_stage(), data := term()}.


-doc "One complete checked source composition selected by plan/2. Keep it unchanged in process with its source codecs loaded. Provider/support files are read during packaging, so this is not a saved or hermetic external-tool input.".
-opaque plan() :: #plan{}.

-doc "The selected kind, its read-only static builder descriptor and provider import paths. Generated-byte identities and support snapshots belong to the written bundle; inspect/2 exposes the retained external-tool schedules.".
-type descriptor() ::
    #{kind := transport, build := hls_protocol_transport:descriptor(), dslx_path := [file:filename()]} |
    #{kind := network, build := hls_protocol_network:descriptor(), dslx_path := [file:filename()]} |
    #{kind := boundary, build := hls_protocol_boundary:descriptor(), dslx_path := [file:filename()]} |
    #{kind := application, build := hls_protocol_application:descriptor(), dslx_path := [file:filename()]} |
    #{kind := bridge, build := hls_protocol_bridge:descriptor(), dslx_path := [file:filename()]} |
    #{kind := deployment, build := hls_protocol_deployment:descriptor(), dslx_path := [file:filename()]} |
    #{kind := mixed, build := hls_protocol_mixed:descriptor(), dslx_path := [file:filename()]}.

-doc "The compiler-owned source bundle format with this builder's kind metadata. Unit schedules use hls_artifact_bundle's shared contract; inputs bind every packaged file and RTL lists are grouped by role.".
-type manifest() :: #{version := 1, metadata := #{kind := kind(), backend := source_protocol, profile := hls_diagnostic:json_value()},
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
    hls_diagnostic:with_context(#{kind => Kind}, fun() ->
        _ = builder(Kind),
        Checked = hls_source_config:validate(Kind, Config),
        Profile = hls_build_profile:protocol(Kind, Checked),
        Imports = maps:get(dslx_path, Checked, []),
        lists:foreach(fun import_directory/1, Imports),
        Stage = stage_plan(Kind, maps:remove(dslx_path, Checked)),
        #{libraries := Libraries, imports := Support} = hls_build_support:layout(Imports),
        Builder = builder(Kind),
        Roles = case Kind of
            deployment ->
                #{directories := Directories} = Builder:descriptor(Stage),
                [{bridge, Name} || Name <- lists:sort(maps:values(Directories))];
            _ -> [{Kind, "."}]
        end,
        {ok, Cwd} = file:get_cwd(),
        #plan{kind = Kind, config = Checked, stage = Stage, cwd = Cwd, libraries = Libraries,
            units = lists:append([units(K, Role, Checked, Support, Profile) || {K, Role} <- Roles]),
            profile = Profile}
    end);
plan(Kind, Filename) ->
    hls_diagnostic:with_context(#{kind => Kind, config_file => text(filename:absname(Filename))},
        fun() -> plan(Kind, hls_source_config:read(Filename)) end).

-doc "Returns the complete static composition and provider import locations. Inspect this value without an output directory; the descriptor grants neither artifact freshness after mutation nor device admission.".
-spec descriptor(plan()) -> descriptor().
descriptor(#plan{kind = Kind, config = Config, stage = Stage}) ->
    Builder = builder(Kind),
    #{kind => Kind, build => Builder:descriptor(Stage), dslx_path => maps:get(dslx_path, Config, [])}.

-doc "Inspects a retained build without source recompilation, rendering, output files or external tools. Source, topology and placement views are indexed by role (whole for an unpartitioned build); configuration includes resolved library locations. Composition includes role-indexed transport transitions and, for a network build, its named clock phases. Schedule uses the exact retained units later written to source-build.json. Reports are diagnostic data, not portable executable plans.".
-spec inspect(plan(), inspection_stage()) -> inspection().
inspect(Plan = #plan{kind = Kind}, Stage) ->
    #{version => 1, kind => Kind, stage => Stage, data => inspection_data(Plan, Stage)}.

%% Keep each report at its owning abstraction instead of printing opaque compiler records.
-spec inspection_data(plan(), inspection_stage()) -> term().
inspection_data(#plan{kind = Kind, config = Config, units = Units}, summary) ->
    #{kind => Kind, sources => length(maps:get(sources, Config)), compilation_units => length(Units),
      roles => lists:usort([maps:get(role, U) || U <- Units]),
      inspection => maps:get(inspection, Config, none), eligible => false, native_measured => false};
inspection_data(#plan{config = Config, cwd = Cwd, libraries = Libraries}, configuration) ->
    #{config => Config, working_directory => text(Cwd),
      compiler => text(code:lib_dir(erl_hls)), fabric => text(code:lib_dir(hls_fabric)),
      libraries => [#{source => text(Source), destination => text(Target), extensions => [text(E) || E <- Extensions]}
          || {Source, Target, Extensions} <- Libraries]};
inspection_data(#plan{units = Units}, schedule) -> Units;
inspection_data(#plan{profile = Profile}, profile) -> Profile;
inspection_data(Plan = #plan{kind = Kind, stage = Stage}, composition) ->
    Descriptor = case descriptor(Plan) of
        D = #{kind := transport, build := Transport} -> D#{build := transport_report(Transport)};
        D -> D
    end,
    Transitions = maps:map(fun(_, Transport) ->
        maps:get(transition, hls_protocol_transport:descriptor(Transport)) end, transports(Plan)),
    Report = Descriptor#{transport_transitions => Transitions},
    case Kind of
        network -> Report#{network_phases => hls_protocol_network:phases(Stage)};
        _ -> Report
    end;
inspection_data(Plan, Stage) when Stage =:= source; Stage =:= topology; Stage =:= placement ->
    maps:map(fun(_, Transport) -> transport_view(Transport, Stage) end, transports(Plan)).

%% All higher composition plans expose their same retained transport; no constructor is called twice.
-spec transports(plan()) -> #{term() => hls_protocol_transport:build()}.
transports(#plan{kind = deployment, stage = Stage}) -> hls_protocol_deployment:transports(Stage);
transports(#plan{kind = transport, stage = Stage}) -> #{whole => Stage};
transports(#plan{kind = Kind, stage = Stage}) ->
    Builder = builder(Kind),
    #{whole => Builder:transport(Stage)}.

%% Public source descriptors retain provenance and interfaces without exposing executable plan records.
-spec transport_view(hls_protocol_transport:build(), source | topology | placement) -> term().
transport_view(Transport, View) ->
    D = #{bundle := #{topology := Topology, modules := Modules, inventory := Inventory}} =
        hls_protocol_transport:descriptor(Transport),
    case View of
        source -> #{modules => maps:map(fun(_, Source) -> hls_local_actor:descriptor(Source) end, Modules),
            inventory => Inventory};
        topology -> Topology;
        placement -> maps:without([bundle], D)
    end.

%% The transport composition has source snapshots; substitute their public reporting descriptors.
-spec transport_report(hls_protocol_transport:descriptor()) -> map().
transport_report(Transport = #{bundle := Bundle = #{modules := Modules}}) ->
    Transport#{bundle := Bundle#{modules := maps:map(fun(_, Source) ->
        hls_local_actor:descriptor(Source) end, Modules)}}.

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
write(#plan{kind = Kind, config = Config, stage = Stage, libraries = Libraries, units = Units, profile = Profile}, Output) ->
    Builder = builder(Kind),
    Directory = filename:absname(Output),
    case file:read_link_info(Directory) of
        {error, enoent} -> ok;
        {ok, _} -> hls_diagnostic:raise(packaging, output_exists,
            <<"Output must be a fresh path; existing output is retained.">>, #{output => text(Directory)});
        {error, Reason} -> hls_diagnostic:raise(packaging, output_unavailable,
            unicode:characters_to_binary(file:format_error(Reason)), #{output => text(Directory)})
    end,
    _ = hls_generated_files:write(Builder:emit(Stage), Directory),
    ok = file:write_file(filename:join(Directory, "config.erl"), io_lib:format("~tp.~n", [Config]), [exclusive]),
    ok = hls_artifact_bundle:snapshot(Directory, Libraries),
    hls_artifact_bundle:finish(Directory, Units, #{kind => Kind, backend => source_protocol, profile => hls_diagnostic:json_value(Profile)}).

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
    case filelib:is_dir(Path) of
        true -> ok;
        false -> hls_diagnostic:raise(configuration, missing_dslx_directory,
            <<"DSLX import directory does not exist.">>, #{field => [dslx_path], path => text(Path)})
    end.

%% Schedules describe existing clock owners, not target-frequency optimization requests.
-spec units(kind(), string(), hls_source_config:config(), [string()], hls_build_profile:profile()) -> [hls_artifact_bundle:unit()].
units(application, Role, Config, Support, Profile) ->
    Boundary = units(boundary, Role, Config, Support, Profile),
    Debug = case maps:get(inspection, Config, none) of
        none -> [];
        process -> ["support/compiler/rtl/debug/" ++ Name
            || Name <- ["hls_debug_route.v", "hls_debug_frame_rx.v", "hls_topology_debug.v"]]
    end,
    Gateway = unit(Role, "application", "gateway.x", "Top", "application_gateway", "gateway.v",
        [join(Role, "application"), "support/fabric/xls" | Support],
        hls_build_profile:flags(Profile, gateway),
        [join(Role, "application/protocol_application_top.sv"), "support/fabric/rtl/hls_partition_activation.sv"] ++ Debug),
    Boundary ++ [Gateway];
units(mixed, Role, Config, Support, Profile) -> units(bridge, Role, Config, Support, Profile);
units(Kind, Role, _, Support, Profile) ->
    {Stage, File, Top, Module, Adapter, ImportDirs} = case Kind of
        transport -> {"dslx", "transport.x", "protocol_clock", "protocol_fabric_core", "protocol_fabric.sv", ["dslx"]};
        network -> {"network", "network.x", "network_clock", "protocol_network_core", "protocol_network.sv", ["network", "actors", "dslx"]};
        boundary -> {"boundary", "boundary.x", "boundary_clock", "protocol_boundary_core", "protocol_boundary.sv", ["network", "actors", "dslx"]};
        bridge -> {"bridge", "bridge.x", "bridge_clock", "protocol_bridge_core", "protocol_bridge_top.sv", ["boundary", "network", "actors", "dslx"]}
    end,
    [unit(Role, Stage, File, Top, Module, "core.v", [join(Role, P) || P <- ImportDirs] ++ Support,
        hls_build_profile:flags(Profile, sampled_clock), [join(Role, filename:join(Stage, Adapter))])].

%% Relative paths make emitted bundles movable before invoking any external tool.
-spec unit(string(), string(), string(), string(), string(), string(), [string()], [binary()], [string()]) -> hls_artifact_bundle:unit().
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
-spec text(unicode:chardata()) -> binary().
text(Value) -> unicode:characters_to_binary(Value).
