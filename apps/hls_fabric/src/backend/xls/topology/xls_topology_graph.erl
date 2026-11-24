%%%% Shared preparation of a resolved, instance-addressed topology graph.
-module(xls_topology_graph).
-moduledoc "Prepares instance-addressed wiring shared by dedicated topology rendering and fabric placement. A normalized profile and materialized logical graph become checked actor interfaces, startup frames and route lanes; the retained-interface entry point avoids source reacquisition. Rendering and scheduler policy belong to downstream consumers.".
%% Resolve a materialized graph with fresh or retained interfaces.
-export([lower/2, lower/3]).
%% Inspect and validate explicit physical producer lanes.
-export([lanes/1, check_lanes/3]).

%% Profile is normalized by the caller. Family rules have already been
%% expanded into exact actor IDs; public logical identities are retained by
%% the placement planner. This module owns wire-layout and startup checks.
-doc "Resolves a materialized graph using a normalized profile, validating public schemas and startup values against its ordinary-frame capacity.".
-spec lower(map(), xls_topology_profile:profile()) -> map().
lower(Plan = #{actors := Actors}, Profile) ->
    Layout = hls_frame_layout:new(maps:get(frame_payload_words, Profile)),
    Interfaces = hls_actor_interface:from_modules([M || #{module := M} <- Actors], Layout),
    lower(Plan, Profile, Interfaces).

-doc "Lowers a materialized graph with a retained physical catalog from hls_actor_interface:from_modules/2. The catalog must cover every actor, use the profile frame layout and project exactly to the core communication catalog; no interface or source is reloaded.".
-spec lower(map(), xls_topology_profile:profile(), #{module() => hls_actor_interface:summary()}) ->
    map().
lower(
    Plan = #{
        families := [],
        ingresses := [],
        route_relations := [],
        lane_relations := []
    },
    Profile,
    Interfaces
) ->
    #{
        name := Name,
        channel_depth := Depth,
        actor_egress_depth := EgressDepth,
        direct_actor_debug := ActorDebug,
        frame_payload_words := PayloadWords
    } =
        Profile,
    Layout = hls_frame_layout:new(PayloadWords),
    ProcessInterfaces = hls_logical_topology:interfaces(Plan),
    ok = validate_physical_interfaces(Plan, Layout, Interfaces),
    ok = validate_lanes(Plan),
    Actors = annotate_actors(
        maps:get(actors, Plan), EgressDepth, Layout, ProcessInterfaces, Interfaces
    ),
    Externals = annotate_externals(maps:get(externals, Plan)),
    ActorIndex = maps:from_list([{maps:get(id, Actor), Actor} || Actor <- Actors]),
    ok = validate_route_selectors(maps:get(routes, Plan), ActorIndex),
    ok = validate_startup_quiescence(maps:get(startup, Plan), ActorIndex),
    Routes = physical_route_order(Actors, maps:get(routes, Plan)),
    Startup = pack_startup(maps:get(startup, Plan), ActorIndex),
    #{
        name => Name,
        frame_layout => Layout,
        depth => Depth,
        direct_actor_debug => ActorDebug,
        actors => Actors,
        externals => Externals,
        routes => Routes,
        lanes => maps:get(lanes, Plan),
        startup => Startup
    }.

%% Reject a materialized plan whose cached exact lanes disagree with its routes.
-spec validate_lanes(map()) -> ok.
validate_lanes(Plan = #{routes := Routes}) ->
    check_lanes(lanes, Routes, Plan).

-doc "Checks one cached exact or family lane set against core derivation, retaining the established backend-specific error tag.".
-spec check_lanes(lanes | lane_relations, [map()], map()) -> ok.
check_lanes(Key, Routes, Plan) ->
    Expected = lanes(Routes),
    case maps:get(Key, Plan, '$missing') of
        Expected ->
            ok;
        Cached ->
            Error =
                case Key of
                    lanes -> inconsistent_dslx_plan_lanes;
                    lane_relations -> inconsistent_dslx_family_plan_lanes
                end,
            error({Error, Expected, Cached})
    end.

-doc "Delegates exact logical lane derivation to the core topology authority.".
-spec lanes([hls_logical_topology:route()]) -> [map()].
lanes(Routes) ->
    hls_logical_topology:lanes(Routes).

%% Retained summaries must have been checked for this physical frame capacity.
-spec annotate_actors(
    [map()],
    burst | non_neg_integer(),
    hls_frame_layout:layout(),
    hls_logical_topology:interface_catalog(),
    #{module() => hls_actor_interface:summary()}
) -> [map()].
annotate_actors(Actors, EgressDepth, Layout, ProcessInterfaces, Interfaces) ->
    [
        begin
            #{frame_layout := Layout} = maps:get(Module, Interfaces),
            annotate_actor(
                Index,
                Actor#{process_interface => maps:get(Module, ProcessInterfaces)},
                Interfaces,
                EgressDepth
            )
        end
     || {Index, Actor = #{module := Module}} <- lists:enumerate(0, Actors)
    ].

%% Rich physical summaries must project exactly to the plan's retained communication contracts.
-spec validate_physical_interfaces(
    hls_logical_topology:materialized_plan(),
    hls_frame_layout:layout(),
    #{module() => hls_actor_interface:summary()}
) -> ok.
validate_physical_interfaces(Plan, Layout, Interfaces) ->
    ok = hls_topology:validate_interfaces(Plan, Interfaces),
    maps:foreach(
        fun(Module, Interface) ->
            case maps:get(frame_layout, Interface) of
                Layout ->
                    ok;
                ActualLayout ->
                    error({physical_frame_layout_mismatch, Module, Layout, ActualLayout})
            end
        end,
        Interfaces
    ).

%% Attach physical interface, rendered names, dense index and selected egress capacity.
-spec annotate_actor(
    non_neg_integer(),
    map(),
    #{module() => hls_actor_interface:summary()},
    burst | non_neg_integer()
) -> map().
annotate_actor(Index, Actor, Interfaces, EgressDepth) ->
    Module = maps:get(module, Actor),
    ModuleName = xls_topology_profile:identifier(
        Module, {actor_module, maps:get(id, Actor)}
    ),
    Outputs = maps:get(outputs, Actor),
    lists:foreach(
        fun(Port) ->
            _ = xls_topology_profile:identifier(
                Port, {actor_output, maps:get(id, Actor)}
            )
        end,
        Outputs
    ),
    Actor#{
        index => Index,
        interface => maps:get(Module, Interfaces),
        module_name => ModuleName,
        stem => ["actor_", integer_to_list(Index)],
        egress_depth => xls_topology_profile:egress_depth(
            EgressDepth,
            maps:get(Module, Interfaces)
        )
    }.

%% Assign stable backend output names without changing logical external identities.
-spec annotate_externals([hls_logical_topology:external()]) -> [map()].
annotate_externals(Externals) ->
    [
        External#{
            output_name => [
                xls_topology_profile:identifier(
                    maps:get(id, External), external_id
                ),
                "_out"
            ]
        }
     || External <- Externals
    ].

%% Require every physical tag selector to preserve the core-validated logical route schemas.
-spec validate_route_selectors([hls_logical_topology:route()], map()) -> ok.
validate_route_selectors(Routes, ActorIndex) ->
    lists:foreach(
        fun(Route) ->
            Source = {SourceId, Port} = maps:get(source, Route),
            SourceActor = maps:get(SourceId, ActorIndex),
            SourceInterface = maps:get(interface, SourceActor),
            Schemas = hls_process_interface:output_schemas(
                maps:get(process_interface, SourceActor),
                Port
            ),
            lists:foreach(
                fun
                    ({actor, DestinationId} = Recipient) ->
                        DestinationActor = maps:get(
                            DestinationId,
                            ActorIndex
                        ),
                        DestinationInterface = maps:get(
                            interface,
                            DestinationActor
                        ),
                        lists:foreach(
                            fun(Schema) ->
                                validate_route_selector(
                                    Source,
                                    Recipient,
                                    Schema,
                                    SourceInterface,
                                    DestinationInterface
                                )
                            end,
                            Schemas
                        );
                    ({external, _ExternalId}) ->
                        ok
                end,
                maps:get(recipients, Route)
            )
        end,
        Routes
    ),
    validate_external_selectors(Routes, ActorIndex).

%% Check one actor-to-actor schema's backend-local selector without redefining its layout.
-spec validate_route_selector(
    term(),
    term(),
    atom(),
    hls_actor_interface:summary(),
    hls_actor_interface:summary()
) -> ok.
validate_route_selector(
    Source,
    Recipient,
    Schema,
    SourceInterface,
    DestinationInterface
) ->
    SourceSelector = maps:get(
        selector,
        hls_actor_interface:schema(SourceInterface, Schema)
    ),
    DestinationSelector = maps:get(
        selector,
        hls_actor_interface:schema(DestinationInterface, Schema)
    ),
    case SourceSelector =:= DestinationSelector of
        true ->
            ok;
        false ->
            error(
                {unsupported_dslx_route_tag_remap, Source, Recipient, Schema, SourceSelector,
                    DestinationSelector}
            )
    end.

%% Collect core schema layouts plus physical selectors for each external output.
-spec validate_external_selectors([hls_logical_topology:route()], map()) -> ok.
validate_external_selectors(Routes, ActorIndex) ->
    Bindings = lists:foldl(
        fun(Route, Acc0) ->
            {SourceId, Port} = Source = maps:get(source, Route),
            Interface = maps:get(
                interface,
                maps:get(SourceId, ActorIndex)
            ),
            ProcessInterface = maps:get(
                process_interface,
                maps:get(SourceId, ActorIndex)
            ),
            Schemas = hls_process_interface:output_schemas(ProcessInterface, Port),
            lists:foldl(
                fun
                    ({external, ExternalId}, Acc1) ->
                        New = [
                            #{
                                source => Source,
                                schema => Schema,
                                selector => maps:get(
                                    selector,
                                    hls_actor_interface:schema(
                                        Interface,
                                        Schema
                                    )
                                ),
                                fields => maps:get(
                                    fields,
                                    hls_process_interface:schema(ProcessInterface, Schema)
                                )
                            }
                         || Schema <- Schemas
                        ],
                        maps:update_with(
                            ExternalId,
                            fun(Old) -> New ++ Old end,
                            New,
                            Acc1
                        );
                    ({actor, _ActorId}, Acc1) ->
                        Acc1
                end,
                Acc0,
                maps:get(recipients, Route)
            )
        end,
        #{},
        Routes
    ),
    maps:foreach(fun validate_external_bindings/2, Bindings).

