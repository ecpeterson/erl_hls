%%%% xls_topology_dslx
%%%%
%%%% Lowers the first closed normalized topology into one DSLX proc graph.

-module(xls_topology_dslx).
-moduledoc """
Generates the deliberately small, closed DSLX topology backend.

The input is a normalized `hls_topology` plan plus a physical profile. This
backend uses complete `axis::Frame` channels, depth-N channel buffers, binary
`axis::FrameMux2` ingress trees, and one `axis::ReservedFrame` admission
boundary per actor. Startup records are packed by their destination actor's
generated Erlang packer, so the topology does not repeat record layouts or
numeric tags.

This is intentionally an executable application fixture, not a general
semantics-preserving topology backend. Logical route schemas and layouts are
checked from emitted actor summaries. Direct Frame transport additionally
requires each routed schema to have the same local selector at both actors;
selector remapping remains a later backend feature. Each generated actor has
one source-ordered typed egress. The topology router maps it into one queue per
logical source/recipient lane, so messages sent through aliased ports cannot be
re-arbitrated before that recipient.

The backend implements only `queued` multi-recipient delivery: the actor event
completes when its one common egress channel accepts the frame, after which a
lossless distributor waits for every bounded branch channel. Startup is not an
ordinary competing ingress. A per-destination prefix emits all startup frames
in list order before it performs its first routed-input receive.

Startup quiescence is checked from the statically known initial phase and its
source-ordered entry effects. Actor callbacks are not executed by topology
generation. Regular-family plans are delegated to the narrower channel-array
backend in `xls_topology_family_dslx`.
""".

-export([emit/2, from_module/2]).
-export_type([profile/0]).

-define(U32_MAX, 16#ffffffff).

-type profile() :: map().

-define(MAX_PAYLOAD_BITS, 96).

-doc "Loads and normalizes `TopologyModule`, then emits its DSLX graph.".
-spec from_module(module(), profile()) -> iolist().
from_module(TopologyModule, Profile) when is_atom(TopologyModule) ->
    emit(hls_topology:from_module(TopologyModule), Profile).

-doc "Emits deterministic DSLX from one normalized plan and physical profile.".
-spec emit(hls_topology:plan(), profile()) -> iolist().
emit(#{actors := [_ | _], families := [_ | _]}, _Profile) ->
    error(mixed_topology);
emit(Plan = #{families := []}, Profile) ->
    render(lower(Plan, Profile));
emit(Plan = #{actors := [], families := [_ | _]}, Profile) ->
    xls_topology_family_dslx:emit(Plan, Profile);
emit(Plan, _Profile) ->
    error({invalid_topology_plan, Plan}).

%%%
%%% Backend lowering and validation
%%%

lower(Plan = #{
        families := [],
        ingresses := [],
        route_relations := [],
        lane_relations := []
    }, Profile) ->
    Actors = annotate_actors(maps:get(actors, Plan)),
    Externals = annotate_externals(maps:get(externals, Plan)),
    ActorIndex = maps:from_list([
        {maps:get(id, Actor), Actor} || Actor <- Actors
    ]),
    Physical = validate_profile(Profile, Plan),
    ok = validate_route_selectors(maps:get(routes, Plan), ActorIndex),
    ok = validate_startup_quiescence(maps:get(startup, Plan), ActorIndex),
    Routes = physical_route_order(Actors, maps:get(routes, Plan)),
    Lanes = annotate_lanes(
        maps:get(lanes, Plan),
        Actors,
        Externals
    ),
    Startup = pack_startup(maps:get(startup, Plan), ActorIndex),
    #{
        name => maps:get(name, Physical),
        depth => maps:get(channel_depth, Physical),
        actors => Actors,
        externals => Externals,
        routes => Routes,
        lanes => Lanes,
        startup => Startup
    }.

validate_profile(Profile, Plan) when is_map(Profile) ->
    Required = lists:sort([channel_depth, name]),
    Keys = lists:sort(maps:keys(Profile)),
    case {Required -- Keys, Keys -- Required} of
        {[], []} -> ok;
        {Missing, Unknown} ->
            error({invalid_dslx_profile_keys, Missing, Unknown})
    end,
    Name = identifier(maps:get(name, Profile), topology_name),
    case maps:get(channel_depth, Profile) of
        Depth when is_integer(Depth), Depth > 0, Depth =< ?U32_MAX -> ok;
        Depth -> error({invalid_dslx_channel_depth, Depth})
    end,
    RealizedLanes = derive_realized_lanes(maps:get(routes, Plan)),
    case maps:get(lanes, Plan, '$missing') of
        RealizedLanes -> ok;
        CachedLanes -> error({inconsistent_dslx_plan_lanes,
            RealizedLanes, CachedLanes})
    end,
    Profile#{name := Name};
validate_profile(Profile, _Plan) ->
    error({invalid_dslx_profile, Profile}).

derive_realized_lanes(Routes) ->
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


annotate_actors(Actors) ->
    Interfaces = maps:from_list([
        {Module, hls_actor_interface:from_module(Module)}
        || Module <- lists:usort([
            maps:get(module, Actor) || Actor <- Actors
        ])
    ]),
    [annotate_actor(Index, Actor, Interfaces)
        || {Index, Actor} <- lists:enumerate(0, Actors)].

annotate_actor(Index, Actor, Interfaces) ->
    Module = maps:get(module, Actor),
    ModuleName = identifier(Module, {actor_module, maps:get(id, Actor)}),
    Outputs = maps:get(outputs, Actor),
    lists:foreach(
        fun(Port) ->
            _ = identifier(Port, {actor_output, maps:get(id, Actor)})
        end,
        Outputs
    ),
    Actor#{
        index => Index,
        interface => maps:get(Module, Interfaces),
        module_name => ModuleName,
        stem => ["actor_", integer_to_list(Index)],
        egress_channel => ["actor_", integer_to_list(Index), "_egress"],
        egress_depth => max(1, hls_actor_interface:max_entry_effects(
            maps:get(Module, Interfaces)
        ))
    }.

annotate_externals(Externals) ->
    [
        External#{
            index => Index,
            output_name => [identifier(
                maps:get(id, External),
                external_id
            ), "_out"],
            stem => ["external_", integer_to_list(Index)]
        }
        || {Index, External} <- lists:enumerate(0, Externals)
    ].

