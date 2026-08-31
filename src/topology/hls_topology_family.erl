%%%% hls_topology_family
%%%%
%%%% Normalizes the first compact actor-family and route-relation subset.

-module(hls_topology_family).
-moduledoc """
Internal family normalizer used by `hls_topology`.

The supported compact subset is intentionally small: zero-based rectangular
families and same-shape wrapped translations. Relations currently target
families or external outputs; routes do not yet cross between the exact and
family sections. Family members and route pairs are never enumerated during
normalization.
""".

-export([normalize/2, routes_for_instance/3]).

-spec normalize(map(), fun((map()) -> map())) -> map().
normalize(
    Spec = #{
        actors := ActorSpecs,
        families := FamilySpecs,
        route_relations := RelationSpecs
    },
    NormalizeExact
) ->
    Families = normalize_families(FamilySpecs),
    FamilyIndex = index_by_id(Families),
    ok = reject_family_namespace_collisions(Families),
    ok = reject_actor_family_collisions(
        ActorSpecs,
        FamilyIndex
    ),
    Exact = #{externals := Externals} = NormalizeExact(Spec),
    ExternalIndex = index_by_id(Externals),
    Relations = normalize_route_relations(
        RelationSpecs,
        FamilyIndex,
        ExternalIndex
    ),
    Exact#{
        families => strip_interfaces(Families),
        route_relations => Relations,
        lane_relations => derive_lane_relations(Relations, FamilyIndex)
    }.

-spec routes_for_instance(map(), term(), [non_neg_integer()]) -> [map()].
routes_for_instance(Plan, FamilyId, Coordinates) ->
    FamilyIndex = index_by_id(maps:get(families, Plan)),
    Family = require_family(FamilyId, FamilyIndex, instance_routes),
    Shape = maps:get(shape, Family),
    ok = validate_coordinates(FamilyId, Coordinates, Shape),
    InstanceId = family_instance_id(FamilyId, Coordinates),
    [
        #{
            source => {InstanceId, Port},
            delivery => maps:get(delivery, Relation),
            recipients => [
                resolve_recipient(Recipient, Coordinates, FamilyIndex)
                || Recipient <- maps:get(recipients, Relation)
            ]
        }
        || Relation <- maps:get(route_relations, Plan),
           {SourceFamilyId, Port} <- [maps:get(source, Relation)],
           SourceFamilyId =:= FamilyId
    ].

%%%
%%% Families
%%%

normalize_families(Specs) when is_map(Specs) ->
    sort_by(
        fun(Family) -> maps:get(id, Family) end,
        [normalize_family(Id, Spec) || {Id, Spec} <- maps:to_list(Specs)]
    );
normalize_families(Specs) ->
    error({invalid_topology_field, families, Specs}).

normalize_family(Id, Spec) when is_map(Spec) ->
    ok = validate_id(Id),
    Required = [module, shape],
    Keys = maps:keys(Spec),
    case {Required -- Keys, Keys -- Required} of
        {[], []} -> ok;
        {Missing, Unknown} ->
            error({invalid_family_keys, Id, Missing, Unknown})
    end,
    Module = maps:get(module, Spec),
    Shape = maps:get(shape, Spec),
    case is_atom(Module) of
        true -> ok;
        false -> error({invalid_family_module, Id, Module})
    end,
    ok = validate_shape(Id, Shape),
    Interface = hls_actor_interface:from_module(Module),
    #{
        id => Id,
        module => Module,
        shape => Shape,
        instance_count => lists:foldl(
            fun(Size, Count) -> Size * Count end,
            1,
            Shape
        ),
        outputs => maps:get(outputs, Interface),
        mailbox_capacity => maps:get(mailbox_capacity, Interface),
        interface => Interface
    };
normalize_family(Id, Spec) ->
    error({invalid_family_spec, Id, Spec}).

reject_family_namespace_collisions(Families) ->
    Collisions = lists:sort([
        {maps:get(id, Family), maps:get(id, Other)}
        || Family <- Families,
           Other <- Families,
           Family =/= Other,
           is_family_instance_id(maps:get(id, Other), Family)
    ]),
    case Collisions of
        [] -> ok;
        _ -> error({family_namespace_collisions, Collisions})
    end.

validate_shape(Id, Shape) when is_list(Shape), Shape =/= [] ->
    case lists:all(
        fun(Size) -> is_integer(Size) andalso Size > 0 end,
        Shape
    ) of
        true -> ok;
        false -> error({invalid_family_shape, Id, Shape})
    end;
