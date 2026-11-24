-module(hls_domain_endpoint_packets_validation).
-moduledoc "Builds a finite eight-offer packet-router RTL witness. Real source capture plans supply canonical frames; native binding packing supplies independent packet bytes. The schedule names expected arbitration winners and fault edges explicitly instead of duplicating the router FSM. Endpoint ownership, carrier integrity and physical timing remain external assumptions.".
-include_lib("hls_runtime/include/hls_domain_channel_endpoints.hrl").

%% Normal source-build compilation and bounded simulation consume the written bundle separately.
-export([write/1]).

%% One packet fixture retains independent semantic fields and its expected carrier vector.
-type packet() :: #{id := hls_nums:u32(), kind := 1 | 2, binding := #endpoint_binding{},
    sequence := hls_nums:u32(), slot := byte(), frame := non_neg_integer(), wire := non_neg_integer(), words := 0..63}.
%% Explicit scenario inputs and expected selected owners; no arbitration state is simulated here.
-type row() :: #{label := binary(), offers := byte(), ready := 0 | 1, tx := -1..7,
    incoming => packet(), rx => -1..7, rx_ready => byte(), fault => 0 | 1,
    reset => 0 | 1, carrier_fault => 0 | 1, frames => #{0..3 => non_neg_integer()}, covers := [binary()]}.
%% Numeric pins follow the emitted adapter's declaration order at serialization only.
-type pins() :: #{string() => non_neg_integer()}.

-doc "Writes a fresh standalone router bundle, real source classes and finite expected pin vectors. Four DATA/four ACK offers cover fairness, held selection, receive independence, exact identity routing, canonical rejection and sticky fault boundaries. No compiler or simulator subprocess runs here; use compile_source_build and tools/hls_fabric/test_domain_endpoint_packets.py afterward.".
-spec write(file:filename()) -> map().
write(Directory) ->
    Config = fixture(),
    #{files := RouterFiles, result := Router = #{unit := Unit}} = hls_domain_endpoint_packets:emit(Config),
    Trace = trace(Router),
    Files = hls_generated_files:merge([RouterFiles, sources(), #{
        "endpoint-packets-trace.json" => json:encode(Trace), "interface.etf" => term_to_binary(Router)
    }]),
    _ = hls_generated_files:write(#{files => Files, result => Router}, Directory),
    #{libraries := Libraries} = hls_build_support:layout([]),
    ok = hls_artifact_bundle:snapshot(Directory, Libraries),
    hls_artifact_bundle:finish(Directory, [Unit], #{kind => independent_endpoint_packets_witness,
        evidence => <<"Finite packet-router RTL comparison inputs">>, rows => length(maps:get(rows, Trace)),
        endpoint_offers => 8, state_bit_budget => maps:get(state_bit_budget, Router)}).

%% Source-derived codecs are shared across synthetic routes without recompiling the full application.
-spec fixture() -> hls_domain_endpoint_packets:config().
fixture() ->
    Program = xls_actor_program:from_file("apps/hls_fabric/test/hls_protocol_capture_fixture.erl", [], hls_frame_layout:new(20)),
    Channels = [#{source => a, port => Tag, tag => Tag, destination => {actor, b}} || Tag <- [unaligned, small]],
    #{channels := Captures} = hls_protocol_capture:plan(#{channels => Channels}, #{a => Program}),
    Classes = [#{slot => I, codec => hls_protocol_codec_plan:plan(Channel, Operation)}
        || {I, Channel = #{source_operation := Operation}} <- lists:enumerate(0, Captures)],
    Ids = [8, 17, 26, 50, 1, 28, 37, 16#100003d],
    Endpoints = [#{id => Id, kind => case I < 4 of true -> tx; false -> rx end}
        || {I, Id} <- lists:enumerate(0, Ids)],
    Crossings = [#{index => Id, source_domain => 0, destination_domain => 1,
        link => #{index => Id, direction => outgoing, source_index => 0, destination_index => 1,
            slots => 2, classes => Classes}} || Id <- Ids],
    Source = hls_source:library_file(hls_runtime, "fabric/runtime/domain/hls_domain_channel_tx.erl"),
    {ok, Parsed} = hls_source:parse_file(Source),
    Forms = hls_records:resolve(Parsed),
    Inputs = maps:from_list(hls_records:fields(hls_records:find(Forms, endpoint_tx_input))),
    Outputs = maps:from_list(hls_records:fields(hls_records:find(Forms, endpoint_tx_output))),
    #{endpoints => Endpoints, crossings => Crossings, codecs => #{operation => maps:get(op, Inputs),
        binding => maps:get(binding, Inputs), status => maps:get(status, Outputs)}}.