annotate_lanes(Lanes, Actors, Externals) ->
    ActorIndex = maps:from_list([
        {maps:get(id, Actor), Actor} || Actor <- Actors
    ]),
    ExternalIndex = maps:from_list([
        {maps:get(id, External), External} || External <- Externals
    ]),
    [
        begin
            Source = maps:get(source, Lane),
            SourceActor = maps:get(Source, ActorIndex),
            Destination = maps:get(destination, Lane),
            Lane#{
                index => Index,
                destination_key => recipient_key(
                    Destination,
                    ActorIndex,
                    ExternalIndex
                ),
                channel => ["actor_",
                    integer_to_list(maps:get(index, SourceActor)),
                    "_lane_", integer_to_list(Index)]
            }
        end
        || {Index, Lane} <- lists:enumerate(0, Lanes)
    ].

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
    [
        begin
            Target = maps:get(target, Item),
            Actor = maps:get(Target, ActorIndex),
            Item#{
                index => Index,
                target_index => maps:get(index, Actor),
                frames => pack_startup_messages(
                    Target,
                    maps:get(messages, Item),
                    ActorIndex
                ),
                channel => ["startup_", integer_to_list(Index)]
            }
        end
        || {Index, Item} <- lists:enumerate(0, Startup)
    ].

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
                     PackedTag =< 255, is_binary(PackedPayload) ->
            {PackedTag, PackedPayload};
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
%%% Physical graph construction
%%%

render(Spec) ->
    Actors = maps:get(actors, Spec),
    Externals = maps:get(externals, Spec),
    Depth = maps:get(depth, Spec),
    RouteGraph = route_graph(
        maps:get(routes, Spec),
        maps:get(lanes, Spec),
        Actors,
        Depth
    ),
    {IngressCode, FinalGraph} = ingress_graph(
        Actors,
        Externals,
        maps:get(startup, Spec),
        RouteGraph,
        Depth
    ),
    [
        preamble(Spec, FinalGraph),
        relay_proc(Externals),
        actor_router_procs(
            Actors,
            maps:get(routes, FinalGraph),
            maps:get(lanes, Spec)
        ),
        startup_procs(maps:get(startup, Spec)),
        top_proc(
            Actors,
            Externals,
            Depth,
            maps:get(route_code, FinalGraph),
            IngressCode
        )
    ].

