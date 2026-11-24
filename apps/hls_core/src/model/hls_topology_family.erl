%%%% hls_topology_family
%%%%
%%%% Normalizes the first compact actor-family and route-relation subset.

-module(hls_topology_family).
-moduledoc """
Internal family normalizer used by `hls_logical_topology`.

The supported compact subset is intentionally small: zero-based rectangular
families, same-shape wrapped translations, and rectangle-addressed ingress
whose targets name statically embedded families or exact actors at fixed points.
Relations target translated family members, fixed exact actors, or external
outputs. Exact source routes may address individual family members. Family members and route pairs are
never enumerated during normalization.

An ingress ID denotes the single router service addressed at the application
boundary. Target IDs and rectangles are selectors interpreted inside that
router; they are not alternate ERTS destinations. Embedded coordinates denote
stable logical services, not actor generations. Router acceptance is a bounded
network handoff rather than an atomic multicast admission guarantee.
""".

%% Compact family declaration, normalization, and route lookup.
-export([interface_modules/1, normalize/3, routes_for_instance/3]).

-doc "Validates compact family declarations and returns their computation modules in declaration order.".
-spec interface_modules(map()) -> [module()].
interface_modules(Specs) ->
    [maps:get(module, Family) || Family <- normalize_families(Specs)].

-spec normalize(map(), #{module() => hls_process_interface:interface()}, fun(
    (map(), map(), map()) -> map()
)) -> map().
-doc "Normalizes bounded families, ingress, route relations, and lane relations using retained process interfaces and an exact-section callback.".
normalize(
    Spec = #{
        actors := ActorSpecs,
        families := FamilySpecs,
        route_relations := RelationSpecs
    },
    Interfaces,
    NormalizeExact
) ->
    Declarations = normalize_families(FamilySpecs),
    Families = [
        family_summary(Family, maps:get(Module, Interfaces))
     || Family = #{module := Module} <- Declarations
    ],
    FamilyIndex = index_by_id(Families),
    ok = reject_family_namespace_collisions(Families),
    ok = reject_actor_family_collisions(
        ActorSpecs,
        FamilyIndex
    ),
    Exact = #{externals := Externals} = NormalizeExact(Spec, FamilyIndex, Interfaces),
    ExternalIndex = index_by_id(Externals),
    ActorIndex = maps:map(
        fun(_Id, Module) ->
            #{interface => maps:get(Module, Interfaces)}
        end,
        ActorSpecs
    ),
    Relations = normalize_route_relations(
        RelationSpecs,
        #{actors => ActorIndex, families => FamilyIndex},
        ExternalIndex
    ),
    Ingresses = normalize_ingresses(
        maps:get(ingresses, Spec),
        #{actors => ActorIndex, families => FamilyIndex}
    ),
    Exact#{
        families => strip_interfaces(Families),
        ingresses => Ingresses,
        route_relations => Relations,
        lane_relations => derive_lane_relations(Relations, FamilyIndex)
    }.

-doc "Resolves the compact route relations emitted by one bounded family instance.".
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

-spec normalize_families(term()) -> [map()].
normalize_families(Specs) when is_map(Specs) ->
    sort_by(
        fun(Family) -> maps:get(id, Family) end,
        [normalize_family(Id, Spec) || {Id, Spec} <- maps:to_list(Specs)]
    );
normalize_families(Specs) ->
    error({invalid_topology_field, families, Specs}).

%% Validate one bounded family declaration and cache its finite instance count.
-spec normalize_family(term(), term()) -> map().
normalize_family(Id, Spec) when is_map(Spec) ->
    ok = hls_logical_identity:validate(Id),
    Required = [module, shape],
    Keys = maps:keys(Spec),
    case {Required -- Keys, Keys -- Required} of
        {[], []} -> ok;
        {Missing, Unknown} -> error({invalid_family_keys, Id, Missing, Unknown})
    end,
    Module = maps:get(module, Spec),
    Shape = maps:get(shape, Spec),
    case is_atom(Module) of
        true -> ok;
        false -> error({invalid_family_module, Id, Module})
    end,
    ok = validate_shape(Id, Shape),
    #{
        id => Id,
        module => Module,
        shape => Shape,
        instance_count => lists:foldl(
            fun(Size, Count) -> Size * Count end,
            1,
            Shape
        )
    };
normalize_family(Id, Spec) ->
    error({invalid_family_spec, Id, Spec}).

