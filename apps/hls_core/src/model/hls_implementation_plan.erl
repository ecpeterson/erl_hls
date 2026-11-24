-module(hls_implementation_plan).
-moduledoc """
Canonical proposed-implementation contract shared by planners and lower layers.

The contract binds a logical-system identity to normalized placement, scheduler requests,
constraints, selected capabilities and provenance. It is neither generated hardware nor a
deployment descriptor. Targets may interpret a checked plan, but they do not own its policy.
""".

-export([new/6, validate/1, identity/1, logical_system/1, placement/1, schedules/1, revise/4]).
-export_type([plan/0, placement/0, provenance/0, schedule/0, target/0]).

-doc "A proposed physical target name, distinct from a runtime endpoint or device session.".
-type target() :: hls_logical_identity:id().

-doc "Complete actor-to-target placement keyed by stable logical observation identity.".
-type placement() :: #{hls_actor_identity:id() => target()}.

-doc "One homogeneous scheduler request. Members retain logical identities and the request does not assert a realized machine layout.".
-type schedule() :: #{
    id := hls_logical_identity:id(),
    target := target(),
    module := module(),
    members := [hls_actor_identity:id(), ...]
}.

-doc "Planner identity and opaque input identities, with an optional characterization basis for a revision.".
-type provenance() :: #{
    planner := binary(),
    inputs := [binary()],
    basis => binary()
}.

-doc "A checked proposed implementation. Constraints and capabilities remain process-free owner-defined terms until lower applications interpret them.".
-type plan() :: #{
    version := 1,
    logical_system := binary(),
    placement := placement(),
    schedules := [schedule()],
    constraints := map(),
    capabilities := map(),
    provenance := provenance()
}.

-doc "Constructs and validates a proposed implementation. Invalid fields raise `{implementation_plan, Reason}`.".
-spec new(binary(), placement(), [schedule()], map(), map(), provenance()) -> plan().
new(LogicalSystem, Placement, Schedules, Constraints, Capabilities, Provenance) ->
    Plan = #{
        version => 1,
        logical_system => LogicalSystem,
        placement => Placement,
        schedules => Schedules,
        constraints => Constraints,
        capabilities => Capabilities,
        provenance => Provenance
    },
    case validate(Plan) of
        ok -> Plan;
        {error, Reason} -> error({implementation_plan, Reason})
    end.

-doc "Checks exact shape, logical identities, unique scheduler membership and provenance without interpreting owner-defined constraints or capabilities.".
-spec validate(term()) -> ok | {error, term()}.
validate(
    #{
        version := 1,
        logical_system := LogicalSystem,
        placement := Placement,
        schedules := Schedules,
        constraints := Constraints,
        capabilities := Capabilities,
        provenance := Provenance
    } = Plan
) when map_size(Plan) =:= 7 ->
    with([
        component(logical_system, LogicalSystem),
        validate_placement(Placement),
        schedules(Schedules, Placement),
        map_field(constraints, Constraints),
        map_field(capabilities, Capabilities),
        provenance(Provenance)
    ]);
validate(_) ->
    {error, invalid_shape}.

-doc "Returns a deterministic lowercase SHA-256 identity for one valid plan.".
-spec identity(plan()) -> binary().
identity(Plan) ->
    ok = valid(Plan),
    string:lowercase(binary:encode_hex(crypto:hash(sha256, term_to_binary(Plan, [deterministic])))).

-doc "Returns the opaque logical-system identity after validating the plan.".
-spec logical_system(plan()) -> binary().
logical_system(Plan) ->
    ok = valid(Plan),
    maps:get(logical_system, Plan).

-doc "Returns the checked actor placement.".
-spec placement(plan()) -> placement().
placement(Plan) ->
    ok = valid(Plan),
    maps:get(placement, Plan).

-doc "Returns checked scheduler requests in retained order.".
-spec schedules(plan()) -> [schedule()].
schedules(Plan) ->
    ok = valid(Plan),
    maps:get(schedules, Plan).

-doc "Creates a checked revision with replacement placement and schedules, retaining the logical system and recording one nonempty characterization identity as its basis.".
-spec revise(plan(), placement(), [schedule()], binary()) -> plan().
revise(Plan, Placement, Schedules, Basis) ->
    ok = valid(Plan),
    ok = component(basis, Basis),
    Provenance0 = maps:get(provenance, Plan),
    Inputs = lists:usort([Basis | maps:get(inputs, Provenance0)]),
    new(
        maps:get(logical_system, Plan),
        Placement,
        Schedules,
        maps:get(constraints, Plan),
        maps:get(capabilities, Plan),
        Provenance0#{inputs := Inputs, basis => Basis}
    ).

%% Accept only nonempty opaque binary identities.
-spec component(atom(), term()) -> ok | {error, term()}.
component(_Name, Value) when is_binary(Value), byte_size(Value) > 0 -> ok;
component(Name, Value) -> {error, {invalid_component, Name, Value}}.

