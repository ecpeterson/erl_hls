-module(hls_node_topology).
-moduledoc """
Scheduled-node setup derives endpoint and slot bindings here, then hls_node validates and uses the retained descriptor. Debug attachment connects that logical view to hls_shared_debug_catalog.

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
%% Runtime attachment and message binding.
-export([validate/1, encode_cast/2, bind_debug/4]).

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
    Interfaces = hls_actor_interface:from_modules([M || #{module := M} <- Groups]),
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

-doc "Checks deployment coherence before a node reserves its physical endpoints.".
-spec validate(map()) -> ok.
validate(#{actors := [_ | _] = Actors, groups := [_ | _] = Groups}) ->
    GroupIds = [Id || #{id := Id} <- Groups],
    ok = unique(duplicate_scheduler_groups, GroupIds),
    ok = unique(duplicate_endpoints, [E || #{endpoint := E} <- Groups]),
    Indices = lists:sort([I || #{index := I} <- Groups]),
    true = Indices =:= lists:seq(0, length(Groups) - 1),
    lists:foreach(
        fun(#{module := M, slot_count := Count, endpoint := E}) when
            is_atom(M),
            is_integer(Count),
            Count > 0,
            Count =< 16#100000000,
            is_integer(E),
            E >= 0,
            E =< 65535
        ->
            ok
        end,
        Groups
    ),
    Targets = lists:sort([Target || #{target := Target} <- Actors]),
    case Targets =:= lists:seq(0, length(Actors) - 1) of
        true -> ok;
        false -> error({actor_targets, Targets})
    end,
    ok = unique(duplicate_actor_identities, [Id || #{identity := Id} <- Actors]),
    ById = maps:from_list([{maps:get(id, G), G} || G <- Groups]),
    [ok = validate_actor(Actor, ById) || Actor <- Actors],
    ok = unique(duplicate_actor_slots, [{E, Slot} || #{endpoint := E, slot := Slot} <- Actors]),
    lists:foreach(
        fun(#{id := Id, slot_count := Count}) ->
            %% Unique bounded slots with the declared population cover the whole
            %% group, including its channel; no second endpoint list is trusted.
            case length([ok || #{placement := #{id := Group}} <- Actors, Group =:= Id]) of
                Count -> ok;
                _ -> error({actor_slots, Id})
            end
        end,
        Groups
    ),
    ok;
validate(_) ->
    error(invalid_topology_deployment).

%% Check that the actor's endpoint and slot agree with its declared scheduler group.
-spec validate_actor(map(), map()) -> ok.
validate_actor(#{identity := Id} = Actor, Groups) ->
    case Actor of
        #{
            kind := actor,
            module := Module,
            endpoint := Endpoint,
            slot := Slot,
            schemas := Schemas,
            placement := #{
                kind := scheduler,
                id := Group,
                index := Index,
                slot := Slot
            }
        } when is_integer(Slot), Slot >= 0, is_map(Schemas) ->
            ok = hls_host_codec:check(Schemas),
            case Groups of
                #{
                    Group := #{
                        module := Module,
                        endpoint := Endpoint,
                        index := Index,
                        slot_count := Count
                    }
                } when Slot < Count ->
                    ok;
                _ ->
                    error({actor_binding, Id})
            end;
        _ ->
            error({actor_binding, Id})
    end.

%% Reject duplicate deployment identities with a domain-specific error tag.
-spec unique(atom(), [term()]) -> ok.
unique(Kind, Values) ->
    case Values -- lists:usort(Values) of
        [] -> ok;
        Duplicates -> error({Kind, lists:usort(Duplicates)})
    end.

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
    Codecs = hls_host_codec:schemas(Interface),
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

-doc "Packs a cast with its scheduler slot; rejects unknown schemas and invalid payloads.".
-spec encode_cast(map(), tuple()) -> {{byte(), 255, 1}, binary()}.
encode_cast(#{slot := Slot, schemas := Schemas}, Message) when
    is_tuple(Message), tuple_size(Message) > 0
->
    Tag = element(1, Message),
    case Schemas of
        #{Tag := #{selector := Selector, width := Width, codec := Codec}} ->
            Packed = hls_record_codec:pack(Codec, Message),
            Width = bit_size(Packed),
            Payload = hls_codec:align(Packed, 32),
            {{Selector, 255, 1}, <<Slot:32/little, Payload/binary>>};
        _ ->
            error({invalid_request, cast, Tag})
    end;
encode_cast(_Actor, _Message) ->
    error(badarg).

-doc "Binds actor snapshots after the device verifies its topology debug manifest.".
-spec bind_debug(hls_topology:plan(), hls_scheduler_plan:spec(), pid(), map()) ->
    {ok, map()} | {error, term()}.
bind_debug(Plan, Specs, DebugPid, Manifest) ->
    case hls_shared_observation:open(DebugPid, Manifest) of
        {ok, Session} -> {ok, hls_shared_debug_catalog:hardware(Plan, Specs, [], Session)};
        Error -> Error
    end.