%% Reject schema or selector aliases whose producer encodings are not identical.
-spec validate_external_bindings(hls_logical_topology:id(), [map()]) -> ok.
validate_external_bindings(ExternalId, Bindings) ->
    _ = lists:foldl(
        fun(Binding, {BySchema0, BySelector0}) ->
            Schema = maps:get(schema, Binding),
            Selector = maps:get(selector, Binding),
            Fields = maps:get(fields, Binding),
            Encoding = {
                Selector,
                Fields,
                maps:get(source, Binding)
            },
            BySchema =
                case maps:find(Schema, BySchema0) of
                    error ->
                        BySchema0#{Schema => Encoding};
                    {ok, {Selector, Fields, _ExistingSource}} ->
                        BySchema0;
                    {ok, Existing} ->
                        error(
                            {incompatible_dslx_external_schema_encoding, ExternalId, Schema,
                                Existing, Encoding}
                        )
                end,
            BySelector =
                case maps:find(Selector, BySelector0) of
                    error ->
                        BySelector0#{Selector => Schema};
                    {ok, Schema} ->
                        BySelector0;
                    {ok, ExistingSchema} ->
                        error(
                            {ambiguous_dslx_external_selector, ExternalId, Selector, ExistingSchema,
                                Schema}
                        )
                end,
            {BySchema, BySelector}
        end,
        {#{}, #{}},
        Bindings
    ),
    ok.

%% Startup messages require actors whose physical initial phase emits no competing effects.
-spec validate_startup_quiescence([map()], map()) -> ok.
validate_startup_quiescence(Startup, ActorIndex) ->
    lists:foreach(
        fun(Item) ->
            Target = maps:get(target, Item),
            Actor = maps:get(Target, ActorIndex),
            Interface = maps:get(interface, Actor),
            case hls_actor_interface:initial_effects(Interface) of
                [] ->
                    ok;
                Effects ->
                    error(
                        {startup_target_has_initial_effects, Target, maps:get(module, Actor),
                            Effects}
                    )
            end
        end,
        Startup
    ).

%% Order routes by dense actor order and each actor's declared output ABI.
-spec physical_route_order([map()], [hls_logical_topology:route()]) ->
    [hls_logical_topology:route()].
physical_route_order(Actors, Routes) ->
    RouteIndex = maps:from_list([{maps:get(source, Route), Route} || Route <- Routes]),
    Ordered = lists:append([
        [
            maps:get({maps:get(id, Actor), Port}, RouteIndex)
         || Port <- maps:get(outputs, Actor)
        ]
     || Actor <- Actors
    ]),
    Ordered.

%% Add physical frames while retaining the logical startup messages and order.
-spec pack_startup([map()], map()) -> [map()].
pack_startup(Startup, ActorIndex) ->
    [
        Item#{frames => pack_startup_messages(Target, Messages, ActorIndex)}
     || Item = #{target := Target, messages := Messages} <- Startup
    ].

%% Bind every startup pack to the destination actor's selected frame layout.
-spec pack_startup_messages(term(), [term()], map()) -> [map()].
pack_startup_messages(Target, Messages, ActorIndex) ->
    Actor = maps:get(Target, ActorIndex),
    Module = maps:get(module, Actor),
    Layout = maps:get(frame_layout, maps:get(interface, Actor)),
    [
        pack_startup_message(Target, Index, Module, Message, Layout)
     || {Index, Message} <- lists:enumerate(0, Messages)
    ].

%% Validate provider-packed startup values before emitting a fixed-capacity axis frame.
-spec pack_startup_message(term(), non_neg_integer(), module(), term(), hls_frame_layout:layout()) ->
    map().
pack_startup_message(Target, Index, Module, Message, Layout) when
    is_tuple(Message),
    tuple_size(Message) > 0,
    is_atom(element(1, Message))
->
    TagName = element(1, Message),
    Packed =
        try {Module:pack_tag(TagName), Module:pack(Message)} of
            Result -> Result
        catch
            Class:Reason ->
                error({cannot_pack_startup_message, Target, Index, Class, Reason})
        end,
    {Tag, Payload} =
        case Packed of
            {PackedTag, PackedPayload} when
                is_integer(PackedTag),
                PackedTag >= 0,
                PackedTag =< 255,
                is_bitstring(PackedPayload)
            ->
                {PackedTag, hls_codec:align(PackedPayload, 32)};
            {InvalidTag, InvalidPayload} ->
                error({invalid_packed_startup_message, Target, Index, InvalidTag, InvalidPayload})
        end,
    Width = bit_size(Payload),
    case
        Width > 0 andalso Width rem 32 =:= 0 andalso
            Width =< hls_frame_layout:payload_bits(Layout)
    of
        true ->
            #{
                tag => Tag,
                payload => xls_nums:packed_unsigned_literal(Payload)
            };
        false ->
            error({unsupported_startup_payload_width, Target, Index, Width})
    end;
pack_startup_message(Target, Index, _Module, Message, _Layout) ->
    error({invalid_startup_message, Target, Index, Message}).
