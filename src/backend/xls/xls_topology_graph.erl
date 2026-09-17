%%%% Shared preparation of a resolved, instance-addressed topology graph.
-module(xls_topology_graph).
-moduledoc false.
-export([lower/2, lanes/1, check_lanes/3]).

-define(MAX_PAYLOAD_BITS, 96).

%% Profile is normalized by the caller. Family rules have already been
%% expanded into exact actor IDs; public logical identities are retained by
%% the placement planner. This module owns wire-layout and startup checks.
lower(Plan = #{
        families := [],
        ingresses := [],
        route_relations := [],
        lane_relations := []
    }, Profile) ->
    #{name := Name, channel_depth := Depth,
        actor_egress_depth := EgressDepth, direct_actor_debug := ActorDebug} =
        Profile,
    ok = validate_lanes(Plan),
    Actors = annotate_actors(maps:get(actors, Plan), EgressDepth),
    Externals = annotate_externals(maps:get(externals, Plan)),
    ActorIndex = maps:from_list([
        {maps:get(id, Actor), Actor} || Actor <- Actors
    ]),
    ok = validate_route_selectors(maps:get(routes, Plan), ActorIndex),
    ok = validate_startup_quiescence(maps:get(startup, Plan), ActorIndex),
    Routes = physical_route_order(Actors, maps:get(routes, Plan)),
    Startup = pack_startup(maps:get(startup, Plan), ActorIndex),
    #{
        name => Name,
        depth => Depth,
        direct_actor_debug => ActorDebug,
        actors => Actors,
        externals => Externals,
        routes => Routes,
        lanes => maps:get(lanes, Plan),
        startup => Startup
    }.

validate_lanes(Plan = #{routes := Routes}) ->
    check_lanes(lanes, Routes, Plan).

%% Exact routes and family relations have the same source/recipient incidence
%% shape once their normalizer has canonicalized wrapped translations.
check_lanes(Key, Routes, Plan) ->
    Expected = lanes(Routes),
    case maps:get(Key, Plan, '$missing') of
        Expected -> ok;
        Cached ->
            Error = case Key of
                lanes -> inconsistent_dslx_plan_lanes;
                lane_relations -> inconsistent_dslx_family_plan_lanes
            end,
            error({Error, Expected, Cached})
    end.

lanes(Routes) ->
    LanePorts = lists:foldl(
        fun(Route, Acc0) ->
            {SourceActor, Port} = maps:get(source, Route),
            lists:foldl(
                fun(Recipient, Acc) ->
                    Key = {SourceActor, Recipient},
                    maps:update_with(
                        Key,
                        fun(Ports) -> [Port | Ports] end,
                        [Port],
                        Acc
                    )
                end,
                Acc0,
                maps:get(recipients, Route)
            )
        end,
        #{},
        Routes
    ),
    [
        #{
            source => Source,
            destination => Destination,
            source_ports => lists:sort(Ports)
        }
        || {{Source, Destination}, Ports} <-
               lists:sort(maps:to_list(LanePorts))
    ].


annotate_actors(Actors, EgressDepth) ->
    Interfaces = hls_actor_interface:from_modules(
        [Module || #{module := Module} <- Actors]),
    [annotate_actor(Index, Actor, Interfaces, EgressDepth)
        || {Index, Actor} <- lists:enumerate(0, Actors)].

annotate_actor(Index, Actor, Interfaces, EgressDepth) ->
    Module = maps:get(module, Actor),
    ModuleName = xls_topology_profile:identifier(
        Module, {actor_module, maps:get(id, Actor)}),
    Outputs = maps:get(outputs, Actor),
    lists:foreach(
        fun(Port) ->
            _ = xls_topology_profile:identifier(
                Port, {actor_output, maps:get(id, Actor)})
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

annotate_externals(Externals) ->
    [External#{output_name => [xls_topology_profile:identifier(
        maps:get(id, External), external_id), "_out"]} || External <- Externals].

