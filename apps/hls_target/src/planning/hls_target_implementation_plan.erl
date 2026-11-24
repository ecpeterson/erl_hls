-module(hls_target_implementation_plan).
-moduledoc """
Projects a shared implementation proposal into one checked target policy.

The first source-protocol projection accepts one complete exact-actor placement on one target.
Explicit schedules become scalar-completion arithmetic groups; unscheduled actors retain their
ordinary local completion. The projection is target configuration and correlation evidence, not
generated hardware, a source-eligibility result, or physical characterization.
""".

%% Checked target projection and public views.
-export([source_protocol/3, descriptor/1, identity/1]).
-export_type([descriptor/0, plan/0]).

-record(plan, {descriptor :: descriptor(), identity :: binary()}).

-doc "A checked in-process target projection. Retain it unchanged; descriptor/1 exposes the stable public value.".
-opaque plan() :: #plan{}.

-doc "The source-protocol policy selected from one exact logical topology and implementation plan.".
-type descriptor() :: #{
    version := 1,
    backend := source_protocol,
    logical_system := binary(),
    implementation_plan := binary(),
    target := hls_implementation_plan:target(),
    actors := [hls_logical_topology:id(), ...],
    arithmetic_groups := [[hls_logical_topology:id(), ...]],
    capabilities := #{scalar_completion := true}
}.

-doc "Validates exact topology correlation, complete exact-actor placement on `Target`, homogeneous scheduled modules and the explicit `source_protocol.scalar_completion` capability. Schedules of two or three actors project to `arithmetic_groups`; an empty schedule list selects local completion. Actor families, multiple targets and ambiguous schedule identities are unsupported in version 1. No source is loaded and no hardware is emitted.".
-spec source_protocol(
    hls_implementation_plan:plan(),
    hls_logical_topology:compact_plan(),
    hls_implementation_plan:target()
) -> plan().
source_protocol(ImplementationPlan, LogicalTopology, Target) ->
    ok = valid_plan(ImplementationPlan),
    ok = valid_target(Target),
    LogicalSystem = logical_identity(LogicalTopology),
    ok = correlated_logical_system(ImplementationPlan, LogicalSystem),
    Instances = hls_logical_topology:instances(LogicalTopology),
    {ActorIds, ActorIndex} = exact_actors(Instances),
    Placement = hls_implementation_plan:placement(ImplementationPlan),
    ok = actor_coverage(Instances, Placement),
    ok = selected_target(Placement, Target),
    ok = scalar_completion(hls_implementation_plan:capabilities(ImplementationPlan)),
    Schedules = hls_implementation_plan:schedules(ImplementationPlan),
    ok = unique_schedule_ids(Schedules),
    Groups = [schedule(Schedule, Target, ActorIndex) || Schedule <- Schedules],
    Descriptor = #{
        version => 1,
        backend => source_protocol,
        logical_system => LogicalSystem,
        implementation_plan => hls_implementation_plan:identity(ImplementationPlan),
        target => Target,
        actors => ActorIds,
        arithmetic_groups => Groups,
        capabilities => #{scalar_completion => true}
    },
    #plan{descriptor = Descriptor, identity = descriptor_identity(Descriptor)}.

