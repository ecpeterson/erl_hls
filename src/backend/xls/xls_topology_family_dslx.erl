%%%% xls_topology_family_dslx
%%%%
%%%% Lowers regular two-dimensional actor families into compact DSLX.

-module(xls_topology_family_dslx).
-moduledoc """
Generates the compact regular-family DSLX backend used by the phi/noise
experiment.

The accepted subset is deliberately narrow: one or more same-shaped
two-dimensional families, wrapped translations between those families,
single-recipient routes, and queued two-way fanout from one family endpoint to
one family endpoint plus one scalar external output. Exact actors and other
route forms remain outside this backend.

The generated source contains one reusable node proc per family and nested
`unroll_for!` spawns over channel arrays. Its routing structure therefore
follows the number of family rules rather than the number of family members.
Each node has one credit-aware ingress which polls its incoming lanes directly,
without a tree of buffered two-way muxes. Explicit startup values still
produce one match arm per configured member.

Families may either instantiate one actor service per coordinate or join a
homogeneous scheduler group. A group replaces the per-coordinate services and
mailboxes with shared ingress, execution, and egress machinery around one
actor implementation. Actor-machine words and mailbox frames cross separate
simple-dual-port RAM boundaries, each with one read and one write port; the
scheduler retains only bounded queue-order metadata. The current backend
requires both scheduler storage bindings to be `block_ram`; a target wrapper
must connect the generated RAM channel quartets to storage with the declared
independent read- and write-channel protocol.

Each compact lane relation becomes a depth-zero direct channel array. The
explicit depth supplies the pinned block stitcher's per-channel FIFO metadata
without installing a global default which could mask another unannotated
channel. The graph must then be code-generated with one registered output per
router lane; the repository scripts enforce that policy. That register is the
lane's bounded holding slot and timing boundary, instead of placing another
FIFO immediately after it. When two ports alias one destination, both router
arms use the same array element, preserving the actor's source-ordered egress.
Queued fanout starts after the common ordered egress accepts the event and waits
for both registered branches. Each lane feeding a scalar external is first
merged across its family grid. When several source families share that
external, a second fair polling merge combines those bounded lane streams.
There is no ordering promise between distinct source families. All receive
sites are statically indexed because runtime channel indexing is not supported
by the pinned XLS build.

The profile's `channel_depth` controls the remaining explicit actor-request,
admission, and external-merge queues. It does not change direct lane capacity.
`actor_egress_depth` separately selects either end-to-end capacity for one
complete entry-effect `burst` on an initially empty path or a literal
nonnegative XLS FIFO depth. The symbolic policy counts the required one-entry
producer output register and therefore depends on code generation retaining
`--flop_outputs=true`; a literal zero is a bypass adapter which leaves only
that physical holding slot.

Family-member startup remains explicit normalized data. A family which has
startup data must provide exactly one frame for every member. The generated
ingress sends that frame under the actor's first admission credit, ahead of its
first routed receive, while the actor graph and routing stay compact.
""".

-export([emit/2]).

-define(U16_MAX, 16#ffff).
-define(U16_EXTENT, 16#10000).
-define(U32_MAX, 16#ffffffff).
-define(MAX_PAYLOAD_BITS, 96).

-doc "Emits deterministic regular-family DSLX from a normalized plan.".
-spec emit(hls_topology:plan(), xls_topology_dslx:profile()) -> iolist().
emit(Plan, Profile) ->
    render(lower(Plan, Profile)).

%%%
%%% Validation and annotation
%%%

lower(Plan, Profile) ->
    ok = require_empty(actors, Plan),
    ok = require_empty(routes, Plan),
    Physical = validate_profile(Profile),
    SchedulerPlan = hls_scheduler_plan:normalize(
        Plan,
        maps:get(scheduler_groups, Physical, #{})
    ),
    Schedulers = annotate_schedulers(maps:get(groups, SchedulerPlan)),
    SchedulerBindings = scheduler_bindings(Schedulers),
    Families0 = require_families(maps:get(families, Plan, [])),
    [Width, Height] = require_common_shape(Families0),
    Families1 = annotate_families(
        Families0,
        maps:get(actor_egress_depth, Physical)
    ),
    FamilyIndex = index_by_id(Families1),
    Ingresses = annotate_ingresses(
        maps:get(ingresses, Plan, []),
        FamilyIndex
    ),
    Externals = annotate_externals(require_externals(
        maps:get(externals, Plan, [])
    )),
    ExternalIndex = maps:from_list([
        {maps:get(id, External), External} || External <- Externals
    ]),
    Relations = maps:get(route_relations, Plan, []),
    ok = validate_relations(Relations, FamilyIndex),
    ok = validate_route_selectors(Relations, FamilyIndex, ExternalIndex),
    LaneRelations = derive_lane_relations(Relations),
    case maps:get(lane_relations, Plan, '$missing') of
        LaneRelations -> ok;
        CachedLanes -> error({inconsistent_dslx_family_plan_lanes,
            LaneRelations, CachedLanes})
    end,
    Lanes = annotate_lanes(
        LaneRelations,
        [Width, Height],
        ExternalIndex
    ),
    Routes = annotate_routes(Relations, Lanes),
    Startup = annotate_startup(maps:get(startup, Plan), FamilyIndex),
    Families = [annotate_family_graph(
        with_scheduler_bindings(Family, SchedulerBindings),
        Routes,
        Lanes,
        Startup,
        Ingresses
    ) || Family <- Families1],
    ok = validate_lane_ports(Families),
    ok = validate_external_lanes(Externals, Lanes),
    #{
        name => maps:get(name, Physical),
        depth => maps:get(channel_depth, Physical),
        schedulers => Schedulers,
        families => Families,
        width => Width,
        height => Height,
        routes => Routes,
        lanes => Lanes,
        startup => Startup,
        ingresses => Ingresses,
        externals => Externals
    }.

annotate_schedulers(Groups) ->
    [annotate_scheduler(Index, Group)
        || {Index, Group} <- lists:enumerate(0, Groups)].

annotate_scheduler(Index, Group = #{
    state_storage := block_ram,
    mailbox_storage := block_ram
}) ->
    Group#{
        index => Index,
        stem => ["scheduler_", integer_to_list(Index)],
        module_name => identifier(maps:get(module, Group), scheduler_module)
    };
annotate_scheduler(_Index, #{
    id := Id,
    state_storage := State,
    mailbox_storage := Mailbox
}) ->
    error({scheduler_storage, Id, State, Mailbox}).

scheduler_bindings(Schedulers) ->
    lists:foldl(
        fun({Id, Binding}, Acc) ->
            maps:update_with(Id, fun(Existing) -> Existing ++ [Binding] end,
                [Binding], Acc)
        end,
        #{},
        [{Id, #{
            group => maps:get(index, Scheduler),
            stem => maps:get(stem, Scheduler),
            base_slot => BaseSlot,
            slot_count => maps:get(slot_count, Scheduler),
            instances => maps:get(instances, Member),
            reference => maps:get(reference, Member)
        }}
        || Scheduler <- Schedulers,
           Member = #{kind := family, id := Id, base_slot := BaseSlot} <-
               maps:get(members, Scheduler)]
    ).