route_graph(Routes, Lanes, Actors, Depth) ->
    lists:foreach(fun validate_route_delivery/1, Routes),
    LaneIndex = maps:from_list([
        {{maps:get(source, Lane), maps:get(destination, Lane)}, Lane}
        || Lane <- Lanes
    ]),
    Routed = [
        Route#{lanes => [
            maps:get({SourceId, Recipient}, LaneIndex)
            || Recipient <- maps:get(recipients, Route)
        ]}
        || Route <- Routes,
           {SourceId, _Port} <- [maps:get(source, Route)]
    ],
    Leaves = lists:foldl(
        fun(Lane, Acc) ->
            maps:update_with(
                maps:get(destination_key, Lane),
                fun(Existing) -> Existing ++ [consumer(
                    maps:get(channel, Lane)
                )] end,
                [consumer(maps:get(channel, Lane))],
                Acc
            )
        end,
        #{},
        Lanes
    ),
    RouteCode = [
        [frame_channel(maps:get(channel, Lane), Depth) || Lane <- Lanes],
        [actor_router_spawn(Actor, Lanes) || Actor <- Actors]
    ],
    #{
        leaves => Leaves,
        route_code => RouteCode,
        routes => Routed
    }.

validate_route_delivery(Route) ->
    Recipients = maps:get(recipients, Route),
    case {maps:get(delivery, Route), Recipients} of
        {direct, [_]} -> ok;
        {queued, [_, _ | _]} -> ok;
        {Delivery, _} ->
            error({unsupported_dslx_route_delivery,
                maps:get(source, Route), Delivery, length(Recipients)})
    end.

recipient_key({actor, Id}, ActorIndex, _ExternalIndex) ->
    {actor, maps:get(index, maps:get(Id, ActorIndex))};
recipient_key({external, Id}, _ActorIndex, ExternalIndex) ->
    {external, maps:get(index, maps:get(Id, ExternalIndex))}.

ingress_graph(Actors, Externals, Startup, Graph0, Depth) ->
    StartupIndex = maps:from_list([
        {maps:get(target_index, Item), Item} || Item <- Startup
    ]),
    {ActorCode, Graph1} = lists:mapfoldl(
        fun(Actor, Graph) ->
            actor_ingress(
                Actor,
                maps:get(maps:get(index, Actor), StartupIndex, none),
                Depth,
                Graph
            )
        end,
        Graph0,
        Actors
    ),
    {ExternalCode, Graph2} = lists:mapfoldl(
        fun(External, Graph) -> external_egress(External, Depth, Graph) end,
        Graph1,
        Externals
    ),
    {[ActorCode, ExternalCode], Graph2}.

actor_ingress(Actor, Startup, Depth, Graph) ->
    Index = maps:get(index, Actor),
    Key = {actor, Index},
    Leaves = maps:get(Key, maps:get(leaves, Graph), []),
    case {Leaves, Startup} of
        {[], none} ->
            error({unconnected_dslx_destination, maps:get(id, Actor)});
        {[], _} ->
            error({unsupported_dslx_startup_only_actor, maps:get(id, Actor)});
        _ -> ok
    end,
    {RouteRoot, MuxCode} = mux_tree(
        ["actor_", integer_to_list(Index), "_ingress"],
        Leaves,
        Depth
    ),
    {Root, PrefixCode} = startup_prefix(Startup, RouteRoot, Depth),
    Stem = maps:get(stem, Actor),
    Code = [
        MuxCode,
        PrefixCode,
        "    spawn axis::ReservedFrame(", Root, ", ",
        producer([Stem, "_req"]), ", ",
        consumer([Stem, "_admit"]), ");\n"
    ],
    {Code, Graph}.

startup_prefix(none, RouteRoot, _Depth) -> {RouteRoot, []};
startup_prefix(Item, RouteRoot, Depth) ->
    Index = maps:get(index, Item),
    Channel = ["startup_", integer_to_list(Index), "_prefix"],
    Code = [
        frame_channel(Channel, Depth),
        "    spawn StartupPrefix", integer_to_list(Index),
        "(", RouteRoot, ", ", producer(Channel), ");\n"
    ],
    {consumer(Channel), Code}.

