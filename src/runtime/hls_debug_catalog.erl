-module(hls_debug_catalog).
-moduledoc """
Logical actor targets derived from the normalized topology and scheduler plan.

CPU bindings name actual hls_statem processes. Hardware bindings describe
placement and related monitored boundaries; they do not infer mailbox state
from a scheduler's transport FIFOs or attribute shared events to one actor.
Boundary targets explicitly describe the monitored interface. hardware/3 is
metadata-only; hardware/4 additionally binds committed-state snapshots through
a verified session and checks the compiler projection against its manifest.
""".
-export([cpu/2, hardware/3, hardware/4, actors/1, actor/2, boundaries/1]).
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
    Scheduler = hls_scheduler_plan:normalize(Plan, SchedulerSpecs),
    Placements = hls_scheduler_plan:placements(Scheduler),
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

-doc "Binds shared actors to committed-state snapshots in a verified topology debug session.".
hardware(Plan, Specs, Boundaries, Session = #{manifest := Manifest}) ->
    Projection = xls_scheduler_debug:projection(Plan, Specs),
    case maps:get(<<"actor_projection">>, Manifest, none) of
        Projection -> ok;
        _ -> error(actor_projection_mismatch)
    end,
    #{<<"resources">> := Resources, <<"fingerprint">> := Hash} = Manifest,
    ActorResources = [R || R = #{<<"kind">> := <<"actor">>} <- Resources],
    ByKey = maps:from_list([{maps:get(<<"key">>, R), R} || R <- ActorResources]),
    Expected = [A#{<<"bank">> => Index, <<"phases">> => Phases, <<"module">> => Module, <<"failures">> => Failures, <<"width">> => 26} ||
        #{<<"index">> := Index, <<"phases">> := Phases, <<"module">> := Module,
            <<"actors">> := Actors, <<"failures">> := Failures} <- maps:get(<<"banks">>, Projection), A <- Actors],
    case length(ActorResources) =:= map_size(ByKey) andalso
            lists:sort(Expected) =:= lists:sort([maps:with(
                [<<"key">>, <<"name">>, <<"slot">>, <<"bank">>, <<"phases">>, <<"module">>, <<"failures">>, <<"width">>], R)
                || R <- ActorResources]) of
        true -> ok;
        false -> error(actor_resources_mismatch)
    end,
    Catalog = #{actors := Targets} = hardware(Plan, Specs, Boundaries),
    Catalog#{actors := maps:map(fun(Id, {actor, Metadata, none}) ->
        case maps:find(xls_scheduler_debug:actor_key(Id), ByKey) of
            {ok, #{<<"id">> := ResourceId}} ->
                {actor, Metadata#{observation => #{kind => committed_state,
                    fingerprint => Hash, resource => ResourceId}},
                    {actor_snapshot, Session, ResourceId}};
            error -> {actor, Metadata, none}
        end
    end, Targets)}.

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