with_scheduler_bindings(Family = #{id := Id}, Bindings) ->
    case maps:get(Id, Bindings, []) of
        [] -> Family#{scheduler => direct, schedulers => []};
        [Binding] -> Family#{scheduler => Binding, schedulers => [Binding]};
        [_ | _] = FamilyBindings ->
            Family#{scheduler => sharded, schedulers => FamilyBindings}
    end.

require_empty(Field, Plan) ->
    case maps:get(Field, Plan, '$missing') of
        [] -> ok;
        Value -> error({unsupported_dslx_family_section, Field, Value})
    end.

require_families([_ | _] = Families) -> Families;
require_families([]) -> error({unsupported_family_count, 0}).

require_common_shape([First | Rest]) ->
    Shape = require_two_dimensional_shape(First),
    lists:foreach(
        fun(Family) ->
            case require_two_dimensional_shape(Family) of
                Shape -> ok;
                Other -> error({incompatible_family_shape,
                    maps:get(id, Family), Shape, Other})
            end
        end,
        Rest
    ),
    Shape.

require_two_dimensional_shape(Family = #{shape := [Width, Height]}) ->
    ok = validate_dimensions(maps:get(id, Family), Width, Height),
    [Width, Height];
require_two_dimensional_shape(#{id := Id, shape := Shape}) ->
    error({unsupported_family_shape, Id, Shape}).

validate_dimensions(_FamilyId, Width, Height)
        when is_integer(Width), Width > 0, Width =< ?U32_MAX,
             is_integer(Height), Height > 0, Height =< ?U32_MAX ->
    ok;
validate_dimensions(FamilyId, Width, Height) ->
    error({unsupported_dslx_family_dimensions,
        FamilyId, [Width, Height], ?U32_MAX}).

require_externals([_ | _] = Externals) -> Externals;
require_externals([]) -> error({unsupported_dslx_family_external_count, 0}).

annotate_families(Families, EgressDepth) ->
    [
        begin
            Module = maps:get(module, Family),
            Interface = hls_actor_interface:from_module(Module),
            Family#{
                index => Index,
                module_name => identifier(Module, family_module),
                interface => Interface,
                egress_depth => egress_depth(EgressDepth, Interface)
            }
        end
        || {Index, Family} <- lists:enumerate(0, Families)
    ].

egress_depth(burst, Interface) ->
    max(0, hls_actor_interface:max_entry_effects(Interface) - 1);
egress_depth(Depth, _Interface) ->
    Depth.

annotate_ingresses([], _FamilyIndex) -> [];
annotate_ingresses([Ingress = #{
    id := Id,
    kind := rectangle,
    shape := [Width, Height],
    targets := Targets
}], FamilyIndex) when Width =< ?U16_EXTENT, Height =< ?U16_EXTENT ->
    length(Targets) =< 4 orelse error({ingress_targets, length(Targets)}),
    AnnotatedTargets = [
        annotate_ingress_target(Index, Target, FamilyIndex)
        || {Index, Target} <- lists:enumerate(0, Targets)
    ],
    Recipients = ingress_recipients(AnnotatedTargets),
    [Ingress#{
        index => 0,
        input_name => [identifier(Id, ingress_id), "_in"],
        targets => AnnotatedTargets,
        recipients => Recipients
    }];
annotate_ingresses([#{shape := Shape}], _FamilyIndex) ->
    error({ingress_shape, Shape, ?U16_EXTENT});
annotate_ingresses(Ingresses, _FamilyIndex) ->
    error({ingress_count, length(Ingresses)}).

annotate_ingress_target(
    Index,
    Target = #{id := Id, schemas := Schemas, recipients := Recipients},
    FamilyIndex
) ->
    TargetName = string:uppercase(identifier(Id, ingress_target)),
    Encodings = lists:usort([
        begin
            #{interface := Interface} = maps:get(FamilyId, FamilyIndex),
            #{selector := Selector, fields := Fields} =
                hls_actor_interface:schema(Interface, Schema),
            {Schema, Selector, Fields}
        end
        || Schema <- Schemas,
           #{family := FamilyId} <- Recipients
    ]),
    lists:foreach(
        fun(Schema) ->
            case [Encoding || Encoding = {Name, _, _} <- Encodings,
                    Name =:= Schema] of
                [_] -> ok;
                Values -> error({ingress_encoding, Id, Schema, Values})
            end
        end,
        Schemas
    ),
    Target#{
        selector => Index,
        target_name => TargetName,
        encodings => Encodings
    }.

ingress_recipients(Targets) ->
    ByFamily = lists:foldl(
        fun(#{id := TargetId, recipients := Recipients}, Acc0) ->
            lists:foldl(
                fun(Recipient = #{family := FamilyId}, Acc) ->
                    maps:update_with(
                        FamilyId,
                        fun(Existing = #{scale := Scale, offset := Offset,
                                targets := TargetIds}) ->
                            #{scale := Scale, offset := Offset} = Recipient,
                            Existing#{targets := [TargetId | TargetIds]}
                        end,
                        Recipient#{targets => [TargetId]},
                        Acc
                    )
                end,
                Acc0,
                Recipients
            )
        end,
        #{},
        Targets
    ),
    [Recipient#{targets := lists:sort(TargetIds)}
        || {_FamilyId, Recipient = #{targets := TargetIds}} <-
               lists:sort(maps:to_list(ByFamily))].

validate_relations(Relations, FamilyIndex) ->
    lists:foreach(
        fun(Relation = #{source := Source = {SourceFamily, _Port}}) ->
            true = maps:is_key(SourceFamily, FamilyIndex),
            case Relation of
                #{delivery := direct, recipients := [Recipient]} ->
                    validate_relation_recipient(
                        Source, Recipient, FamilyIndex
                    );
                #{delivery := queued, recipients := Recipients}
                        when length(Recipients) =:= 2 ->
                    validate_queued_recipients(
                        Source, Recipients, FamilyIndex
                    );
                #{delivery := Delivery, recipients := Recipients} ->
                    error({unsupported_route, Source, Delivery, Recipients})
            end
        end,
        Relations
    ).

validate_relation_recipient(
        _Source,
        {family, DestinationId, {translate, [_DX, _DY], wrap}},
        FamilyIndex) ->
    true = maps:is_key(DestinationId, FamilyIndex),
    ok;
validate_relation_recipient(_Source, {external, _ExternalId}, _FamilyIndex) ->
    ok;
validate_relation_recipient(Source, Recipient, _FamilyIndex) ->
    error({unsupported_recipient, Source, Recipient}).

validate_queued_recipients(Source, Recipients, FamilyIndex) ->
    lists:foreach(
        fun(Recipient) ->
            validate_relation_recipient(Source, Recipient, FamilyIndex)
        end,
        Recipients
    ),
    case lists:sort([recipient_kind(Recipient) || Recipient <- Recipients]) of
        [external, family] -> ok;
        Kinds -> error({unsupported_queued_recipients, Source, Kinds})
    end.

recipient_kind({family, _, _}) -> family;
recipient_kind({external, _}) -> external.

derive_lane_relations(Relations) ->
    LanePorts = lists:foldl(
        fun(Relation, Acc0) ->
            {SourceFamily, Port} = maps:get(source, Relation),
            lists:foldl(
                fun(Destination, Acc) ->
                    Key = {SourceFamily, Destination},
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
            source => SourceFamily,
            destination => Destination,
            source_ports => lists:sort(Ports)
        }
        || {{SourceFamily, Destination}, Ports} <-
               lists:sort(maps:to_list(LanePorts))
    ].

annotate_externals(Externals) ->
    [
        begin
            case maps:get(direction, External) of
                out -> ok;
                Direction -> error({unsupported_dslx_family_external_direction,
                    maps:get(id, External), Direction})
            end,
            External#{
                index => Index,
                output_name => [identifier(
                    maps:get(id, External),
                    external_id
                ), "_out"]
            }
        end
        || {Index, External} <- lists:enumerate(0, Externals)
    ].

annotate_lanes(Lanes, Shape, ExternalIndex) ->
    [
        annotate_lane(Index, Lane, Shape, ExternalIndex)
        || {Index, Lane} <- lists:enumerate(0, Lanes)
    ].

annotate_lane(
        Index,
        Lane = #{destination :=
            {family, DestinationId, {translate, [DX, DY], wrap}}},
        [Width, Height],
        _ExternalIndex) ->
    Stem = ["lane_", integer_to_list(Index)],
    Base = Lane#{index => Index, stem => Stem},
    Base#{
        kind => family,
        destination_family => DestinationId,
        inverse_shift => [
            inverse_shift(DX, Width),
            inverse_shift(DY, Height)
        ]
    };
annotate_lane(
        Index,
        Lane = #{destination := {external, ExternalId}},
        _Shape,
        ExternalIndex) ->
    Stem = ["lane_", integer_to_list(Index)],
    Base = Lane#{index => Index, stem => Stem},
    case maps:find(ExternalId, ExternalIndex) of
        {ok, External} -> Base#{kind => external, external => External};
        error -> error({unknown_external, ExternalId})
    end;
annotate_lane(_Index, #{destination := Destination}, _Shape, _ExternalIndex) ->
    error({unsupported_destination, Destination}).

inverse_shift(0, _Size) -> zero;
inverse_shift(Offset, _Size) when Offset > 0 ->
    {minus, Offset};
inverse_shift(Offset, _Size) ->
    {plus, -Offset}.

annotate_routes(Relations, Lanes) ->
    LaneIndex = maps:from_list([
        {{maps:get(source, Lane), maps:get(destination, Lane)}, Lane}
        || Lane <- Lanes
    ]),
    [
        Relation#{lanes => [
            maps:get({SourceFamily, Recipient}, LaneIndex)
            || Recipient <- maps:get(recipients, Relation)
        ]}
        || Relation <- Relations,
           {SourceFamily, _Port} <- [maps:get(source, Relation)]
    ].

