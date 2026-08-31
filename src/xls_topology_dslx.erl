%%%% xls_topology_dslx
%%%%
%%%% Lowers the first closed normalized topology into one DSLX proc graph.

-module(xls_topology_dslx).
-moduledoc """
Generates the deliberately small, closed DSLX topology backend.

The input is a normalized `xls_topology` plan plus a physical profile. This
backend uses complete `axis::Frame` channels, one shared public actor codebook,
depth-N channel buffers, binary `axis::FrameMux2` ingress trees, and one
`axis::ReservedFrame` admission boundary per actor. Startup records are packed
by their destination actor's generated Erlang packer, so the topology does not
repeat record layouts or numeric tags.

This is intentionally an executable application fixture, not a general
semantics-preserving topology backend. The profile must explicitly assume
route-interface compatibility because actor summaries do not expose enough
information to check it yet. Its
`aliased_port_order` setting says whether the fixture permits the current mux
trees to reorder messages sent through different ports of one actor to one
destination. The generator derives the affected lanes from the semantic plan;
the physical profile does not repeat their actors, modules, ports, or routes.
`may_reorder` is an explicit fixture limitation, not a proof that an
application is permutation-invariant and not general Erlang lane-ordering
support.

The backend implements only `queued` multi-recipient delivery: the actor event
completes when its one common egress channel accepts the frame, after which a
lossless distributor waits for every bounded branch channel. Startup is not an
ordinary competing ingress. A per-destination prefix emits all startup frames
in list order before it performs its first routed-input receive.

Until actor summaries expose initial-effect metadata, startup quiescence
validation executes `init/1` and the initial `handle_enter/3` in the build VM.
This fixture backend must therefore be used only with trusted, deterministic
actor modules; isolation and timeouts remain future compiler work.
""".

-export([emit/2, from_module/2]).
-export_type([profile/0]).

-type profile() :: map().

-define(MAX_PAYLOAD_BITS, 96).

-doc "Loads and normalizes `TopologyModule`, then emits its DSLX graph.".
-spec from_module(module(), profile()) -> iolist().
from_module(TopologyModule, Profile) when is_atom(TopologyModule) ->
    emit(xls_topology:from_module(TopologyModule), Profile).

-doc "Emits deterministic DSLX from one normalized plan and physical profile.".
-spec emit(xls_topology:plan(), profile()) -> iolist().
emit(Plan, Profile) ->
    render(lower(Plan, Profile)).

%%%
%%% Backend lowering and validation
%%%

lower(Plan, Profile) ->
    case maps:get(version, Plan, '$missing') of
        0 -> ok;
        Version -> error({unsupported_dslx_topology_version, Version})
    end,
    Actors = annotate_actors(maps:get(actors, Plan)),
    Externals = annotate_externals(maps:get(externals, Plan)),
    ActorIndex = maps:from_list([
        {maps:get(id, Actor), Actor} || Actor <- Actors
    ]),
    Physical = validate_profile(Profile, Plan),
    ok = validate_shared_codebook(Actors),
    ok = validate_startup_quiescence(maps:get(startup, Plan), ActorIndex),
    Routes = physical_route_order(Actors, maps:get(routes, Plan)),
    Startup = pack_startup(maps:get(startup, Plan), ActorIndex),
    #{
        name => maps:get(name, Physical),
        depth => maps:get(channel_depth, Physical),
        actors => Actors,
        externals => Externals,
        routes => Routes,
        startup => Startup,
        aliased_lanes => maps:get(aliased_lanes, Physical)
    }.

