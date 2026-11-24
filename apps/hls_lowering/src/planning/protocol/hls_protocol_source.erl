-module(hls_protocol_source).
-moduledoc "Plans complete source entry batches, retained host replies and independent recipient outputs for transport preparation. Combines retained transactions, capture layouts and bit projections for the transport renderer; connected receive, capacity and progress qualification remain separate.".

%% Source publication planning.
-export([plan/3]).
-export_type([row/0, output/0, source/0, plan/0]).

-doc "One selected effect projected to a recipient. A reply carries its declared schema union and the complete runtime frame; ordinary entries retain checked constant omissions.".
-type row() :: #{
    layout := non_neg_integer(),
    sequence := non_neg_integer(),
    source_order := non_neg_integer(),
    port := atom(),
    tag := atom() | {reply, [atom()]},
    bits := [hls_protocol_projection:bit()],
    capture_slot := non_neg_integer(),
    constant_requirements := [{{payload, non_neg_integer()}, 0 | 1}]
}.

-doc "One independently stalled recipient output, packed at offset within the publisher's combined output.".
-type output() :: #{
    index := non_neg_integer(),
    destination := hls_logical_topology:destination(),
    offset := non_neg_integer(),
    width := pos_integer(),
    rows := [row()]
}.

-doc "One actor's immutable entry snapshot, per-recipient output wiring and pending-delivery masks.".
-type source() :: #{
    index := non_neg_integer(),
    actor := hls_logical_topology:id(),
    payload_width := pos_integer(),
    snapshot_width := pos_integer(),
    destinations := pos_integer(),
    logical_destinations := non_neg_integer(),
    sequence_slots := pos_integer(),
    outputs := [output()],
    output_width := pos_integer(),
    masks := [#{layout := non_neg_integer(), mask := non_neg_integer()}],
    same_sender_order := one_snapshot_and_per_recipient_subsequence,
    invariant_scope := source_bound_constant_omissions_not_runtime_input_validation
}.

-doc "The source-wide publisher catalogue; source snapshots do not establish cross-sender chronology or protocol admission.".
-type plan() :: #{
    frame_layout := hls_frame_layout:layout(),
    sources := [source()],
    snapshot := ordinary_evaluated_payload_and_layout,
    no_cross_sender_chronology := true,
    whole_protocol_eligible := false
}.

%% Only wiring and constant requirements differ between internal and boundary recipients.
-type projection() :: #{
    bits := [hls_protocol_projection:bit()],
    capture_slot := non_neg_integer(),
    constant_requirements := [{{payload, non_neg_integer()}, 0 | 1}]
}.
%% Ordinary effect projection remains compiler-ordered before compact capture selection.
-type effect_projection() :: #{
    layout := non_neg_integer(),
    index := non_neg_integer(),
    port := atom(),
    tag := atom(),
    frame := [hls_protocol_projection:bit()],
    port_number := non_neg_integer()
}.

