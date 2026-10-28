-module(hls_partition_dslx).
-moduledoc """
Legacy partition build drivers render a checked device view here. The emitter composes hls_partition_links, reduction and scheduler helpers; board shells and runtime streams remain separate.

Emits direct or RAM-scheduled actors on one side of a private partition.

The remote Frame arrays expose the deployment's directed lanes to a lossless
credit bridge. They are not one multiplexed mailbox. Local source/recipient
lanes retain independent bounded queues and aliased ports retain source order.
Code generation must retain registered outputs (`--flop_outputs=true`). Shared
placement exposes physical RAM ports and passive mailbox-observation outputs;
the shell must always accept those observations.
""".
%% Device-level DSLX composition.
-export([emit/3]).

-doc "Emits the deployment's actor graph and any shared RAM ports. Requires bidirectional lanes and registered codegen outputs; placement comes from the deployment, not profile options.".
-spec emit(map(), term(), map()) -> iolist().
emit(Partition, Device, Options) ->
    #{name := Name, channel_depth := Depth, actor_egress_depth := Egress} =
        profile(Options),
    Local =
        #{actors := Actors, tx_lanes := Tx, rx_lanes := Rx, schedulers := Groups} = hls_partition:device(
            Partition, Device
        ),
    case {Tx, Rx} of
        {[_ | _], [_ | _]} -> ok;
        _ -> error({partition_requires_bidirectional_lanes, Device})
    end,
    [
        "// ",
        Name,
        ": generated private actor partition.\n",
        "// Remote lane numbers come from the checked deployment manifest.\n",
        "import axis;\nimport mailbox;\nimport frame_transport;\nimport hls_spatial_router;\n",
        [
            ["import ", atom_to_list(Module), ";\n"]
         || Module <- lists:usort([M || #{module := M} <- Actors])
        ],
        "\n",
        hls_frame_layout:assert_dslx(maps:get(frame_layout, Local)),
        "const CHANNEL_DEPTH = u32:",
        integer_to_list(Depth),
        ";\n\n",
        [router(A, Local) || A <- Actors],
        hls_partition_shared_dslx:support(Local),
        [
            hls_partition_shared_dslx:ingress_support(A, Local, ingress_inputs(A, Partition, Local))
         || A <- Actors, Groups =/= []
        ],
        hls_partition_reduction_dslx:support(Partition, Local),
        [control_router(I, Local) || I <- maps:get(ingresses, Local)],
        case Groups of
            [] ->
                [
                    prefix(A, incoming(A, Partition) =/= [] orelse controlled(A, Partition))
                 || A <- Actors
                ];
            _ ->
                []
        end,
        top(Partition, Local, Egress)
    ].

%% Reject physical options that this backend cannot implement, including observation hooks.
-spec profile(map()) -> map().
profile(Options) ->
    Profile = xls_fabric_topology_profile:normalize(Options),
    Unsupported = [
        Key
     || {Key, Default} <- [
            {scheduler_groups, #{}},
            {reduction_placements, #{}},
            {mailbox_debug, false},
            {direct_actor_debug, false},
            {effect_window_partition, global}
        ],
        maps:get(Key, Profile) =/= Default
    ],
    case Unsupported of
        [] -> Profile;
        _ -> error({partition_profile, Unsupported})
    end.

%% Render one actor's ordered fanout to its destination lanes.
-spec router(map(), map()) -> iolist().
router(A = #{module := Module}, Local) ->
    Out = hls_partition_outbox:ordinary(A, Local),
    Members = [
        ["egress_in: chan<", atom_to_list(Module), "::Egress> in"]
        | [[lane_name(L), "_out: chan<axis::Frame> out"] || L <- Out]
    ],
    Names = ["egress_in" | [[lane_name(L), "_out"] || L <- Out]],
    [
        "proc Router",
        index(A),
        " {\n",
        fields(Members),
        config(Members, Names),
        "  init { () }\n  next(state: ()) {\n",
        "    let (tok, egress) = recv(join(), egress_in);\n",
        [router_send(Module, L) || L <- Out],
        "    let _done = join(tok",
        [[", tok_", lane_name(L)] || L <- Out],
        ");\n",
        "    state\n  }\n}\n\n"
    ].

%% Send an effect to a lane when its output port selects that destination.
-spec router_send(module(), map()) -> iolist().
router_send(Module, L = #{ports := Ports}) ->
    Name = lane_name(L),
    [
        "    let selected_",
        Name,
        " = match egress.port {\n",
        [
            [
                "      ",
                atom_to_list(Module),
                "::OutputPort::",
                xls_names:enum_member(Port),
                " => true,\n"
            ]
         || Port <- Ports
        ],
        "      _ => false,\n    };\n",
        "    let tok_",
        Name,
        " = send_if(tok, ",
        Name,
        "_out, selected_",
        Name,
        ", egress.frame);\n"
    ].

%% Emit startup frames before accepting routed input for the actor.
-spec prefix(map(), boolean()) -> iolist().
prefix(A = #{startup := Startup}, HasInput) ->
    Members =
        case HasInput of
            true -> ["routed_in: chan<axis::Frame> in", "frame_out: chan<axis::Frame> out"];
            false -> ["frame_out: chan<axis::Frame> out"]
        end,
    Names =
        case HasInput of
            true -> ["routed_in", "frame_out"];
            false -> ["frame_out"]
        end,
    [
        "proc Prefix",
        index(A),
        " {\n",
        fields(Members),
        config(Members, Names),
        "  init { u32:0 }\n  next(index: u32) {\n",
        "    let starting = index < u32:",
        integer_to_list(length(Startup)),
        ";\n",
        "    let startup_frame = match index {\n",
        [
            ["      u32:", integer_to_list(I), " => ", frame(F), ",\n"]
         || {I, F} <- lists:enumerate(0, Startup)
        ],
        "      _ => zero!<axis::Frame>(),\n    };\n",
        case HasInput of
            true ->
                [
                    "    let (tok, routed) = recv_if(join(), routed_in, !starting, zero!<axis::Frame>());\n",
                    "    let _done = send(tok, frame_out, if starting { startup_frame } else { routed });\n"
                ];
            false ->
                "    let _done = send_if(join(), frame_out, starting, startup_frame);\n"
        end,
        "    if starting { index + u32:1 } else { index }\n  }\n}\n\n"
    ].

%% Render a prepacked startup frame with its exact word count.
-spec frame(#{selector := byte(), payload := binary()}) -> iolist().
frame(#{selector := Selector, payload := Payload}) ->
    Size = bit_size(Payload),
    Words = Size div 32,
    Value =
        case Payload of
            <<>> -> "bits[axis::PAYLOAD_BITS]:0";
            _ -> [xls_nums:packed_unsigned_literal(Payload), " as bits[axis::PAYLOAD_BITS]"]
        end,
    [
        "axis::Frame { header: axis::Header { op: u8:",
        integer_to_list(Selector),
        ", payload_words: u8:",
        integer_to_list(Words),
        ", ..zero!<axis::Header>() }, payload: ",
        Value,
        " }"
    ].

%% Connect actors, lane queues, startup prefixes and external channels.
-spec top(map(), map(), burst | non_neg_integer()) -> iolist().
top(
    Partition,
    Local = #{
        actors := Actors,
        lanes := Lanes,
        externals := Externals,
        ingresses := Ingresses,
        schedulers := Groups
    },
    Egress
) ->
    Members =
        hls_partition_links:frame_parameters(Local) ++
            [[Port, ": chan<axis::Frame> out"] || #{port := Port} <- Externals] ++
            [
                [Input, ": chan<hls_spatial_router::SpatialFrame> in"]
             || #{input_name := Input} <- Ingresses
            ] ++
            hls_partition_shared_dslx:parameters(Local) ++ hls_partition_tile:parameters(Local),
    Names =
        hls_partition_links:frame_names(Local) ++ [Port || #{port := Port} <- Externals] ++
            [Input || #{input_name := Input} <- Ingresses] ++ hls_partition_shared_dslx:names(Local) ++
            hls_partition_tile:names(Local),
    [
        "pub proc Top {\n",
        fields(Members),
        "  config(\n    ",
        lists:join(",\n    ", Members),
        ") {\n",
        case Groups of
            [] -> [actor_channels(A, Egress) || A <- Actors];
            _ -> hls_partition_shared_dslx:channels(Partition, Local)
        end,
        hls_partition_reduction_dslx:channels(Partition, Local),
        [lane_channel(L, Partition) || L = #{kind := Kind} <- Lanes, Kind =/= remote],
        [frame_channel(control_name(A)) || A <- Actors, controlled(A, Partition)],
        [control_spawn(I, Local) || I <- Ingresses],
        case Groups of
            [] -> [actor_spawn(A) || A <- Actors];
            _ -> hls_partition_shared_dslx:spawn(Partition, Local)
        end,
        hls_partition_reduction_dslx:spawn(Partition, Local),
        [hls_partition_reduction_dslx:collector(A, Partition, Local) || A <- Actors],
        [router_spawn(A, Local) || A <- Actors],
        [ingress(A, Partition, Local) || A <- Actors],
        [external(E, Local) || E <- Externals],
        "    (",
        lists:join(", ", Names),
        ")\n  }\n",
        "  init { () }\n  next(state: ()) { state }\n}\n"
    ].

%% Declare actor request, admission and egress channels with the selected buffering policy.
-spec actor_channels(map(), burst | non_neg_integer()) -> iolist().
actor_channels(A = #{module := Module, max_entry_effects := Max}, Egress) ->
    Stem = actor_name(A),
    EgressDepth =
        case Egress of
            burst -> max(0, Max - 1);
            N -> N
        end,
    [
        frame_channel([Stem, "_req"]),
        frame_channel([Stem, "_prefix"]),
        "    let (",
        Stem,
        "_admit_p, ",
        Stem,
        "_admit_c) = chan<u1, CHANNEL_DEPTH>(\"",
        Stem,
        "_admit\");\n",
        "    let (",
        Stem,
        "_egress_p, ",
        Stem,
        "_egress_c) = chan<",
        atom_to_list(Module),
        "::Egress, u32:",
        integer_to_list(EgressDepth),
        ">(\"",
        Stem,
        "_egress\");\n"
    ].

%% Instantiate the actor module's standalone service.
-spec actor_spawn(map()) -> iolist().
actor_spawn(A = #{module := Module}) ->
    Stem = actor_name(A),
    [
        "    spawn ",
        atom_to_list(Module),
        "::Service(",
        Stem,
        "_req_c, ",
        Stem,
        "_egress_p, ",
        Stem,
        "_admit_p);\n"
    ].

%% Bind a router's outputs to local channels or device-local remote channel indices.
-spec router_spawn(map(), map()) -> iolist().
router_spawn(A, Local = #{schedulers := Groups}) ->
    Input =
        case Groups of
            [] -> [actor_name(A), "_egress_c"];
            _ -> hls_partition_shared_dslx:egress(A, Local)
        end,
    Outputs = [
        case L of
            #{kind := remote} -> hls_partition_links:channel(Local, L, out);
            _ -> [lane_name(L), "_p"]
        end
     || L <- hls_partition_outbox:ordinary(A, Local)
    ],
    [
        "    spawn Router",
        index(A),
        "(",
        Input,
        [[", ", Out] || Out <- Outputs],
        ");\n"
    ].

%% Select all lanes that terminate at this actor.
-spec incoming(map(), map()) -> [map()].
incoming(#{identity := Id}, Partition) -> hls_partition_tile:incoming(Id, Partition).

%% Select ordinary producer lanes, leaving proved contributions on their reduction plane.
-spec ingress_inputs(map(), map(), map()) -> [iodata()].
ingress_inputs(A, Partition, Local) ->
    Captured = [Id || #{id := Id} <- hls_partition_reduction:inputs(A, Partition)],
    [
        case L of
            #{kind := remote} -> hls_partition_links:channel(Local, L, in);
            _ -> [lane_name(L), "_c"]
        end
     || L = #{id := Id} <- incoming(A, Partition), not lists:member(Id, Captured)
    ] ++
        case controlled(A, Partition) of
            true -> [[control_name(A), "_c"]];
            false -> []
        end.

%% A shared actor merges the final pair while wrapping the scheduled request.
-spec ingress(map(), map(), map()) -> iolist().
ingress(A, Partition, Local = #{schedulers := [_ | _]}) ->
    case ingress_inputs(A, Partition, Local) of
        [] ->
            [];
        Inputs ->
            {Before, Roots} = ingress_roots(Inputs, [actor_name(A), "_mux"], 0),
            [Before, hls_partition_shared_dslx:input(A, Local, Roots)]
    end;
ingress(A, Partition, Local) ->
    Stem = actor_name(A),
    Inputs = ingress_inputs(A, Partition, Local),
    {Before, Input} =
        case Inputs of
            [] ->
                {[], []};
            [Only] ->
                {[], [Only, ", "]};
            _ ->
                {Muxes, Merged} = merge(Inputs, [Stem, "_mux"], 0),
                {Muxes, [Merged, ", "]}
        end,
    [
        Before,
        "    spawn Prefix",
        index(A),
        "(",
        Input,
        Stem,
        "_prefix_p);\n",
        "    spawn axis::ReservedFrame(",
        Stem,
        "_prefix_c, ",
        Stem,
        "_req_p, ",
        Stem,
        "_admit_c);\n"
    ].

%% Retain the lower merger levels; the final arbitration and wrapper share one proc.
-spec ingress_roots([iodata(), ...], iodata(), non_neg_integer()) -> {iolist(), [iodata()]}.
ingress_roots(Inputs, _Stem, _Level) when length(Inputs) =< 2 -> {[], Inputs};
ingress_roots(Inputs, Stem, Level) ->
    {Procs, Outputs} = merge_pairs(Inputs, Stem, Level, 0),
    {More, Roots} = ingress_roots(Outputs, Stem, Level + 1),
    {[Procs, More], Roots}.

%% Merge the local producers of one external output.
-spec external(map(), map()) -> iolist().
external(#{id := Id, port := Port}, #{lanes := Lanes}) ->
    Inputs = [
        [lane_name(L), "_c"]
     || L = #{destination := {external, Target}} <- Lanes, Target =:= Id
    ],
    case Inputs of
        [Only] ->
            ["    spawn frame_transport::FrameRelay(", Only, ", ", Port, ");\n"];
        _ ->
            {Muxes, Root} = merge(Inputs, [Port, "_mux"], 0),
            [Muxes, "    spawn frame_transport::FrameRelay(", Root, ", ", Port, ");\n"]
    end.

%% Scalar channel arguments avoid the pinned DSLX typechecker's inconsistent
%% FrameN parametric identity when a literal channel array mixes indexed
%% external channels with locally created channels. Each pair polls fairly.
-spec merge([iodata(), ...], iodata(), non_neg_integer()) -> {iolist(), iodata()}.
merge([Only], _Stem, _Level) ->
    {[], Only};
merge(Inputs, Stem, Level) ->
    {Procs, Outputs} = merge_pairs(Inputs, Stem, Level, 0),
    {More, Root} = merge(Outputs, Stem, Level + 1),
    {[Procs, More], Root}.

%% Build one level of fair two-input mergers, passing an odd channel through.
-spec merge_pairs([iodata()], iodata(), non_neg_integer(), non_neg_integer()) ->
    {iolist(), [iodata()]}.
merge_pairs([], _Stem, _Level, _Index) ->
    {[], []};
merge_pairs([Only], _Stem, _Level, _Index) ->
    {[], [Only]};
merge_pairs([Left, Right | Rest], Stem, Level, Index) ->
    Name = [Stem, "_", integer_to_list(Level), "_", integer_to_list(Index)],
    {More, Outputs} = merge_pairs(Rest, Stem, Level, Index + 1),
    {
        [
            frame_channel(Name),
            "    spawn axis::FrameMux2(",
            Left,
            ", ",
            Right,
            ", ",
            Name,
            "_p);\n",
            More
        ],
        [[Name, "_c"] | Outputs]
    }.

%% Consolidate a singleton fragment's two queue slots and one relay register upstream.
-spec lane_channel(map(), map()) -> iolist().
lane_channel(L = #{id := Id}, Partition) ->
    Name = lane_name(L),
    Extra = hls_partition_reduction:queue_extra(Id, Partition),
    [
        "    let (",
        Name,
        "_p, ",
        Name,
        "_c) = chan<axis::Frame, {CHANNEL_DEPTH + u32:",
        integer_to_list(Extra),
        "}>(\"",
        Name,
        "\");\n"
    ].

%% Declare a frame channel at the deployment's selected depth.
-spec frame_channel(iodata()) -> iolist().
frame_channel(Name) ->
    ["    let (", Name, "_p, ", Name, "_c) = chan<axis::Frame, CHANNEL_DEPTH>(\"", Name, "\");\n"].

%% Render channel member declarations inside a proc.
-spec fields([iodata()]) -> iolist().
fields(Members) -> [["  ", Member, ";\n"] || Member <- Members].
%% Render a proc configuration signature and its member tuple.
-spec config([iodata()], [iodata()]) -> iolist().
config(Members, Names) ->
    [
        "  config(",
        lists:join(",\n      ", Members),
        ") {\n",
        "    (",
        lists:join(", ", Names),
        case Names of
            [_] -> ",";
            _ -> []
        end,
        ")\n  }\n"
    ].
%% Render a stable actor index for generated identifiers.
-spec index(#{index := non_neg_integer(), atom() => term()}) -> string().
index(#{index := Index}) -> integer_to_list(Index).
%% Construct the generated channel stem for an actor.
-spec actor_name(map()) -> iolist().
actor_name(A) -> ["actor_", index(A)].
%% Construct the generated channel stem for a lane.
-spec lane_name(#{id := non_neg_integer(), atom() => term()}) -> iolist().
lane_name(L) -> ["lane_", integer_to_list(hls_partition_tile:lane_id(L))].

%% One ordered control lane per actor preserves update/query order across targets.
-spec control_router(map(), map()) -> iolist().
control_router(Ingress = #{bindings := Bindings}, Local) ->
    Tile = maps:get(tile, Local, false),
    Config =
        case Tile of
            true -> [["points: chan<bits[", integer_to_list(32 * length(Bindings)), "]> in"]];
            false -> []
        end,
    Members =
        ["spatial_in: chan<hls_spatial_router::SpatialFrame> in"] ++ Config ++
            [[control_name(A), "_out: chan<axis::Frame> out"] || A <- Bindings],
    Names =
        ["spatial_in"] ++
            case Tile of
                true -> ["points"];
                false -> []
            end ++ [[control_name(A), "_out"] || A <- Bindings],
    [
        "proc ControlRouter {\n",
        fields(Members),
        config(Members, Names),
        "  init { () }\n  next(state: ()) {\n",
        "    let (tok, packet) = recv(join(), spatial_in);\n",
        case Tile of
            true -> "    let (tok, points) = recv(tok, points);\n";
            false -> []
        end,
        [
            [
                "    let tok_",
                control_name(A),
                " = send_if(tok, ",
                control_name(A),
                "_out, (",
                xls_topology_ingress:condition(Targets, Ingress, "packet"),
                ") && hls_spatial_router::contains(packet.rectangle, ",
                case Tile of
                    true ->
                        [
                            "points[",
                            integer_to_list(32 * J + 16),
                            "+:u16], points[",
                            integer_to_list(32 * J),
                            "+:u16]"
                        ];
                    false ->
                        ["u16:", integer_to_list(X), ", u16:", integer_to_list(Y)]
                end,
                "), packet.frame);\n"
            ]
         || {J, A = #{point := [X, Y], targets := Targets}} <- lists:enumerate(0, Bindings)
        ],
        "    let _done = join(tok",
        [[", tok_", control_name(A)] || A <- Bindings],
        ");\n",
        "    state\n  }\n}\n\n"
    ].

%% Connect the checked local selection to independently buffered actor inputs.
-spec control_spawn(map(), map()) -> iolist().
control_spawn(#{input_name := Input, bindings := Bindings}, Local) ->
    [
        "    spawn ControlRouter(",
        Input,
        case Local of
            #{tile := true} -> ", tile_points";
            _ -> []
        end,
        [[", ", control_name(A), "_p"] || A <- Bindings],
        ");\n"
    ].

%% Control membership is independent of actor-to-actor routes.
-spec controlled(map(), map()) -> boolean().
controlled(#{identity := Id}, #{ingresses := Ingresses}) ->
    lists:any(
        fun(#{bindings := Bindings}) ->
            lists:any(fun(#{identity := Target}) -> Target =:= Id end, Bindings)
        end,
        Ingresses
    ).

%% Name the single control lane serving this actor across all ingress targets.
-spec control_name(map()) -> iolist().
control_name(A) -> [actor_name(A), "_control"].
