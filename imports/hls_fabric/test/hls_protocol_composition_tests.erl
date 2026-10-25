-module(hls_protocol_composition_tests).
-moduledoc "Static composition interfaces and early rejection of host/deployment constraints. Tracing checks actual renderer entry; these are compiler tests, not RTL behavior witnesses.".
-include_lib("eunit/include/eunit.hrl").

%% Interfaces and observation mode exist before transport, network or boundary files do.
-spec inspected_plans_test_() -> term().
inspected_plans_test_() -> {timeout, 30, fun inspected_plans/0}.

%% Positive emissions establish that the same tracer observes the complete renderer chain.
-spec inspected_plans() -> ok.
inspected_plans() ->
    Build = hls_protocol_transport:plan(whole()),
    Options = #{inspection => process, activation => explicit_start},
    {{Network, Boundary}, PlanningCalls} = trace_renderers(fun() ->
        {hls_protocol_network:plan(Build, Options), hls_protocol_boundary:plan(Build, Options)}
    end),
    ?assertEqual(#{}, PlanningCalls),
    NetworkInterface = #{actors := 4, native_indices := [0, 1, 2, 3], inspection := process,
        inputs := Inputs} = hls_protocol_network:descriptor(Network),
    ?assert(lists:member(#{name => <<"inspect_address">>, width => 32}, Inputs)),
    BoundaryInterface = #{inspection := process, arbitration_state_bits := 5, externals := Groups} =
        hls_protocol_boundary:descriptor(Boundary),
    ?assertEqual([3, 1, 0], [length(Members) || #{members := Members} <- Groups]),
    ?assertNot(maps:is_key(dslx_sha256, NetworkInterface)),
    ?assertNot(maps:is_key(components, NetworkInterface)),
    ?assertNot(maps:is_key(dslx_sha256, BoundaryInterface)),
    {{NetworkOutput, BoundaryOutput}, Calls} = trace_renderers(fun() ->
        {hls_protocol_network:emit(Network), hls_protocol_boundary:emit(Boundary)}
    end),
    ?assertEqual(#{
        {hls_protocol_transport, emit, 1} => 2,
        {xls_protocol_network, emit, 2} => 2,
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
    Build = hls_protocol_transport:plan(partition()),
    {Plan, PlanningCalls} = trace_renderers(fun() ->
        hls_protocol_bridge:plan(Build, #{host => 2, service => 29, control => rectangle})
    end),
    ?assertEqual(#{}, PlanningCalls),
    Interface = #{native_indices := [0, 2], incoming := Incoming, outgoing := Outgoing,
        links := Links, credits := Credits, actors := 3} = hls_protocol_bridge:descriptor(Plan),
    ?assert(Incoming =/= []),
    ?assert(Outgoing =/= []),
    ?assert(Credits =/= []),
    ?assertEqual(lists:sort(Links), lists:sort(Incoming ++ Outgoing)),
    ?assertNot(maps:is_key(identity, Interface)),
    ?assertNot(maps:is_key(libraries, Interface)),
    {#{result := #{bridge := Bridge}}, Calls} = trace_renderers(fun() -> hls_protocol_bridge:emit(Plan) end),
    ?assertEqual(#{
        {hls_protocol_transport, emit, 1} => 1,
        {xls_protocol_network, emit, 2} => 1,
        {xls_protocol_boundary, emit, 2} => 1,
        {xls_protocol_bridge, emit, 3} => 1}, Calls),
    ?assertEqual(Interface, maps:without([identity, libraries], Bridge)),
    ?assertEqual(32, byte_size(maps:get(identity, Bridge))).

%% Unsupported observation cannot trigger a partial transport render through any parent.
-spec partition_inspection_test() -> ok.
partition_inspection_test() ->
    Build = hls_protocol_transport:plan(partition()),
    {ok, Calls} = trace_renderers(fun() ->
        ?assertError(partition_inspection_unavailable,
            hls_protocol_network:plan(Build, #{inspection => process})),
        ?assertError(partition_inspection_unavailable,
            hls_protocol_boundary:plan(Build, #{inspection => process})),
        ?assertError(partition_inspection_unavailable,
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
        ?assertException(error, _, hls_protocol_mixed:emit(Multicast)),
        ?assertError({badmatch, true}, hls_protocol_mixed:emit(HostLink)),
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
    ?assertEqual(#{
        {hls_protocol_transport, emit, 1} => 1,
        {xls_protocol_network, emit, 2} => 1,
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
        ?assertError({badmatch, false}, hls_protocol_deployment:emit(Config)),
        ok
    end),
    ?assertEqual(#{}, Calls).

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
trace_renderers(Build) ->
    Targets = [{hls_protocol_transport, emit, 1}, {xls_protocol_network, emit, 2},
        {xls_protocol_boundary, emit, 2}, {xls_protocol_bridge, emit, 3},
        {xls_protocol_application, emit, 1}, {hls_protocol_inspection, emit, 1}],
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
