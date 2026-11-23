-module(hls_protocol_build_tests).
-moduledoc "In-process source preparation and placement regressions. These check build boundaries and artifact identity, not hardware execution or progress.".
-include_lib("eunit/include/eunit.hrl").

%% Planning different roles must use the prepared source even when its files are no longer present.
-spec reusable_program_test() -> ok.
reusable_program_test() ->
    Root = fresh("prepared-program"),
    ok = file:make_dir(Root),
    Files = ["hls_protocol_network_fixture.erl", "hls_protocol_inbox_fixture.erl"],
    Sources = [begin
        Target = filename:join(Root, File),
        {ok, _} = file:copy(filename:join("apps/hls_fabric/test", File), Target),
        {Target, []}
    end || File <- Files],
    Program = hls_protocol_transport:prepare(#{sources => Sources,
        topology => {hls_protocol_network_fixture, framed, []}, actor_limit => 3}),
    lists:foreach(fun({File, _}) -> ok = file:rename(File, File ++ ".prepared") end, Sources),
    North = hls_protocol_transport:plan(Program, #{native_actors => [left, sink]}),
    South = hls_protocol_transport:plan(Program, #{native_actors => [right]}),
    #{bundle := NorthBundle, fabric := #{sources := NorthActors}} = hls_protocol_transport:descriptor(North),
    #{bundle := SouthBundle, fabric := #{sources := SouthActors}} = hls_protocol_transport:descriptor(South),
    ?assertEqual(hls_protocol_transport:bundle(Program), NorthBundle),
    ?assertEqual(NorthBundle, SouthBundle),
    ?assertEqual([0, 2], [I || #{index := I} <- NorthActors]),
    ?assertEqual([1], [I || #{index := I} <- SouthActors]),
    %% A placement API must not silently accept a request to change its source configuration.
    ?assertError({hls_diagnostic, #{stage := transport, code := unsupported_transport_options, context := #{options := [sources]}}},
        hls_protocol_transport:plan(Program, #{sources => Sources})),
    Before = relative_files(Root),
    Output = #{files := Generated, result := Descriptor} = hls_protocol_transport:emit(North),
    finalized_transport(hls_protocol_transport:descriptor(North), Descriptor, Generated),
    ?assertEqual(Output, hls_protocol_transport:emit(North)),
    ?assertEqual(Before, relative_files(Root)),
    First = filename:join(Root, "first"), Second = filename:join(Root, "second"),
    ?assertEqual(Descriptor, hls_generated_files:write(Output, First)),
    ?assertEqual(Descriptor, hls_protocol_transport:write(North, Second)),
    FilesWritten = relative_files(First),
    ?assertEqual(lists:sort(maps:keys(Generated)), FilesWritten),
    ?assertEqual(FilesWritten, relative_files(Second)),
    lists:foreach(fun(File) ->
        Bytes = iolist_to_binary(maps:get(File, Generated)),
        ?assertEqual({ok, Bytes}, file:read_file(filename:join(First, File))),
        ?assertEqual({ok, Bytes}, file:read_file(filename:join(Second, File)))
    end, FilesWritten),
    %% Inspection follows retained native ownership after the original source files are gone.
    #{network := #{native_indices := [1], inspection := Inspection}} =
        hls_protocol_network:write(South, #{inspection => process}, filename:join(Root, "inspection")),
    ?assertMatch([#{<<"id">> := 1, <<"owner_index">> := 1}], maps:get(<<"resources">>, Inspection)),
    ?assertEqual(true, filelib:is_file(filename:join([Root, "inspection", "network", "inspection.etf"]))),
    Override = filename:join(Root, "override"),
    ?assertError({hls_diagnostic, #{stage := network, code := unsupported_network_options, context := #{options := [native_actors]}}},
        hls_protocol_network:write(South, #{native_actors => [left]}, Override)),
    ?assertError({hls_diagnostic, #{stage := bridge, code := unsupported_bridge_options, context := #{options := [sources]}}},
        hls_protocol_bridge:write(South, #{host => 1, service => 7, control => rectangle, sources => Sources}, Override)),
    ?assertEqual(false, filelib:is_dir(Override)),
    ok.

%% Finalization adds only generated module bytes and their exact owner/receiver hashes.
-spec finalized_transport(map(), map(), hls_generated_files:files()) -> ok.
finalized_transport(Static = #{bundle := #{modules := Sources}},
        Final = #{bundle := Bundle = #{modules := Modules}, actor_functions := Functions, receivers := Receivers}, Files) ->
    maps:foreach(fun(Module, Source) ->
        ?assertNot(maps:is_key(emitted, Source)),
        Artifact = #{emitted := Emitted} = maps:get(Module, Modules),
        ?assert(is_binary(xls_emitted:bytes(Emitted))),
        ?assertEqual(Source, maps:remove(emitted, Artifact))
    end, Sources),
    ?assertEqual(lists:sort(maps:keys(Sources)), lists:sort(maps:keys(Modules))),
    ?assertEqual(Static, Final#{bundle := Bundle#{modules := Sources},
        actor_functions := [static_actor(A, Files) || A <- Functions],
        receivers := [static_actor(A, Files) || A <- Receivers]}).

%% Verify emitted module/configuration identities before removing hashes unavailable during planning.
-spec static_actor(map(), hls_generated_files:files()) -> map().
static_actor(Actor = #{file := File, manifest := Manifest = #{dslx_sha256 := Hash}}, Files) ->
    ?assertEqual(Hash, digest(maps:get(binary_to_list(File), Files))),
    ConfigFile = filename:join(filename:dirname(binary_to_list(File)), "frame_config.x"),
    ?assertEqual(maps:get(frame_config_sha256, Manifest), digest(maps:get(ConfigFile, Files))),
    ok = dependency_hashes(Manifest, File, Files),
    Static = maps:without([dslx_sha256, dslx_dependencies, frame_config_sha256, failure_sites], Manifest),
    case maps:get(owner_import, Static, none) of
        none -> Actor#{manifest := Static};
        Import = #{file := OwnerFile, dslx_sha256 := OwnerHash} ->
            ?assertEqual(OwnerHash, digest(maps:get(binary_to_list(OwnerFile), Files))),
            ok = dependency_hashes(Import, OwnerFile, Files),
            Actor#{manifest := Static#{owner_import := maps:without([dslx_sha256, dslx_dependencies], Import)}}
    end.

%% Helper imports acquire byte identities at emission, just like their enclosing actor.
-spec dependency_hashes(map(), binary(), hls_generated_files:files()) -> ok.
dependency_hashes(#{dslx_dependencies := Dependencies}, File, Files) ->
    Directory = filename:dirname(binary_to_list(File)),
    maps:foreach(fun(Relative, Hash) ->
        Path = filename:join(Directory, binary_to_list(Relative)),
        ?assertEqual(Hash, digest(maps:get(Path, Files)))
    end, Dependencies).

%% Filename input is a trusted source map; emission has no output side effects and hashes its returned bytes.
-spec emission_inputs_test() -> ok.
emission_inputs_test() ->
    Root = fresh("emission-inputs"),
    ok = file:make_dir(Root),
    Config = #{sources => [{"apps/hls_fabric/test/hls_protocol_network_fixture.erl", []}],
        topology => {hls_protocol_network_fixture, isolated, []}, actor_limit => 1},
    Filename = filename:join(Root, "source.config"),
    ok = file:write_file(Filename, io_lib:format("~tp.~n", [Config]), [exclusive]),
    Before = relative_files(Root),
    #{files := FromMap, result := #{network := Network}} = hls_protocol_network:emit(Config),
    #{files := FromFile, result := #{network := Network}} = hls_protocol_network:emit(Filename),
    ?assertEqual(Before, relative_files(Root)),
    %% Compiler-origin references in trusted ETF plans need not survive another preparation.
    ?assertEqual(hardware_files(FromMap), hardware_files(FromFile)),
    #{dslx_sha256 := Hash, components := Components} = Network,
    ?assertEqual(Hash, digest(maps:get("network/network.x", FromMap))),
    lists:foreach(fun(#{file := File, sha256 := Expected}) ->
        ?assertEqual(Expected, digest(maps:get(binary_to_list(File), FromMap)))
    end, Components),
    Saved = filename:join(Root, "saved.etf"),
    ok = file:write_file(Saved, term_to_binary(Config, [deterministic]), [exclusive]),
    ?assertException(error, _, hls_protocol_network:emit(Saved)),
    ok.

%% Trace a real small build; three producer instances must share one ordinary source compilation.
-spec shared_source_program_test_() -> term().
shared_source_program_test_() -> {timeout, 30, fun shared_source_program/0}.

%% Every source phase, conditional send and instance transaction survives compilation reuse.
-spec shared_source_program() -> ok.
shared_source_program() ->
    Config = #{sources => [{"apps/hls_fabric/test/hls_protocol_capture_fixture.erl", []},
            {"apps/hls_fabric/test/hls_protocol_transport_topology.erl", []}],
        topology => {hls_protocol_transport_topology, topology, []}, actor_limit => 3},
    {Build, Compiled} = trace_build(fun() -> hls_protocol_transport:plan(Config) end),
    ?assertEqual(["hls_protocol_capture_fixture.erl"], [filename:basename(File) || File <- Compiled]),
    #{bundle := #{topology := #{actors := Actors}, modules := Modules,
            inventory := #{modules := #{hls_protocol_capture_fixture := #{alternatives := Alternatives}}}},
        capture := #{channels := Channels}, transactions := #{actors := Transactions}} =
        hls_protocol_transport:descriptor(Build),
    ?assertEqual([a, b, c], [Id || #{id := Id} <- Actors]),
    ?assertEqual([hls_protocol_capture_fixture], maps:keys(Modules)),
    ?assertEqual([{first, <<1:3>>}, {second, <<2:3>>}], lists:usort([
        {Phase, Value} || #{phase := Phase, port := varying, fields := [#{constant := Value}]} <- Alternatives])),
    ?assertEqual([<<1:3>>, <<2:3>>], lists:usort([
        Value || #{port := conditional, fields := [#{constant := Value}]} <- Alternatives])),
    ?assertEqual([{Id, Port, 3} || Id <- [a, b, c], Port <- [conditional, varying]],
        lists:sort([{Id, Port, Bits} || #{source := Id, port := Port, payload_bits := Bits} <- Channels,
            Port =:= conditional orelse Port =:= varying])),
    lists:foreach(fun(#{batches := Batches}) ->
        ?assertEqual([lists:seq(0, 7), lists:seq(0, 7)],
            [Order || #{phase := first, logical_send_order := Order} <- Batches]),
        ?assertEqual([[0]], [Order || #{phase := second, logical_send_order := Order} <- Batches]),
        %% Partial constants retain the ordinary storage slices, not the inventory's display projection.
        PartialWidths = [lists:sum([Width || {_, Width} <- Slices])
            || #{effects := Effects} <- Batches,
               #{port := partial, fields := [#{slices := Slices}]} <- Effects],
        ?assertEqual([2, 2], PartialWidths)
    end, Transactions).

%% A private trace session observes only this test process, so concurrent builds cannot inflate the count.
-spec trace_build(fun(() -> hls_protocol_transport:build())) -> {hls_protocol_transport:build(), [file:filename()]}.
trace_build(Build) ->
    {module, xls_statem_plan} = code:ensure_loaded(xls_statem_plan),
    {Collector, Monitor} = spawn_monitor(fun() -> collect_compilations([]) end),
    Session = trace:session_create(protocol_build_compilations, Collector, []),
    try
        1 = trace:process(Session, self(), true, [call]),
        1 = trace:function(Session, {xls_statem_plan, from_file, 3}, [], []),
        Result = Build(),
        1 = trace:process(Session, self(), false, [call]),
        Ref = trace:delivered(Session, self()),
        receive
            {trace_delivered, _, Ref} -> ok
        after 5000 -> error(compile_trace_delivery_timeout)
        end,
        Collector ! {collect, self(), Ref},
        receive
            {Ref, Files} -> {Result, Files}
        after 5000 -> error(compile_trace_collection_timeout)
        end
    after
        trace:session_destroy(Session),
        exit(Collector, kill),
        receive
            {'DOWN', Monitor, process, Collector, _} -> ok
        after 5000 -> error(compile_trace_cleanup_timeout)
        end
    end.

%% Retain source filenames, not full compiler contexts, until the caller has observed trace delivery.
-spec collect_compilations([file:filename()]) -> ok.
collect_compilations(Files) ->
    receive
        %% Each ordinary planner entry is one actual source compilation by the traced build process.
        {trace, _, call, {xls_statem_plan, from_file, [File, _Options, _FrameLayout]}} ->
            collect_compilations([File | Files]);
        %% The delivery barrier guarantees every preceding call is already in this mailbox.
        {collect, Owner, Ref} -> Owner ! {Ref, lists:reverse(Files)}, ok
    end.

%% Compare generated hardware independently of process-local compiler provenance in plans.
-spec hardware_files(hls_generated_files:files()) -> #{string() => binary()}.
hardware_files(Files) ->
    maps:from_list([{File, iolist_to_binary(Bytes)} || {File, Bytes} <- maps:to_list(Files),
        lists:member(filename:extension(File), [".x", ".sv"])]).

%% Use the standard hash operation independently of the file-bundle helper.
-spec digest(iodata()) -> binary().
digest(Bytes) -> binary:encode_hex(crypto:hash(sha256, Bytes), lowercase).

%% All generated actor files and sidecars are bound, not just one representative DSLX module.
-spec relative_files(file:filename()) -> [file:filename()].
relative_files(Root) ->
    Prefix = Root ++ "/",
    lists:sort(filelib:fold_files(Root, ".*", true,
        fun(File, Acc) -> [lists:nthtail(length(Prefix), File) | Acc] end, [])).

%% Fresh disposable output avoids both overwriting old evidence and dependence on test order.
-spec fresh(string()) -> file:filename().
fresh(Name) -> filename:join("_build", Name ++ "-" ++ integer_to_list(erlang:system_time(nanosecond))).