annotate_family_graph(Family, Routes, Lanes, Startup, Ingresses) ->
    Id = maps:get(id, Family),
    OutboundLanes = [Lane || Lane <- Lanes, maps:get(source, Lane) =:= Id],
    InboundLanes = [
        Lane
        || Lane <- Lanes,
           maps:get(kind, Lane) =:= family,
           maps:get(destination_family, Lane) =:= Id
    ],
    FamilyStartup = [
        Item || Item <- Startup, maps:get(family, Item) =:= Id
    ],
    Family#{
        routes => [
            Route
            || Route <- Routes,
               {SourceFamily, _} <- [maps:get(source, Route)],
               SourceFamily =:= Id
        ],
        outbound_lanes => OutboundLanes,
        inbound_lanes => InboundLanes,
        startup => family_startup(Family, FamilyStartup),
        ingress => family_ingress_binding(Family, Ingresses)
    }.

family_ingress_binding(#{id := FamilyId}, Ingresses) ->
    Matches = [
        Recipient#{
            ingress => maps:get(id, Ingress),
            targets => ingress_family_targets(FamilyId, Ingress)
        }
        || Ingress <- Ingresses,
           Recipient = #{family := RecipientId} <-
               maps:get(recipients, Ingress),
           RecipientId =:= FamilyId
    ],
    case Matches of
        [] -> none;
        [Ingress] -> Ingress;
        [_, _ | _] -> error({family_ingresses, FamilyId, length(Matches)})
    end.

ingress_family_targets(FamilyId, #{targets := Targets}) ->
    [
        maps:get(id, Target)
        || Target <- Targets,
           lists:any(
               fun(#{family := RecipientId}) ->
                   RecipientId =:= FamilyId
               end,
               maps:get(recipients, Target)
           )
    ].

family_startup(_Family, []) -> none;
family_startup(Family, Items) ->
    Expected = maps:get(instance_count, Family),
    case length(Items) of
        Expected -> #{items => Items};
        Count -> error({incomplete_family_startup,
            maps:get(id, Family), Expected, Count})
    end.

validate_lane_ports(Families) ->
    lists:foreach(
        fun(Family) ->
            Ports = lists:usort(lists:append([
                maps:get(source_ports, Lane)
                || Lane <- maps:get(outbound_lanes, Family)
            ])),
            Outputs = lists:sort(maps:get(outputs, Family)),
            case lists:sort(Ports) of
                Outputs -> ok;
                Other -> error({inconsistent_family_lane_ports,
                    maps:get(id, Family), Outputs, Other})
            end
        end,
        Families
    ).

validate_external_lanes(Externals, Lanes) ->
    lists:foreach(
        fun(External) ->
            Id = maps:get(id, External),
            case external_lanes(External, Lanes) of
                [] -> error({external_lanes, Id, 0});
                [_ | _] -> ok
            end
        end,
        Externals
    ).

validate_route_selectors(Relations, FamilyIndex, ExternalIndex) ->
    lists:foreach(
        fun(#{
            source := Source = {SourceId, Port},
            recipients := Recipients
        }) ->
            SourceInterface = maps:get(
                interface,
                maps:get(SourceId, FamilyIndex)
            ),
            Schemas = hls_actor_interface:output_schemas(
                SourceInterface,
                Port
            ),
            lists:foreach(
                fun
                    ({family, DestinationId, _} = Recipient) ->
                        DestinationInterface = maps:get(
                            interface,
                            maps:get(DestinationId, FamilyIndex)
                        ),
                        lists:foreach(
                            fun(Schema) ->
                                SourceSelector = maps:get(
                                    selector,
                                    hls_actor_interface:schema(
                                        SourceInterface, Schema
                                    )
                                ),
                                DestinationSelector = maps:get(
                                    selector,
                                    hls_actor_interface:schema(
                                        DestinationInterface, Schema
                                    )
                                ),
                                case DestinationSelector of
                                    SourceSelector -> ok;
                                    _ -> error({unsupported_route_tag_remap,
                                        Source, Recipient, Schema,
                                        SourceSelector, DestinationSelector})
                                end
                            end,
                            Schemas
                        );
                    ({external, ExternalId}) ->
                        true = maps:is_key(ExternalId, ExternalIndex)
                end,
                Recipients
            )
        end,
        Relations
    ),
    validate_external_selectors(Relations, FamilyIndex).

validate_external_selectors(Relations, FamilyIndex) ->
    Bindings = lists:foldl(
        fun(#{
            source := Source = {SourceId, Port},
            recipients := Recipients
        }, Acc0) ->
            #{interface := Interface} = maps:get(SourceId, FamilyIndex),
            Schemas = hls_actor_interface:output_schemas(Interface, Port),
            lists:foldl(
                fun
                    ({external, ExternalId}, Acc) ->
                        New = [external_binding(
                            Source,
                            Schema,
                            Interface
                        ) || Schema <- Schemas],
                        maps:update_with(
                            ExternalId,
                            fun(Old) -> New ++ Old end,
                            New,
                            Acc
                        );
                    ({family, _, _}, Acc) ->
                        Acc
                end,
                Acc0,
                Recipients
            )
        end,
        #{},
        Relations
    ),
    maps:foreach(fun validate_external_bindings/2, Bindings).

external_binding(Source, Schema, Interface) ->
    #{selector := Selector, fields := Fields} =
        hls_actor_interface:schema(Interface, Schema),
    #{
        source => Source,
        schema => Schema,
        selector => Selector,
        fields => Fields
    }.

validate_external_bindings(ExternalId, Bindings) ->
    _ = lists:foldl(
        fun(#{
            source := Source,
            schema := Schema,
            selector := Selector,
            fields := Fields
        }, {BySchema0, BySelector0}) ->
            Encoding = {Selector, Fields, Source},
            BySchema = case maps:find(Schema, BySchema0) of
                error -> BySchema0#{Schema => Encoding};
                {ok, {Selector, Fields, _}} -> BySchema0;
                {ok, Existing} -> error({external_schema,
                    ExternalId, Schema, Existing, Encoding})
            end,
            BySelector = case maps:find(Selector, BySelector0) of
                error -> BySelector0#{Selector => Schema};
                {ok, Schema} -> BySelector0;
                {ok, ExistingSchema} -> error({external_selector,
                    ExternalId, Selector, ExistingSchema, Schema})
            end,
            {BySchema, BySelector}
        end,
        {#{}, #{}},
        Bindings
    ),
    ok.

annotate_startup(Startup, FamilyIndex) when is_list(Startup) ->
    [annotate_startup_item(Item, FamilyIndex) || Item <- Startup];
annotate_startup(Startup, _FamilyIndex) ->
    error({invalid_startup, Startup}).

annotate_startup_item(
        #{target := Target, delivery := cast, messages := [Message]},
        FamilyIndex) ->
    [FamilyId | Coordinates] = tuple_to_list(Target),
    #{interface := Interface, module := Module} =
        maps:get(FamilyId, FamilyIndex),
    case hls_actor_interface:initial_effects(Interface) of
        [] -> ok;
        Effects -> error({startup_target_has_initial_effects,
            Target, Module, Effects})
    end,
    Packed = pack_startup_message(Target, Module, Interface, Message),
    Packed#{
        target => Target,
        family => FamilyId,
        coordinates => Coordinates
    };
annotate_startup_item(Item, _FamilyIndex) ->
    error({unsupported_family_startup, Item}).