-doc "Returns the stable source-protocol policy and correlation descriptor without re-reading topology or plan state.".
-spec descriptor(plan()) -> descriptor().
descriptor(#plan{descriptor = Descriptor}) -> Descriptor.

-doc "Returns the lowercase SHA-256 identity of the checked, domain-separated descriptor.".
-spec identity(plan()) -> binary().
identity(#plan{identity = Identity}) -> Identity.

%% Convert shared-plan validation failures into this target projection's error domain.
-spec valid_plan(term()) -> ok.
valid_plan(Plan) ->
    case hls_implementation_plan:validate(Plan) of
        ok -> ok;
        {error, Reason} -> fail({invalid_implementation_plan, Reason})
    end.

%% Target identity remains logical policy rather than a runtime endpoint.
-spec valid_target(term()) -> ok.
valid_target(Target) ->
    case hls_logical_identity:is_valid(Target) of
        true -> ok;
        false -> fail({invalid_target, Target})
    end.

%% Normalize topology errors before admitting a plan against its claimed logical identity.
-spec logical_identity(term()) -> binary().
logical_identity(LogicalTopology) ->
    try hls_logical_topology:identity(LogicalTopology) of
        Identity -> Identity
    catch
        error:Reason -> fail({invalid_logical_topology, Reason})
    end.

%% Require the plan to name this exact canonical logical topology.
-spec correlated_logical_system(hls_implementation_plan:plan(), binary()) -> ok.
correlated_logical_system(ImplementationPlan, LogicalSystem) ->
    case hls_implementation_plan:logical_system(ImplementationPlan) of
        LogicalSystem -> ok;
        Claimed -> fail({logical_system_mismatch, LogicalSystem, Claimed})
    end.

%% Version 1 has no rule for expanding or assigning compact actor families.
-spec exact_actors([hls_logical_topology:instance()]) ->
    {[hls_logical_topology:id(), ...], #{hls_actor_identity:id() => map()}}.
exact_actors(Instances) ->
    case [Identity || #{identity := Identity} <- Instances, not is_exact_actor(Identity)] of
        [] ->
            Pairs = [
                {Identity, Actor}
             || #{identity := Identity = {actor, _}, actor := Actor} <- Instances
            ],
            {[Id || {{actor, Id}, _} <- Pairs], maps:from_list(Pairs)};
        Unsupported ->
            fail({unsupported_actor_families, Unsupported})
    end.

%% Identify the exact actor observation domain accepted by this projection.
-spec is_exact_actor(term()) -> boolean().
is_exact_actor({actor, _}) -> true;
is_exact_actor(_) -> false.

%% Placement must neither omit a topology instance nor introduce an unrelated identity.
-spec actor_coverage(
    [hls_logical_topology:instance()], hls_implementation_plan:placement()
) -> ok.
actor_coverage(Instances, Placement) ->
    Expected = lists:sort([Identity || #{identity := Identity} <- Instances]),
    Actual = lists:sort(maps:keys(Placement)),
    case {Expected -- Actual, Actual -- Expected} of
        {[], []} when length(Expected) =:= length(Actual) -> ok;
        {Missing, Extra} -> fail({actor_coverage_mismatch, Missing, Extra})
    end.

%% A whole source-protocol network has one selected physical target in version 1.
-spec selected_target(
    hls_implementation_plan:placement(), hls_implementation_plan:target()
) -> ok.
selected_target(Placement, Target) ->
    case lists:usort(maps:values(Placement)) of
        [Target] -> ok;
        [Other] -> fail({selected_target_mismatch, Target, Other});
        Targets -> fail({multiple_placement_targets, Targets})
    end.

%% Capability ownership stays in hls_target; the shared plan intentionally treats it as opaque.
-spec scalar_completion(map()) -> ok.
scalar_completion(Capabilities) ->
    case maps:find(source_protocol, Capabilities) of
        {ok, #{scalar_completion := true} = SourceProtocol} when
            map_size(SourceProtocol) =:= 1
        ->
            ok;
        {ok, SourceProtocol} ->
            fail({unsupported_source_protocol_capability, SourceProtocol});
        error ->
            fail(missing_source_protocol_capability)
    end.

%% Duplicate request names would make evidence and later schedule selection ambiguous.
-spec unique_schedule_ids([hls_implementation_plan:schedule()]) -> ok.
unique_schedule_ids(Schedules) ->
    Ids = [maps:get(id, Schedule) || Schedule <- Schedules],
    case duplicates(Ids) of
        [] -> ok;
        Duplicates -> fail({duplicate_schedule_ids, Duplicates})
    end.

%% Project one homogeneous explicit actor group to the source-protocol actor-ID domain.
-spec schedule(
    hls_implementation_plan:schedule(),
    hls_implementation_plan:target(),
    #{hls_actor_identity:id() => map()}
) -> [hls_logical_topology:id(), ...].
schedule(
    #{id := ScheduleId, target := Target, module := Module, members := Members},
    Target,
    ActorIndex
) ->
    ok = schedule_size(ScheduleId, Members),
    [schedule_member(ScheduleId, Module, Member, ActorIndex) || Member <- Members];
schedule(#{id := ScheduleId, target := Other}, Target, _ActorIndex) ->
    fail({schedule_target_mismatch, ScheduleId, Target, Other}).

%% Shared scalar completion currently owns one cursor bit for two members or two for three.
-spec schedule_size(hls_logical_identity:id(), [hls_actor_identity:id(), ...]) -> ok.
schedule_size(_ScheduleId, [_, _]) ->
    ok;
schedule_size(_ScheduleId, [_, _, _]) ->
    ok;
schedule_size(ScheduleId, Members) ->
    fail({unsupported_schedule_size, ScheduleId, length(Members)}).

%% Resolve an exact member and require its declared computation module.
-spec schedule_member(
    hls_logical_identity:id(),
    module(),
    hls_actor_identity:id(),
    #{hls_actor_identity:id() => map()}
) -> hls_logical_topology:id().
schedule_member(ScheduleId, Module, Member = {actor, Id}, ActorIndex) ->
    case maps:find(Member, ActorIndex) of
        {ok, #{module := Module}} ->
            Id;
        {ok, #{module := Actual}} ->
            fail({schedule_module_mismatch, ScheduleId, Member, Module, Actual});
        error ->
            fail({unknown_schedule_member, ScheduleId, Member})
    end;
schedule_member(ScheduleId, _Module, Member, _ActorIndex) ->
    fail({unsupported_schedule_member, ScheduleId, Member}).

%% Hash only the stable public value with a module/version domain separator.
-spec descriptor_identity(descriptor()) -> binary().
descriptor_identity(Descriptor) ->
    string:lowercase(
        binary:encode_hex(
            crypto:hash(
                sha256,
                term_to_binary({hls_target_implementation_plan, 1, Descriptor}, [deterministic])
            )
        )
    ).

%% Report repeated exact values in deterministic order.
-spec duplicates([term()]) -> [term()].
duplicates(Values) ->
    lists:usort([Value || Value <- Values, count(Value, Values) > 1]).

%% Count one schedule identity without constructing an intermediate frequency map.
-spec count(term(), [term()]) -> non_neg_integer().
count(Value, Values) -> length([Item || Item <- Values, Item =:= Value]).

%% Keep every admission failure in one target-owned error namespace.
-spec fail(term()) -> no_return().
fail(Reason) -> error({target_implementation_plan, Reason}).