external_egress(External, Depth, Graph) ->
    Index = maps:get(index, External),
    Key = {external, Index},
    Leaves = destination_leaves(Key, maps:get(id, External), Graph),
    {Root, MuxCode} = mux_tree(
        ["external_", integer_to_list(Index), "_egress"],
        Leaves,
        Depth
    ),
    Code = [
        MuxCode,
        "    spawn FrameRelay(", Root, ", ",
        maps:get(output_name, External), ");\n"
    ],
    {Code, Graph}.

destination_leaves(Key, Id, Graph) ->
    case maps:get(Key, maps:get(leaves, Graph), []) of
        [] -> error({unconnected_dslx_destination, Id});
        Leaves -> Leaves
    end.

mux_tree(_Stem, [Root], _Depth) -> {Root, []};
mux_tree(Stem, Leaves, Depth) -> mux_tree(Stem, Leaves, Depth, 0, []).

mux_tree(_Stem, [Root], _Depth, _Level, Code) -> {Root, Code};
mux_tree(Stem, Leaves, Depth, Level, Code0) ->
    {Next, RoundCode} = mux_round(Stem, Leaves, Depth, Level, 0, [], []),
    mux_tree(Stem, Next, Depth, Level + 1, Code0 ++ RoundCode).

mux_round(_Stem, [], _Depth, _Level, _Pair, Next, Code) ->
    {lists:reverse(Next), Code};
mux_round(_Stem, [Last], _Depth, _Level, _Pair, Next, Code) ->
    {lists:reverse([Last | Next]), Code};
mux_round(Stem, [Left, Right | Rest], Depth, Level, Pair, Next, Code0) ->
    Channel = [
        Stem, "_mux_", integer_to_list(Level), "_", integer_to_list(Pair)
    ],
    Code = Code0 ++ [
        frame_channel(Channel, Depth),
        "    spawn axis::FrameMux2(", Left, ", ", Right, ", ",
        producer(Channel), ");\n"
    ],
    mux_round(
        Stem,
        Rest,
        Depth,
        Level,
        Pair + 1,
        [consumer(Channel) | Next],
        Code
    ).

%%%
%%% DSLX rendering
%%%

preamble(Spec, Graph) ->
    Modules = lists:usort([
        maps:get(module_name, Actor) || Actor <- maps:get(actors, Spec)
    ]),
    AliasCount = length([
        Lane
        || Lane <- maps:get(lanes, Spec),
           length(maps:get(source_ports, Lane)) > 1
    ]),
    FanoutCount = length([
        Route
        || Route <- maps:get(routes, Graph),
           maps:get(delivery, Route) =:= queued
    ]),
    StartupCount = length(maps:get(startup, Spec)),
    [
        "// ", maps:get(name, Spec), ".x\n",
        "// Auto-generated by xls_topology_dslx from normalized Erlang data.\n",
        "// Manual changes will be overwritten.\n",
        "//\n",
        "// Actor summaries validate route schemas and actor-to-actor layouts.\n",
        "// Direct Frame edges also require matching local selectors; tag ",
        "remapping\n",
        "// is not implemented. External producers must agree on one encoding.\n",
        "// One typed actor egress feeds one queue per source/recipient lane; ",
        "the ",
        integer_to_list(AliasCount), "\n",
        "// lane(s) reached through multiple source ports retain actor action ",
        "order.\n",
        "// ", integer_to_list(StartupCount), " startup prefix(es) emit all ",
        "target startup frames before\n",
        "// receiving that target's first routed frame.\n\n",
        "import axis;\n",
        [["import ", Module, ";\n"] || Module <- Modules],
        "\n",
        "const CHANNEL_DEPTH = u32:", integer_to_list(maps:get(depth, Spec)),
        ";\n\n",
        case FanoutCount of
            0 -> [];
            _ -> [
                "// ", integer_to_list(FanoutCount),
                " queued fanout route(s) complete at actor-egress acceptance;\n",
                "// their source router subsequently waits for every lane ",
                "queue.\n\n"
            ]
        end
    ].

