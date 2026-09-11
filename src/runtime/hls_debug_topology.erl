-module(hls_debug_topology).
-moduledoc """
Logical actor targets derived from the normalized topology and scheduler plan.

CPU bindings name actual hls_statem processes. Hardware bindings describe
placement and related monitored boundaries; they do not infer mailbox state
from a scheduler's transport FIFOs or attribute shared events to one actor.
Boundary targets must explicitly describe the monitored interface, not an
actor behind it. These host bindings do not attest to a bitstream's identity.
Physical resource sessions independently verify their RTL manifest fingerprint.
""".
-export([cpu/2, hardware/3, actors/1, actor/2, boundaries/1]).
-export_type([actor_id/0]).

-type actor_id() :: {actor, term()} | {family, term(), [non_neg_integer()]}.

-doc "Binds every logical actor to its CPU reference process.".
-spec cpu(hls_topology:plan(), #{actor_id() := pid()}) -> map().
cpu(Plan, Processes) ->
    Logical = logical_actors(Plan),
    case {maps:keys(Logical) -- maps:keys(Processes), maps:keys(Processes) -- maps:keys(Logical)} of
        {[], []} -> ok;
        {Missing, Extra} -> error({process_bindings, lists:sort(Missing), lists:sort(Extra)})
    end,
    Targets = maps:map(fun(Id, Metadata) ->
        Pid = maps:get(Id, Processes),
        ActorMetadata = maps:remove(mailbox_capacity, Metadata),
        {actor, ActorMetadata#{scope => #{kind => actor, backend => erts, id => Id},
            placement => #{kind => process, pid => Pid}, boundaries => []}, {hls_statem, Pid}}
    end, Logical),
    #{actors => Targets, boundaries => []}.

-doc "Describes hardware placement and explicitly related shared boundary monitors.".
-spec hardware(hls_topology:plan(), hls_scheduler_plan:spec(),
    [{boundary, pid(), term()}]) -> map().
hardware(Plan, SchedulerSpecs, Boundaries) ->
    #{groups := Groups} = hls_scheduler_plan:normalize(Plan, SchedulerSpecs),
    Placements = maps:from_list(lists:append([
        group_placements(Group, Index) || {Index, Group} <- lists:enumerate(0, Groups)])),
    Logical = logical_actors(Plan),
    BoundaryIds = [Id || {boundary, _Client, Id} <- Boundaries],
    case BoundaryIds -- lists:usort(BoundaryIds) of
        [] -> ok;
        Duplicates -> error({duplicate_boundaries, Duplicates})
    end,
    Targets = maps:map(fun(Id, Metadata) ->
        {actor, Metadata#{scope => #{kind => actor, backend => hardware, id => Id},
            placement => maps:get(Id, Placements, #{kind => direct}),
            boundaries => Boundaries}, none}
    end, Logical),
    #{actors => Targets, boundaries => Boundaries}.

-spec actors(map()) -> [actor_id()].
actors(#{actors := Actors}) -> lists:sort(maps:keys(Actors)).

-spec actor(map(), actor_id()) -> {ok, hls_debug_target:target()} | {error, term()}.
actor(#{actors := Actors}, Id) ->
    case maps:find(Id, Actors) of
        {ok, Target} -> {ok, Target};
        error -> {error, {unknown_actor, Id}}
    end.

boundaries(#{boundaries := Boundaries}) -> Boundaries.

logical_actors(Plan) ->
    maps:from_list([{Id, #{identity => Id, module => Module, mailbox_capacity => Capacity}} ||
        {Id, Module, Capacity} <- instances(Plan)]).

instances(#{actors := Actors, families := Families}) ->
    [{{actor, Id}, Module, Capacity} ||
        #{id := Id, module := Module, mailbox_capacity := Capacity} <- Actors] ++
    [{{family, Id, [X, Y]}, Module, Capacity} ||
        #{id := Id, module := Module, mailbox_capacity := Capacity, shape := [Width, Height]} <- Families,
        X <- lists:seq(0, Width-1), Y <- lists:seq(0, Height-1)].

group_placements(#{id := GroupId, members := Members}, Index) ->
    [{instance_id(Member, Instance), #{kind => scheduler, id => GroupId,
        index => Index, slot => Base + Local}} ||
        Member = #{base_slot := Base, instances := Instances} <- Members,
        Instance = #{local_index := Local} <- Instances].

instance_id(#{kind := actor, id := Id}, _) -> {actor, Id};
instance_id(#{kind := family, id := Id}, #{coordinates := Coordinates}) ->
    {family, Id, Coordinates}.