%% Placement keys and targets remain in their separate logical identity domains.
-spec validate_placement(term()) -> ok | {error, term()}.
validate_placement(Placement) when is_map(Placement), map_size(Placement) > 0 ->
    with([
        case {actor_identity(Actor), logical_identity(Target)} of
            {ok, ok} -> ok;
            {{error, Why}, _} -> {error, Why};
            {_, {error, Why}} -> {error, Why}
        end
     || {Actor, Target} <- maps:to_list(Placement)
    ]);
validate_placement(Placement) ->
    {error, {invalid_placement, Placement}}.

%% A scheduler member occurs once and must be placed on that scheduler's target.
-spec schedules(term(), placement()) -> ok | {error, term()}.
schedules(Schedules, Placement) when is_list(Schedules) ->
    case with([schedule(Schedule, Placement) || Schedule <- Schedules]) of
        ok -> unique_members(Schedules);
        Error -> Error
    end;
schedules(Schedules, _Placement) ->
    {error, {invalid_schedules, Schedules}}.

%% Validate one exact scheduler request without assigning physical slots.
-spec schedule(term(), placement()) -> ok | {error, term()}.
schedule(
    #{id := Id, target := Target, module := Module, members := [_ | _] = Members} = Schedule,
    Placement
) when
    map_size(Schedule) =:= 4, is_atom(Module)
->
    case {logical_identity(Id), logical_identity(Target), unique(Members)} of
        {ok, ok, true} ->
            with([scheduler_member(Member, Target, Placement) || Member <- Members]);
        {{error, Why}, _, _} ->
            {error, Why};
        {_, {error, Why}, _} ->
            {error, Why};
        {_, _, false} ->
            {error, {duplicate_schedule_members, Id}}
    end;
schedule(Schedule, _Placement) ->
    {error, {invalid_schedule, Schedule}}.

%% Check stable member identity and exact placement target.
-spec scheduler_member(term(), target(), placement()) -> ok | {error, term()}.
scheduler_member(Member, Target, Placement) ->
    case actor_identity(Member) of
        {error, Why} ->
            {error, Why};
        ok ->
            case maps:find(Member, Placement) of
                {ok, Target} -> ok;
                {ok, Other} -> {error, {schedule_target_mismatch, Member, Target, Other}};
                error -> {error, {unplaced_schedule_member, Member}}
            end
    end.

%% Reject membership in two requested schedulers.
-spec unique_members([schedule()]) -> ok | {error, term()}.
unique_members(Schedules) ->
    Members = lists:append([maps:get(members, Schedule) || Schedule <- Schedules]),
    case unique(Members) of
        true -> ok;
        false -> {error, duplicate_scheduler_membership}
    end.

%% Actor observation identities preserve exact and bounded-family domains.
-spec actor_identity(term()) -> ok | {error, term()}.
actor_identity({actor, Id}) ->
    logical_identity(Id);
actor_identity({family, Family, Coordinates}) when is_list(Coordinates), Coordinates =/= [] ->
    case logical_identity(Family) of
        ok ->
            case lists:all(fun(C) -> is_integer(C) andalso C >= 0 end, Coordinates) of
                true -> ok;
                false -> {error, {invalid_actor_identity, {family, Family, Coordinates}}}
            end;
        Error ->
            Error
    end;
actor_identity(Id) ->
    {error, {invalid_actor_identity, Id}}.

%% Reuse the logical identity validator while retaining a nonthrowing contract API.
-spec logical_identity(term()) -> ok | {error, term()}.
logical_identity(Id) ->
    case hls_logical_identity:is_valid(Id) of
        true -> ok;
        false -> {error, {invalid_logical_identity, Id}}
    end.

%% Provenance is exact except for the optional revision basis.
-spec provenance(term()) -> ok | {error, term()}.
provenance(#{planner := Planner, inputs := Inputs} = Provenance) when
    is_list(Inputs), map_size(Provenance) >= 2, map_size(Provenance) =< 3
->
    case lists:sort(maps:keys(Provenance)) -- [basis, inputs, planner] of
        [] ->
            with(
                [component(planner, Planner)] ++
                    [component(input, Input) || Input <- Inputs] ++
                    case maps:find(basis, Provenance) of
                        error -> [];
                        {ok, Basis} -> [component(basis, Basis)]
                    end
            );
        _ ->
            {error, {invalid_provenance, Provenance}}
    end;
provenance(Provenance) ->
    {error, {invalid_provenance, Provenance}}.

%% Owner-defined fields must remain maps so extensions stay namespaced.
-spec map_field(atom(), term()) -> ok | {error, term()}.
map_field(_Name, Value) when is_map(Value) -> ok;
map_field(Name, Value) -> {error, {invalid_field, Name, Value}}.

%% Return the first validation failure in deterministic field order.
-spec with([ok | {error, term()}]) -> ok | {error, term()}.
with([]) -> ok;
with([ok | Rest]) -> with(Rest);
with([{error, _} = Error | _]) -> Error.

%% Deterministic plans reject repeated exact terms.
-spec unique([term()]) -> boolean().
unique(Values) -> length(Values) =:= length(lists:usort(Values)).

%% Internal accessors raise the same public plan reason on malformed terms.
-spec valid(term()) -> ok.
valid(Plan) ->
    case validate(Plan) of
        ok -> ok;
        {error, Reason} -> error({implementation_plan, Reason})
    end.
