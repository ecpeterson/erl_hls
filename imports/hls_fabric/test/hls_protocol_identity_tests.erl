-module(hls_protocol_identity_tests).
-moduledoc "Fresh source builds preserve attachment identity across process-local provenance and relocation. These are build-contract checks, not hardware or source-refinement proofs.".
-include_lib("eunit/include/eunit.hrl").

%% Repeated tiny builds exercise the real compiler, host binding and inspection catalog.
-spec application_identity_test_() -> term().
application_identity_test_() -> {timeout, 120, fun application_identity/0}.

%% Identity follows the source/wire contract while retaining typed external IDs.
-spec application_identity() -> ok.
application_identity() ->
    Config = application_config("test"),
    First = hls_protocol_application:emit(Config),
    Second = hls_protocol_application:emit(Config),
    Identity = application_identity(First, board),
    ?assertEqual(32, byte_size(Identity)),
    ?assertEqual(Identity, application_identity(Second, board)),
    Fingerprint = inspection_fingerprint(First),
    ?assertEqual(Fingerprint, inspection_fingerprint(Second)),
    #{result := #{devices := #{board := #{events := Events}}}} = First,
    ?assertEqual([3, '3', {bucket, 1}], [Id || {_, #{id := Id}} <- lists:sort(maps:to_list(Events))]),
    Host = hls_protocol_application:emit(Config#{host := 20}),
    Device = hls_protocol_application:emit(Config#{device := other_board}),
    Uninspected = hls_protocol_application:emit(Config#{inspection := none}),
    Startup = hls_protocol_application:emit(Config#{topology := {hls_protocol_identity_fixture, topology, [changed_startup]}}),
    lists:foreach(fun(Changed) -> ?assertNotEqual(Identity, Changed) end,
        [application_identity(Host, board), application_identity(Device, other_board),
         application_identity(Uninspected, board), application_identity(Startup, board)]),
    ?assertEqual(Fingerprint, inspection_fingerprint(Host)),
    ?assertEqual(Fingerprint, inspection_fingerprint(Device)),
    ok = relocated_source(Config, First),
    ok.

%% A whole source/include tree can move; changing an initial state value must still invalidate attachment.
-spec relocated_source(map(), hls_generated_files:output()) -> ok.
relocated_source(Config, Original) ->
    Root = filename:join("_build", "identity-relocation-" ++ integer_to_list(erlang:system_time(nanosecond))),
    ok = file:make_dir(Root),
    Files = ["hls_protocol_boundary_fixture.erl", "hls_protocol_identity_fixture.erl",
        "hls_protocol_identity_fixture.hrl"],
    lists:foreach(fun(File) ->
        {ok, _} = file:copy(filename:join("test", File), filename:join(Root, File))
    end, Files),
    RelocatedConfig = Config#{sources := maps:get(sources, application_config(Root))},
    Relocated = hls_protocol_application:emit(RelocatedConfig),
    ?assertEqual(application_identity(Original, board), application_identity(Relocated, board)),
    ?assertEqual(inspection_fingerprint(Original), inspection_fingerprint(Relocated)),
    Source = filename:join(Root, "hls_protocol_boundary_fixture.erl"),
    {ok, Bytes} = file:read_file(Source),
    Changed = binary:replace(Bytes, <<"\ninit([]) -> {ok,boot,#cell{}}.">>,
        <<"\ninit([]) -> {ok,boot,#cell{base=1}}.">>),
    ?assertNotEqual(Bytes, Changed),
    ok = file:write_file(Source, Changed),
    Different = hls_protocol_application:emit(RelocatedConfig),
    ?assertNotEqual(application_identity(Original, board), application_identity(Different, board)),
    ok.

%% One prepared program suffices for endpoint and placement sensitivity; annotation is a separate fresh build.
-spec bridge_identity_test_() -> term().
bridge_identity_test_() -> {timeout, 120, fun bridge_identity/0}.

%% Optional analysis must not change a framed role's attachment contract or generated interface.
-spec bridge_identity() -> ok.
bridge_identity() ->
    Config = bridge_config(),
    Program = hls_protocol_transport:prepare(Config),
    North = hls_protocol_transport:plan(Program, #{native_actors => [left, sink]}),
    South = hls_protocol_transport:plan(Program, #{native_actors => [right]}),
    Options = #{host => 2, service => 29, control => rectangle},
    Baseline = hls_protocol_bridge:emit(North, Options),
    ok = emitted_boundary_inputs(Baseline),
    Identity = bridge_identity(Baseline),
    ?assertEqual(32, byte_size(Identity)),
    ChangedHost = hls_protocol_bridge:emit(North, Options#{host := 3}),
    ChangedService = hls_protocol_bridge:emit(North, Options#{service := 31}),
    ChangedPlacement = hls_protocol_bridge:emit(South, Options),
    lists:foreach(fun(Output) -> ?assertNotEqual(Identity, bridge_identity(Output)) end,
        [ChangedHost, ChangedService, ChangedPlacement]),
    erase(model_calls),
    AnnotatedProgram = hls_protocol_transport:prepare(Config#{protocol_model => {hls_protocol_model_tests, independent}}),
    AnnotatedBuild = hls_protocol_transport:plan(AnnotatedProgram, #{native_actors => [left, sink]}),
    Annotated = #{files := AnnotatedFiles} = hls_protocol_bridge:emit(AnnotatedBuild, Options),
    ?assertEqual([summary, derive], erase(model_calls)),
    ?assert(maps:is_key("protocol-model.json", AnnotatedFiles)),
    ?assertEqual(Identity, bridge_identity(Annotated)),
    #{files := BaselineFiles} = Baseline,
    ?assertEqual(iolist_to_binary(maps:get("bridge/bridge.x", BaselineFiles)),
        iolist_to_binary(maps:get("bridge/bridge.x", AnnotatedFiles))),
    ok.

%% Exact generated bytes are part of the boundary even when source and port metadata stay fixed.
-spec emitted_boundary_inputs(hls_generated_files:output()) -> ok.
emitted_boundary_inputs(#{files := Files, result := #{transport := Plan}}) ->
    BoundaryFiles = maps:filter(fun(File, _) -> not lists:prefix("bridge/", File) end, Files),
    Identity = hls_protocol_identity:boundary(Plan, BoundaryFiles),
    Source = maps:get("boundary/boundary.x", BoundaryFiles),
    ChangedHardware = BoundaryFiles#{"boundary/boundary.x" := [Source, "\n// changed generated bytes\n"]},
    ?assertNotEqual(Identity, hls_protocol_identity:boundary(Plan, ChangedHardware)),
    ChangedReports = BoundaryFiles#{"summary.json" := <<"{\"diagnostic\":\"updated\"}">>,
        "extra-report.etf" => term_to_binary(#{measurement => pending})},
    ?assertEqual(Identity, hls_protocol_identity:boundary(Plan, ChangedReports)),
    ok.

%% Capacity changes the actual attachment identity without renumbering logical actors or crossing lanes.
-spec frame_capacity_identity_test_() -> term().
frame_capacity_identity_test_() -> {timeout, 60, fun frame_capacity_identity/0}.

%% Two fresh compilations retain identical source identities but bind distinct frame-aware artifacts.
-spec frame_capacity_identity() -> ok.
frame_capacity_identity() ->
    Config = (bridge_config())#{native_actors => [left,sink], host => 2,service => 29,control => rectangle},
    Narrow = #{result := #{transport := NarrowTransport}} =
        hls_protocol_bridge:emit(Config#{frame_payload_words => 1}),
    Wide = #{result := #{transport := WideTransport}} =
        hls_protocol_bridge:emit(Config#{frame_payload_words => 3}),
    ?assertNotEqual(bridge_identity(Narrow), bridge_identity(Wide)),
    #{bundle := #{topology := Topology,modules := NarrowModules},fabric := NarrowFabric} = NarrowTransport,
    #{bundle := #{topology := Topology,modules := WideModules},fabric := WideFabric} = WideTransport,
    LaneKeys = [index,source_index,destination_index,output_index,direction,pair],
    ?assertEqual([maps:with(LaneKeys,L) || L <- maps:get(crossings,NarrowFabric)],
        [maps:with(LaneKeys,L) || L <- maps:get(crossings,WideFabric)]),
    NarrowIdentities = hls_protocol_identity:source_modules(NarrowModules),
    WideIdentities = hls_protocol_identity:source_modules(WideModules),
    maps:foreach(fun(Module,NarrowIdentity) ->
        WideIdentity = maps:get(Module,WideIdentities),
        ?assertEqual(maps:get(source_sha256,NarrowIdentity),maps:get(source_sha256,WideIdentity)),
        ?assertNotEqual(maps:get(artifact_sha256,NarrowIdentity),maps:get(artifact_sha256,WideIdentity)),
        ?assertNotEqual(maps:get(plan_sha256,NarrowIdentity),maps:get(plan_sha256,WideIdentity))
    end,NarrowIdentities),
    ok.

%% Independent complete deployments must derive the same identities for both real source partitions.
-spec deployment_identity_test_() -> term().
deployment_identity_test_() -> {timeout, 120, fun deployment_identity/0}.

%% The role pair shares sources but each owns a different native subset and endpoint pair.
-spec deployment_identity() -> ok.
deployment_identity() ->
    Config = (bridge_config())#{control => rectangle,
        devices => #{north => #{native_actors => [left, sink], host => 2, service => 29},
            south => #{native_actors => [right], host => 3, service => 31}},
        limits => #{crossings => 8, commands => 8, events => 8}},
    #{result := #{devices := First}} = hls_protocol_deployment:emit(Config),
    #{result := #{devices := Second}} = hls_protocol_deployment:emit(Config),
    Identities = maps:map(fun(_, #{identity := Identity}) -> Identity end, First),
    ?assertEqual(Identities, maps:map(fun(_, #{identity := Identity}) -> Identity end, Second)),
    ?assertNotEqual(maps:get(north, Identities), maps:get(south, Identities)),
    ok.

%% The existing actor fixture supplies four small producers and the wrapper supplies typed endpoint IDs.
-spec application_config(file:filename()) -> map().
application_config(Directory) ->
    #{sources => [{filename:join(Directory, File), []}
        || File <- ["hls_protocol_boundary_fixture.erl", "hls_protocol_identity_fixture.erl"]],
      topology => {hls_protocol_identity_fixture, topology, [default]}, actor_limit => 4,
      device => board, host => 19, inspection => process}.

%% Three ordinary actors provide actual source-derived crossings, ingress and separate external streams.
-spec bridge_config() -> map().
bridge_config() ->
    #{sources => [{"test/hls_protocol_network_fixture.erl", []}, {"test/hls_protocol_inbox_fixture.erl", []}],
      topology => {hls_protocol_network_fixture, framed, []}, actor_limit => 3}.

%% Read the identity consumed by host attachment, not an intermediate hashing helper.
-spec application_identity(hls_generated_files:output(), term()) -> binary().
application_identity(#{result := #{devices := Devices}}, Device) ->
    #{identity := Identity} = maps:get(Device, Devices), Identity.

%% The inspection consumer recomputes this public fingerprint from the generated catalog.
-spec inspection_fingerprint(hls_generated_files:output()) -> binary().
inspection_fingerprint(#{files := Files}) ->
    Manifest = #{<<"fingerprint">> := Fingerprint} = json:decode(iolist_to_binary(maps:get("network/inspection.json", Files))),
    ?assertEqual(Fingerprint, hls_topology_debug:manifest_fingerprint(Manifest)),
    Fingerprint.

%% A framed peer uses the bridge descriptor's identity directly during attachment.
-spec bridge_identity(hls_generated_files:output()) -> binary().
bridge_identity(#{result := #{bridge := #{identity := Identity}}}) -> Identity.
