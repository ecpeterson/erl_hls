-module(hls_target_implementation_plan_tests).

-include_lib("eunit/include/eunit.hrl").

%% A complete homogeneous proposal projects one explicit sharing schedule and stable correlation.
-spec source_protocol_projection_test() -> ok.
source_protocol_projection_test() ->
    Topology = topology([a, b, c], actor_math),
    Plan = plan(Topology, fpga, [schedule(shared, fpga, actor_math, [a, b, c])]),
    Projection = hls_target_implementation_plan:source_protocol(Plan, Topology, fpga),
    ?assertEqual(
        #{
            version => 1,
            backend => source_protocol,
            logical_system => hls_logical_topology:identity(Topology),
            implementation_plan => hls_implementation_plan:identity(Plan),
            target => fpga,
            actors => [a, b, c],
            arithmetic_groups => [[a, b, c]],
            capabilities => #{scalar_completion => true}
        },
        hls_target_implementation_plan:descriptor(Projection)
    ),
    Identity = hls_target_implementation_plan:identity(Projection),
    ?assertEqual(64, byte_size(Identity)),
    ?assertEqual(string:lowercase(Identity), Identity),
    ?assertEqual(
        Identity,
        hls_target_implementation_plan:identity(
            hls_target_implementation_plan:source_protocol(Plan, Topology, fpga)
        )
    ).

%% Empty schedules deliberately preserve three independent local completions.
-spec local_completion_projection_test() -> ok.
local_completion_projection_test() ->
    Topology = topology([a, b, c], actor_math),
    Plan = plan(Topology, fpga, []),
    Projection = hls_target_implementation_plan:source_protocol(Plan, Topology, fpga),
    Descriptor = hls_target_implementation_plan:descriptor(Projection),
    ?assertEqual([], maps:get(arithmetic_groups, Descriptor)),
    ?assertEqual([a, b, c], maps:get(actors, Descriptor)),
    ?assertNot(maps:is_key(native_actors, Descriptor)).

%% Logical correlation, exact actor coverage and one selected target are all mandatory.
-spec correlation_and_placement_rejections_test() -> ok.
correlation_and_placement_rejections_test() ->
    Topology = topology([a, b, c], actor_math),
    Valid = plan(Topology, fpga, []),
    ?assertError(
        {target_implementation_plan, {logical_system_mismatch, _, <<"other">>}},
        hls_target_implementation_plan:source_protocol(
            Valid#{logical_system := <<"other">>}, Topology, fpga
        )
    ),
    Missing = Valid#{placement := #{{actor, a} => fpga, {actor, b} => fpga}},
    ?assertError(
        {target_implementation_plan, {actor_coverage_mismatch, [{actor, c}], []}},
        hls_target_implementation_plan:source_protocol(Missing, Topology, fpga)
    ),
    CrossTarget = Valid#{
        placement := #{
            {actor, a} => fpga, {actor, b} => fpga, {actor, c} => fpga_b
        }
    },
    ?assertError(
        {target_implementation_plan, {multiple_placement_targets, [fpga, fpga_b]}},
        hls_target_implementation_plan:source_protocol(CrossTarget, Topology, fpga)
    ),
    ?assertError(
        {target_implementation_plan, {selected_target_mismatch, fpga_b, fpga}},
        hls_target_implementation_plan:source_protocol(Valid, Topology, fpga_b)
    ).