validate_profile(Profile, Plan) when is_map(Profile) ->
    Required = lists:sort([
        aliased_port_order,
        channel_depth,
        codebook,
        name,
        route_interfaces,
        version
    ]),
    Keys = lists:sort(maps:keys(Profile)),
    case {Required -- Keys, Keys -- Required} of
        {[], []} -> ok;
        {Missing, Unknown} ->
            error({invalid_dslx_profile_keys, Missing, Unknown})
    end,
    case maps:get(version, Profile) of
        0 -> ok;
        Version -> error({unsupported_dslx_profile_version, Version})
    end,
    Name = identifier(maps:get(name, Profile), topology_name),
    case maps:get(channel_depth, Profile) of
        Depth when is_integer(Depth), Depth > 0 -> ok;
        Depth -> error({invalid_dslx_channel_depth, Depth})
    end,
    case maps:get(route_interfaces, Profile) of
        assumed_compatible -> ok;
        InterfacePolicy ->
            error({unsupported_dslx_route_interfaces, InterfacePolicy})
    end,
    case maps:get(codebook, Profile) of
        shared -> ok;
        CodebookPolicy -> error({unsupported_dslx_codebook, CodebookPolicy})
    end,
    RealizedLanes = derive_realized_lanes(maps:get(routes, Plan)),
    case maps:get(lanes, Plan, '$missing') of
        RealizedLanes -> ok;
        CachedLanes -> error({inconsistent_dslx_plan_lanes,
            RealizedLanes, CachedLanes})
    end,
    AliasedLanes = describe_aliased_lanes(
        RealizedLanes,
        maps:get(actors, Plan)
    ),
    ok = validate_aliased_port_order(
        maps:get(aliased_port_order, Profile),
        AliasedLanes
    ),
    Profile#{
        name := Name,
        aliased_lanes => AliasedLanes
    };
validate_profile(Profile, _Plan) ->
    error({invalid_dslx_profile, Profile}).

validate_aliased_port_order(preserve, []) -> ok;
validate_aliased_port_order(preserve, Lanes) ->
    error({unsupported_dslx_aliased_port_order, preserve, Lanes});
validate_aliased_port_order(may_reorder, _Lanes) -> ok;
validate_aliased_port_order(Policy, _Lanes) ->
    error({invalid_dslx_aliased_port_order, Policy}).

describe_aliased_lanes(Lanes, Actors) ->
    ActorIndex = maps:from_list([
        {maps:get(id, Actor), Actor} || Actor <- Actors
    ]),
    [describe_aliased_lane(Lane, ActorIndex)
        || Lane <- Lanes,
           length(maps:get(source_ports, Lane)) > 1].

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

describe_aliased_lane(Lane, ActorIndex) ->
    Source = maps:get(source, Lane),
    Destination = maps:get(destination, Lane),
    SourceActor = maps:get(Source, ActorIndex),
    DestinationModule = case Destination of
        {actor, DestinationId} ->
            maps:get(module, maps:get(DestinationId, ActorIndex));
        {external, ExternalId} ->
            error({unsupported_dslx_aliased_external_lane,
                Source, ExternalId});
        _ -> error({invalid_dslx_aliased_destination, Destination})
    end,
    #{
        source => Source,
        source_module => maps:get(module, SourceActor),
        source_ports => maps:get(source_ports, Lane),
        destination => Destination,
        destination_module => DestinationModule
    }.

annotate_actors(Actors) ->
    [annotate_actor(Index, Actor)
        || {Index, Actor} <- lists:enumerate(0, Actors)].

annotate_actor(Index, Actor) ->
    Module = maps:get(module, Actor),
    ModuleName = identifier(Module, {actor_module, maps:get(id, Actor)}),
    Outputs = maps:get(outputs, Actor),
    lists:foreach(
        fun(Port) ->
            _ = identifier(Port, {actor_output, maps:get(id, Actor)})
        end,
        Outputs
    ),
    OutputChannels = maps:from_list([
        {Port, ["actor_", integer_to_list(Index), "_output_",
            integer_to_list(OutputIndex)]}
        || {OutputIndex, Port} <- lists:enumerate(0, Outputs)
    ]),
    Actor#{
        index => Index,
        module_name => ModuleName,
        stem => ["actor_", integer_to_list(Index)],
        output_channels => OutputChannels
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