%% Adds routing facts from the retained process interface to a family declaration.
-spec family_summary(map(), hls_process_interface:interface()) -> map().
family_summary(
    Family,
    Interface = #{
        outputs := Outputs,
        mailbox_capacity := Capacity
    }
) ->
    Family#{
        outputs => Outputs,
        mailbox_capacity => Capacity,
        interface => Interface
    }.

%%%
%%% Rectangle-addressed ingress
%%%

-spec normalize_ingresses(term(), map()) -> [map()].
normalize_ingresses(Specs, Endpoints) when is_list(Specs) ->
    Ingresses = [normalize_ingress(Spec, Endpoints) || Spec <- Specs],
    require_unique(
        duplicate_ingress_ids,
        [maps:get(id, Ingress) || Ingress <- Ingresses]
    ),
    sort_by(fun(Ingress) -> maps:get(id, Ingress) end, Ingresses);
normalize_ingresses(Specs, _Endpoints) ->
    error({invalid_topology_field, ingresses, Specs}).

%% Normalize one bounded rectangular ingress and its selector targets.
-spec normalize_ingress(term(), map()) -> map().
normalize_ingress({Id, {rectangle, Shape}, TargetSpecs}, Endpoints) when
    is_list(TargetSpecs), TargetSpecs =/= []
->
    ok = hls_logical_identity:validate(Id),
    ok = validate_rectangle_shape(Id, Shape),
    Targets = [
        normalize_ingress_target(Target, Shape, Endpoints)
     || Target <- TargetSpecs
    ],
    require_unique(
        duplicate_ingress_targets,
        [maps:get(id, Target) || Target <- Targets]
    ),
    ok = validate_ingress_embeddings(Id, Targets),
    #{
        id => Id,
        kind => rectangle,
        shape => Shape,
        targets => sort_by(fun(Target) -> maps:get(id, Target) end, Targets)
    };
normalize_ingress(Spec, _Endpoints) ->
    error({invalid_ingress, Spec}).

%% Normalize one ingress target's schemas and statically embedded recipients.
-spec normalize_ingress_target(term(), [pos_integer()], map()) -> map().
normalize_ingress_target(
    {Id, Schemas, RecipientSpecs},
    Shape,
    Endpoints
) when
    is_list(Schemas),
    Schemas =/= [],
    is_list(RecipientSpecs),
    RecipientSpecs =/= []
->
    ok = hls_logical_identity:validate(Id),
    case lists:all(fun erlang:is_atom/1, Schemas) of
        true -> require_unique(duplicate_ingress_schemas, Schemas);
        false -> error({invalid_ingress_schemas, Id, Schemas})
    end,
    Recipients = [
        normalize_ingress_recipient(Recipient, Shape, Endpoints)
     || Recipient <- RecipientSpecs
    ],
    require_unique(duplicate_ingress_recipients, Recipients),
    ok = validate_ingress_interfaces(Id, Schemas, Recipients, Endpoints),
    #{
        id => Id,
        schemas => lists:sort(Schemas),
        recipients => lists:sort(Recipients)
    };
normalize_ingress_target(Target, _Shape, _Endpoints) ->
    error({invalid_ingress_target, Target}).

%% Normalizes one embedded family or exact-actor ingress recipient.
-spec normalize_ingress_recipient(term(), [pos_integer()], map()) -> map().
normalize_ingress_recipient(
    {family, FamilyId, {embed, Scale, Offset}},
    AddressShape,
    Endpoints
) ->
    Family = require_family(FamilyId, maps:get(families, Endpoints), ingress),
    FamilyShape = maps:get(shape, Family),
    case {FamilyShape, Scale, Offset, AddressShape} of
        {[_, _], [ScaleX, ScaleY], [OffsetX, OffsetY], [LimitX, LimitY]} when
            is_integer(ScaleX),
            ScaleX > 0,
            ScaleX =< LimitX,
            is_integer(ScaleY),
            ScaleY > 0,
            ScaleY =< LimitY,
            is_integer(OffsetX),
            OffsetX >= 0,
            is_integer(OffsetY),
            OffsetY >= 0
        ->
            [FamilyWidth, FamilyHeight] = FamilyShape,
            case
                OffsetX + ScaleX * (FamilyWidth - 1) < LimitX andalso
                    OffsetY + ScaleY * (FamilyHeight - 1) < LimitY
            of
                true ->
                    #{
                        family => FamilyId,
                        scale => Scale,
                        offset => Offset
                    };
                false ->
                    error({ingress_embedding, FamilyId, FamilyShape, Scale, Offset, AddressShape})
            end;
        _ ->
            error({ingress_embedding, FamilyId, FamilyShape, Scale, Offset, AddressShape})
    end;