%% Version 1 requires an exact scalar-completion declaration and exact actor identities.
-spec capability_and_family_rejections_test() -> ok.
capability_and_family_rejections_test() ->
    Topology = topology([a, b, c], actor_math),
    Valid = plan(Topology, fpga, []),
    ?assertError(
        {target_implementation_plan, missing_source_protocol_capability},
        hls_target_implementation_plan:source_protocol(
            Valid#{capabilities := #{}}, Topology, fpga
        )
    ),
    ?assertError(
        {target_implementation_plan,
            {unsupported_source_protocol_capability, #{scalar_completion := false}}},
        hls_target_implementation_plan:source_protocol(
            Valid#{capabilities := #{source_protocol => #{scalar_completion => false}}},
            Topology,
            fpga
        )
    ),
    FamilyTopology = family_topology(),
    FamilyPlan = hls_implementation_plan:new(
        hls_logical_topology:identity(FamilyTopology),
        #{{family, cluster, [0]} => fpga, {family, cluster, [1]} => fpga},
        [],
        #{},
        capability(),
        provenance()
    ),
    ?assertError(
        {target_implementation_plan,
            {unsupported_actor_families, [{family, cluster, [0]}, {family, cluster, [1]}]}},
        hls_target_implementation_plan:source_protocol(FamilyPlan, FamilyTopology, fpga)
    ).

%% Source sharing rejects singleton, module-mismatched and ambiguously named requests.
-spec schedule_rejections_test() -> ok.
schedule_rejections_test() ->
    Topology = topology([a, b, c, d], actor_math),
    Singleton = plan(Topology, fpga, [schedule(one, fpga, actor_math, [a])]),
    ?assertError(
        {target_implementation_plan, {unsupported_schedule_size, one, 1}},
        hls_target_implementation_plan:source_protocol(Singleton, Topology, fpga)
    ),
    WrongModule = plan(Topology, fpga, [schedule(shared, fpga, other_math, [a, b])]),
    ?assertError(
        {target_implementation_plan,
            {schedule_module_mismatch, shared, {actor, a}, other_math, actor_math}},
        hls_target_implementation_plan:source_protocol(WrongModule, Topology, fpga)
    ),
    DuplicateIds = plan(Topology, fpga, [
        schedule(shared, fpga, actor_math, [a, b]),
        schedule(shared, fpga, actor_math, [c, d])
    ]),
    ?assertError(
        {target_implementation_plan, {duplicate_schedule_ids, [shared]}},
        hls_target_implementation_plan:source_protocol(DuplicateIds, Topology, fpga)
    ).

%% The projection identity changes with an explicit arithmetic assignment.
-spec projection_identity_tracks_target_policy_test() -> ok.
projection_identity_tracks_target_policy_test() ->
    Topology = topology([a, b, c], actor_math),
    Local = hls_target_implementation_plan:source_protocol(
        plan(Topology, fpga, []), Topology, fpga
    ),
    Shared = hls_target_implementation_plan:source_protocol(
        plan(Topology, fpga, [schedule(shared, fpga, actor_math, [a, b, c])]),
        Topology,
        fpga
    ),
    ?assertNotEqual(
        hls_target_implementation_plan:identity(Local),
        hls_target_implementation_plan:identity(Shared)
    ).

%% Construct one exact-actor topology with a process-free homogeneous interface.
-spec topology([hls_logical_topology:id(), ...], module()) ->
    hls_logical_topology:compact_plan().
topology(Ids, Module) ->
    hls_logical_topology:normalize(
        topology_spec(maps:from_list([{Id, Module} || Id <- Ids]), #{}),
        #{Module => interface(Module)}
    ).

%% Construct a compact family topology to exercise the explicit version-1 rejection.
-spec family_topology() -> hls_logical_topology:compact_plan().
family_topology() ->
    hls_logical_topology:normalize(
        topology_spec(#{}, #{cluster => #{module => actor_math, shape => [2]}}),
        #{actor_math => interface(actor_math)}
    ).

%% Supply the complete normalized-topology vocabulary without communication edges.
-spec topology_spec(map(), map()) -> hls_logical_topology:spec().
topology_spec(Actors, Families) ->
    #{
        version => 1,
        actors => Actors,
        families => Families,
        externals => [],
        ingresses => [],
        routes => [],
        route_relations => [],
        startup => []
    }.

%% Build a valid empty-message interface sufficient for target-only planning checks.
-spec interface(module()) -> hls_process_interface:interface().
interface(Module) ->
    hls_process_interface:new(#{
        version => 1,
        module => Module,
        mailbox_capacity => 4,
        outputs => [],
        schemas => [],
        dispatched_schemas => [],
        emitted_schemas => #{}
    }).

%% Bind every exact actor to one target and retain explicit schedule requests.
-spec plan(
    hls_logical_topology:compact_plan(),
    hls_implementation_plan:target(),
    [hls_implementation_plan:schedule()]
) -> hls_implementation_plan:plan().
plan(Topology, Target, Schedules) ->
    Placement = maps:from_list([
        {Identity, Target}
     || #{identity := Identity} <- hls_logical_topology:instances(Topology)
    ]),
    hls_implementation_plan:new(
        hls_logical_topology:identity(Topology),
        Placement,
        Schedules,
        #{},
        capability(),
        provenance()
    ).

%% Name one target schedule from raw exact actor IDs.
-spec schedule(
    hls_logical_identity:id(),
    hls_implementation_plan:target(),
    module(),
    [hls_logical_topology:id(), ...]
) -> hls_implementation_plan:schedule().
schedule(Id, Target, Module, Members) ->
    #{
        id => Id,
        target => Target,
        module => Module,
        members => [{actor, Member} || Member <- Members]
    }.

%% Declare the only source-protocol capability interpreted by this projection.
-spec capability() -> map().
capability() -> #{source_protocol => #{scalar_completion => true}}.

%% Retain a deterministic synthetic planner identity for test proposals.
-spec provenance() -> hls_implementation_plan:provenance().
provenance() -> #{planner => <<"target projection fixture">>, inputs => []}.
