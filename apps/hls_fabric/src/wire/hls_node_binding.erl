-module(hls_node_binding).
-moduledoc "Runtime validation and cast packing for retained scheduled-node deployments. hls_node_topology derives endpoint and slot bindings during lowering; node managers and connection workers use this module without topology normalization or actor-interface discovery.".

%% Retained deployment admission and record encoding.
-export([validate/1, encode_cast/2]).

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