pack_startup_message(Target, Module, Interface, Message)
        when is_tuple(Message), tuple_size(Message) > 0,
             is_atom(element(1, Message)) ->
    TagName = element(1, Message),
    Schema = hls_actor_interface:schema(Interface, TagName),
    {Tag, Payload} = case {Module:pack_tag(TagName), Module:pack(Message)} of
        {PackedTag, PackedPayload}
                when is_integer(PackedTag), PackedTag >= 0,
                     PackedTag =< 255, is_binary(PackedPayload) ->
            {PackedTag, PackedPayload};
        Invalid -> error({invalid_packed_startup, Target, Invalid})
    end,
    Width = bit_size(Payload),
    case Width > 0 andalso Width rem 32 =:= 0 andalso
            Width =< ?MAX_PAYLOAD_BITS of
        true -> #{
            tag => Tag,
            payload => xls_nums:packed_unsigned_literal(Payload),
            schema => TagName,
            fields => startup_fields(
                Target,
                maps:get(fields, Schema),
                tl(tuple_to_list(Message))
            )
        };
        false -> error({unsupported_startup_payload, Target, Width})
    end;
pack_startup_message(Target, _Module, _Interface, Message) ->
    error({invalid_startup_message, Target, Message}).

startup_fields(_Target, Fields, Values)
        when length(Fields) =:= length(Values) ->
    [Field#{value => Value} || {Field, Value} <- lists:zip(Fields, Values)];
startup_fields(Target, Fields, Values) ->
    error({invalid_startup_fields, Target, length(Fields), length(Values)}).

validate_profile(Profile) when is_map(Profile) ->
    Required = lists:sort([actor_egress_depth, channel_depth, name]),
    Keys = lists:sort(maps:keys(Profile)),
    Allowed = lists:sort([scheduler_groups | Required]),
    case {Required -- Keys, Keys -- Allowed} of
        {[], []} -> ok;
        {Missing, Unknown} ->
            error({invalid_dslx_profile_keys, Missing, Unknown})
    end,
    Name = identifier(maps:get(name, Profile), topology_name),
    case maps:get(channel_depth, Profile) of
        Depth when is_integer(Depth), Depth > 0, Depth =< ?U32_MAX -> ok;
        Depth -> error({invalid_dslx_channel_depth, Depth})
    end,
    case maps:get(actor_egress_depth, Profile) of
        burst -> ok;
        EgressDepth when is_integer(EgressDepth),
                EgressDepth >= 0, EgressDepth =< ?U32_MAX -> ok;
        EgressDepth -> error({egress_depth, EgressDepth})
    end,
    case maps:get(scheduler_groups, Profile, #{}) of
        Groups when is_map(Groups) -> ok;
        Groups -> error({scheduler_groups, Groups})
    end,
    Profile#{name := Name};
validate_profile(Profile) ->
    error({invalid_dslx_profile, Profile}).

identifier(Name, Context) when is_atom(Name) ->
    identifier(atom_to_list(Name), Context);
identifier(Name, Context) when is_list(Name) ->
    case re:run(Name, "^[a-z][a-z0-9_]*$", [{capture, none}]) of
        match ->
            case lists:member(Name, reserved_identifiers()) of
                true -> error({reserved_dslx_identifier, Context, Name});
                false -> Name
            end;
        nomatch -> error({invalid_dslx_identifier, Context, Name})
    end;
identifier(Name, Context) ->
    error({invalid_dslx_identifier, Context, Name}).

reserved_identifiers() ->
    [
        "as", "const", "else", "enum", "fn", "for", "if", "import",
        "in", "let", "match", "proc", "pub", "spawn", "struct",
        "type", "while"
    ].

%%%
%%% Rendering
%%%

render(Spec = #{schedulers := [_ | _]}) ->
    xls_topology_scheduler_dslx:emit(Spec);
render(Spec) ->
    [
        preamble(Spec),
        startup_support(maps:get(families, Spec)),
        family_routers(Spec),
        frame_grid_mux(maps:get(externals, Spec)),
        control_support(Spec),
        family_ingresses(Spec),
        family_nodes(Spec),
        family_grid(Spec),
        top_proc(Spec)
    ].

preamble(Spec) ->
    Families = maps:get(families, Spec),
    Modules = lists:usort([
        maps:get(module_name, Family) || Family <- Families
    ]),
    [
        "// ", maps:get(name, Spec), ".x\n",
        "// Auto-generated by xls_topology_dslx from compact Erlang family ",
        "rules.\n",
        "// Manual changes will be overwritten.\n",
        "//\n",
        preamble_node_comment(Families),
        "// Direct lanes carry depth-zero metadata and require registered ",
        "router output slots.\n",
        "// Scalar external streams use fair polling over statically indexed ",
        "family lanes.\n\n",
        "import axis;\n",
        case maps:get(ingresses, Spec) of
            [] -> [];
            [_] -> "import hls_spatial_router;\n"
        end,
        [["import ", Module, ";\n"] || Module <- Modules],
        "\n",
        "const CHANNEL_DEPTH = u32:", integer_to_list(maps:get(depth, Spec)),
        ";\n",
        "const WIDTH = u32:", integer_to_list(maps:get(width, Spec)), ";\n",
        "const HEIGHT = u32:", integer_to_list(maps:get(height, Spec)),
        ";\n\n"
    ].

preamble_node_comment([_]) ->
    "// One reusable node and nested unroll_for! spawns retain regular "
    "source structure.\n";
preamble_node_comment([_, _ | _]) ->
    "// Reusable family nodes and nested unroll_for! spawns retain regular "
    "source structure.\n".

startup_support(Families) ->
    [startup_function(Family) || Family <- Families].

startup_function(#{startup := none}) -> [];
startup_function(Family = #{startup := #{items := Items}}) ->
    [
        "fn ", startup_function_name(Family),
        "(x: u32, y: u32) -> axis::Frame {\n",
        "  match (x, y) {\n",
        [startup_arm(Item) || Item <- Items],
        "    _ => zero!<axis::Frame>(),\n",
        "  }\n}\n\n"
    ].

startup_arm(#{coordinates := [X, Y], tag := Tag, payload := Payload}) ->
    ["    (u32:", integer_to_list(X), ", u32:", integer_to_list(Y),
        ") => axis::pack(u8:", integer_to_list(Tag), ", ", Payload,
        "),\n"].

family_routers(Spec) ->
    [family_router(Spec, Family) || Family <- maps:get(families, Spec)].

family_router(Spec, Family) ->
    Module = maps:get(module_name, Family),
    Lanes = maps:get(outbound_lanes, Family),
    Members = [["egress_in: chan<", Module, "::Egress> in"] |
        [[lane_output(Lane), ": chan<axis::Frame> out"]
            || Lane <- Lanes]],
    Routes = maps:get(routes, Family),
    [
        "proc ", router_name(Spec, Family), " {\n",
        "  egress_in: chan<", Module, "::Egress> in;\n",
        [["  ", lane_output(Lane), ": chan<axis::Frame> out;\n"]
            || Lane <- Lanes],
        "\n",
        config_signature(Members, 2),
        "    (egress_in",
        [[", ", lane_output(Lane)] || Lane <- Lanes],
        ")\n  }\n\n",
        "  init { () }\n\n",
        "  next(state: ()) {\n",
        "    let (tok, egress) = recv(join(), egress_in);\n",
        [family_lane_selection(Module, Lane, Routes) || Lane <- Lanes],
        [family_lane_send(Lane) || Lane <- Lanes],
        "    let _route_tok = ", join_tokens([
            family_lane_token(Lane) || Lane <- Lanes
        ]), ";\n",
        "    state\n  }\n}\n\n"
    ].

family_lane_selection(Module, Lane, Routes) ->
    LaneIndex = maps:get(index, Lane),
    Ports = [
        Port
        || Route <- Routes,
           lists:any(
               fun(RouteLane) -> maps:get(index, RouteLane) =:= LaneIndex end,
               maps:get(lanes, Route)
           ),
           {_FamilyId, Port} <- [maps:get(source, Route)]
    ],
    [
        "    let ", family_lane_selected(Lane), " = match egress.port {\n",
        [["      ", Module, "::OutputPort::", uppercase(Port),
            " => true,\n"] || Port <- Ports],
        "      _ => false,\n",
        "    };\n"
    ].

family_lane_send(Lane) ->
    [
        "    let ", family_lane_token(Lane), " = send_if(\n",
        "      tok, ", lane_output(Lane), ", ",
        family_lane_selected(Lane), ", egress.frame);\n"
    ].

family_lane_selected(Lane) ->
    [maps:get(stem, Lane), "_selected"].

family_lane_token(Lane) ->
    [maps:get(stem, Lane), "_tok"].

frame_grid_mux([]) -> [];
frame_grid_mux(_Externals) ->
    %% DSLX writes array dimensions from inner to outer. Consequently
    %% `[GRID_HEIGHT][GRID_WIDTH]` has `GRID_WIDTH` outer elements and
    %% supports the coordinate order `frame_in[x][y]` used below.
    """
    proc FrameArrayMux<INPUT_COUNT: u32> {
      frame_in: chan<axis::Frame>[INPUT_COUNT] in;
      frame_out: chan<axis::Frame> out;

      config(
          frame_in: chan<axis::Frame>[INPUT_COUNT] in,
          frame_out: chan<axis::Frame> out
      ) {
        (frame_in, frame_out)
      }

      init { u32:0 }

      next(cursor: u32) {
        let (tok, received, frame) =
          unroll_for! (candidate, acc):
              (u32, (token, u1, axis::Frame)) in u32:0..INPUT_COUNT {
            let selected = cursor == candidate;
            let (next_tok, next_frame, valid) = recv_if_non_blocking(
              acc.0,
              frame_in[candidate],
              selected,
              zero!<axis::Frame>());
            (
              next_tok,
              acc.1 | valid,
              if valid { next_frame } else { acc.2 }
            )
          }((join(), u1:0, zero!<axis::Frame>()));
        let _done = send_if(tok, frame_out, received, frame);
        if cursor + u32:1 == INPUT_COUNT {
          u32:0
        } else {
          cursor + u32:1
        }
      }
    }

    proc FrameGridMux<GRID_WIDTH: u32, GRID_HEIGHT: u32> {
      config(
          frame_in: chan<axis::Frame>[GRID_HEIGHT][GRID_WIDTH] in,
          frame_out: chan<axis::Frame> out
      ) {
        let (column_p, column_c) =
          chan<axis::Frame, CHANNEL_DEPTH>[GRID_WIDTH]("grid_column");
        unroll_for! (x, _): (u32, ()) in u32:0..GRID_WIDTH {
          spawn FrameArrayMux<GRID_HEIGHT>(frame_in[x], column_p[x]);
        }(());
        spawn FrameArrayMux<GRID_WIDTH>(column_c, frame_out);
        ()
      }

      init { () }
      next(state: ()) { state }
    }

    """.

control_support(#{ingresses := []}) -> [];
control_support(Spec = #{ingresses := [Ingress]}) ->
    [
        control_target_enum(Ingress),
        spatial_ingress_router(Spec, Ingress),
        [family_control(Family)
            || Family <- maps:get(families, Spec),
               maps:get(ingress, Family) =/= none]
    ].

control_target_enum(#{targets := Targets}) ->
    [
        "pub enum ControlTarget : u2 {\n",
        [["  ", maps:get(target_name, Target), " = ",
            integer_to_list(maps:get(selector, Target)), ",\n"]
            || Target <- Targets],
        "}\n\n"
    ].

spatial_ingress_router(Spec, Ingress = #{recipients := Recipients}) ->
    Members = [
        [control_spatial_name(Family), ": chan<",
            "hls_spatial_router::SpatialFrame> out"]
        || Family <- controlled_families(Spec, Recipients)
    ],
    Names = [control_spatial_name(Family)
        || Family <- controlled_families(Spec, Recipients)],
    [
        "// One ordered application stream enters the addressed router service.\n",
        "// Target and rectangle are selectors interpreted inside that service.\n",
        "proc SpatialIngressRouter {\n",
        "  spatial_in: chan<hls_spatial_router::SpatialFrame> in;\n",
        [["  ", Member, ";\n"] || Member <- Members],
        "\n",
        config_signature(
            ["spatial_in: chan<hls_spatial_router::SpatialFrame> in" |
                Members],
            2
        ),
        "    (spatial_in",
        [[", ", Name] || Name <- Names],
        ")\n  }\n\n",
        "  init { () }\n\n",
        "  next(state: ()) {\n",
        "    let (tok, packet) = recv(join(), spatial_in);\n",
        spatial_ingress_router_sends(
            controlled_families(Spec, Recipients),
            Ingress,
            0,
            "tok"
        ),
        "    state\n  }\n}\n\n"
    ].

spatial_ingress_router_sends([Family], Ingress, _Index, PreviousToken) ->
    [
        "    let _done = send_if(", PreviousToken, ", ",
        control_spatial_name(Family), ", ",
        control_target_condition(
            maps:get(targets, maps:get(ingress, Family)),
            Ingress
        ),
        ", packet);\n"
    ];
spatial_ingress_router_sends([Family | Rest], Ingress, Index, PreviousToken) ->
    Token = ["tok_", integer_to_list(Index)],
    [
        "    let ", Token, " = send_if(", PreviousToken, ", ",
        control_spatial_name(Family), ", ",
        control_target_condition(
            maps:get(targets, maps:get(ingress, Family)),
            Ingress
        ),
        ", packet);\n",
        spatial_ingress_router_sends(Rest, Ingress, Index + 1, Token)
    ].

control_target_condition(TargetIds, #{targets := Targets}) ->
    join_with(" || ", [
        control_target_clause(Target)
        || Target = #{id := Id} <- Targets,
           lists:member(Id, TargetIds)
    ]).

control_target_clause(#{target_name := Name, encodings := Encodings}) ->
    Selectors = [Selector || {_Schema, Selector, _Fields} <- Encodings],
    ["(packet.target == ControlTarget::", Name, " as u2 && (",
        join_with(" || ", [
            ["packet.frame.header.op == u8:", integer_to_list(Selector)]
            || Selector <- Selectors
        ]), "))"].

family_control(Family = #{ingress := #{
    scale := [ScaleX, ScaleY],
    offset := [OffsetX, OffsetY]
}}) ->
    [
        "proc ", control_name(Family), " {\n",
        "  spatial_in: chan<hls_spatial_router::SpatialFrame> in;\n",
        "  frame_out: chan<axis::Frame>[HEIGHT][WIDTH] out;\n\n",
        config_signature([
            "spatial_in: chan<hls_spatial_router::SpatialFrame> in",
            "frame_out: chan<axis::Frame>[HEIGHT][WIDTH] out"
        ], 2),
        "    (spatial_in, frame_out)\n  }\n\n",
        "  init { () }\n\n",
        "  next(state: ()) {\n",
        "    let (tok, packet) = recv(join(), spatial_in);\n",
        "    let _done = unroll_for! (x, x_tok):\n",
        "        (u32, token) in u32:0..WIDTH {\n",
        "      unroll_for! (y, y_tok):\n",
        "          (u32, token) in u32:0..HEIGHT {\n",
        "        let address_x = (x * u32:", integer_to_list(ScaleX),
        " + u32:", integer_to_list(OffsetX), ") as u16;\n",
        "        let address_y = (y * u32:", integer_to_list(ScaleY),
        " + u32:", integer_to_list(OffsetY), ") as u16;\n",
        "        send_if(\n",
        "          y_tok, frame_out[x][y],\n",
        "          hls_spatial_router::contains(\n",
        "            packet.rectangle, address_x, address_y),\n",
        "          packet.frame)\n",
        "      }(x_tok)\n",
        "    }(tok);\n",
        "    state\n  }\n}\n\n"
    ].

controlled_families(Spec, Recipients) ->
    RecipientIds = maps:from_keys(
        [maps:get(family, Recipient) || Recipient <- Recipients],
        true
    ),
    [Family || Family <- maps:get(families, Spec),
        maps:is_key(maps:get(id, Family), RecipientIds)].

family_ingresses(Spec) ->
    [family_ingress(Spec, Family) || Family <- maps:get(families, Spec)].

family_ingress(Spec, Family = #{inbound_lanes := InboundLanes}) ->
    InputCount = length(InboundLanes) + control_input_count(Family),
    case InputCount of
        0 -> error(no_inbound_lanes);
        _ -> ok
    end,
    InputNames = [incoming_name(Index)
        || Index <- lists:seq(0, InputCount - 1)],
    CursorType = xls_nums:unsigned_type(cursor_width(InputCount)),
    InputMembers = [
        [Name, ": chan<axis::Frame> in"] || Name <- InputNames
    ],
    Members = InputMembers ++ [
        "frame_out: chan<axis::Frame> out",
        "admission_in: chan<u1> in"
    ],
    MemberNames = InputNames ++ ["frame_out", "admission_in"],
    [
        "// Retains one mailbox credit while polling one input per ",
        "activation.\n",
        "proc ", ingress_name(Spec, Family), node_parametrics(Family), " {\n",
        [["  ", Member, ";\n"] || Member <- Members],
        "\n",
        config_signature(Members, 2),
        "    (", join_with(", ", MemberNames), ")\n  }\n\n",
        ingress_init(Family, CursorType),
        ingress_next(Family, CursorType, InputCount),
        "}\n\n"
    ].

control_input_count(#{ingress := none}) -> 0;
control_input_count(#{
    ingress := #{scale := [_, _], offset := [_, _]}
}) -> 1.

ingress_init(#{startup := none}, CursorType) ->
    ["  init { (", cursor_literal(CursorType, 0), ", u1:0) }\n\n"];
ingress_init(#{startup := #{}}, CursorType) ->
    ["  init { (", cursor_literal(CursorType, 0),
        ", u1:0, u1:0) }\n\n"].

ingress_next(#{startup := none}, CursorType, InputCount) ->
    [
        "  next(state: (", CursorType, ", u1)) {\n",
        "    if !state.1 {\n",
        ingress_credit_state(false),
        "    } else {\n",
        ingress_poll(CursorType, InputCount, false),
        "    }\n",
        "  }\n"
    ];
ingress_next(Family = #{startup := #{}}, CursorType, InputCount) ->
    [
        "  next(state: (", CursorType, ", u1, u1)) {\n",
        "    if !state.1 {\n",
        ingress_credit_state(true),
        "    } else if !state.2 {\n",
        "      let _tok = send(\n",
        "        join(), frame_out, ", startup_function_name(Family),
        "(X, Y));\n",
        "      (state.0, u1:0, u1:1)\n",
        "    } else {\n",
        ingress_poll(CursorType, InputCount, true),
        "    }\n",
        "  }\n"
    ].

ingress_credit_state(HasStartup) ->
    [
        "      let (_tok, _credit) = recv(join(), admission_in);\n",
        "      (state.0, u1:1", ingress_started_state(HasStartup), ")\n"
    ].

ingress_started_state(false) -> [];
ingress_started_state(true) -> ", state.2".

ingress_poll(CursorType, InputCount, HasStartup) ->
    Indexes = lists:seq(0, InputCount - 1),
    [
        [ingress_receive(Index, CursorType) || Index <- Indexes],
        "      let received = ",
        join_with(" || ", [valid_name(Index) || Index <- Indexes]), ";\n",
        "      let frame = ", select_received_frame(Indexes), ";\n",
        "      let _done = send_if(", token_name(InputCount - 1),
        ", frame_out, received, frame);\n",
        "      let next_cursor = if state.0 == ",
        cursor_literal(CursorType, InputCount - 1), " {\n",
        "        ", cursor_literal(CursorType, 0), "\n",
        "      } else {\n",
        "        state.0 + ", cursor_literal(CursorType, 1), "\n",
        "      };\n",
        "      (next_cursor, !received", ingress_started_state(HasStartup),
        ")\n"
    ].

ingress_receive(Index, CursorType) ->
    PreviousToken = case Index of
        0 -> "join()";
        _ -> token_name(Index - 1)
    end,
    [
        "      let (", token_name(Index), ", ", frame_name(Index), ", ",
        valid_name(Index), ") = recv_if_non_blocking(\n",
        "        ", PreviousToken, ", ", incoming_name(Index),
        ", state.0 == ", cursor_literal(CursorType, Index),
        ", zero!<axis::Frame>());\n"
    ].

select_received_frame([Index]) -> frame_name(Index);
select_received_frame([Index | Rest]) ->
    ["if ", valid_name(Index), " { ", frame_name(Index),
        " } else { ", select_received_frame(Rest), " }"].

cursor_width(InputCount) ->
    cursor_width(InputCount - 1, 0).

cursor_width(0, 0) -> 1;
cursor_width(0, Width) -> Width;
cursor_width(Value, Width) -> cursor_width(Value bsr 1, Width + 1).

cursor_literal(CursorType, Value) ->
    [CursorType, ":", integer_to_list(Value)].

token_name(Index) -> ["tok_", integer_to_list(Index)].
frame_name(Index) -> ["frame_", integer_to_list(Index)].
valid_name(Index) -> ["valid_", integer_to_list(Index)].

family_nodes(Spec) ->
    [family_node(Spec, Family) || Family <- maps:get(families, Spec)].

family_node(Spec, Family) ->
    InboundLanes = maps:get(inbound_lanes, Family),
    OutboundLanes = maps:get(outbound_lanes, Family),
    InputCount = length(InboundLanes) + control_input_count(Family),
    Inputs = [[incoming_name(Index), ": chan<axis::Frame> in"]
        || Index <- lists:seq(0, InputCount - 1)],
    Outputs = [[lane_output(Lane), ": chan<axis::Frame> out"]
        || Lane <- OutboundLanes],
    SchedulerMembers = node_scheduler_members(Family),
    [
        "proc ", node_name(Spec, Family), node_parametrics(Family), " {\n",
        config_signature(Inputs ++ Outputs ++ SchedulerMembers, 2),
        node_body(Spec, Family, InputCount, OutboundLanes),
        "    ()\n  }\n\n",
        "  init { () }\n",
        "  next(state: ()) { state }\n",
        "}\n\n"
    ].

node_scheduler_members(#{scheduler := direct}) -> [];
node_scheduler_members(#{
    scheduler := #{group := _},
    module_name := Module
}) ->
    [
        "actor_req_out: chan<axis::Frame> out",
        "actor_admit_in: chan<u1> in",
        ["actor_egress_in: chan<", Module, "::Egress> in"]
    ].

node_body(Spec, Family = #{scheduler := direct}, InputCount, OutboundLanes) ->
    Module = maps:get(module_name, Family),
    [
        "    let (actor_req_p, actor_req_c) =\n",
        "      chan<axis::Frame, CHANNEL_DEPTH>(\"actor_req\");\n",
        "    let (actor_admit_p, actor_admit_c) =\n",
        "      chan<u1, CHANNEL_DEPTH>(\"actor_admit\");\n",
        "    let (actor_egress_p, actor_egress_c) =\n",
        "      chan<", Module, "::Egress, u32:",
        integer_to_list(maps:get(egress_depth, Family)),
        ">(\"actor_egress\");\n",
        "    spawn ", Module, "::Service(\n",
        "      actor_req_c, actor_egress_p, actor_admit_p);\n",
        "    spawn ", router_name(Spec, Family), "(actor_egress_c",
        [[", ", lane_output(Lane)] || Lane <- OutboundLanes],
        ");\n",
        "    spawn ", ingress_name(Spec, Family),
        ingress_specialization(Family), "(",
        join_with(", ", [
            incoming_name(Index)
            || Index <- lists:seq(0, InputCount - 1)
        ] ++ ["actor_req_p", "actor_admit_c"]),
        ");\n"
    ];
node_body(Spec, Family = #{scheduler := #{group := _}}, InputCount,
        OutboundLanes) ->
    [
        "    spawn ", router_name(Spec, Family), "(actor_egress_in",
        [[", ", lane_output(Lane)] || Lane <- OutboundLanes],
        ");\n",
        "    spawn ", ingress_name(Spec, Family),
        ingress_specialization(Family), "(",
        join_with(", ", [
            incoming_name(Index)
            || Index <- lists:seq(0, InputCount - 1)
        ] ++ ["actor_req_out", "actor_admit_in"]),
        ");\n"
    ].

family_grid(Spec) ->
    Lanes = maps:get(lanes, Spec),
    Externals = maps:get(externals, Spec),
    IngressArguments = ingress_arguments(Spec),
    RamArguments = scheduler_ram_arguments(Spec),
    [
        "proc ", grid_name(Spec),
        "<TORUS_WIDTH: u32, TORUS_HEIGHT: u32> {\n",
        config_signature(
            RamArguments ++ IngressArguments ++
                [[OutputName, ": chan<axis::Frame> out"]
                || #{output_name := OutputName} <- Externals],
            2
        ),
        [lane_array(Lane) || Lane <- Lanes],
        control_channels(Spec),
        scheduler_channels(Spec),
        [family_spawn(Spec, Family)
            || Family <- maps:get(families, Spec)],
        scheduler_spawns(Spec),
        control_spawns(Spec),
        [external_merge_spawn(External, Lanes) || External <- Externals],
        "    ()\n  }\n\n",
        "  init { () }\n",
        "  next(state: ()) { state }\n",
        "}\n\n"
    ].

scheduler_channels(#{schedulers := Schedulers}) ->
    [scheduler_channel_bank(Scheduler) || Scheduler <- Schedulers].

scheduler_channel_bank(#{
    stem := Stem,
    module_name := Module,
    slot_count := SlotCount
}) ->
    Count = ["u32:", integer_to_list(SlotCount)],
    [
        "    let (", Stem, "_req_p, ", Stem, "_req_c) =\n",
        "      chan<axis::Frame, CHANNEL_DEPTH>[", Count, "]",
        "(\"", Stem, "_req\");\n",
        "    let (", Stem, "_admit_p, ", Stem, "_admit_c) =\n",
        "      chan<u1, CHANNEL_DEPTH>[", Count, "]",
        "(\"", Stem, "_admit\");\n",
        "    let (", Stem, "_egress_p, ", Stem, "_egress_c) =\n",
        "      chan<", Module, "::Egress, u32:1>[", Count, "]",
        "(\"", Stem, "_egress\");\n",
        "    let (", Stem, "_request_p, ", Stem, "_request_c) =\n",
        "      chan<", Module, "::ScheduledRequest, u32:1>(\"",
        Stem, "_request\");\n",
        "    let (", Stem, "_scheduled_egress_p, ", Stem,
        "_scheduled_egress_c) =\n",
        "      chan<", Module, "::ScheduledEgress, u32:1>(\"",
        Stem, "_scheduled_egress\");\n",
        "    let (", Stem, "_scheduled_admit_p, ", Stem,
        "_scheduled_admit_c) =\n",
        "      chan<", Module, "::ScheduledAdmission, u32:1>(\"",
        Stem, "_scheduled_admit\");\n",
        "    let (", Stem, "_credit_p, ", Stem, "_credit_c) =\n",
        "      chan<u1, u32:1>(\"", Stem, "_credit\");\n"
    ].

scheduler_spawns(#{schedulers := Schedulers}) ->
    [
        [
            "    spawn ", Module, "::SchedulerRequestMux<u32:",
            integer_to_list(SlotCount), ">(\n",
            "      ", Stem, "_req_c, ", Stem, "_request_p);\n",
            "    spawn ", Module, "::SharedService<u32:",
            integer_to_list(SlotCount), ">(\n",
            "      ", Stem, "_request_c, ", Stem,
            "_scheduled_egress_p,\n",
            "      ", Stem, "_scheduled_admit_p, ", Stem,
            "_credit_c,\n",
            "      ", Stem, "_ram_read_req_out, ", Stem,
            "_ram_read_resp_in,\n",
            "      ", Stem, "_ram_write_req_out, ", Stem,
            "_ram_write_resp_in,\n",
            "      ", Stem, "_mailbox_read_req_out, ", Stem,
            "_mailbox_read_resp_in,\n",
            "      ", Stem, "_mailbox_write_req_out, ", Stem,
            "_mailbox_write_resp_in);\n",
            "    spawn ", Module, "::SchedulerEgressDemux<u32:",
            integer_to_list(SlotCount), ">(\n",
            "      ", Stem, "_scheduled_egress_c, ", Stem,
            "_egress_p, ", Stem, "_credit_p);\n",
            "    spawn ", Module, "::SchedulerAdmissionDemux<u32:",
            integer_to_list(SlotCount), ">(\n",
            "      ", Stem, "_scheduled_admit_c, ", Stem,
            "_admit_p);\n"
        ]
        || #{stem := Stem, module_name := Module, slot_count := SlotCount} <-
               Schedulers
    ].

scheduler_ram_arguments(#{schedulers := Schedulers}) ->
    lists:append([
        [
            [Stem, "_ram_read_req_out: chan<", Module,
                "::MachineRamReadReq> out"],
            [Stem, "_ram_read_resp_in: chan<", Module,
                "::MachineRamReadResp> in"],
            [Stem, "_ram_write_req_out: chan<", Module,
                "::MachineRamWriteReq> out"],
            [Stem, "_ram_write_resp_in: chan<", Module,
                "::MachineRamWriteResp> in"],
            [Stem, "_mailbox_read_req_out: chan<", Module,
                "::MailboxRamReadReq> out"],
            [Stem, "_mailbox_read_resp_in: chan<", Module,
                "::MailboxRamReadResp> in"],
            [Stem, "_mailbox_write_req_out: chan<", Module,
                "::MailboxRamWriteReq> out"],
            [Stem, "_mailbox_write_resp_in: chan<", Module,
                "::MailboxRamWriteResp> in"]
        ]
        || #{stem := Stem, module_name := Module} <- Schedulers
    ]).

control_channels(#{ingresses := []}) -> [];
control_channels(Spec = #{ingresses := [#{recipients := Recipients}]}) ->
    [
        begin
            SpatialStem = control_spatial_name(Family),
            ChannelStem = control_channel_name(Family),
            [
                "    let (", SpatialStem, "_p, ", SpatialStem, "_c) =\n",
                "      chan<hls_spatial_router::SpatialFrame, u32:0>(\"",
                SpatialStem, "\");\n",
                "    let (", ChannelStem, "_p, ", ChannelStem, "_c) =\n",
                "      chan<axis::Frame, u32:0>",
                "[TORUS_HEIGHT][TORUS_WIDTH](\"", ChannelStem, "\");\n"
            ]
        end
        || Family <- controlled_families(Spec, Recipients)
    ].

control_spawns(#{ingresses := []}) -> [];
control_spawns(Spec = #{ingresses := [Ingress = #{recipients := Recipients}]}) ->
    Families = controlled_families(Spec, Recipients),
    [
        [
            ["    spawn ", control_name(Family), "(",
                control_spatial_name(Family), "_c, ",
                control_channel_name(Family), "_p);\n"]
            || Family <- Families
        ],
        "    spawn SpatialIngressRouter(", maps:get(input_name, Ingress),
        [[", ", control_spatial_name(Family), "_p"] || Family <- Families],
        ");\n"
    ].

ingress_arguments(#{ingresses := []}) -> [];
ingress_arguments(#{ingresses := Ingresses}) ->
    [[maps:get(input_name, Ingress),
        ": chan<hls_spatial_router::SpatialFrame> in"]
        || Ingress <- Ingresses].

lane_array(Lane) ->
    %% Codegen retains one registered output per router lane, so a nonzero FIFO
    %% here would double-buffer every route. As above, the rightmost dimension
    %% is the outer x dimension in DSLX.
    Stem = maps:get(stem, Lane),
    [
        "    let (", Stem, "_p, ", Stem, "_c) =\n",
        "      chan<axis::Frame, u32:0>",
        "[TORUS_HEIGHT][TORUS_WIDTH](\"", Stem, "\");\n"
    ].

family_spawn(Spec, Family) ->
    [
        family_comment(Spec, Family),
        "    unroll_for! (x, _): (u32, ()) in u32:0..TORUS_WIDTH {\n",
        "      unroll_for! (y, _): (u32, ()) in u32:0..TORUS_HEIGHT {\n",
        "        spawn ", node_name(Spec, Family),
        node_specialization(Family), "(\n",
        node_spawn_arguments(Family),
        "        );\n",
        "      }(())\n",
        "    }(());\n"
    ].

family_comment(#{families := [_]}, _Family) -> [];
family_comment(_Spec, Family) ->
    ["    // Family ", io_lib:format("~tp", [maps:get(id, Family)]), ".\n"].

node_spawn_arguments(Family) ->
    InboundLanes = maps:get(inbound_lanes, Family),
    OutboundLanes = maps:get(outbound_lanes, Family),
    Arguments =
        [family_lane_consumer(Lane) || Lane <- InboundLanes] ++
        control_consumer(Family) ++
        [[maps:get(stem, Lane), "_p[x][y]"] || Lane <- OutboundLanes] ++
        scheduler_node_arguments(Family),
    [
        ["          ", Argument, separator(Index, length(Arguments)), "\n"]
        || {Index, Argument} <- lists:enumerate(0, Arguments)
    ].

scheduler_node_arguments(#{scheduler := direct}) -> [];
scheduler_node_arguments(#{scheduler := #{
    stem := Stem,
    base_slot := BaseSlot
}}) ->
    Slot = ["(u32:", integer_to_list(BaseSlot),
        " + x * TORUS_HEIGHT + y)"],
    [
        [Stem, "_req_p[", Slot, "]"],
        [Stem, "_admit_c[", Slot, "]"],
        [Stem, "_egress_c[", Slot, "]"]
    ].

control_consumer(#{ingress := none}) -> [];
control_consumer(Family = #{
    ingress := #{scale := [_, _], offset := [_, _]}
}) ->
    [[control_channel_name(Family), "_c[x][y]"]].

family_lane_consumer(Lane) ->
    [DX, DY] = maps:get(inverse_shift, Lane),
    [maps:get(stem, Lane), "_c[", shifted_index("x", DX, "TORUS_WIDTH"),
        "][", shifted_index("y", DY, "TORUS_HEIGHT"), "]"].

shifted_index(Axis, zero, _Size) -> Axis;
shifted_index(Axis, {plus, Offset}, Size) ->
    ["(", Axis, " + u32:", integer_to_list(Offset), ") % ", Size];
shifted_index(Axis, {minus, Offset}, Size) ->
    ["(", Axis, " + ", Size, " - u32:", integer_to_list(Offset),
        ") % ", Size].

external_merge_spawn(External, Lanes) ->
    external_merge_spawn(External, external_lanes(External, Lanes),
        maps:get(output_name, External)).

external_merge_spawn(_External, [#{stem := Stem}], OutputName) ->
    [
        "    spawn FrameGridMux<TORUS_WIDTH, TORUS_HEIGHT>(",
        Stem, "_c, ", OutputName,
        ");\n"
    ];
external_merge_spawn(External, Lanes = [_, _ | _], OutputName) ->
    Count = length(Lanes),
    CountLiteral = ["u32:", integer_to_list(Count)],
    Stem = ["external_", integer_to_list(maps:get(index, External)),
        "_lanes"],
    [
        "    let (", Stem, "_p, ", Stem, "_c) =\n",
        "      chan<axis::Frame, CHANNEL_DEPTH>[", CountLiteral, "](",
        "\"", Stem, "\");\n",
        [
            [
                "    spawn FrameGridMux<TORUS_WIDTH, TORUS_HEIGHT>(",
                maps:get(stem, Lane), "_c, ", Stem, "_p[u32:",
                integer_to_list(Index), "]);\n"
            ]
            || {Index, Lane} <- lists:enumerate(0, Lanes)
        ],
        "    spawn FrameArrayMux<", CountLiteral, ">(", Stem, "_c, ",
        OutputName, ");\n"
    ].

external_lanes(#{id := Id}, Lanes) ->
    [
        Lane
        || Lane = #{kind := external, external := #{id := ExternalId}} <-
               Lanes,
           ExternalId =:= Id
    ].

top_proc(Spec) ->
    Externals = maps:get(externals, Spec),
    Ingresses = maps:get(ingresses, Spec),
    IngressMembers = [[InputName,
        ": chan<hls_spatial_router::SpatialFrame> in"]
        || #{input_name := InputName} <- Ingresses],
    ExternalMembers = [[OutputName, ": chan<axis::Frame> out"]
        || #{output_name := OutputName} <- Externals],
    RamMembers = scheduler_ram_arguments(Spec),
    RamNames = lists:append([
        [
            [Stem, "_ram_read_req_out"],
            [Stem, "_ram_read_resp_in"],
            [Stem, "_ram_write_req_out"],
            [Stem, "_ram_write_resp_in"],
            [Stem, "_mailbox_read_req_out"],
            [Stem, "_mailbox_read_resp_in"],
            [Stem, "_mailbox_write_req_out"],
            [Stem, "_mailbox_write_resp_in"]
        ]
        || #{stem := Stem} <- maps:get(schedulers, Spec)
    ]),
    Names = RamNames ++
        [InputName || #{input_name := InputName} <- Ingresses] ++
        [OutputName || #{output_name := OutputName} <- Externals],
    [
        "pub proc Top {\n",
        [["  ", Member, ";\n"]
            || Member <- RamMembers ++ IngressMembers ++ ExternalMembers],
        "\n",
        config_signature(
            RamMembers ++ IngressMembers ++ ExternalMembers,
            2
        ),
        "    spawn ", grid_name(Spec), "<WIDTH, HEIGHT>(",
        join_with(", ", Names),
        ");\n",
        "    ", channel_tuple(Names), "\n",
        "  }\n\n",
        "  init { () }\n",
        "  next(state: ()) { state }\n",
        "}\n"
    ].

config_signature(Arguments, Indent) ->
    Padding = lists:duplicate(Indent + 2, $ ),
    [
        lists:duplicate(Indent, $ ), "config(\n",
        [
            [Padding, Argument, separator(Index, length(Arguments)), "\n"]
            || {Index, Argument} <- lists:enumerate(0, Arguments)
        ],
        lists:duplicate(Indent, $ ), ") {\n"
    ].

incoming_name(Index) -> ["incoming_", integer_to_list(Index)].
lane_output(Lane) -> [maps:get(stem, Lane), "_out"].

router_name(Spec, Family) ->
    ["FamilyRouter", family_suffix(Spec, Family)].

node_name(Spec, Family) ->
    ["FamilyNode", family_suffix(Spec, Family)].

ingress_name(Spec, Family) ->
    ["FamilyIngress", family_suffix(Spec, Family)].

control_name(#{index := Index}) ->
    ["FamilyControl", integer_to_list(Index)].

control_spatial_name(#{index := Index}) ->
    ["control_family_", integer_to_list(Index), "_spatial"].

control_channel_name(#{index := Index}) ->
    ["control_family_", integer_to_list(Index)].

startup_function_name(Family) ->
    ["family_", integer_to_list(maps:get(index, Family)), "_startup"].

node_parametrics(#{startup := none}) -> [];
node_parametrics(#{startup := #{}}) -> "<X: u32, Y: u32>".

node_specialization(#{startup := none}) -> [];
node_specialization(#{startup := #{}}) -> "<x, y>".

ingress_specialization(#{startup := none}) -> [];
ingress_specialization(#{startup := #{}}) -> "<X, Y>".

family_suffix(#{families := [_]}, _Family) -> [];
family_suffix(#{families := [_, _ | _]}, #{index := Index}) ->
    integer_to_list(Index).

grid_name(#{families := [_]}) -> "FamilyTorus";
grid_name(#{families := [_, _ | _]}) -> "FamilyGrid".

separator(Index, Arity) when Index + 1 < Arity -> ",";
separator(_Index, _Arity) -> "".

channel_tuple([]) -> "()";
channel_tuple([Name]) -> ["(", Name, ",)"];
channel_tuple(Names) -> ["(", join_with(", ", Names), ")"].

uppercase(Atom) -> string:uppercase(atom_to_list(Atom)).

join_tokens([Token]) -> Token;
join_tokens([First, Second | Rest]) ->
    join_tokens([["join(", First, ", ", Second, ")"] | Rest]).

join_with(_Separator, []) -> [];
join_with(Separator, [First | Rest]) ->
    [First | [[Separator, Item] || Item <- Rest]].

index_by_id(Items) ->
    maps:from_list([{maps:get(id, Item), Item} || Item <- Items]).