-doc "Binds source entry batches to exact ordinary frame projections and declared typed capture channels, and retained host replies to their complete runtime frames. Outputs to one recipient keep their source order across ports; separate recipients have independent backpressure. Internal constant omissions retain explicit source-invariant requirements. This plan does not authorize eliminating receipt guards or establish a safe whole-network capacity.".
-spec plan(
    #{
        topology := #{
            actors := [
                #{
                    id := hls_logical_topology:id(),
                    module := module(),
                    atom() => term()
                }
            ],
            routes := [hls_logical_topology:route()],
            atom() => term()
        },
        modules := #{module() => hls_local_actor:source() | hls_local_actor:artifact()},
        atom() => term()
    },
    hls_protocol_transactions:plan(),
    hls_protocol_capture:plan()
) -> plan().
plan(
    #{topology := #{actors := Actors, routes := Routes}, modules := Modules},
    #{actors := Transactions},
    Capture = #{frame_layout := FrameLayout}
) ->
    #{pairs := Pairs} = hls_protocol_inbox:plan(Capture),
    Components = [
        begin
            [Transaction] = [T || T = #{actor := A} <- Transactions, A =:= Id],
            #{program := Program} = maps:get(M, Modules),
            Spec = xls_actor_program:spec(Program),
            reply_output(actor(I, Id, Spec, Transaction, Capture, Pairs), Spec, Routes)
        end
     || {I, #{id := Id, module := M}} <- lists:enumerate(0, Actors)
    ],
    #{
        frame_layout => FrameLayout,
        sources => Components,
        snapshot => ordinary_evaluated_payload_and_layout,
        no_cross_sender_chronology => true,
        whole_protocol_eligible => false
    }.

%% Original layout payloads are retained once; their width includes shared dynamic fields.
-spec actor(
    non_neg_integer(),
    hls_logical_topology:id(),
    xls_actor_codegen:spec(),
    hls_protocol_transactions:actor(),
    hls_protocol_capture:plan(),
    [hls_protocol_inbox:pair()]
) -> source().
actor(I, Id, Spec, #{batches := Batches}, Capture, Pairs) ->
    Projection = hls_protocol_projection:plan(Spec),
    #{frame_layout := FrameLayout, payload_width := Width, rows := Effects} = Projection,
    FrameLayout = maps:get(frame_layout, Capture),
    Destinations = lists:usort([D || #{per_recipient := Rs} <- Batches, #{destination := D} <- Rs]),
    Depth = lists:max([0 | [N || #{required_pair_sequence_depth := N} <- Batches]]),
    Slots = max(1, Depth),
    {Outputs, Total} = lists:mapfoldl(
        fun({D, Destination}, At) ->
            Rows = lists:append([
                recipient_rows(Id, Destination, B, Effects, Capture, Pairs)
             || B <- Batches
            ]),
            OutputWidth = lists:max([1 | [length(Bits) || #{bits := Bits} <- Rows]]),
            {
                #{
                    index => D,
                    destination => Destination,
                    offset => At,
                    width => OutputWidth,
                    rows => Rows
                },
                At + OutputWidth
            }
        end,
        0,
        lists:enumerate(0, Destinations)
    ),
    Masks = [
        #{
            layout => L,
            mask => lists:foldl(
                fun(#{index := D, rows := Rows}, Mask) ->
                    lists:foldl(
                        fun(#{layout := RL, sequence := K}, M) ->
                            case RL =:= L of
                                true -> M bor (1 bsl (D * Slots + K));
                                false -> M
                            end
                        end,
                        Mask,
                        Rows
                    )
                end,
                0,
                Outputs
            )
        }
     || #{layout := L} <- Batches
    ],
    true = length(Masks) =:= length(lists:usort([L || #{layout := L} <- Masks])),
    #{
        index => I,
        actor => Id,
        payload_width => Width,
        snapshot_width => Width + 8,
        destinations => max(1, length(Destinations)),
        logical_destinations => length(Destinations),
        sequence_slots => Slots,
        outputs => Outputs,
        output_width => max(1, Total),
        masks => Masks,
        same_sender_order => one_snapshot_and_per_recipient_subsequence,
        invariant_scope => source_bound_constant_omissions_not_runtime_input_validation
    }.

%% One physical output covers one logical destination, including all of its source ports.
-spec recipient_rows(
    hls_logical_topology:id(),
    hls_logical_topology:destination(),
    hls_protocol_transactions:batch(),
    [effect_projection()],
    hls_protocol_capture:plan(),
    [hls_protocol_inbox:pair()]
) -> [row()].
recipient_rows(
    Source, Destination, #{layout := Layout, deliveries := Deliveries}, Effects, Capture, Pairs
) ->
    Selected = [D || D = #{destination := Target} <- Deliveries, Target =:= Destination],
    [
        begin
            [#{frame := Frame}] = [
                E
             || E = #{layout := L, index := N, port := P, tag := T} <- Effects,
                L =:= Layout,
                N =:= Order,
                P =:= Port,
                T =:= Tag
            ],
            maps:merge(
                #{layout => Layout, sequence => K, source_order => Order, port => Port, tag => Tag},
                projection(Source, Destination, Port, Tag, Frame, Capture, Pairs)
            )
        end
     || {K, #{order := Order, port := Port, tag := Tag}} <- lists:enumerate(0, Selected)
    ].

%% Boundary recipients retain ordinary frames; internal links omit only certified source constants.
-spec projection(
    hls_logical_topology:id(),
    hls_logical_topology:destination(),
    atom(),
    atom(),
    [hls_protocol_projection:bit()],
    hls_protocol_capture:plan(),
    [hls_protocol_inbox:pair()]
) -> projection().
projection(_, {external, _}, _, _, Frame, _, _) ->
    #{bits => Frame, capture_slot => 0, constant_requirements => []};
projection(
    Source,
    Destination,
    Port,
    Tag,
    Frame,
    #{frame_layout := FrameLayout, channels := Channels},
    Pairs
) ->
    [C] = [
        C0
     || C0 = #{source := S, destination := D, port := P, tag := T} <- Channels,
        S =:= Source,
        D =:= Destination,
        P =:= Port,
        T =:= Tag
    ],
    %% Operation comes from the complete ordinary projection and must be constant.
    OpBits = lists:sublist(Frame, hls_frame_layout:header_offset(op) + 1, 8),
    true = lists:all(fun(B) -> B =:= 0 orelse B =:= 1 end, OpBits),
    Op = hls_protocol_projection:evaluate(OpBits, 0),
    #{frame_positions := Positions, mask := Mask, value := Value} = hls_protocol_codec_plan:plan(
        C, Op, FrameLayout
    ),
    Requirements = lists:filtermap(
        fun(J) ->
            Expected = (Value bsr J) band 1,
            Actual = lists:nth(J + 1, Frame),
            case (Mask bsr J) band 1 of
                0 ->
                    false;
                1 ->
                    case Actual of
                        Expected -> false;
                        {payload, _} -> {true, {Actual, Expected}};
                        _ -> error({inconsistent_static_channel, Source, Destination, Port, Tag, J})
                    end
            end
        end,
        lists:seq(0, hls_frame_layout:frame_bits(FrameLayout) - 1)
    ),
    [#{slots := PairSlots}] = [
        P
     || P = #{source := S, destination := D} <- Pairs, S =:= Source, D =:= Destination
    ],
    [Index] = [
        N
     || #{index := N, channel := #{port := P, tag := T}} <- PairSlots, P =:= Port, T =:= Tag
    ],
    Bits =
        case Positions of
            [] -> [0];
            _ -> [lists:nth(J + 1, Frame) || J <- Positions]
        end,
    #{bits => Bits, capture_slot => Index, constant_requirements => lists:usort(Requirements)}.

%% A retained reply is a complete dynamic frame, not an entry-field projection.
%% The reply port has one dedicated external recipient so caller identity never
%% passes through static internal capture slots or mixes with ordinary effects.
-spec reply_output(source(), xls_actor_codegen:spec(), [hls_logical_topology:route()]) -> source().
reply_output(Source, #{retained_calls := none}, _Routes) ->
    Source;
reply_output(
    Source = #{
        actor := Id,
        outputs := Outputs,
        payload_width := Payload,
        output_width := OutputWidth,
        sequence_slots := Slots,
        masks := Masks
    },
    Spec = #{retained_calls := #{port := Port, calls := Calls}, frame_layout := FrameLayout},
    Routes
) ->
    Recipients = [R || #{source := S, recipients := R} <- Routes, S =:= {Id, Port}],
    Destination =
        case Recipients of
            [[D = {external, _}]] -> D;
            _ -> error({unsupported_protocol_reply_route, Id, Port, Recipients})
        end,
    case [O || O = #{destination := D} <- Outputs, D =:= Destination] of
        [] -> ok;
        _ -> error({shared_protocol_reply_destination, Id, Port, Destination})
    end,
    FrameBits = hls_frame_layout:frame_bits(FrameLayout),
    Width = max(Payload, FrameBits),
    Layout = xls_statem_reply_codegen:layout(Spec),
    Index = length(Outputs),
    Offset =
        case Outputs of
            [] -> 0;
            _ -> OutputWidth
        end,
    Tags = lists:usort(lists:append(maps:values(Calls))),
    Output = #{
        index => Index,
        destination => Destination,
        offset => Offset,
        width => FrameBits,
        rows => [
            #{
                layout => Layout,
                sequence => 0,
                source_order => 0,
                port => Port,
                tag => {reply, Tags},
                bits => [{payload, J} || J <- lists:seq(0, FrameBits - 1)],
                capture_slot => 0,
                constant_requirements => []
            }
        ]
    },
    Source#{
        payload_width := Width,
        snapshot_width := Width + 8,
        destinations := Index + 1,
        logical_destinations := Index + 1,
        outputs := Outputs ++ [Output],
        output_width := Offset + FrameBits,
        masks := Masks ++ [#{layout => Layout, mask => 1 bsl (Index * Slots)}]
    }.
