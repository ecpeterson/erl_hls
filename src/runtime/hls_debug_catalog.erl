-module(hls_debug_catalog).
-moduledoc """
Logical actor targets and verified committed-state observations.

CPU bindings name actual hls_statem processes. Hardware bindings describe
placement and related monitored boundaries; they do not infer mailbox state
from transport FIFOs or attribute boundary events to one actor.
Boundary targets explicitly describe the monitored interface. hardware/3 is
metadata-only; hardware/4 additionally binds committed-state snapshots through
a verified session and checks the compiler projection against its manifest.
""".
-export([cpu/2, hardware/3, hardware/4, bind/3, actors/1, actor/2, boundaries/1]).
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
-spec hardware(hls_topology:plan(), #{actor_id() => map()},
    [{boundary, pid(), term()}]) -> map().
hardware(Plan, Placements, Boundaries) ->
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

-doc "Binds dedicated actors to a verified committed-state debug session.".
-spec hardware(hls_topology:plan(), #{}, list(), map()) -> map().
hardware(Plan, Empty, Boundaries, Session = #{manifest := Manifest}) when map_size(Empty) =:= 0 ->
    Projection = maps:get(<<"actor_projection">>, Manifest, none),
    ok = xls_actor_debug:validate(Plan, Projection),
    bind(hardware(Plan, Empty, Boundaries), Projection, Session).

-doc "Binds a backend-validated projection to a logical catalog, checking every manifest resource.".
-spec bind(map(), map(), map()) -> map().
bind(Catalog = #{actors := Targets}, Projection, Session = #{manifest := Manifest}) ->
    case maps:get(<<"actor_projection">>, Manifest, none) =:= Projection of
        true -> ok;
        false -> error(actor_projection_mismatch)
    end,
    #{<<"resources">> := Resources, <<"fingerprint">> := Hash} = Manifest,
    ActorResources = [R || R = #{<<"kind">> := <<"actor">>} <- Resources],
    ByKey = maps:from_list([{maps:get(<<"key">>, R), R} || R <- ActorResources]),
    Expected = [maps:merge(A#{<<"bank">> => Index, <<"phases">> => Phases, <<"module">> => Module,
        <<"failures">> => Failures}, observation_fields(Bank)) ||
        #{<<"index">> := Index, <<"phases">> := Phases, <<"module">> := Module,
            <<"actors">> := Actors, <<"failures">> := Failures} = Bank <- maps:get(<<"banks">>, Projection) ++ maps:get(<<"direct">>, Projection, []), A <- Actors],
    case length(ActorResources) =:= map_size(ByKey) andalso
            lists:sort(Expected) =:= lists:sort([maps:with(
                [<<"key">>, <<"name">>, <<"slot">>, <<"bank">>, <<"phases">>, <<"module">>, <<"failures">>, <<"width">>, <<"mailbox_capacity">>, <<"mailbox_kind">>, <<"reduction">>], R)
                || R <- ActorResources]) of
        true -> ok;
        false -> error(actor_resources_mismatch)
    end,
    Catalog#{actors := maps:map(fun(Id, {actor, Metadata, none}) ->
        case maps:find(xls_actor_debug:actor_key(Id), ByKey) of
            {ok, #{<<"id">> := ResourceId} = Resource} ->
                {actor, Metadata#{observation => #{kind => committed_state,
                    mailbox => case maps:get(<<"mailbox_kind">>, Resource, none) of
                        <<"direct">> -> actor_step;
                        none -> unavailable;
                        _Kind -> backend_step
                    end,
                    fingerprint => Hash, resource => ResourceId}},
                    {actor_snapshot, Session, ResourceId}};
            error -> {actor, Metadata, none}
        end
    end, Targets)}.

observation_fields(Bank = #{<<"reduction">> := Reduction = #{<<"width">> := Width}}) ->
    (observation_fields(maps:remove(<<"reduction">>, Bank)))#{
        <<"width">> := 56 + Width, <<"reduction">> => Reduction};
observation_fields(#{<<"mailbox">> := #{<<"capacity">> := Capacity, <<"kind">> := Kind}}) ->
    #{<<"width">> => 56, <<"mailbox_capacity">> => Capacity, <<"mailbox_kind">> => Kind};
observation_fields(_) -> #{<<"width">> => 26}.

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