validate_shape(Id, Shape) ->
    error({invalid_family_shape, Id, Shape}).

reject_actor_family_collisions(ActorSpecs, FamilyIndex)
        when is_map(ActorSpecs) ->
    Collisions = lists:sort([
        Id
        || Id <- maps:keys(ActorSpecs),
           maps:is_key(Id, FamilyIndex) orelse
               lists:any(
                   fun(Family) -> is_family_instance_id(Id, Family) end,
                   maps:values(FamilyIndex)
               )
    ]),
    case Collisions of
        [] -> ok;
        _ -> error({actor_family_id_collisions, Collisions})
    end;
reject_actor_family_collisions(_ActorSpecs, _FamilyIndex) ->
    ok.

is_family_instance_id(Id, Family) when is_tuple(Id) ->
    Shape = maps:get(shape, Family),
    tuple_size(Id) =:= length(Shape) + 1 andalso
        element(1, Id) =:= maps:get(id, Family) andalso
        coordinates_in_shape(tl(tuple_to_list(Id)), Shape);
is_family_instance_id(_Id, _Family) ->
    false.

%%%
%%% Route relations
%%%

normalize_route_relations(Specs, FamilyIndex, ExternalIndex)
        when is_list(Specs) ->
    Relations = [
        normalize_route_relation(Spec, FamilyIndex, ExternalIndex)
        || Spec <- Specs
    ],
    Sources = [maps:get(source, Relation) || Relation <- Relations],
    require_unique(duplicate_route_relation_sources, Sources),
    Expected = lists:sort([
        {maps:get(id, Family), Port}
        || Family <- maps:values(FamilyIndex),
           Port <- maps:get(outputs, Family)
    ]),
    case Expected -- lists:sort(Sources) of
        [] ->
            Sorted = sort_by(
                fun(Relation) -> maps:get(source, Relation) end,
                Relations
            ),
            ok = validate_relation_interfaces(
                Sorted,
                FamilyIndex,
                ExternalIndex
            ),
            Sorted;
        Missing -> error({unrouted_family_outputs, Missing})
    end;
normalize_route_relations(Specs, _FamilyIndex, _ExternalIndex) ->
    error({invalid_topology_field, route_relations, Specs}).

normalize_route_relation({Source, []}, _FamilyIndex, _ExternalIndex) ->
    error({empty_route_relation, Source});
normalize_route_relation({Source, Recipients}, FamilyIndex, ExternalIndex)
        when is_list(Recipients) ->
    case Recipients of
        [_] ->
            normalize_route_relation(
                Source,
                direct,
                Recipients,
                FamilyIndex,
                ExternalIndex
            );
        _ ->
            error({fanout_delivery_required, Source})
    end;
normalize_route_relation(
    {Source, _Delivery, []},
    _FamilyIndex,
    _ExternalIndex
) ->
    error({empty_route_relation, Source});
normalize_route_relation(
    {Source, Delivery, Recipients},
    FamilyIndex,
    ExternalIndex
) when is_list(Recipients), length(Recipients) > 1 ->
    case lists:member(Delivery, [buffered, coupled, queued, best_effort]) of
        true ->
            normalize_route_relation(
                Source,
                Delivery,
                Recipients,
                FamilyIndex,
                ExternalIndex
            );
        false ->
            error({invalid_fanout_delivery, Source, Delivery})
    end;
normalize_route_relation(
    {Source, Delivery, Recipients},
    _FamilyIndex,
    _ExternalIndex
) when is_list(Recipients) ->
    error({invalid_fanout, Source, Delivery, Recipients});
normalize_route_relation(Spec, _FamilyIndex, _ExternalIndex) ->
    error({invalid_route_relation_spec, Spec}).

normalize_route_relation(
    Source,
    Delivery,
    Recipients,
    FamilyIndex,
    ExternalIndex
) ->
    NormalSource = normalize_source(Source, FamilyIndex),
    {SourceFamilyId, _Port} = NormalSource,
    SourceShape = maps:get(shape, maps:get(SourceFamilyId, FamilyIndex)),
    ValidatedRecipients = [
        normalize_recipient(
            Recipient,
            NormalSource,
            SourceShape,
            FamilyIndex,
            ExternalIndex
        )
        || Recipient <- Recipients
    ],
    NormalRecipients = [
        canonical_recipient(Recipient, SourceShape)
        || Recipient <- ValidatedRecipients
    ],
    case duplicates(NormalRecipients) of
        [] -> ok;
        Duplicates ->
            error({duplicate_route_relation_recipients,
                NormalSource, Duplicates})
    end,
    #{
        source => NormalSource,
        delivery => Delivery,
        recipients => lists:sort(NormalRecipients)
    }.