normalize_ingress_recipient({actor, ActorId, {at, Point}}, Shape, Endpoints) ->
    %% An exact actor is a point in the ingress address space, not a family.
    _ = hls_topology_endpoint:actor(ActorId, Endpoints#{families := #{}}, ingress),
    case {Point, Shape} of
        {[X, Y], [Width, Height]} when
            is_integer(X),
            X >= 0,
            X < Width,
            is_integer(Y),
            Y >= 0,
            Y < Height
        ->
            #{actor => ActorId, at => Point};
        _ ->
            error({ingress_point, ActorId, Point, Shape})
    end;
normalize_ingress_recipient(Recipient, _Shape, _Endpoints) ->
    error({invalid_ingress_recipient, Recipient}).

%% Requires repeated target declarations to embed each endpoint at one position.
-spec validate_ingress_embeddings(term(), [map()]) -> ok.
validate_ingress_embeddings(IngressId, Targets) ->
    Bindings = lists:foldl(
        fun(#{recipients := Recipients}, Acc) ->
            lists:foldl(
                fun(Recipient, Inner) ->
                    {Key, Position} = ingress_binding(Recipient),
                    maps:update_with(
                        Key,
                        fun(Values) -> [Position | Values] end,
                        [Position],
                        Inner
                    )
                end,
                Acc,
                Recipients
            )
        end,
        #{},
        Targets
    ),
    lists:foreach(
        fun({Key, Values}) ->
            case lists:usort(Values) of
                [_] ->
                    ok;
                Distinct ->
                    error({ingress_embeddings, IngressId, ingress_binding_id(Key), Distinct})
            end
        end,
        lists:sort(maps:to_list(Bindings))
    ).

%% Returns the endpoint key and spatial position represented by an ingress recipient.
-spec ingress_binding(map()) -> {{family | actor, term()}, term()}.
ingress_binding(#{family := Id, scale := Scale, offset := Offset}) ->
    {{family, Id}, {Scale, Offset}};
ingress_binding(#{actor := Id, at := Point}) ->
    {{actor, Id}, Point}.

%% Projects the diagnostic ID from an ingress endpoint key.
-spec ingress_binding_id({family | actor, term()}) -> term().
ingress_binding_id({family, Id}) -> Id;
ingress_binding_id({actor, Id}) -> {actor, Id}.

%% Accepts only positive two-dimensional ingress address spaces.
-spec validate_rectangle_shape(term(), term()) -> ok.
validate_rectangle_shape(_Id, [Width, Height]) when
    is_integer(Width),
    Width > 0,
    is_integer(Height),
    Height > 0
->
    ok;
validate_rectangle_shape(Id, Shape) ->
    error({invalid_ingress_shape, Id, Shape}).

%% Require every ingress recipient to dispatch identical declared schema layouts.
-spec validate_ingress_interfaces(term(), [atom()], [map()], map()) -> ok.
validate_ingress_interfaces(TargetId, Schemas, Recipients, Endpoints) ->
    Interfaces = [
        {ingress_binding_id(Key), ingress_interface(Recipient, Endpoints)}
     || Recipient <- Recipients, {Key, _Position} <- [ingress_binding(Recipient)]
    ],
    lists:foreach(
        fun({Id, Interface}) ->
            Missing = Schemas -- hls_process_interface:dispatched_schemas(Interface),
            case Missing of
                [] -> ok;
                _ -> error({ingress_schemas, TargetId, Id, Missing})
            end
        end,
        Interfaces
    ),
    lists:foreach(
        fun(Schema) ->
            Layouts = lists:usort([
                maps:get(
                    fields,
                    hls_process_interface:schema(Interface, Schema)
                )
             || {_, Interface} <- Interfaces
            ]),
            case Layouts of
                [_] -> ok;
                _ -> error({ingress_layouts, TargetId, Schema, Layouts})
            end
        end,
        Schemas
    ).

%% Selects the process interface attached to a normalized ingress recipient.
-spec ingress_interface(map(), map()) -> hls_process_interface:interface().
ingress_interface(#{family := Id}, #{families := Families}) ->
    #{interface := Interface} = maps:get(Id, Families),
    Interface;
ingress_interface(#{actor := Id}, #{actors := Actors}) ->
    #{interface := Interface} = maps:get(Id, Actors),
    Interface.

%% Rejects family IDs whose tuple namespace contains another family ID.
-spec reject_family_namespace_collisions([map()]) -> ok.
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

%% Requires a nonempty shape whose dimensions are positive integers.
-spec validate_shape(term(), term()) -> ok.
validate_shape(Id, Shape) when is_list(Shape), Shape =/= [] ->
    case
        lists:all(
            fun(Size) -> is_integer(Size) andalso Size > 0 end,
            Shape
        )
    of
        true -> ok;
        false -> error({invalid_family_shape, Id, Shape})
    end;
validate_shape(Id, Shape) ->
    error({invalid_family_shape, Id, Shape}).

%% Rejects exact actor IDs that occupy a family declaration or member namespace.
-spec reject_actor_family_collisions(term(), map()) -> ok.
reject_actor_family_collisions(ActorSpecs, FamilyIndex) when
    is_map(ActorSpecs)
->
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

%% Reports whether an ID is a bounded member of the supplied normalized family.
-spec is_family_instance_id(term(), map()) -> boolean().
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

-spec normalize_route_relations(term(), map(), map()) -> [map()].
normalize_route_relations(Specs, Endpoints = #{families := FamilyIndex}, ExternalIndex) when
    is_list(Specs)
->
    Relations = [
        normalize_route_relation(Spec, Endpoints, ExternalIndex)
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
                Endpoints,
                ExternalIndex
            ),
            Sorted;
        Missing ->
            error({unrouted_family_outputs, Missing})
    end;
normalize_route_relations(Specs, _Endpoints, _ExternalIndex) ->
    error({invalid_topology_field, route_relations, Specs}).

%% Selects direct or explicit fanout delivery and rejects malformed relation syntax.
-spec normalize_route_relation(term(), map(), map()) -> map().
normalize_route_relation({Source, []}, _Endpoints, _ExternalIndex) ->
    error({empty_route_relation, Source});
normalize_route_relation({Source, Recipients}, Endpoints, ExternalIndex) when
    is_list(Recipients)
->
    case Recipients of
        [_] ->
            normalize_route_relation(
                Source,
                direct,
                Recipients,
                Endpoints,
                ExternalIndex
            );
        _ ->
            error({fanout_delivery_required, Source})
    end;
normalize_route_relation(
    {Source, _Delivery, []},
    _Endpoints,
    _ExternalIndex
) ->
    error({empty_route_relation, Source});
normalize_route_relation(
    {Source, Delivery, Recipients},
    Endpoints,
    ExternalIndex
) when is_list(Recipients), length(Recipients) > 1 ->
    case lists:member(Delivery, [buffered, coupled, queued, best_effort]) of
        true ->
            normalize_route_relation(
                Source,
                Delivery,
                Recipients,
                Endpoints,
                ExternalIndex
            );
        false ->
            error({invalid_fanout_delivery, Source, Delivery})
    end;
normalize_route_relation(
    {Source, Delivery, Recipients},
    _Endpoints,
    _ExternalIndex
) when is_list(Recipients) ->
    error({invalid_fanout, Source, Delivery, Recipients});
normalize_route_relation(Spec, _Endpoints, _ExternalIndex) ->
    error({invalid_route_relation_spec, Spec}).

%% Validates one route source and its recipients, then canonicalizes translations.
-spec normalize_route_relation(term(), atom(), [term()], map(), map()) -> map().
normalize_route_relation(
    Source,
    Delivery,
    Recipients,
    Endpoints = #{families := FamilyIndex},
    ExternalIndex
) ->
    NormalSource = normalize_source(Source, Endpoints),
    {SourceFamilyId, _Port} = NormalSource,
    #{shape := SourceShape} = maps:get(SourceFamilyId, FamilyIndex),
    ValidatedRecipients = [
        normalize_recipient(
            Recipient,
            NormalSource,
            SourceShape,
            Endpoints,
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
        Duplicates -> error({duplicate_route_relation_recipients, NormalSource, Duplicates})
    end,
    #{
        source => NormalSource,
        delivery => Delivery,
        recipients => lists:sort(NormalRecipients)
    }.

%% Resolves a declared family output used as a compact relation source.
-spec normalize_source(term(), map()) -> {term(), atom()}.
normalize_source({FamilyId, Port}, #{families := FamilyIndex}) when is_atom(Port) ->
    Family = require_family(FamilyId, FamilyIndex, route_relation_source),
    case lists:member(Port, maps:get(outputs, Family)) of
        true -> {FamilyId, Port};
        false -> error({unknown_family_output, FamilyId, Port})
    end;
normalize_source(Source, _Endpoints) ->
    error({invalid_route_relation_source, Source}).

%% Validates one translated family, exact actor, or external relation recipient.
-spec normalize_recipient(term(), term(), [pos_integer()], map(), map()) -> term().
normalize_recipient(
    Recipient = {family, DestinationId, {translate, Offset, wrap}},
    Source,
    SourceShape,
    #{families := FamilyIndex},
    _ExternalIndex
) ->
    Destination = require_family(
        DestinationId,
        FamilyIndex,
        {route_relation_recipient, Source}
    ),
    DestinationShape = maps:get(shape, Destination),
    case DestinationShape =:= SourceShape of
        true ->
            ok;
        false ->
            error(
                {incompatible_relation_shapes, Source, DestinationId, SourceShape, DestinationShape}
            )
    end,
    case
        is_list(Offset) andalso
            length(Offset) =:= length(SourceShape) andalso
            lists:all(fun erlang:is_integer/1, Offset)
    of
        true -> Recipient;
        false -> error({invalid_relation_translation, Source, Recipient, SourceShape})
    end;
normalize_recipient(
    Recipient = {actor, ActorId},
    Source,
    _SourceShape,
    #{actors := ActorIndex},
    _ExternalIndex
) ->
    _ = hls_topology_endpoint:actor(
        ActorId,
        #{actors => ActorIndex, families => #{}},
        {route_relation_recipient, Source}
    ),
    Recipient;
normalize_recipient(
    Recipient = {external, ExternalId},
    Source,
    _SourceShape,
    _Endpoints,
    ExternalIndex
) ->
    case maps:is_key(ExternalId, ExternalIndex) of
        true -> Recipient;
        false -> error({unknown_external, ExternalId, {route_relation_recipient, Source}})
    end;
normalize_recipient(
    Recipient,
    Source,
    _SourceShape,
    _Endpoints,
    _ExternalIndex
) ->
    error({invalid_route_relation_recipient, Source, Recipient}).

%% Validate schemas and layouts on every compact family-relation edge.
-spec validate_relation_interfaces([map()], map(), map()) -> ok.
validate_relation_interfaces(
    Relations, #{families := FamilyIndex, actors := ActorIndex}, ExternalIndex
) ->
    lists:foreach(
        fun(Relation) ->
            Source = {FamilyId, Port} = maps:get(source, Relation),
            SourceInterface = maps:get(
                interface,
                maps:get(FamilyId, FamilyIndex)
            ),
            Emitted = hls_process_interface:output_schemas(
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
                        hls_topology_endpoint:validate_route(
                            Source,
                            Recipient,
                            SourceInterface,
                            Emitted,
                            DestinationInterface
                        );
                    (Recipient = {actor, ActorId}) ->
                        #{interface := DestinationInterface} = maps:get(ActorId, ActorIndex),
                        hls_topology_endpoint:validate_route(
                            Source,
                            Recipient,
                            SourceInterface,
                            Emitted,
                            DestinationInterface
                        );
                    (Recipient = {external, ExternalId}) ->
                        External = maps:get(ExternalId, ExternalIndex),
                        hls_topology_endpoint:require_schemas(
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

%%%
%%% Compact lanes and point resolution
%%%

-spec derive_lane_relations([map()], map()) -> [map()].
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

%% Reduces translations modulo shape while leaving exact destinations unchanged.
-spec canonical_recipient(term(), [pos_integer()]) -> term().
canonical_recipient(
    {family, DestinationId, {translate, Offset, wrap}},
    Shape
) ->
    {family, DestinationId,
        {translate,
            [
                canonical_offset(Value, Size)
             || {Value, Size} <- lists:zip(Offset, Shape)
            ],
            wrap}};
canonical_recipient(Recipient = {actor, _ActorId}, _Shape) ->
    Recipient;
canonical_recipient(Recipient = {external, _ExternalId}, _Shape) ->
    Recipient.

%% Resolves a compact recipient at one source-family coordinate.
-spec resolve_recipient(term(), [non_neg_integer()], map()) -> term().
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
resolve_recipient(Recipient = {actor, _ActorId}, _Coordinates, _FamilyIndex) ->
    Recipient;
resolve_recipient(
    Recipient = {external, _ExternalId},
    _Coordinates,
    _FamilyIndex
) ->
    Recipient.

%% Constructs the canonical tuple ID of one family member.
-spec family_instance_id(term(), [non_neg_integer()]) -> tuple().
family_instance_id(FamilyId, Coordinates) ->
    list_to_tuple([FamilyId | Coordinates]).

%% Requires a coordinate vector to match the rank and bounds of a family shape.
-spec validate_coordinates(term(), term(), [pos_integer()]) -> ok.
validate_coordinates(FamilyId, Coordinates, Shape) when
    is_list(Coordinates), length(Coordinates) =:= length(Shape)
->
    case coordinates_in_shape(Coordinates, Shape) of
        true -> ok;
        false -> error({invalid_family_coordinates, FamilyId, Coordinates, Shape})
    end;
validate_coordinates(FamilyId, Coordinates, Shape) ->
    error({invalid_family_coordinates, FamilyId, Coordinates, Shape}).

%% Reports whether every supplied coordinate lies inside its paired dimension.
-spec coordinates_in_shape(term(), [pos_integer()]) -> boolean().
coordinates_in_shape(Coordinates, Shape) ->
    lists:all(
        fun({Coordinate, Size}) ->
            is_integer(Coordinate) andalso
                Coordinate >= 0 andalso Coordinate < Size
        end,
        lists:zip(Coordinates, Shape)
    ).

%% Zips three equal-length lists; callers establish matching ranks first.
-spec zip3([term()], [term()], [term()]) -> [{term(), term(), term()}].
zip3([A | As], [B | Bs], [C | Cs]) ->
    [{A, B, C} | zip3(As, Bs, Cs)];
zip3([], [], []) ->
    [].

%% Returns the nonnegative residue for a positive modulus.
-spec positive_mod(integer(), pos_integer()) -> non_neg_integer().
positive_mod(Value, Modulus) ->
    ((Value rem Modulus) + Modulus) rem Modulus.

%% Chooses the shortest signed representative of a wrapped offset.
-spec canonical_offset(integer(), pos_integer()) -> integer().
canonical_offset(Value, Size) ->
    Offset = positive_mod(Value, Size),
    case Offset > Size div 2 of
        true -> Offset - Size;
        false -> Offset
    end.

%%%
%%% Shared validation
%%%

-spec require_family(term(), map(), term()) -> map().
require_family(FamilyId, FamilyIndex, Context) ->
    case maps:find(FamilyId, FamilyIndex) of
        {ok, Family} -> Family;
        error -> error({unknown_family, FamilyId, Context})
    end.

%% Requires all values to be unique, reporting sorted duplicates under `ErrorTag`.
-spec require_unique(atom(), [term()]) -> ok.
require_unique(ErrorTag, Values) ->
    case duplicates(Values) of
        [] -> ok;
        Duplicates -> error({ErrorTag, Duplicates})
    end.

%% Returns the sorted values occurring more than once.
-spec duplicates([term()]) -> [term()].
duplicates(Values) ->
    Counts = lists:foldl(
        fun(Value, Acc) ->
            maps:update_with(Value, fun(Count) -> Count + 1 end, 1, Acc)
        end,
        #{},
        Values
    ),
    lists:sort([Value || {Value, Count} <- maps:to_list(Counts), Count > 1]).

%% Indexes normalized declarations by their required `id` field.
-spec index_by_id([map()]) -> map().
index_by_id(Items) ->
    maps:from_list([{maps:get(id, Item), Item} || Item <- Items]).

%% Removes retained process interfaces from public normalized family declarations.
-spec strip_interfaces([map()]) -> [map()].
strip_interfaces(Items) ->
    [maps:remove(interface, Item) || Item <- Items].

%% Sorts values by a derived Erlang term key.
-spec sort_by(fun((term()) -> term()), [term()]) -> [term()].
sort_by(Key, Values) ->
    lists:sort(fun(A, B) -> Key(A) < Key(B) end, Values).
