-module(hls_protocol_composition_tests).
-moduledoc "Static composition interfaces and early rejection of host/deployment constraints. Tracing checks actual renderer entry; these are compiler tests, not RTL behavior witnesses.".
-include_lib("eunit/include/eunit.hrl").

%% Interfaces and observation mode exist before transport, network or boundary files do.
-spec inspected_plans_test_() -> term().
inspected_plans_test_() -> {timeout, 30, fun inspected_plans/0}.

%% Positive emissions establish that the same tracer observes the complete renderer chain.
-spec inspected_plans() -> ok.
inspected_plans() ->
    Options = #{inspection => process, activation => explicit_start},
    {{Network, Boundary}, PlanningCalls} = trace_renderers(fun() ->
        Build = hls_protocol_transport:plan(whole()),
        {hls_protocol_network:plan(Build, Options), hls_protocol_boundary:plan(Build, Options)}
    end),
    ?assertEqual(#{}, PlanningCalls),
    NetworkInterface = #{actors := 4, native_indices := [0, 1, 2, 3], inspection := process,
        inputs := Inputs} = hls_protocol_network:descriptor(Network),
    ?assert(lists:member(#{name => <<"inspect_address">>, width => 32}, Inputs)),
    ?assertMatch(#{observe := #{actors := [0, 1, 2, 3], inspection := true, host := true},
        select := [], advance := #{ingress := [#{actor := 3, slot := 1},
            #{actor := 2, slot := 1}, #{actor := 1, slot := 0}, #{actor := 0, slot := 0}]},
        commit := #{activation := #{host := true,
            faults := [ingress, {actor, 0}, {actor, 1}, {actor, 2}, {actor, 3}]}}},
        hls_protocol_network:phases(Network)),
    BoundaryInterface = #{inspection := process, arbitration_state_bits := 5, externals := Groups} =
        hls_protocol_boundary:descriptor(Boundary),
    ?assertEqual([3, 1, 0], [length(Members) || #{members := Members} <- Groups]),
    ?assertNot(maps:is_key(dslx_sha256, NetworkInterface)),
    ?assertNot(maps:is_key(components, NetworkInterface)),
    ?assertNot(maps:is_key(dslx_sha256, BoundaryInterface)),
    {{NetworkOutput, BoundaryOutput}, Calls} = trace_renderers(fun() ->
        {hls_protocol_network:emit(Network), hls_protocol_boundary:emit(Boundary)}
    end),
    assert_emissions(#{
        {hls_protocol_transport, emit, 1} => 2,
        {xls_protocol_network, emit, 3} => 2,
        {xls_protocol_boundary, emit, 2} => 1,
        {hls_protocol_inspection, emit, 1} => 2}, Calls),
    #{result := #{network := NetworkManifest}} = NetworkOutput,
    #{result := #{boundary := BoundaryManifest}} = BoundaryOutput,
    check_manifest(NetworkInterface, NetworkManifest),
    check_manifest(BoundaryInterface, BoundaryManifest).

%% Framing ownership and budgets are available before emitted bytes define an identity.
-spec bridge_plan_test_() -> term().
bridge_plan_test_() -> {timeout, 30, fun bridge_plan/0}.

%% The planned bridge retains exact cuts while its emitter adds attachment-only evidence.
-spec bridge_plan() -> ok.
bridge_plan() ->
    {{Plan, Network}, PlanningCalls} = trace_renderers(fun() ->
        Build = hls_protocol_transport:plan(partition()),
        {hls_protocol_bridge:plan(Build, #{host => 2, service => 29, control => rectangle}),
         hls_protocol_network:plan(Build, #{activation => explicit_start})}
    end),
    ?assertEqual(#{}, PlanningCalls),
    Interface = #{native_indices := [0, 2], incoming := Incoming, outgoing := Outgoing,
        links := Links, credits := Credits, actors := 3} = hls_protocol_bridge:descriptor(Plan),
    ?assert(Incoming =/= []),
    ?assert(Outgoing =/= []),
    ?assert(Credits =/= []),
    ?assertEqual(lists:sort(Links), lists:sort(Incoming ++ Outgoing)),
    #{observe := #{actors := [0, 2], host := true},
      advance := #{ingress := HostRetirements},
      commit := #{activation := #{faults := Faults}}} = hls_protocol_network:phases(Network),
    ?assertEqual([ingress] ++ [{crossing, I} || #{index := I} <- Incoming] ++
        [{actor, 0}, {actor, 2}], Faults),
    ?assertMatch([none, none, #{actor := 0}], HostRetirements),
    ?assertNot(maps:is_key(identity, Interface)),
    ?assertNot(maps:is_key(libraries, Interface)),
    {#{result := #{bridge := Bridge}}, Calls} = trace_renderers(fun() -> hls_protocol_bridge:emit(Plan) end),
    assert_emissions(#{
        {hls_protocol_transport, emit, 1} => 1,
        {xls_protocol_network, emit, 3} => 1,
        {xls_protocol_boundary, emit, 2} => 1,
        {xls_protocol_bridge, emit, 3} => 1}, Calls),
    ?assertEqual(Interface, maps:without([identity, libraries], Bridge)),
    ?assertEqual(32, byte_size(maps:get(identity, Bridge))).

%% Unsupported observation cannot trigger a partial transport render through any parent.
-spec partition_inspection_test() -> ok.
partition_inspection_test() ->
    Build = hls_protocol_transport:plan(partition()),
    {ok, Calls} = trace_renderers(fun() ->
        ?assertError({hls_diagnostic, #{stage := network, code := partition_inspection_unavailable}},
            hls_protocol_network:plan(Build, #{inspection => process})),
        ?assertError({hls_diagnostic, #{stage := network, code := partition_inspection_unavailable}},
            hls_protocol_boundary:plan(Build, #{inspection => process})),
        ?assertError({hls_diagnostic, #{stage := network, code := partition_inspection_unavailable}},
            hls_protocol_bridge:plan(Build, #{host => 2, service => 29,
                control => rectangle, inspection => process})),
        ok
    end),
    ?assertEqual(#{}, Calls).

%% Each failure exercises a distinct host constraint with an otherwise valid framed cut.
-spec mixed_rejections_test_() -> term().
mixed_rejections_test_() -> {timeout, 30, fun mixed_rejections/0}.

%% Multicast and host-to-host routes reject before entering any hardware emitter.
-spec mixed_rejections() -> ok.
mixed_rejections() ->
    Multicast = partition(),
    HostLink = (fixture(beam_to_beam))#{native_actors => [left], host => 2, service => 29},
    {ok, Calls} = trace_renderers(fun() ->
        ?assertError({hls_diagnostic, #{stage := mixed, code := unsupported_host_fanout,
            context := #{actor := right, port := early, recipients := [_, _]}}},
            hls_protocol_mixed:emit(Multicast)),
        ?assertError({hls_diagnostic, #{stage := mixed, code := unsupported_host_route,
            context := #{capability := beam_to_beam}}}, hls_protocol_mixed:emit(HostLink)),
        ok
    end),
    ?assertEqual(#{}, Calls).

%% Equal-width event schemas must agree before the application emits its source network.
-spec application_rejection_test_() -> term().
application_rejection_test_() -> {timeout, 30, fun application_rejection/0}.

%% A valid application is the positive trace control for the exact rejected build path.
-spec application_rejection() -> ok.
application_rejection() ->
    Collision = #{sources => [{"test/hls_protocol_boundary_fixture.erl", []},
        {"test/hls_protocol_application_conflict.erl", []}, {"test/hls_protocol_application_tests.erl", []}],
        topology => {hls_protocol_application_tests, collision, []}, actor_limit => 5, device => board, host => 1},
    {ok, RejectedCalls} = trace_renderers(fun() ->
        ?assertError({ambiguous_application_event, shared, 5}, hls_protocol_application:emit(Collision)),
        ok
    end),
    ?assertEqual(#{}, RejectedCalls),
    {#{result := #{devices := #{board := _}}}, Calls} = trace_renderers(fun() ->
        hls_protocol_application:emit((whole())#{device => board, host => 19})
    end),
    assert_emissions(#{
        {hls_protocol_transport, emit, 1} => 1,
        {xls_protocol_network, emit, 3} => 1,
        {xls_protocol_boundary, emit, 2} => 1,
        {xls_protocol_application, emit, 1} => 1}, Calls).

%% Planning a later invalid role must prevent rendering the preceding valid roles.
-spec deployment_rejection_test_() -> term().
deployment_rejection_test_() -> {timeout, 30, fun deployment_rejection/0}.

%% Sorted role zzz is isolated; north and south retain the established bidirectional cut.
-spec deployment_rejection() -> ok.
deployment_rejection() ->
    Config = (fixture(isolated_role))#{actor_limit := 4,
        devices => #{north => #{native_actors => [left, sink], host => 2, service => 29},
            south => #{native_actors => [right], host => 3, service => 31},
            zzz => #{native_actors => [orphan], host => 4, service => 37}},
        limits => #{crossings => 8, commands => 8, events => 8}},
    {ok, Calls} = trace_renderers(fun() ->
        ?assertError({hls_diagnostic, #{stage := bridge, code := missing_bridge_paths,
            context := #{role := zzz, missing := [incoming, outgoing]}}},
            hls_protocol_deployment:emit(Config)),
        ok
    end),
    ?assertEqual(#{}, Calls).

%% Shared completions use the same static planning boundary as ordinary imported owners.
-spec shared_arithmetic_plan_test_() -> term().
shared_arithmetic_plan_test_() -> {timeout, 30, fun shared_arithmetic_plan/0}.

%% Three receivers retain the shared ABI and their startup slots before any hardware is rendered.
-spec shared_arithmetic_plan() -> ok.
shared_arithmetic_plan() ->
    Config = #{sources => [{"test/hls_protocol_arithmetic_fixture.erl", []}],
        topology => {hls_protocol_arithmetic_fixture, topology, [3]}, actor_limit => 3,
        arithmetic_groups => [[0, 1, 2]]},
    {{Plan, Network}, PlanningCalls} = trace_renderers(fun() ->
        Transport = hls_protocol_transport:plan(Config),
        {Transport, hls_protocol_network:plan(Transport, #{activation => explicit_start})}
    end),
    ?assertEqual(#{}, PlanningCalls),
    #{select := [#{index := 0, members := [0, 1, 2]}],
      advance := #{receivers := Steps, ingress := none}} = hls_protocol_network:phases(Network),
    ?assertEqual([{I, #{group => 0, member => I}} || I <- [0, 1, 2]],
        [{I, Binding} || #{index := I, completion := Binding} <- Steps]),
    #{receivers := StaticReceivers, bundle := #{modules := Modules}} = hls_protocol_transport:descriptor(Plan),
    lists:foreach(fun(Source) -> ?assertNot(maps:is_key(emitted, Source)) end, maps:values(Modules)),
    ?assertEqual([0, 1, 2], [I || #{index := I} <- StaticReceivers]),
    lists:foreach(fun(#{manifest := Manifest}) ->
        #{completion := #{mode := shared, group := 0},
          inbox := #{startup := #{count := 2}, inputs := Inputs}} = Manifest,
        ?assert(lists:member(#{name => <<"completion_granted">>, width => 1}, Inputs)),
        ?assertNot(maps:is_key(dslx_sha256, Manifest))
    end, StaticReceivers),
    {#{result := #{receivers := Receivers}}, Calls} = trace_renderers(fun() -> hls_protocol_transport:emit(Plan) end),
    assert_early_emissions(Calls),
    #{hls_protocol_arithmetic_fixture := #{program := Program}} = Modules,
    #{failure_locations := Locations} = xls_actor_program:spec(Program),
    lists:foreach(fun({#{manifest := Before}, #{manifest := After = #{dslx_sha256 := Hash}}}) ->
        ?assertEqual(ok, xls_failure_sites:validate_sites(Locations, maps:get(failure_sites, After))),
        ?assertEqual(64, byte_size(Hash)),
        ?assertEqual(64, byte_size(maps:get(frame_config_sha256, After))),
        ?assertEqual(#{}, maps:get(dslx_dependencies, After)),
        ?assertEqual(Before, maps:without([dslx_sha256, dslx_dependencies, frame_config_sha256, failure_sites], After))
    end, lists:zip(StaticReceivers, Receivers)).

%% Bounded caller ownership is retained at preparation without generating an owner.
-spec local_reply_preparation_test() -> ok.
local_reply_preparation_test() ->
    {Source, Calls} = trace_renderers(fun() ->
        hls_local_actor:prepare("test/hls_protocol_call_fixture.erl", [])
    end),
    ?assertEqual(#{}, Calls),
    #{retained_calls := #{pending_calls := 1, port := reply}} =
        hls_local_actor:descriptor(Source),
    ok.

%% Every outer builder owns a checked plan; changing its files cannot change retained semantics.
-spec retained_outer_plans_test_() -> term().
retained_outer_plans_test_() -> {timeout, 120, fun retained_outer_plans/0}.

%% Plan each small application once, then render only its captured source and host bindings.
-spec retained_outer_plans() -> ok.
retained_outer_plans() ->
    lists:foreach(fun({Builder, Config}) -> retained_plan(Builder, Config) end,
        [{hls_protocol_application, (whole())#{device => board, host => 19, inspection => process}},
         {hls_protocol_mixed, mixed()},
         {hls_protocol_deployment, deployment()}]).

%% A later emission neither recompiles nor consults corrupted or missing source files.
-spec retained_plan(module(), map()) -> ok.
retained_plan(Builder, Config) ->
    {_Root, Copied = #{sources := Sources}} = copied_sources(Config),
    try
        {Plan, PlanningCalls} = trace_calls(fun() -> Builder:plan(Copied) end,
            renderer_targets() ++ source_targets()),
        ?assertEqual(#{}, renderer_calls(PlanningCalls)),
        Static = Builder:descriptor(Plan),
        check_static(Builder, Static),
        case Builder of
            hls_protocol_deployment ->
                ?assertEqual(2, maps:get({compile, file, 2}, PlanningCalls, 0)),
                ?assertEqual(2, maps:get({xls_actor_program, from_file, 3}, PlanningCalls, 0)),
                ?assertEqual(1, maps:get({hls_protocol_transport, prepare, 1}, PlanningCalls, 0));
            _ -> ok
        end,
        {First, EmissionCalls} = trace_calls(fun() -> Builder:emit(Plan) end,
            renderer_targets() ++ source_targets()),
        ?assertEqual(#{}, source_calls(EmissionCalls)),
        assert_early_emissions(EmissionCalls),
        case Builder of
            hls_protocol_deployment -> same_role_snapshot(First);
            _ -> ok
        end,
        invalidate_sources(Sources),
        {Again, RetainedCalls} = trace_calls(fun() -> Builder:emit(Plan) end,
            renderer_targets() ++ source_targets()),
        ?assertEqual(First, Again),
        ?assertEqual(Static, Builder:descriptor(Plan)),
        ?assertEqual(#{}, source_calls(RetainedCalls)),
        assert_early_emissions(RetainedCalls)
    after restore_sources(Config) end.

%% The toolchain wrapper keeps the same checked build through its separate packaging stage.
-spec retained_source_build_test_() -> term().
retained_source_build_test_() -> {timeout, 60, fun retained_source_build/0}.

%% Packaging uses the selected plan after its application files disappear; support reads remain legal.
-spec retained_source_build() -> ok.
retained_source_build() ->
    Config = (whole())#{device => board, host => 19},
    {Root, Copied = #{sources := Sources}} = copied_sources(Config),
    try
        {Plan, PlanningCalls} = trace_calls(fun() -> hls_source_build:plan(application, Copied) end,
            renderer_targets() ++ source_targets()),
        ?assertEqual(#{}, renderer_calls(PlanningCalls)),
        #{kind := application, build := Build, dslx_path := []} = hls_source_build:descriptor(Plan),
        check_static(hls_protocol_application, Build),
        invalidate_sources(Sources),
        Output = filename:join(Root, "packaged"),
        {Manifest, Calls} = trace_calls(fun() -> hls_source_build:write(Plan, Output) end,
            renderer_targets() ++ source_targets()),
        ?assert(is_map(Manifest)),
        ?assert(filelib:is_regular(filename:join(Output, "source-build.json"))),
        ?assertEqual(#{}, source_calls(Calls)),
        assert_early_emissions(Calls)
    after restore_sources(Config) end.

%% Generated attachment identities and hardware hashes do not masquerade as planning facts.
-spec check_static(module(), map()) -> ok.
check_static(hls_protocol_application, #{devices := #{board := Binding}, source_boundary := Boundary}) ->
    ?assertNot(maps:is_key(identity, Binding)),
    ?assertNot(maps:is_key(dslx_sha256, Boundary));
check_static(hls_protocol_mixed, #{actors := Actors, bridge := Bridge, mixed := Mixed}) ->
    ?assertEqual([1], maps:keys(Actors)),
    ?assertNot(maps:is_key(identity, Bridge)),
    ?assertNot(maps:is_key(identity, Mixed));
check_static(hls_protocol_deployment, #{devices := Devices, directories := Directories}) ->
    ?assertEqual([north, south], lists:sort(maps:keys(Devices))),
    ?assertEqual([north, south], lists:sort(maps:keys(Directories))),
    lists:foreach(fun(Bridge) -> ?assertNot(maps:is_key(identity, Bridge)) end, maps:values(Devices)).

%% Equal compiler-origin references prove both emitted roles retained one preparation, not equivalent recompilations.
-spec same_role_snapshot(hls_generated_files:output()) -> ok.
same_role_snapshot(#{files := Files, result := #{directories := Directories}}) ->
    [First, Second] = [begin
        Bytes = maps:get(filename:join(Directory, "transport.etf"), Files),
        #{bundle := Bundle} = binary_to_term(iolist_to_binary(Bytes)),
        Bundle
    end || {_Role, Directory} <- lists:sort(maps:to_list(Directories))],
    ?assertEqual(First, Second).

%% Each copy retains its original module basename and source options; no checked-in fixture is modified.
-spec copied_sources(map()) -> {file:filename(), map()}.
copied_sources(Config = #{sources := Sources}) ->
    Root = filename:join("_build", "composition-plan-" ++ integer_to_list(erlang:system_time(nanosecond)) ++
        "-" ++ integer_to_list(erlang:unique_integer([positive, monotonic]))),
    ok = file:make_dir(Root),
    Copied = [begin
        Target = filename:join(Root, filename:basename(File)),
        {ok, _} = file:copy(File, Target),
        {Target, Options}
    end || {File, Options} <- Sources],
    {Root, Config#{sources := Copied}}.

%% Source loading is a build side effect; restore checked-in paths and ?FILE for later tests even on failure.
-spec restore_sources(map()) -> ok.
restore_sources(#{sources := Sources}) ->
    lists:foreach(fun({File, Options}) ->
        {ok, Module, Bytes} = compile:file(File, [binary, debug_info, warnings_as_errors, report | Options]),
        {module, Module} = code:load_binary(Module, File, Bytes)
    end, Sources).

%% One source becomes invalid Erlang and the rest move away; successful emission must use retained data.
-spec invalidate_sources([{file:filename(), list()}]) -> ok.
invalidate_sources([{First, _} | Rest]) ->
    ok = file:write_file(First, <<"This source is unavailable to a new compiler invocation.\n">>),
    lists:foreach(fun({File, _}) -> ok = file:rename(File, File ++ ".prepared") end, Rest).

%% The BEAM-owned producer has one recipient while native producers retain multicast.
-spec mixed() -> map().
mixed() ->
    Config = #{sources := Sources} = partition(),
    Config#{sources := Sources ++ [{"test/hls_protocol_mixed_tests.erl", []}],
        topology := {hls_protocol_mixed_tests, topology, []}}.

%% Both roles share the same two actor modules and one global source topology.
-spec deployment() -> map().
deployment() -> (base())#{
    devices => #{north => #{native_actors => [left, sink], host => 2, service => 29},
        south => #{native_actors => [right], host => 3, service => 31}},
    limits => #{crossings => 8, commands => 8, events => 8}}.

%% Static interface fields survive emission; observation mode becomes its generated catalog.
-spec check_manifest(map(), map()) -> ok.
check_manifest(Interface, Manifest) ->
    ?assertEqual(maps:remove(inspection, Interface),
        maps:with(maps:keys(maps:remove(inspection, Interface)), Manifest)),
    ?assert(is_map(maps:get(inspection, Manifest))),
    ?assertEqual(64, byte_size(maps:get(dslx_sha256, Manifest))).

%% Existing four-producer fixture contains shared, singleton and empty external endpoints.
-spec whole() -> map().
whole() -> #{sources => [{"test/hls_protocol_boundary_fixture.erl", []}],
    topology => {hls_protocol_boundary_fixture, topology, []}, actor_limit => 4}.

%% Global identities remain left=0, right=1 and sink=2 across the two native actors.
-spec partition() -> map().
partition() -> (base())#{native_actors => [left, sink], host => 2, service => 29}.

%% The same feedback actors provide source-correct incoming/outgoing framing classes.
-spec base() -> map().
base() -> #{sources => [{"test/hls_protocol_network_fixture.erl", []},
    {"test/hls_protocol_inbox_fixture.erl", []}],
    topology => {hls_protocol_network_fixture, framed, []}, actor_limit => 3, control => rectangle}.

%% Only the topology constructor changes for the two placement-negative fixtures.
-spec fixture(atom()) -> map().
fixture(Function) ->
    Config = #{sources := Sources} = base(),
    Config#{sources := Sources ++ [{"test/hls_protocol_composition_fixture.erl", []}],
        topology := {hls_protocol_composition_fixture, Function, []}}.

%% A private trace session observes this caller only; a delivery barrier precedes collection.
-spec trace_renderers(fun(() -> term())) -> {term(), map()}.
trace_renderers(Build) -> trace_calls(Build, renderer_targets()).

%% Trace leaf renderers as well as composition wrappers, so moving generation into planning is observable.
-spec renderer_targets() -> [{module(), atom(), arity()}].
renderer_targets() -> composition_targets() ++ [
    {xls_activation_codegen, artifact, 1}, {xls_local_owner, ports, 2},
    {xls_template, render, 2}, {xls_protocol_transport, emit, 1}].

%% Existing complete-renderer controls retain exact composition multiplicities.
-spec composition_targets() -> [{module(), atom(), arity()}].
composition_targets() -> [{hls_protocol_transport, emit, 1}, {xls_protocol_network, emit, 3},
    {xls_protocol_boundary, emit, 2}, {xls_protocol_bridge, emit, 3},
    {xls_protocol_application, emit, 1}, {hls_protocol_inspection, emit, 1}].

%% Source preparation and source topology evaluation are distinct from support/template reads.
-spec source_targets() -> [{module(), atom(), arity()}].
source_targets() -> [{compile, file, 2}, {xls_actor_program, from_file, 3},
    {xls_statem_plan, from_file, 3}, {hls_protocol_transport, prepare, 1},
    {hls_protocol_topology, elaborate, 2}].

%% Select actual hardware generation without counting legitimate source preparation during planning.
-spec renderer_calls(map()) -> map().
renderer_calls(Calls) -> maps:with(renderer_targets(), Calls).

%% Emission must not recompile callbacks or reevaluate the source topology constructor.
-spec source_calls(map()) -> map().
source_calls(Calls) -> maps:with(source_targets(), Calls).

%% Exact parent counts and nonzero leaf counts establish that the planning negatives use live traces.
-spec assert_emissions(map(), map()) -> ok.
assert_emissions(Expected, Calls) ->
    ?assertEqual(Expected, maps:with(composition_targets(), Calls)),
    assert_early_emissions(Calls).

%% Ordinary execution, clock-owner ports and receiver templates are each observed at emission.
-spec assert_early_emissions(map()) -> ok.
assert_early_emissions(Calls) ->
    lists:foreach(fun(Target) -> ?assert(maps:get(Target, Calls, 0) > 0) end,
        [{xls_activation_codegen, artifact, 1}, {xls_local_owner, ports, 2},
         {xls_template, render, 2}]).

%% A private trace session observes only this caller and waits for all call events before returning.
-spec trace_calls(fun(() -> term()), [{module(), atom(), arity()}]) -> {term(), map()}.
trace_calls(Build, Targets) ->
    lists:foreach(fun({Module, _, _}) -> {module, Module} = code:ensure_loaded(Module) end, Targets),
    {Collector, Monitor} = spawn_monitor(fun() -> collect(#{}) end),
    Session = trace:session_create(protocol_composition_emission, Collector, []),
    try
        1 = trace:process(Session, self(), true, [call]),
        lists:foreach(fun(Target) -> 1 = trace:function(Session, Target, [], []) end, Targets),
        Result = Build(),
        1 = trace:process(Session, self(), false, [call]),
        Ref = trace:delivered(Session, self()),
        receive {trace_delivered, _, Ref} -> ok
        after 5000 -> error(composition_trace_delivery_timeout) end,
        Collector ! {collect, self(), Ref},
        receive {Ref, Counts} -> {Result, Counts}
        after 5000 -> error(composition_trace_collection_timeout) end
    after
        trace:session_destroy(Session),
        exit(Collector, kill),
        receive {'DOWN', Monitor, process, Collector, _} -> ok
        after 5000 -> error(composition_trace_cleanup_timeout) end
    end.

%% Retain call counts, never the source program arguments carried in trace messages.
-spec collect(map()) -> ok.
collect(Counts) ->
    receive
        %% A real renderer crossed the checked composition boundary.
        {trace, _, call, {Module, Function, Arguments}} ->
            Key = {Module, Function, length(Arguments)},
            collect(maps:update_with(Key, fun(N) -> N + 1 end, 1, Counts));
        %% The owner confirmed trace delivery before requesting these counts.
        {collect, Owner, Ref} -> Owner ! {Ref, Counts}, ok
    end.