validate_shared_codebook([]) -> ok;
validate_shared_codebook([First | Rest]) ->
    Expected = public_codebook(First),
    lists:foreach(
        fun(Actor) ->
            case public_codebook(Actor) of
                Expected -> ok;
                Actual -> error({incompatible_actor_codebook,
                    maps:get(id, Actor), Expected, Actual})
            end
        end,
        Rest
    ).

public_codebook(Actor) ->
    Module = maps:get(module, Actor),
    Attributes = Module:module_info(attributes),
    Fragments = proplists:get_all_values(xls_tags, Attributes),
    case Fragments =/= [] andalso lists:all(
        fun(Fragment) ->
            is_list(Fragment) andalso
                lists:all(fun erlang:is_atom/1, Fragment)
        end,
        Fragments
    ) of
        true ->
            Tags = lists:append(Fragments),
            case duplicate_values(Tags) of
                [] -> Tags;
                Duplicates -> error({duplicate_actor_codebook_tags,
                    maps:get(id, Actor), Module, Duplicates})
            end;
        false -> error({invalid_actor_codebook,
            maps:get(id, Actor), Module, Fragments})
    end.

validate_startup_quiescence(Startup, ActorIndex) ->
    lists:foreach(
        fun(Item) ->
            Target = maps:get(target, Item),
            Actor = maps:get(Target, ActorIndex),
            Module = maps:get(module, Actor),
            InitResult = try Module:init([]) of
                Result0 -> Result0
            catch
                InitClass:InitReason ->
                    error({cannot_validate_startup_target_init,
                        Target, Module, InitClass, InitReason})
            end,
            {InitialPhase, InitialData} = case InitResult of
                {ok, Phase, Data} -> {Phase, Data};
                _ -> error({invalid_startup_target_init,
                    Target, Module, InitResult})
            end,
            EntryResult = try Module:handle_enter(
                InitialPhase,
                InitialPhase,
                InitialData
            ) of
                Result1 -> Result1
            catch
                EntryClass:EntryReason ->
                    error({cannot_validate_startup_target_entry,
                        Target, Module, EntryClass, EntryReason})
            end,
            case EntryResult of
                {_EnteredData, []} -> ok;
                {_EnteredData, Effects} ->
                    error({startup_target_has_initial_effects,
                        Target, Module, Effects});
                _ -> error({invalid_startup_target_entry,
                    Target, Module, EntryResult})
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
    [Route#{index => Index}
        || {Index, Route} <- lists:enumerate(0, Ordered)].

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
            payload => payload_literal(Payload)
        };
        false -> error({unsupported_startup_payload_width,
            Target, Index, Width})
    end;
pack_startup_message(Target, Index, _Module, Message) ->
    error({invalid_startup_message, Target, Index, Message}).

payload_literal(Payload) ->
    Width = bit_size(Payload),
    Digits = Width div 4,
    Value = binary:decode_unsigned(Payload, little),
    Hex = integer_to_list(Value, 16),
    ["u", integer_to_list(Width), ":0x",
        lists:duplicate(Digits - length(Hex), $0), Hex].

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
        Actors,
        Externals,
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
        fanout_procs(maps:get(fanout_arities, FinalGraph)),
        startup_procs(maps:get(startup, Spec)),
        top_proc(
            Actors,
            Externals,
            Depth,
            maps:get(route_code, FinalGraph),
            IngressCode
        )
    ].

route_graph(Routes, Actors, Externals, Depth) ->
    ActorIndex = maps:from_list([
        {maps:get(id, Actor), Actor} || Actor <- Actors
    ]),
    ExternalIndex = maps:from_list([
        {maps:get(id, External), External} || External <- Externals
    ]),
    lists:foldl(
        fun(Route, Graph) ->
            lower_route(Route, ActorIndex, ExternalIndex, Depth, Graph)
        end,
        #{
            leaves => #{},
            route_code => [],
            fanout_arities => []
        },
        Routes
    ).

