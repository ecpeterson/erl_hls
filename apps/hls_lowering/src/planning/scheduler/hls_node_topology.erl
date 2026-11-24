-module(hls_node_topology).
-moduledoc """
Scheduled-node setup derives endpoint and slot bindings here, then hls_node_binding validates and packs the retained descriptor for hls_node. Debug attachment connects that logical view to hls_shared_debug_catalog.

Binds scheduled logical actors to a private addressed ingress deployment.

The normalized topology and scheduler plan determine logical identities,
modules and RAM slots. The deployment supplies one physical application
endpoint per scheduler group. A matching gateway must realize those bindings;
this descriptor does not connect an arbitrary topology to an ingress.

Actor PIDs accept casts. The ingress envelope carries a scheduler-local slot
followed by the actor's generated packed record. It does not turn emitted
actor effects into replies. Shared topology observations are bound separately
through a fingerprint-checked debug session.
""".
%% Scheduled deployment derivation.
-export([normalize/3]).
%% Source-checked inspection convenience.
-export([bind_debug/4]).

-doc "Binds every scheduled actor to a group endpoint and slot; rejects direct actors and missing or duplicate endpoints.".
-spec normalize(hls_topology:plan(), hls_scheduler_plan:spec(), map()) -> map().
normalize(Plan, Specs, Endpoints) ->
    Scheduler =
        #{groups := Groups, direct_members := Direct} =
        hls_scheduler_plan:normalize(Plan, Specs),
    case Direct of
        [] -> ok;
        _ -> error({unscheduled_actors, Direct})
    end,
    GroupIds = [Id || #{id := Id} <- Groups],
    case {GroupIds -- maps:keys(Endpoints), maps:keys(Endpoints) -- GroupIds} of
        {[], []} -> ok;
        {Missing, Extra} -> error({scheduler_endpoints, Missing, lists:sort(Extra)})
    end,
    Values = maps:values(Endpoints),
    true = lists:all(fun(E) -> is_integer(E) andalso E >= 0 andalso E =< 65535 end, Values),
    case Values -- lists:usort(Values) of
        [] -> ok;
        Duplicates -> error({duplicate_endpoints, lists:usort(Duplicates)})
    end,
    Interfaces = maps:get(interfaces, Scheduler),
    Codecs = maps:map(fun schemas/2, Interfaces),
    Bindings = [group(Group, Index, Endpoints) || {Index, Group} <- lists:enumerate(0, Groups)],
    ById = maps:from_list([{Id, G} || G = #{id := Id} <- Bindings]),
    Actors = [
        actor(Id, Target, Placement, ById, Codecs)
     || {Target, {Id, Placement}} <- lists:enumerate(
            0,
            lists:sort(maps:to_list(hls_scheduler_plan:placements(Scheduler)))
        )
    ],
    #{actors => Actors, groups => Bindings}.

%% Bind a scheduler group to its checked endpoint and dense catalog index.
-spec group(map(), non_neg_integer(), map()) -> map().
group(#{id := Id, module := Module, slot_count := Count}, Index, Endpoints) when
    Count > 0, Count =< 16#100000000
->
    #{
        id => Id,
        index => Index,
        module => Module,
        slot_count => Count,
        endpoint => maps:get(Id, Endpoints)
    }.

%% Attach routing, codec and debug placement metadata to a logical actor identity.
-spec actor(term(), non_neg_integer(), map(), map(), map()) -> map().
actor(Id, Target, Placement = #{id := GroupId, slot := Slot}, ById, Codecs) ->
    #{module := Module, endpoint := Endpoint} = maps:get(GroupId, ById),
    #{
        identity => Id,
        target => Target,
        kind => actor,
        module => Module,
        endpoint => Endpoint,
        slot => Slot,
        placement => Placement,
        schemas => maps:get(Module, Codecs)
    }.

%% Cross-check generated codecs against the actor interface and the three-word payload bound.
-spec schemas(module(), hls_actor_interface:summary()) -> map().
schemas(Module, Interface) ->
    Codecs = hls_host_codec_plan:schemas(Interface),
    maps:from_list([
        begin
            #{selector := Selector, fields := Fields} = hls_actor_interface:schema(Interface, Name),
            Selector = Module:pack_tag(Name),
            Width = lists:sum([hls_type:width(Type) || #{type := Type} <- Fields]),
            Width = Module:pack_width(Name),
            %% The generated actor ABI holds three payload words. The ingress
            %% adds its slot word outside that frame before mailbox admission.
            true = Selector >= 0 andalso Selector =< 255 andalso Width =< 96,
            {Name, maps:get(Name, Codecs)}
        end
     || Name <- hls_actor_interface:dispatched_schemas(Interface)
    ]).

-doc "Binds actor snapshots after the device verifies its topology debug manifest.".
-spec bind_debug(hls_topology:plan(), hls_scheduler_plan:spec(), pid(), map()) ->
    {ok, map()} | {error, term()}.
bind_debug(Plan, Specs, DebugPid, Manifest) ->
    case hls_shared_observation:open(DebugPid, Manifest) of
        {ok, Session} -> {ok, hls_shared_debug_catalog:hardware(Plan, Specs, [], Session)};
        Error -> Error
    end.