normalize_source({FamilyId, Port}, FamilyIndex) when is_atom(Port) ->
    Family = require_family(FamilyId, FamilyIndex, route_relation_source),
    case lists:member(Port, maps:get(outputs, Family)) of
        true -> {FamilyId, Port};
        false -> error({unknown_family_output, FamilyId, Port})
    end;
normalize_source(Source, _FamilyIndex) ->
    error({invalid_route_relation_source, Source}).

normalize_recipient(
    Recipient = {family, DestinationId, {translate, Offset, wrap}},
    Source,
    SourceShape,
    FamilyIndex,
    _ExternalIndex
) ->
    Destination = require_family(
        DestinationId,
        FamilyIndex,
        {route_relation_recipient, Source}
    ),
    DestinationShape = maps:get(shape, Destination),
    case DestinationShape =:= SourceShape of
        true -> ok;
        false -> error({incompatible_relation_shapes,
            Source, DestinationId, SourceShape, DestinationShape})
    end,
    case is_list(Offset) andalso
            length(Offset) =:= length(SourceShape) andalso
            lists:all(fun erlang:is_integer/1, Offset) of
        true -> Recipient;
        false -> error({invalid_relation_translation,
            Source, Recipient, SourceShape})
    end;
normalize_recipient(
    Recipient = {external, ExternalId},
    Source,
    _SourceShape,
    _FamilyIndex,
    ExternalIndex
) ->
    case maps:is_key(ExternalId, ExternalIndex) of
        true -> Recipient;
        false -> error({unknown_external, ExternalId,
            {route_relation_recipient, Source}})
    end;
normalize_recipient(
    Recipient,
    Source,
    _SourceShape,
    _FamilyIndex,
    _ExternalIndex
) ->
    error({invalid_route_relation_recipient, Source, Recipient}).

validate_relation_interfaces(Relations, FamilyIndex, ExternalIndex) ->
    lists:foreach(
        fun(Relation) ->
            Source = {FamilyId, Port} = maps:get(source, Relation),
            SourceInterface = maps:get(
                interface,
                maps:get(FamilyId, FamilyIndex)
            ),
            Emitted = hls_actor_interface:output_schemas(
                SourceInterface,
                Port
            ),
            lists:foreach(
                fun
                    (Recipient = {family, DestinationId, _Transform}) ->
                        DestinationInterface = maps:get(
                            interface,
                            maps:get(DestinationId, FamilyIndex)
                        ),
                        validate_actor_interface(
                            Source,
                            Recipient,
                            SourceInterface,
                            Emitted,
                            DestinationInterface
                        );
                    (Recipient = {external, ExternalId}) ->
                        External = maps:get(ExternalId, ExternalIndex),
                        require_route_schemas(
                            Source,
                            Recipient,
                            Emitted,
                            maps:get(schemas, External)
                        )
                end,
                maps:get(recipients, Relation)
            )
        end,
        Relations
    ).

validate_actor_interface(
    Source,
    Recipient,
    SourceInterface,
    Emitted,
    DestinationInterface
) ->
    Dispatched = hls_actor_interface:dispatched_schemas(DestinationInterface),
    require_route_schemas(Source, Recipient, Emitted, Dispatched),
    lists:foreach(
        fun(Schema) ->
            SourceFields = maps:get(
                fields,
                hls_actor_interface:schema(SourceInterface, Schema)
            ),
            DestinationFields = maps:get(
                fields,
                hls_actor_interface:schema(DestinationInterface, Schema)
            ),
            case SourceFields =:= DestinationFields of
                true -> ok;
                false -> error({incompatible_route_schema_layout,
                    Source, Recipient, Schema,
                    SourceFields, DestinationFields})
            end
        end,
        Emitted
    ).

require_route_schemas(Source, Recipient, Emitted, Dispatched) ->
    case Emitted -- Dispatched of
        [] -> ok;
        Unsupported -> error({incompatible_route_schemas,
            Source, Recipient, Unsupported, Dispatched})
    end.

%%%
%%% Compact lanes and point resolution
%%%