lower_route(Route, ActorIndex, ExternalIndex, Depth, Graph) ->
    {SourceActorId, Port} = maps:get(source, Route),
    SourceActor = maps:get(SourceActorId, ActorIndex),
    SourceChannel = maps:get(Port, maps:get(output_channels, SourceActor)),
    Recipients = maps:get(recipients, Route),
    case {maps:get(delivery, Route), Recipients} of
        {direct, [Recipient]} ->
            add_leaf(
                recipient_key(Recipient, ActorIndex, ExternalIndex),
                consumer(SourceChannel),
                Graph
            );
        {queued, [_, _ | _]} ->
            lower_queued_fanout(
                Route,
                SourceChannel,
                Recipients,
                ActorIndex,
                ExternalIndex,
                Depth,
                Graph
            );
        {Delivery, _} ->
            error({unsupported_dslx_route_delivery,
                maps:get(source, Route), Delivery, length(Recipients)})
    end.

lower_queued_fanout(
    Route,
    SourceChannel,
    Recipients,
    ActorIndex,
    ExternalIndex,
    Depth,
    Graph0
) ->
    RouteIndex = maps:get(index, Route),
    Branches = [
        ["route_", integer_to_list(RouteIndex), "_branch_",
            integer_to_list(Index)]
        || {Index, _Recipient} <- lists:enumerate(0, Recipients)
    ],
    Declarations = [frame_channel(Channel, Depth) || Channel <- Branches],
    Spawn = [
        "    spawn QueuedFanout", integer_to_list(length(Recipients)),
        "(", consumer(SourceChannel),
        [[", ", producer(Branch)] || Branch <- Branches],
        ");\n"
    ],
    Graph1 = Graph0#{
        route_code := maps:get(route_code, Graph0) ++
            Declarations ++ [Spawn],
        fanout_arities := lists:usort([
            length(Recipients) | maps:get(fanout_arities, Graph0)
        ])
    },
    lists:foldl(
        fun({Recipient, Branch}, Graph) ->
            add_leaf(
                recipient_key(Recipient, ActorIndex, ExternalIndex),
                consumer(Branch),
                Graph
            )
        end,
        Graph1,
        lists:zip(Recipients, Branches)
    ).

recipient_key({actor, Id}, ActorIndex, _ExternalIndex) ->
    {actor, maps:get(index, maps:get(Id, ActorIndex))};
recipient_key({external, Id}, _ActorIndex, ExternalIndex) ->
    {external, maps:get(index, maps:get(Id, ExternalIndex))}.

add_leaf(Key, Channel, Graph) ->
    Leaves0 = maps:get(leaves, Graph),
    Leaves = maps:update_with(
        Key,
        fun(Existing) -> Existing ++ [Channel] end,
        [Channel],
        Leaves0
    ),
    Graph#{leaves := Leaves}.

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
    AliasedLanes = maps:get(aliased_lanes, Spec),
    AliasCount = length(AliasedLanes),
    StartupCount = length(maps:get(startup, Spec)),
    [
        "// ", maps:get(name, Spec), ".x\n",
        "// Auto-generated by xls_topology_dslx from normalized Erlang data.\n",
        "// Manual changes will be overwritten.\n",
        "//\n",
        "// Fixture boundary: route-interface compatibility is assumed by ",
        "the profile,\n",
        "// not compiler-checked. Actor public tags use one validated shared ",
        "codebook.\n",
        "// The ",
        integer_to_list(AliasCount),
        " aliased lane(s)\n",
        "// below may reorder across source ports; these muxes do not ",
        "implement general\n",
        "// Erlang same-sender lane ordering.\n",
        "// ", integer_to_list(StartupCount), " startup prefix(es) emit all ",
        "target startup frames before\n",
        "// receiving that target's first routed frame.\n\n",
        "import axis;\n",
        [["import ", Module, ";\n"] || Module <- Modules],
        "\n",
        "const CHANNEL_DEPTH = u32:", integer_to_list(maps:get(depth, Spec)),
        ";\n\n",
        alias_comments(AliasedLanes),
        case maps:get(fanout_arities, Graph) of
            [] -> [];
            _ -> [
                "// Queued fanout: source completion is acceptance by the ",
                "common actor-output\n",
                "// channel; the downstream distributor then waits for ",
                "every branch channel.\n\n"
            ]
        end
    ].