validate_route_selectors(Routes, ActorIndex) ->
    lists:foreach(
        fun(Route) ->
            Source = {SourceId, Port} = maps:get(source, Route),
            SourceActor = maps:get(SourceId, ActorIndex),
            SourceInterface = maps:get(interface, SourceActor),
            Schemas = hls_actor_interface:output_schemas(
                SourceInterface,
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

validate_route_selector(Source, Recipient, Schema,
        SourceInterface, DestinationInterface) ->
    SourceSelector = maps:get(
        selector,
        hls_actor_interface:schema(SourceInterface, Schema)
    ),
    DestinationSelector = maps:get(
        selector,
        hls_actor_interface:schema(DestinationInterface, Schema)
    ),
    case SourceSelector =:= DestinationSelector of
        true -> ok;
        false -> error({unsupported_dslx_route_tag_remap,
            Source, Recipient, Schema,
            SourceSelector, DestinationSelector})
    end.

validate_external_selectors(Routes, ActorIndex) ->
    Bindings = lists:foldl(
        fun(Route, Acc0) ->
            {SourceId, Port} = Source = maps:get(source, Route),
            Interface = maps:get(
                interface,
                maps:get(SourceId, ActorIndex)
            ),
            Schemas = hls_actor_interface:output_schemas(Interface, Port),
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
                                    hls_actor_interface:schema(
                                        Interface,
                                        Schema
                                    )
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
            BySchema = case maps:find(Schema, BySchema0) of
                error -> BySchema0#{Schema => Encoding};
                {ok, {Selector, Fields, _ExistingSource}} ->
                    BySchema0;
                {ok, Existing} ->
                    error({incompatible_dslx_external_schema_encoding,
                        ExternalId, Schema, Existing, Encoding})
            end,
            BySelector = case maps:find(Selector, BySelector0) of
                error -> BySelector0#{Selector => Schema};
                {ok, Schema} -> BySelector0;
                {ok, ExistingSchema} ->
                    error({ambiguous_dslx_external_selector,
                        ExternalId, Selector, ExistingSchema, Schema})
            end,
            {BySchema, BySelector}
        end,
        {#{}, #{}},
        Bindings
    ),
    ok.

validate_startup_quiescence(Startup, ActorIndex) ->
    lists:foreach(
        fun(Item) ->
            Target = maps:get(target, Item),
            Actor = maps:get(Target, ActorIndex),
            Interface = maps:get(interface, Actor),
            case hls_actor_interface:initial_effects(Interface) of
                [] -> ok;
                Effects -> error({startup_target_has_initial_effects,
                    Target, maps:get(module, Actor), Effects})
            end
        end,
        Startup
    ).

physical_route_order(Actors, Routes) ->
    RouteIndex = maps:from_list([
        {maps:get(source, Route), Route} || Route <- Routes
    ]),
    Ordered = lists:append([
        [maps:get({maps:get(id, Actor), Port}, RouteIndex)
            || Port <- maps:get(outputs, Actor)]
        || Actor <- Actors
    ]),
    Ordered.

pack_startup(Startup, ActorIndex) ->
    [Item#{frames => pack_startup_messages(Target, Messages, ActorIndex)}
        || Item = #{target := Target, messages := Messages} <- Startup].

pack_startup_messages(Target, Messages, ActorIndex) ->
    Actor = maps:get(Target, ActorIndex),
    Module = maps:get(module, Actor),
    [pack_startup_message(Target, Index, Module, Message)
        || {Index, Message} <- lists:enumerate(0, Messages)].

pack_startup_message(Target, Index, Module, Message)
        when is_tuple(Message), tuple_size(Message) > 0,
             is_atom(element(1, Message)) ->
    TagName = element(1, Message),
    Packed = try {Module:pack_tag(TagName), Module:pack(Message)} of
        Result -> Result
    catch
        Class:Reason ->
            error({cannot_pack_startup_message,
                Target, Index, Class, Reason})
    end,
    {Tag, Payload} = case Packed of
        {PackedTag, PackedPayload}
                when is_integer(PackedTag), PackedTag >= 0,
                     PackedTag =< 255, is_bitstring(PackedPayload) ->
            {PackedTag, hls_codec:align(PackedPayload, 32)};
        {InvalidTag, InvalidPayload} ->
            error({invalid_packed_startup_message,
                Target, Index, InvalidTag, InvalidPayload})
    end,
    Width = bit_size(Payload),
    case Width > 0 andalso Width rem 32 =:= 0 andalso
            Width =< ?MAX_PAYLOAD_BITS of
        true -> #{
            tag => Tag,
            payload => xls_nums:packed_unsigned_literal(Payload)
        };
        false -> error({unsupported_startup_payload_width,
            Target, Index, Width})
    end;
pack_startup_message(Target, Index, _Module, Message) ->
    error({invalid_startup_message, Target, Index, Message}).