relay_proc([]) -> [];
relay_proc(_Externals) ->
    ["""
    proc FrameRelay {
      frame_in: chan<axis::Frame> in;
      frame_out: chan<axis::Frame> out;

      config(frame_in: chan<axis::Frame> in,
             frame_out: chan<axis::Frame> out) {
        (frame_in, frame_out)
      }

      init { () }

      next(state: ()) {
        let (tok, frame) = recv(join(), frame_in);
        send(tok, frame_out, frame);
        state
      }
    }

    """, "\n"].

actor_router_procs(Actors, Routes, Lanes) ->
    [
        actor_router_proc(
            Actor,
            [Route || Route <- Routes,
                element(1, maps:get(source, Route)) =:= maps:get(id, Actor)],
            [Lane || Lane <- Lanes,
                maps:get(source, Lane) =:= maps:get(id, Actor)]
        )
        || Actor <- Actors
    ].

actor_router_proc(Actor, Routes, Lanes) ->
    Module = maps:get(module_name, Actor),
    Count = length(Lanes),
    [
        "proc ActorRouter", integer_to_list(maps:get(index, Actor)), " {\n",
        "  egress_in: chan<", Module, "::Egress> in;\n",
        [["  ", lane_output(Lane),
            ": chan<axis::Frame> out;\n"] || Lane <- Lanes],
        "\n  config(egress_in: chan<", Module, "::Egress> in,\n",
        [["         ", lane_output(Lane),
            ": chan<axis::Frame> out",
            separator(Index, Count), "\n"]
            || {Index, Lane} <- lists:enumerate(0, Lanes)],
        "  ) {\n    (egress_in",
        [[", ", lane_output(Lane)] || Lane <- Lanes],
        ")\n  }\n\n",
        "  init { () }\n\n",
        "  next(state: ()) {\n",
        "    let (tok, egress) = recv(join(), egress_in);\n",
        "    let _route_tok = match egress.port {\n",
        [actor_router_arm(Module, Route) || Route <- Routes],
        "    };\n",
        "    state\n  }\n}\n\n"
    ].

actor_router_arm(Module, Route) ->
    {_Source, Port} = maps:get(source, Route),
    Lanes = maps:get(lanes, Route),
    Tokens = [["lane_", integer_to_list(maps:get(index, Lane)), "_tok"]
        || Lane <- Lanes],
    Body = case Lanes of
        [Lane] -> [
            "send(tok, ", lane_output(Lane), ", egress.frame)"
        ];
        [_, _ | _] -> [
            "{\n",
            [
                ["        let ", Token, " = send(tok, ",
                    lane_output(Lane), ", egress.frame);\n"]
                || {Token, Lane} <- lists:zip(Tokens, Lanes)
            ],
            "        ", join_tokens(Tokens), "\n",
            "      }"
        ]
    end,
    [
        "      ", Module, "::OutputPort::", uppercase(Port), " =>\n",
        "        ", Body, ",\n"
    ].

actor_router_spawn(Actor, Lanes) ->
    ActorLanes = [Lane || Lane <- Lanes,
        maps:get(source, Lane) =:= maps:get(id, Actor)],
    [
        "    spawn ActorRouter", integer_to_list(maps:get(index, Actor)),
        "(", consumer(maps:get(egress_channel, Actor)),
        [[", ", producer(maps:get(channel, Lane))] || Lane <- ActorLanes],
        ");\n"
    ].

lane_output(Lane) -> [maps:get(channel, Lane), "_out"].

separator(Index, Arity) when Index + 1 < Arity -> ",";
separator(_Index, _Arity) -> "".

startup_procs(Startup) -> [startup_proc(Item) || Item <- Startup].

startup_proc(Item) ->
    Index = maps:get(index, Item),
    Frames = maps:get(frames, Item),
    Count = length(Frames),
    [
        "proc StartupPrefix", integer_to_list(Index), " {\n",
        "  routed_in: chan<axis::Frame> in;\n",
        "  frame_out: chan<axis::Frame> out;\n\n",
        "  config(routed_in: chan<axis::Frame> in,\n",
        "         frame_out: chan<axis::Frame> out) {\n",
        "    (routed_in, frame_out)\n",
        "  }\n\n",
        "  init { u32:0 }\n\n",
        "  next(index: u32) {\n",
        "    let starting = index < u32:", integer_to_list(Count), ";\n",
        "    let startup_frame = match index {\n",
        [startup_arm(FrameIndex, Frame)
            || {FrameIndex, Frame} <- lists:enumerate(0, Frames)],
        "      _ => zero!<axis::Frame>(),\n",
        "    };\n",
        "    let (tok, routed_frame) = recv_if(\n",
        "      join(), routed_in, !starting, zero!<axis::Frame>());\n",
        "    let frame = if starting { startup_frame } else { routed_frame };\n",
        "    send(tok, frame_out, frame);\n",
        "    if starting { index + u32:1 } else { index }\n",
        "  }\n}\n\n"
    ].