%% Retain the source capture fixture, native binding declaration and witness reference beside the bundle.
-spec sources() -> hls_generated_files:files().
sources() -> maps:from_list([begin {ok, Bytes} = file:read_file(Path), {"evidence/native/" ++ Name, Bytes} end
    || {Name, Path} <- [{"hls_protocol_capture_fixture.erl", filename:absname("apps/hls_fabric/test/hls_protocol_capture_fixture.erl")},
        {"hls_domain_channel_endpoints.hrl", filename:join([code:lib_dir(hls_runtime), "include", "hls_domain_channel_endpoints.hrl"])},
        {"hls_domain_endpoint_packets_validation.erl", filename:absname(?FILE)}]]).

%% Pack every driven input and all relevant outputs; valid packet/data fields are compared in full.
-spec trace(hls_domain_endpoint_packets:result()) -> map().
trace(Router = #{inputs := Inputs, outputs := Outputs, routes := Routes, codecs := #{binding := Type}}) ->
    Outgoing = [packet(R, I, outgoing, Type) || {I, R} <- lists:enumerate(0, Routes)],
    Incoming = [packet(R, I, incoming, Type) || {I, R} <- lists:enumerate(0, Routes)],
    Schedule = schedule(Routes, Outgoing, Incoming, Type),
    Rows = [begin
        {Expected, Checked} = expected(Row, Outputs, Outgoing, Routes),
        #{label => maps:get(label, Row), covers => maps:get(covers, Row), delay => 2 + I rem 5,
            input => hex(pack(Inputs, input(Row, Outgoing, Routes))),
            expected => hex(pack(Outputs, Expected)), mask => hex(pack(Outputs, Checked)),
            selected_tx => maps:get(tx, Row), selected_rx => maps:get(rx, Row, -1)}
    end || {I, Row} <- lists:enumerate(0, Schedule)],
    #{version => 1, evidence => <<"finite_endpoint_packets_rtl_witness">>,
        profile => #{module => b(maps:get(top_module, Router)), inputs => profile(Inputs), outputs => profile(Outputs),
            state_bit_budget => 4, packet_bits => 1024, frame_bits => 672},
        endpoints => [maps:with([id, kind, common_mask, common_value, common_fixed_bits], R) || R <- Routes],
        rows => Rows, coverage => coverage(Rows),
        limits => <<"Finite explicit scenario comparison, not a formal fairness proof. Raw endpoint offers/readiness and opaque carrier packets are controlled inputs; native endpoint ownership, host binding coordination, CDC and physical delivery are not executed here.">>}.