derive_lane_relations(Relations, FamilyIndex) ->
    LanePorts = lists:foldl(
        fun(Relation, Acc0) ->
            {SourceFamilyId, Port} = maps:get(source, Relation),
            Shape = maps:get(
                shape,
                maps:get(SourceFamilyId, FamilyIndex)
            ),
            lists:foldl(
                fun(Recipient, Acc) ->
                    Destination = canonical_recipient(Recipient, Shape),
                    Key = {SourceFamilyId, Destination},
                    maps:update_with(
                        Key,
                        fun(Ports) -> [Port | Ports] end,
                        [Port],
                        Acc
                    )
                end,
                Acc0,
                maps:get(recipients, Relation)
            )
        end,
        #{},
        Relations
    ),
    [
        #{
            source => SourceFamilyId,
            destination => Destination,
            source_ports => lists:sort(Ports)
        }
        || {{SourceFamilyId, Destination}, Ports} <-
               lists:sort(maps:to_list(LanePorts))
    ].

canonical_recipient(
    {family, DestinationId, {translate, Offset, wrap}},
    Shape
) ->
    {family, DestinationId, {translate,
        [canonical_offset(Value, Size)
            || {Value, Size} <- lists:zip(Offset, Shape)],
        wrap}};
canonical_recipient(Recipient = {external, _ExternalId}, _Shape) ->
    Recipient.

resolve_recipient(
    {family, DestinationId, {translate, Offset, wrap}},
    Coordinates,
    FamilyIndex
) ->
    Shape = maps:get(shape, maps:get(DestinationId, FamilyIndex)),
    Resolved = [
        positive_mod(Coordinate + Delta, Size)
        || {Coordinate, Delta, Size} <- zip3(Coordinates, Offset, Shape)
    ],
    {actor, family_instance_id(DestinationId, Resolved)};
resolve_recipient(
    Recipient = {external, _ExternalId},
    _Coordinates,
    _FamilyIndex
) ->
    Recipient.

family_instance_id(FamilyId, Coordinates) ->
    list_to_tuple([FamilyId | Coordinates]).

validate_coordinates(FamilyId, Coordinates, Shape)
        when is_list(Coordinates), length(Coordinates) =:= length(Shape) ->
    case coordinates_in_shape(Coordinates, Shape) of
        true -> ok;
        false -> error({invalid_family_coordinates,
            FamilyId, Coordinates, Shape})
    end;
validate_coordinates(FamilyId, Coordinates, Shape) ->
    error({invalid_family_coordinates, FamilyId, Coordinates, Shape}).

coordinates_in_shape(Coordinates, Shape) ->
    lists:all(
        fun({Coordinate, Size}) ->
            is_integer(Coordinate) andalso
                Coordinate >= 0 andalso Coordinate < Size
        end,
        lists:zip(Coordinates, Shape)
    ).

zip3([A | As], [B | Bs], [C | Cs]) ->
    [{A, B, C} | zip3(As, Bs, Cs)];
zip3([], [], []) ->
    [].

positive_mod(Value, Modulus) ->
    ((Value rem Modulus) + Modulus) rem Modulus.

canonical_offset(Value, Size) ->
    Offset = positive_mod(Value, Size),
    case Offset > Size div 2 of
        true -> Offset - Size;
        false -> Offset
    end.

%%%
%%% Shared validation
%%%

require_family(FamilyId, FamilyIndex, Context) ->
    case maps:find(FamilyId, FamilyIndex) of
        {ok, Family} -> Family;
        error -> error({unknown_family, FamilyId, Context})
    end.

validate_id(Id) when is_atom(Id); is_integer(Id), Id >= 0 ->
    ok;
validate_id(Id) when is_tuple(Id), tuple_size(Id) > 0 ->
    lists:foreach(fun validate_id/1, tuple_to_list(Id));
validate_id(Id) ->
    error({invalid_topology_id, Id}).

require_unique(ErrorTag, Values) ->
    case duplicates(Values) of
        [] -> ok;
        Duplicates -> error({ErrorTag, Duplicates})
    end.

duplicates(Values) ->
    Counts = lists:foldl(
        fun(Value, Acc) ->
            maps:update_with(Value, fun(Count) -> Count + 1 end, 1, Acc)
        end,
        #{},
        Values
    ),
    lists:sort([Value || {Value, Count} <- maps:to_list(Counts), Count > 1]).

index_by_id(Items) ->
    maps:from_list([{maps:get(id, Item), Item} || Item <- Items]).

strip_interfaces(Items) ->
    [maps:remove(interface, Item) || Item <- Items].

sort_by(Key, Values) ->
    lists:sort(fun(A, B) -> Key(A) < Key(B) end, Values).