alias_comments([]) -> [];
alias_comments(AliasedLanes) ->
    [
        "// Aliased-port lanes permitted to reorder in this fixture:\n",
        [aliased_lane_comment(Lane) || Lane <- AliasedLanes],
        "\n"
    ].

aliased_lane_comment(Lane) ->
    [
        "//   ", io_lib:format("~p (~p) ~p -> ~p (~p)", [
            maps:get(source, Lane),
            maps:get(source_module, Lane),
            maps:get(source_ports, Lane),
            maps:get(destination, Lane),
            maps:get(destination_module, Lane)
        ]),
        "\n"
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

fanout_procs(Arities) -> [fanout_proc(Arity) || Arity <- Arities].

fanout_proc(Arity) ->
    Indexes = lists:seq(0, Arity - 1),
    Tokens = [["branch_", integer_to_list(Index), "_tok"]
        || Index <- Indexes],
    [
        "proc QueuedFanout", integer_to_list(Arity), " {\n",
        "  frame_in: chan<axis::Frame> in;\n",
        [["  branch_", integer_to_list(Index),
            "_out: chan<axis::Frame> out;\n"] || Index <- Indexes],
        "\n  config(frame_in: chan<axis::Frame> in,\n",
        [["         branch_", integer_to_list(Index),
            "_out: chan<axis::Frame> out",
            separator(Index, Arity), "\n"] || Index <- Indexes],
        "  ) {\n    (frame_in",
        [[", branch_", integer_to_list(Index), "_out"] || Index <- Indexes],
        ")\n  }\n\n",
        "  init { () }\n\n",
        "  next(state: ()) {\n",
        "    let (tok, frame) = recv(join(), frame_in);\n",
        [["    let ", lists:nth(Index + 1, Tokens),
            " = send(tok, branch_", integer_to_list(Index),
            "_out, frame);\n"] || Index <- Indexes],
        "    let _done = ", join_tokens(Tokens), ";\n",
        "    state\n  }\n}\n\n"
    ].

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
            [frame_channel(Channel, Depth)
                || {_Port, Channel} <- output_channels(Actor)]
        ]
        || Actor <- Actors
    ].

actor_spawns(Actors) ->
    [
        [
            "    spawn ", maps:get(module_name, Actor), "::Service(\n",
            "      ", consumer([maps:get(stem, Actor), "_req"]),
            [[",\n      ", producer(Channel)]
                || {_Port, Channel} <- output_channels(Actor)],
            ",\n      ", producer([maps:get(stem, Actor), "_admit"]),
            ");\n"
        ]
        || Actor <- Actors
    ].

output_channels(Actor) ->
    Channels = maps:get(output_channels, Actor),
    [{Port, maps:get(Port, Channels)} || Port <- maps:get(outputs, Actor)].

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

producer(Channel) -> [Channel, "_p"].
consumer(Channel) -> [Channel, "_c"].

join_tokens([Token]) -> Token;
join_tokens([First, Second | Rest]) ->
    join_tokens([["join(", First, ", ", Second, ")"] | Rest]).

join_with(_Separator, []) -> [];
join_with(Separator, [First | Rest]) ->
    [First | [[Separator, Item] || Item <- Rest]].

duplicate_values(Values) ->
    Counts = lists:foldl(
        fun(Value, Acc) ->
            maps:update_with(Value, fun(Count) -> Count + 1 end, 1, Acc)
        end,
        #{},
        Values
    ),
    lists:sort([
        Value || {Value, Count} <- maps:to_list(Counts), Count > 1
    ]).