%% Explicit winners exercise both rounds and cursor pinning; no reference scheduler computes these choices.
-spec schedule([map()], [packet()], [packet()], hls_type:descriptor()) -> [row()].
schedule(Routes, Outgoing, Incoming, Type) ->
    Data = lists:nth(5, Incoming),
    Ack = hd(Incoming),
    [#{common_mask := Common} | _] = Routes,
    FixedBit = lists:last([I || I <- lists:seq(0, 671), Common band (1 bsl I) =/= 0]),
    TxFrame = maps:get(frame, hd(Outgoing)) bxor (1 bsl FixedBit),
    RxBad = wire(Data, maps:get(wire, Data) bxor (1 bsl (352 + FixedBit))),
    #{classes := [#{codec := FirstClass}, #{codec := SecondClass}]} = lists:nth(5, Routes),
    {error, invalid_frame} = hls_protocol_codec:encode(FirstClass, maps:get(frame, Data) bxor (1 bsl FixedBit)),
    {error, invalid_frame} = hls_protocol_codec:encode(SecondClass, maps:get(frame, Data)),
    Binding = maps:get(binding, Data),
    StaleData = repack(Data#{binding := Binding#endpoint_binding{generation = 1, source_incarnation = 2,
        destination_incarnation = 3}, sequence := 7}, Type),
    StaleAck = repack(Ack#{binding := (maps:get(binding, Ack))#endpoint_binding{generation = 1,
        source_incarnation = 2, destination_incarnation = 3}, sequence := 9}, Type),
    Fair = [row("round_robin_" ++ integer_to_list(I), 255, 1, I rem 8, [<<"eight_offer_round_robin">>])
        || I <- lists:seq(0, 15)],
    Match = [(row("incoming_full_identity_" ++ integer_to_list(I), 0, 0, -1, [<<"all_data_ack_full_identity">>]))#{
        incoming => Packet, rx => I, rx_ready => 255} || {I, Packet} <- lists:enumerate(0, Incoming)],
    Bad = [
        {"wrong_kind", wire(Data, (maps:get(wire, Data) band bnot 255) bor 3)},
        {"ack_to_data_endpoint", repack(Data#{kind := 2, words := 11, slot := 0, frame := 0}, Type)},
        {"data_to_credit_endpoint", repack(Data#{id := maps:get(id, Ack)}, Type)},
        {"unknown_id", wire(Data, (maps:get(wire, Data) band bnot (((1 bsl 32) - 1) bsl 32)) bor (16#ffffffff bsl 32))},
        {"data_short_length", Data#{words := 31}},
        {"ack_long_length", Ack#{words := 12}},
        {"reserved_control", wire(Data, maps:get(wire, Data) bor (1 bsl 16))},
        {"undeclared_slot", wire(Data, (maps:get(wire, Data) band bnot (255 bsl 8)) bor (255 bsl 8))},
        {"ack_nonzero_slot", wire(Ack, maps:get(wire, Ack) bor (1 bsl 8))},
        {"ack_unused_tail", wire(Ack, maps:get(wire, Ack) bor (1 bsl 352))},
        {"source_padding_before_restore", RxBad},
        {"wrong_source_class", wire(Data, maps:get(wire, Data) bxor (1 bsl 8))},
        {"malformed_stale_padding", wire(StaleData, maps:get(wire, StaleData) bxor (1 bsl (352 + FixedBit)))}
    ],
    [cold("initial_cold_reset")] ++ Fair ++ [cold("reset_before_pin_test"),
        (row("pin_selected_offer", 4, 0, 2, [<<"stalled_selection_pinned">>]))#{incoming => Data, rx => 4, rx_ready => 239},
        (row("earlier_offer_cannot_overtake", 21, 0, 2, [<<"stalled_selection_pinned">>, <<"rx_progress_while_tx_stalled">>]))#{
            incoming => Data, rx => 4, rx_ready => 255},
        row("accept_pinned_offer", 21, 1, 2, [<<"stalled_selection_pinned">>]),
        row("next_ack_gets_turn", 21, 1, 4, [<<"eight_offer_round_robin">>]),
        row("wrap_to_waiting_data", 21, 1, 0, [<<"eight_offer_round_robin">>]),
        row("next_data_gets_turn", 21, 1, 2, [<<"eight_offer_round_robin">>])
    ] ++ Match ++ [
        (row("rx_selected_endpoint_backpressure", 0, 0, -1, [<<"selected_receive_backpressure">>]))#{incoming => Data, rx => 4, rx_ready => 239},
        (row("rx_selected_endpoint_release", 0, 0, -1, [<<"selected_receive_backpressure">>]))#{incoming => Data, rx => 4, rx_ready => 255},
        (row("stale_data_passed_unchanged", 0, 0, -1, [<<"stale_identity_delegated">>]))#{incoming => StaleData, rx => 4, rx_ready => 255},
        (row("stale_ack_passed_unchanged", 0, 0, -1, [<<"stale_identity_delegated">>]))#{incoming => StaleAck, rx => 0, rx_ready => 255}
    ] ++ lists:append([[cold(Label ++ "_reset"),
        (row(Label, 255, 1, -1, [<<"malformed_route_kind_length_reserved_slot_padding">>] ++ case Label of
            "source_padding_before_restore" -> [<<"canonical_before_restore">>];
            "malformed_stale_padding" -> [<<"canonical_before_restore">>];
            _ -> []
        end))#{incoming => Packet, rx => -1, rx_ready => 255},
        (row(Label ++ "_sticky", 255, 1, -1, [<<"sticky_fault_requires_cold_reset">>]))#{incoming => Data, rx => -1, rx_ready => 255, fault => 1}
    ] || {Label, Packet} <- Bad]) ++ [cold("tx_shape_fault_reset"),
        (row("tx_fault_allows_independent_rx_edge", 1, 1, -1, [<<"tx_fault_detection_edge_rx_transfer">>, <<"tx_canonical_validation">>]))#{
            frames => #{0 => TxFrame}, incoming => Data, rx => 4, rx_ready => 255},
        (row("tx_fault_next_edge_closes_both", 255, 1, -1, [<<"tx_fault_detection_edge_rx_transfer">>, <<"sticky_fault_requires_cold_reset">>]))#{
            incoming => Data, rx => -1, rx_ready => 255, fault => 1},
        cold("carrier_fault_reset"),
        (row("carrier_fault_immediate_fence", 255, 1, -1, [<<"carrier_fault_fences">>]))#{
            carrier_fault => 1, incoming => Data, rx => -1, rx_ready => 255},
        (row("carrier_recovery_does_not_rearm", 255, 1, -1, [<<"carrier_fault_fences">>, <<"sticky_fault_requires_cold_reset">>]))#{
            incoming => Data, rx => -1, rx_ready => 255, fault => 1},
        cold("only_cold_reset_rearms"), row("post_reset_data_progress", 255, 1, 0, [<<"sticky_fault_requires_cold_reset">>]),
        row("finite_quiet_tail", 0, 0, -1, [<<"finite_quiet_tail">>])
    ].

%% Every ordinary scenario declares its expected winner directly.
-spec row(string(), byte(), 0 | 1, -1..7, [binary()]) -> row().
row(Label, Offers, Ready, Tx, Covers) -> #{label => b(Label), offers => Offers, ready => Ready, tx => Tx, covers => Covers}.

%% Reset is deliberately asserted while offers exist, checking that no ownership handshake escapes.
-spec cold(string()) -> row().
cold(Label) -> (row(Label, 255, 1, -1, [<<"cold_reset_masks_handshakes">>]))#{reset => 1}.

%% Packet vectors are independent native record packing plus the explicit fixed wire envelope.
-spec packet(map(), non_neg_integer(), incoming | outgoing, hls_type:descriptor()) -> packet().
packet(#{id := Id, kind := Local, classes := Classes}, Index, Direction, Type) ->
    Data = (Local =:= tx) =:= (Direction =:= outgoing),
    Slot = case Data of true -> Index rem 2; false -> 0 end,
    #{codec := Codec = #{payload_bits := Bits}} = lists:nth(Slot + 1, Classes),
    Payload = ((1 bsl Bits) - 1) bxor (Index band ((1 bsl Bits) - 1)),
    Frame = case Data of true -> hls_protocol_codec:decode(Codec, Payload); false -> 0 end,
    case Data of true -> {ok, Payload} = hls_protocol_codec:encode(Codec, Frame); false -> ok end,
    repack(#{id => Id, kind => case Data of true -> 1; false -> 2 end,
        binding => #endpoint_binding{namespace = 16#9000000000000000 + Id, generation = (1 bsl 40) + Index + 1,
            source_incarnation = (1 bsl 48) + Index + 17, destination_incarnation = (1 bsl 56) + Index + 33},
        sequence => 16#80000001 + Index, slot => Slot, frame => Frame,
        words => case Data of true -> 32; false -> 11 end, wire => 0}, Type).

%% The retained binding provider, not a second field-order table, supplies all 256 identity bits.
-spec repack(packet(), hls_type:descriptor()) -> packet().
repack(Packet = #{id := Id, kind := Kind, binding := Binding, sequence := Sequence, slot := Slot, frame := Frame}, Type) ->
    BindingBytes = hls_type:pack(Binding, Type),
    Bytes = <<((Slot bsl 8) bor Kind):32/little, Id:32/little, BindingBytes/binary, Sequence:32/little, Frame:672/little>>,
    Packet#{wire := binary:decode_unsigned(Bytes, little)}.

%% Adversarial bytes preserve their semantic fixture only for labels; rejected payload fields are never expected as valid.
-spec wire(packet(), non_neg_integer()) -> packet().
wire(Packet, Wire) -> Packet#{wire := Wire}.

%% Every offered packet stays fixed while valid; only explicit fault scenarios override one DATA frame.
-spec input(row(), [packet()], [map()]) -> pins().
input(Row, Outgoing, Routes) ->
    Incoming = maps:get(incoming, Row, #{wire => 0, words => 0}),
    Base = #{"reset" => maps:get(reset, Row, 0), "carrier_fault" => maps:get(carrier_fault, Row, 0),
        "packet_tx_ready" => maps:get(ready, Row), "packet_rx" => maps:get(wire, Incoming),
        "packet_rx_words" => maps:get(words, Incoming), "packet_rx_valid" => bit(maps:is_key(incoming, Row))},
    lists:foldl(fun({Index, {Packet, #{id := Id, kind := Kind}}}, Acc) ->
        Prefix = prefix(Id), Name = case Kind of tx -> "tx_"; rx -> "ack_" end,
        Ready = case Kind of tx -> "credit_ready"; rx -> "data_ready" end,
        Offered = maps:merge(binding_pins(Prefix ++ Name, maps:get(binding, Packet)), #{
            Prefix ++ Name ++ "valid" => bit(maps:get(offers, Row) band (1 bsl Index) =/= 0),
            Prefix ++ Name ++ "sequence" => maps:get(sequence, Packet),
            Prefix ++ Ready => bit(maps:get(rx_ready, Row, 255) band (1 bsl Index) =/= 0)}),
        Data = case Kind of
            rx -> #{};
            tx -> #{Prefix ++ "tx_slot" => maps:get(slot, Packet),
                Prefix ++ "tx_frame" => maps:get(Index, maps:get(frames, Row, #{}), maps:get(frame, Packet))}
        end,
        maps:merge(Acc, maps:merge(Offered, Data))
    end, Base, lists:enumerate(0, lists:zip(Outgoing, Routes))).

%% Expected ownership flags come from explicit winners; packet bytes come from the independent format reference.
-spec expected(row(), [{string(), pos_integer()}], [packet()], [map()]) -> {pins(), pins()}.
expected(Row, Outputs, Outgoing, Routes) ->
    Values = maps:from_list([{Name, 0} || {Name, _} <- Outputs]),
    Mask = maps:from_list([{Name, 0} || {Name, _} <- Outputs]),
    Tx = maps:get(tx, Row), Rx = maps:get(rx, Row, -1),
    Controls = #{"packet_tx_valid" => bit(Tx >= 0),
        "packet_rx_ready" => bit(Rx >= 0 andalso maps:get(rx_ready, Row, 255) band (1 bsl Rx) =/= 0),
        "router_fault" => maps:get(fault, Row, 0)},
    ExpectedControls = lists:foldl(fun({Index, #{id := Id, kind := Kind}}, Acc) ->
        Prefix = prefix(Id),
        {Ready, Valid} = case Kind of tx -> {"data_tx_ready", "credit_valid"}; rx -> {"ack_tx_ready", "data_valid"} end,
        Acc#{Prefix ++ Ready => bit(Index =:= Tx andalso maps:get(ready, Row) =:= 1), Prefix ++ Valid => bit(Index =:= Rx)}
    end, Controls, lists:enumerate(0, Routes)),
    TxFields = case Tx of
        -1 -> #{};
        _ -> Packet = lists:nth(Tx + 1, Outgoing), #{"packet_tx" => maps:get(wire, Packet), "packet_tx_words" => maps:get(words, Packet)}
    end,
    RxFields = case Rx of
        -1 -> #{};
        _ -> #{id := Id, kind := Kind} = lists:nth(Rx + 1, Routes),
            Incoming = maps:get(incoming, Row),
            P = prefix(Id) ++ case Kind of tx -> "credit_"; rx -> "data_" end,
            Fields = (binding_pins(P, maps:get(binding, Incoming)))#{P ++ "sequence" => maps:get(sequence, Incoming)},
            case Kind of tx -> Fields; rx -> Fields#{P ++ "slot" => maps:get(slot, Incoming), P ++ "frame" => maps:get(frame, Incoming)} end
    end,
    Checked = maps:merge(ExpectedControls, maps:merge(TxFields, RxFields)),
    {maps:merge(Values, Checked), maps:merge(Mask, maps:from_list([{Name, (1 bsl proplists:get_value(Name, Outputs)) - 1}
        || Name <- maps:keys(Checked)]))}.

%% Named packet identity fields expose every native binding bit to comparison.
-spec binding_pins(string(), #endpoint_binding{}) -> pins().
binding_pins(P, #endpoint_binding{namespace = N, generation = G, source_incarnation = S, destination_incarnation = D}) ->
    #{P ++ "namespace" => N, P ++ "generation" => G, P ++ "source_incarnation" => S, P ++ "destination_incarnation" => D}.

%% Ordered pin vectors are range-checked before serializing values or comparison masks.
-spec pack([{string(), pos_integer()}], pins()) -> non_neg_integer().
pack(Pins, Values) -> lists:foldl(fun({Name, Width}, Acc) -> Value = maps:get(Name, Values),
    true = Value >= 0 andalso Value < (1 bsl Width), (Acc bsl Width) bor Value end, 0, Pins).

%% The generated interface, not a guessed packed ABI, names every vector field.
-spec profile([{string(), pos_integer()}]) -> [map()].
profile(Pins) -> [#{name => b(Name), width => Width} || {Name, Width} <- Pins].

%% Scenario names point to actual finite rows rather than unchecked coverage assertions.
-spec coverage([map()]) -> map().
coverage(Rows) -> lists:foldl(fun({Index, #{covers := Names}}, Acc) -> lists:foldl(fun(Name, M) ->
    maps:update_with(Name, fun(Indices) -> Indices ++ [Index] end, [Index], M)
end, Acc, lists:usort(Names)) end, #{}, lists:enumerate(0, Rows)).

%% Static full-width channel IDs match the production raw endpoint naming convention.
-spec prefix(hls_nums:u32()) -> string().
prefix(Id) -> "endpoint_" ++ integer_to_list(Id) ++ "_".

%% Trace pins encode explicit one-bit decisions.
-spec bit(boolean()) -> 0 | 1.
bit(true) -> 1;
bit(false) -> 0.

%% Hex strings preserve arbitrary-width vectors in ordinary JSON readers.
-spec hex(non_neg_integer()) -> binary().
hex(Value) -> integer_to_binary(Value, 16).

%% Labels and profile names are portable UTF-8 strings.
-spec b(string()) -> binary().
b(Value) -> unicode:characters_to_binary(Value).