startup_arm(Index, Frame) ->
    [
        "      u32:", integer_to_list(Index), " => axis::pack(u8:",
        integer_to_list(maps:get(tag, Frame)), ", ",
        maps:get(payload, Frame), "),\n"
    ].

top_proc(Actors, Externals, Depth, RouteCode, IngressCode) ->
    [
        "pub proc Top {\n",
        [["  ", maps:get(output_name, External),
            ": chan<axis::Frame> out;\n"] || External <- Externals],
        "\n",
        top_config_signature(Externals),
        actor_channels(Actors, Depth),
        actor_spawns(Actors),
        RouteCode,
        IngressCode,
        "\n    ", external_tuple(Externals), "\n",
        "  }\n\n",
        "  init { () }\n",
        "  next(state: ()) { state }\n",
        "}\n"
    ].

top_config_signature([]) -> "  config() {\n";
top_config_signature(Externals) ->
    [
        "  config(\n",
        [
            ["      ", maps:get(output_name, External),
                ": chan<axis::Frame> out",
                separator(Index, length(Externals)), "\n"]
            || {Index, External} <- lists:enumerate(0, Externals)
        ],
        "  ) {\n"
    ].

actor_channels(Actors, Depth) ->
    [
        [
            "    // Actor ", io_lib:format("~p", [maps:get(id, Actor)]),
            " uses ", maps:get(module_name, Actor),
            " output ABI order ",
            io_lib:format("~p", [maps:get(outputs, Actor)]), ".\n",
            frame_channel([maps:get(stem, Actor), "_req"], Depth),
            admission_channel([maps:get(stem, Actor), "_admit"], Depth),
            egress_channel(Actor, Depth)
        ]
        || Actor <- Actors
    ].

actor_spawns(Actors) ->
    [
        [
            "    spawn ", maps:get(module_name, Actor), "::Service(\n",
            "      ", consumer([maps:get(stem, Actor), "_req"]),
            ",\n      ", producer(maps:get(egress_channel, Actor)),
            ",\n      ", producer([maps:get(stem, Actor), "_admit"]),
            ");\n"
        ]
        || Actor <- Actors
    ].

external_tuple([]) -> "()";
external_tuple([External]) -> ["(", maps:get(output_name, External), ",)"];
external_tuple(Externals) ->
    ["(", join_with(", ", [maps:get(output_name, External)
        || External <- Externals]), ")"].

frame_channel(Channel, _Depth) ->
    [
        "    let (", producer(Channel), ", ", consumer(Channel),
        ") = chan<axis::Frame, CHANNEL_DEPTH>(\"", Channel, "\");\n"
    ].

admission_channel(Channel, _Depth) ->
    [
        "    let (", producer(Channel), ", ", consumer(Channel),
        ") = chan<u1, CHANNEL_DEPTH>(\"", Channel, "\");\n"
    ].

egress_channel(Actor, _Depth) ->
    Channel = maps:get(egress_channel, Actor),
    [
        "    let (", producer(Channel), ", ", consumer(Channel),
        ") = chan<", maps:get(module_name, Actor),
        "::Egress, u32:", integer_to_list(maps:get(egress_depth, Actor)),
        ">(\"", Channel, "\");\n"
    ].

producer(Channel) -> [Channel, "_p"].
consumer(Channel) -> [Channel, "_c"].

uppercase(Atom) -> string:uppercase(atom_to_list(Atom)).

join_tokens([Token]) -> Token;
join_tokens([First, Second | Rest]) ->
    join_tokens([["join(", First, ", ", Second, ")"] | Rest]).

join_with(_Separator, []) -> [];
join_with(Separator, [First | Rest]) ->
    [First | [[Separator, Item] || Item <- Rest]].
