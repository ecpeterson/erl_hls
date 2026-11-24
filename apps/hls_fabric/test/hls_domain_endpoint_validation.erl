-module(hls_domain_endpoint_validation).
-moduledoc "Builds a fresh two-unit endpoint bundle and finite native reference traces. Independent sampled clocks, retained payloads and adversarial packets are simulation-witness inputs; only the external RTL runner supplies a comparison verdict. This fixture establishes neither arbitrary-history equivalence, physical CDC behavior nor recovery progress.".
-include_lib("hls_runtime/include/hls_domain_channel_endpoints.hrl").

%% Fixture publication does not invoke XLS or a simulator.
-export([write/1]).

%% Trace fields follow the emitted public pin names and widths.
-type direction() :: hls_domain_endpoint_build:direction().
%% Each edge supplies one native input plus the wrapper's external payload pins.
-type input() :: #endpoint_tx_input{} | #endpoint_rx_input{}.
%% Selected assertions ensure each schedule reaches its intended ownership event.
-type checks() :: #{string() => non_neg_integer() | boolean() | atom()}.
%% Cold-reset observations are masked; the following ordinary edge is fully checked.
-type event() :: {direction(), string(), input(), non_neg_integer(), hls_nums:u8(), boolean(), checks()}.
%% The sole external payload register survives ordinary local lifecycle retirement.
-type shadow() :: #{state := #endpoint_tx_state{} | #endpoint_rx_state{}, frame := non_neg_integer(), slot := hls_nums:u8()}.
%% Pin maps are numeric, including booleans and type-provider status codes.
-type pins() :: #{string() => non_neg_integer()}.
%% Both interfaces remain source-derived throughout reference generation.
-type interfaces() :: #{tx := hls_domain_endpoint_build:result(), rx := hls_domain_endpoint_build:result()}.

-doc "Writes a fresh endpoint-only source bundle, native traces and separate TX/RX support snapshots. TX controller capacity is source-derived independently of RX and the twenty-word data frame. Rejects existing output and any unmet native scenario assertion. The normal compile_source_build driver and tools/hls_fabric/test_domain_endpoints.py consume the result separately; this function runs neither.".
-spec write(file:filename()) -> map().
write(Directory) ->
    #{files := TxFiles, result := Tx} = hls_domain_endpoint_build:emit(tx, 20),
    #{files := RxFiles, result := Rx} = hls_domain_endpoint_build:emit(rx, 20),
    Interfaces = #{tx => Tx, rx => Rx},
    Trace = trace(Interfaces),
    Files = hls_generated_files:merge([TxFiles, RxFiles, native_sources(), #{
        "endpoint-trace.json" => json:encode(Trace),
        "interface.etf" => term_to_binary(Interfaces)
    }]),
    _ = hls_generated_files:write(#{files => Files, result => Interfaces}, Directory),
    #{libraries := Libraries, imports := Imports} = hls_compile:support_layout([]),
    Units = [unit(Directory, maps:get(Role, Interfaces), Libraries, Imports) || Role <- [tx, rx]],
    hls_artifact_bundle:finish(Directory, Units, #{
        kind => independent_domain_endpoint_witness,
        evidence => <<"Simulation witness inputs; RTL verdict is external">>,
        frame_payload_words => 20,
        controller_words => #{tx => maps:get(controller_words, Tx), rx => maps:get(controller_words, Rx)},
        reference_edges => length(maps:get(rows, Trace))
    }).

%% Retain the exact native reference inputs beside generated artifacts for audit and replay.
-spec native_sources() -> hls_generated_files:files().
native_sources() ->
    SourceNames = ["hls_domain_channel_tx.erl", "hls_domain_channel_rx.erl",
        "hls_domain_channel_binding.erl"],
    Sources = [{Name, hls_source:library_file(hls_runtime, "fabric/runtime/domain/" ++ Name)}
        || Name <- SourceNames] ++ [
        {"hls_domain_channel_endpoints.hrl", filename:join([code:lib_dir(hls_runtime),
            "include", "hls_domain_channel_endpoints.hrl"])},
        {"hls_domain_endpoint_validation.erl", filename:absname(?FILE)}
    ],
    maps:from_list([begin
        {ok, Bytes} = file:read_file(Path),
        {"evidence/native/" ++ Name, Bytes}
    end || {Name, Path} <- Sources]).

%% Each unit resolves its own controller ABI, never the peer's or application frame profile.
-spec unit(file:filename(), hls_domain_endpoint_build:result(), [hls_artifact_bundle:library()], [binary()]) -> hls_artifact_bundle:unit().
unit(Directory, #{dependency_directory := Name, controller_words := Words,
        clock_proc := Clock, core_module := Core}, Libraries, Imports) ->
    Root = filename:join(Directory, Name),
    Layout = hls_frame_layout:new(Words),
    ok = hls_artifact_bundle:snapshot(Root, Libraries),
    ok = hls_compile:configure_support(Root, Layout),
    #{
        role => <<".">>, directory => b(Name), source => b(Name ++ "/" ++ Name ++ ".x"),
        top => b(Clock), module => b(Core), output => b(Name ++ "/core.v"),
        dslx_path => [b(Name) | [b(Name ++ "/" ++ binary_to_list(P)) || P <- Imports]],
        rtl => [b(Name ++ "/core.v"), b(Name ++ "/" ++ Name ++ ".sv")],
        codegen_flags => hls_build_profile:flags(hls_build_profile:owner(Layout), sampled_clock)
    }.

%% The schedule is finite and clocks only one endpoint per row at irregular intervals.
-spec trace(interfaces()) -> map().
trace(Interfaces) ->
    Initial = #{tx => cold(tx), rx => cold(rx)},
    {_, Reversed, _} = lists:foldl(fun(Event, {States, Rows, Index}) ->
        {Next, Row} = edge(Event, States, Interfaces, Index),
        {Next, [Row | Rows], Index + 1}
    end, {Initial, [], 0}, schedule()),
    #{
        version => 1,
        evidence => <<"finite_native_rtl_witness">>,
        profiles => maps:map(fun(_, Interface) -> profile(Interface) end, Interfaces),
        rows => lists:reverse(Reversed),
        scenarios => [
            <<"independent_clocks_and_stalls">>, <<"receiver_confirmation">>,
            <<"retained_payload_and_ack_after_capture">>, <<"stale_and_duplicate_packets">>,
            <<"local_retirement_and_incarnation_rebind">>,
            <<"premature_ack_and_future_data_fail_closed">>, <<"exact_fence">>,
            <<"cold_namespace_replacement">>,
            <<"partial_bind_generation_gap_recovery">>,
            <<"generation_gaps_and_exhaustion">>
        ]
    }.

%% Numeric bit order is exactly the named-pin adapter's ordered concatenation.
-spec profile(hls_domain_endpoint_build:result()) -> map().
profile(#{inputs := Inputs, outputs := Outputs, top_module := Module,
        controller_words := Words, frame_bits := FrameBits}) ->
    #{module => b(Module), controller_words => Words, frame_bits => FrameBits,
        inputs => [#{name => b(Name), width => Width} || {Name, Width} <- Inputs],
        outputs => [#{name => b(Name), width => Width} || {Name, Width} <- Outputs]}.

%% Reference outputs use the native kernel and old wrapper storage before one local edge.
-spec edge(event(), #{tx := shadow(), rx := shadow()}, interfaces(), non_neg_integer()) ->
    {#{tx := shadow(), rx := shadow()}, map()}.
edge({Role, Label, Input, Frame, Slot, Reset, Checks}, States, Interfaces, Index) ->
    Interface = #{inputs := InputPins, outputs := OutputPins} = maps:get(Role, Interfaces),
    Inputs = input_pins(Input, Frame, Slot, Reset),
    {Next, Expected, Mask} = case Reset of
        true -> {cold(Role), 0, 0};
        false ->
            {Successor, Outputs} = model(Role, Input, Frame, Slot, maps:get(Role, States), Interface),
            check(Label, Checks, Outputs, Interface),
            {Successor, pack(OutputPins, Outputs), (1 bsl width(OutputPins)) - 1}
    end,
    {States#{Role := Next}, #{role => atom_to_binary(Role), label => b(Label),
        delay => 2 + ((Index * 7) rem 9), input => hex(pack(InputPins, Inputs)),
        expected => hex(Expected), mask => hex(Mask)}}.

%% Cold reset alone forgets both metadata tombstones and the external payload bits.
-spec cold(direction()) -> shadow().
cold(tx) -> #{state => hls_domain_channel_tx:new(), frame => 0, slot => 0};
cold(rx) -> #{state => hls_domain_channel_rx:new(), frame => 0, slot => 0}.

%% TX publication storage changes only when the native source_take event occurs.
-spec model(direction(), input(), non_neg_integer(), hls_nums:u8(), shadow(), hls_domain_endpoint_build:result()) -> {shadow(), pins()}.
model(tx, Input = #endpoint_tx_input{}, Frame, Slot,
        Old = #{state := State = #endpoint_tx_state{}, frame := Held, slot := HeldSlot}, Interface) ->
    Output = hls_domain_channel_tx:step(Input, State),
    #endpoint_tx_output{state = Next, source_take = Take, tx_valid = Valid,
        credit_ready = Ready, credit_drop = Drop, packet = Packet, status = Status} = Output,
    Pins = maps:merge(packet_pins("tx_", Packet), #{
        "source_ready" => bit(Take), "source_take" => bit(Take), "tx_valid" => bit(Valid),
        "tx_frame" => Held, "tx_slot" => HeldSlot,
        "credit_ready" => bit(Ready), "credit_drop" => bit(Drop)
    }),
    {retain(Old#{state := Next}, Take, Frame, Slot), maps:merge(Pins,
        observed(Next#endpoint_tx_state.binding, Next#endpoint_tx_state.sequence,
            Next#endpoint_tx_state.active, Status, Interface))};
%% RX network capture fills storage; native delivery and ACK observe that retained publication.
model(rx, Input = #endpoint_rx_input{}, Frame, Slot,
        Old = #{state := State = #endpoint_rx_state{}, frame := Held, slot := HeldSlot}, Interface) ->
    #endpoint_rx_output{state = Next, data_ready = Ready, data_take = Take, data_drop = Drop,
        destination_valid = Valid, destination_take = Deliver, ack_valid = Ack,
        packet = Packet, status = Status} = hls_domain_channel_rx:step(Input, State),
    Pins = maps:merge(packet_pins("ack_", Packet), #{
        "data_ready" => bit(Ready), "data_take" => bit(Take), "data_drop" => bit(Drop),
        "destination_valid" => bit(Valid), "destination_take" => bit(Deliver),
        "destination_frame" => Held, "destination_slot" => HeldSlot, "ack_valid" => bit(Ack)
    }),
    {retain(Old#{state := Next}, Take, Frame, Slot), maps:merge(Pins,
        observed(Next#endpoint_rx_state.binding, Next#endpoint_rx_state.sequence,
            Next#endpoint_rx_state.active, Status, Interface))}.

%% This shadow has one writer, no queue and no clearing on retirement or rebind.
-spec retain(shadow(), boolean(), non_neg_integer(), hls_nums:u8()) -> shadow().
retain(State, false, _Frame, _Slot) -> State;
retain(State, true, Frame, Slot) -> State#{frame := Frame, slot := Slot}.

%% Native execution has no compiler failure; a nonzero RTL failure therefore mismatches.
-spec observed(#endpoint_binding{}, hls_nums:u32(), boolean(), endpoint_status(), hls_domain_endpoint_build:result()) -> pins().
observed(Binding, Sequence, Active, Status, Interface) ->
    maps:merge(binding_pins("bound_", Binding), #{
        "packet_sequence" => Sequence, "active" => bit(Active),
        "status" => status(Status, Interface), "fault" => 0, "failure" => 0
    }).

%% Input adapters expose only the records' explicit local lifecycle and packet fields.
-spec input_pins(input(), non_neg_integer(), hls_nums:u8(), boolean()) -> pins().
input_pins(#endpoint_tx_input{op = Op, binding = Binding, receiver_binding = Receiver,
        receiver_active = Active, local_ready = Ready, local_incarnation = Incarnation,
        source_valid = Valid, data_tx_ready = TxReady, credit_valid = CreditValid,
        credit_packet = Credit}, Frame, Slot, Reset) ->
    merge([control_pins(Op, Binding, Ready, Incarnation, Reset), binding_pins("receiver_", Receiver),
        packet_pins("credit_", Credit), #{
            "receiver_active" => bit(Active), "source_valid" => bit(Valid),
            "source_frame" => Frame, "source_slot" => Slot,
            "data_tx_ready" => bit(TxReady), "credit_valid" => bit(CreditValid)
        }]);
input_pins(#endpoint_rx_input{op = Op, binding = Binding, local_ready = Ready,
        local_incarnation = Incarnation, data_valid = Valid, data_packet = Packet,
        destination_ready = DestinationReady, ack_tx_ready = AckReady}, Frame, Slot, Reset) ->
    merge([control_pins(Op, Binding, Ready, Incarnation, Reset), packet_pins("data_", Packet), #{
        "data_valid" => bit(Valid), "data_frame" => Frame, "data_slot" => Slot,
        "destination_ready" => bit(DestinationReady), "ack_tx_ready" => bit(AckReady)
    }]).

%% Bind and fence are disjoint management commands in every fixture event.
-spec control_pins(endpoint_operation(), #endpoint_binding{}, boolean(), hls_nums:u64(), boolean()) -> pins().
control_pins(Op, Binding, Ready, Incarnation, Reset) ->
    maps:merge(binding_pins("", Binding), #{
        "reset" => bit(Reset), "bind_request" => bit(Op =:= bind), "fence" => bit(Op =:= fence),
        "local_ready" => bit(Ready), "local_incarnation" => Incarnation
    }).

%% No identity field is compressed, inferred from the peer or omitted from comparison.
-spec binding_pins(string(), #endpoint_binding{}) -> pins().
binding_pins(Prefix, #endpoint_binding{namespace = Namespace, generation = Generation,
        source_incarnation = Source, destination_incarnation = Destination}) ->
    #{Prefix ++ "namespace" => Namespace, Prefix ++ "generation" => Generation,
        Prefix ++ "source_incarnation" => Source, Prefix ++ "destination_incarnation" => Destination}.

%% ACK and data packets use the identical complete binding-plus-sequence identity.
-spec packet_pins(string(), #endpoint_packet{}) -> pins().
packet_pins(Prefix, #endpoint_packet{binding = Binding, sequence = Sequence}) ->
    (binding_pins(Prefix, Binding))#{Prefix ++ "sequence" => Sequence}.

%% Catch vacuous schedules before emitting expected RTL observations.
-spec check(string(), checks(), pins(), hls_domain_endpoint_build:result()) -> ok.
check(Label, Checks, Outputs, Interface) ->
    maps:foreach(fun(Name, Value) ->
        Want = case Name of "status" -> status(Value, Interface); _ -> bit(Value) end,
        case maps:get(Name, Outputs) of
            Want -> ok;
            Got -> error({endpoint_witness_expectation, Label, Name, Want, Got})
        end
    end, Checks).

%% Status codes come from the same source-derived provider retained by emission.
-spec status(endpoint_status(), hls_domain_endpoint_build:result()) -> non_neg_integer().
status(Value, #{codecs := #{status := Descriptor}}) ->
    Width = hls_type:width(Descriptor),
    <<Code:Width>> = hls_type:pack(Value, Descriptor),
    Code.

%% All public pins are checked for width before mechanical MSB-first concatenation.
-spec pack([{string(), pos_integer()}], pins()) -> non_neg_integer().
pack(Pins, Values) ->
    lists:foldl(fun({Name, Width}, Acc) ->
        Value = maps:get(Name, Values),
        true = Value >= 0 andalso Value < (1 bsl Width),
        (Acc bsl Width) bor Value
    end, 0, Pins).

%% Width sums define full-output comparison masks, including retained inactive payload bits.
-spec width([{string(), pos_integer()}]) -> pos_integer().
width(Pins) -> lists:sum([Width || {_, Width} <- Pins]).

%% Reference pin values are integers; named scenario checks may use booleans.
-spec bit(non_neg_integer() | boolean()) -> non_neg_integer().
bit(true) -> 1;
bit(false) -> 0;
bit(Value) -> Value.

%% Keep pin groups explicit without imposing another packed representation.
-spec merge([pins()]) -> pins().
merge(Maps) -> lists:foldl(fun maps:merge/2, #{}, Maps).

%% JSON hex strings preserve wide vectors without a consumer's numeric precision limit.
-spec hex(non_neg_integer()) -> binary().
hex(Value) -> integer_to_binary(Value, 16).

%% Manifest and trace text use portable UTF-8 strings.
-spec b(string()) -> binary().
b(Value) -> unicode:characters_to_binary(Value).

%% Fixture identities are nonzero; both local lifetimes advance on every warm rebind.
-spec binding(pos_integer(), pos_integer(), pos_integer(), pos_integer()) -> #endpoint_binding{}.
binding(Namespace, Generation, Source, Destination) ->
    #endpoint_binding{namespace = Namespace, generation = Generation,
        source_incarnation = Source, destination_incarnation = Destination}.

%% Native source ticks carry host confirmation, which the kernel consults only on bind.
-spec tx(#endpoint_binding{}) -> #endpoint_tx_input{}.
tx(Binding) -> #endpoint_tx_input{binding = Binding, receiver_binding = Binding,
    receiver_active = true, local_ready = true,
    local_incarnation = Binding#endpoint_binding.source_incarnation}.

%% Native destination ticks observe only the local destination lifetime.
-spec rx(#endpoint_binding{}) -> #endpoint_rx_input{}.
rx(Binding) -> #endpoint_rx_input{binding = Binding, local_ready = true,
    local_incarnation = Binding#endpoint_binding.destination_incarnation}.

%% A checked packet fixture names one publication within the selected binding.
-spec packet(#endpoint_binding{}, hls_nums:u32()) -> #endpoint_packet{}.
packet(Binding, Sequence) -> #endpoint_packet{binding = Binding, sequence = Sequence}.

%% Full-capacity canonical frames vary every word, including their high stored bits.
-spec payload(hls_nums:u8()) -> non_neg_integer().
payload(Marker) ->
    Bytes = iolist_to_binary([<<(Marker * 16#10001 + I * 16#10203):32/little>> || I <- lists:seq(1, 20)]),
    hls_frame_layout:pack_integer(hls_frame_layout:new(20), #{op => 3, txid => Marker, flags => 0}, Bytes).

%% Ordinary ticks may mutate irrelevant carrier payload pins to challenge retained storage.
-spec t(string(), #endpoint_tx_input{}, checks()) -> event().
t(Label, Input, Checks) -> t(Label, Input, 0, 0, Checks).

%% Source payload and slot are external to the native ownership metadata.
-spec t(string(), #endpoint_tx_input{}, non_neg_integer(), hls_nums:u8(), checks()) -> event().
t(Label, Input, Frame, Slot, Checks) -> {tx, Label, Input, Frame, Slot, false, Checks}.

%% Destination control events default to a zero current carrier offer.
-spec r(string(), #endpoint_rx_input{}, checks()) -> event().
r(Label, Input, Checks) -> r(Label, Input, 0, 0, Checks).

%% Carrier payload enters the shadow only on a native data_take event.
-spec r(string(), #endpoint_rx_input{}, non_neg_integer(), hls_nums:u8(), checks()) -> event().
r(Label, Input, Frame, Slot, Checks) -> {rx, Label, Input, Frame, Slot, false, Checks}.

%% Explicit assertion sets cover both blocked and accepted edges, without assuming progress.
-spec schedule() -> [event()].
schedule() ->
    B = binding(7, 1, 10, 20), F = binding(7, 2, 11, 21), G = binding(7, 3, 12, 22),
    C = binding(8, 1, 100, 200), Wrong = binding(8, 1, 10, 20),
    A = payload(1), P = payload(2), Q = payload(3), D = payload(4), E = payload(5),
    Tx = tx(B), Rx = rx(B), FT = tx(F), FR = rx(F), GT = tx(G), GR = rx(G),
    CT = tx(C), CR = rx(C), One = packet(B, 1), Two = packet(B, 2), Fresh = packet(F, 1),
    [
        {tx, "cold_tx", Tx, 0, 0, true, #{}},
        {rx, "cold_rx", Rx, 0, 0, true, #{}},
        t("closed_tx", Tx, #{"status" => closed, "credit_ready" => true, "tx_frame" => 0}),
        r("closed_rx", Rx, #{"status" => closed, "data_ready" => true, "destination_frame" => 0}),
        t("unconfirmed_rx_rejects_tx_bind", Tx#endpoint_tx_input{op = bind, receiver_active = false}, #{"status" => busy, "active" => false}),
        r("bind_rx_first", Rx#endpoint_rx_input{op = bind}, #{"status" => accepted, "active" => true}),
        t("confirm_rx_then_bind_tx", Tx#endpoint_tx_input{op = bind}, #{"status" => accepted, "active" => true}),
        t("capture_first_publication", Tx#endpoint_tx_input{source_valid = true, data_tx_ready = true}, A, 9, #{"source_take" => true, "tx_valid" => false}),
        r("rx_idle_on_separate_clock", Rx, #{"destination_valid" => false, "ack_valid" => false}),
        t("tx_stall_one", Tx#endpoint_tx_input{source_valid = true}, P, 17, #{"source_take" => false, "tx_valid" => true, "tx_frame" => A, "tx_slot" => 9}),
        t("tx_stall_two", Tx, Q, 18, #{"tx_valid" => true, "tx_frame" => A}),
        r("rx_still_idle", Rx, #{"destination_valid" => false}),
        t("whole_packet_handoff", Tx#endpoint_tx_input{data_tx_ready = true}, #{"tx_valid" => true, "tx_frame" => A}),
        r("network_capture_is_not_native_capture", Rx#endpoint_rx_input{data_valid = true, data_packet = One, destination_ready = true, ack_tx_ready = true}, A, 9, #{"data_take" => true, "destination_take" => false, "ack_valid" => false}),
        t("missing_ack_retains_publication", Tx#endpoint_tx_input{source_valid = true}, P, 17, #{"source_take" => false, "tx_valid" => false, "tx_frame" => A}),
        r("duplicate_cannot_overwrite_payload", Rx#endpoint_rx_input{data_valid = true, data_packet = One, ack_tx_ready = true}, P, 17, #{"data_drop" => true, "data_take" => false, "destination_valid" => true, "destination_frame" => A, "destination_slot" => 9, "ack_valid" => false}),
        r("native_stall_one", Rx, Q, 18, #{"destination_valid" => true, "destination_frame" => A, "ack_valid" => false}),
        t("tx_waits_independently", Tx, #{"tx_valid" => false, "tx_frame" => A}),
        r("native_stall_two", Rx, D, 19, #{"destination_valid" => true, "destination_frame" => A}),
        r("native_capture_precedes_ack", Rx#endpoint_rx_input{destination_ready = true, ack_tx_ready = true}, #{"destination_take" => true, "destination_frame" => A, "ack_valid" => false}),
        r("ack_stall_one", Rx, #{"ack_valid" => true, "ack_sequence" => 1, "destination_valid" => false}),
        t("wrong_binding_ack_drops", Tx#endpoint_tx_input{credit_valid = true, credit_packet = packet(Wrong, 1)}, #{"credit_drop" => true, "source_take" => false}),
        r("duplicate_during_ack_stall", Rx#endpoint_rx_input{data_valid = true, data_packet = One}, D, 19, #{"data_drop" => true, "ack_valid" => true, "destination_frame" => A}),
        r("ack_handoff", Rx#endpoint_rx_input{ack_tx_ready = true}, #{"ack_valid" => true}),
        r("no_ack_replay", Rx#endpoint_rx_input{data_valid = true, data_packet = One}, #{"data_drop" => true, "ack_valid" => false}),
        t("exact_ack_releases_on_separate_edge", Tx#endpoint_tx_input{credit_valid = true, credit_packet = One, source_valid = true}, P, 17, #{"credit_drop" => false, "source_take" => false}),
        t("duplicate_ack_drops", Tx#endpoint_tx_input{credit_valid = true, credit_packet = One}, #{"credit_drop" => true}),
        t("capture_second_publication", Tx#endpoint_tx_input{source_valid = true}, P, 17, #{"source_take" => true, "tx_sequence" => 2}),
        t("second_packet_handoff", Tx#endpoint_tx_input{data_tx_ready = true}, #{"tx_valid" => true, "tx_frame" => P, "tx_slot" => 17}),
        r("wrong_binding_data_drops", Rx#endpoint_rx_input{data_valid = true, data_packet = packet(Wrong, 2)}, D, 19, #{"data_drop" => true, "data_take" => false, "active" => true}),
        r("capture_second_packet", Rx#endpoint_rx_input{data_valid = true, data_packet = Two}, P, 17, #{"data_take" => true, "destination_valid" => false}),
        r("local_retirement_suppresses_capture_and_ack", Rx#endpoint_rx_input{local_ready = false, destination_ready = true, ack_tx_ready = true, data_valid = true, data_packet = packet(B, 3)}, Q, 18, #{"status" => closed, "active" => false, "data_ready" => false, "destination_take" => false, "ack_valid" => false, "destination_frame" => P}),
        t("tx_does_not_infer_remote_failure", Tx#endpoint_tx_input{source_valid = true}, Q, 18, #{"active" => true, "source_take" => false, "tx_frame" => P}),
        t("local_incarnation_retires_tx", Tx#endpoint_tx_input{local_incarnation = 11, credit_valid = true, credit_packet = Two}, #{"status" => closed, "active" => false, "credit_ready" => false, "tx_frame" => P}),
        r("old_local_binding_cannot_reactivate", Rx#endpoint_rx_input{op = bind, local_incarnation = 21}, #{"status" => busy, "active" => false, "destination_frame" => P}),
        r("replacement_rx_binds_first", FR#endpoint_rx_input{op = bind}, #{"status" => accepted, "active" => true, "destination_frame" => P}),
        t("replacement_requires_matching_confirmation", FT#endpoint_tx_input{op = bind, receiver_binding = B}, #{"status" => busy, "active" => false}),
        t("replacement_tx_binds_second", FT#endpoint_tx_input{op = bind}, #{"status" => accepted, "active" => true, "tx_frame" => P}),
        r("old_data_excluded_after_rebind", FR#endpoint_rx_input{data_valid = true, data_packet = Two}, P, 17, #{"data_drop" => true, "data_take" => false, "destination_valid" => false}),
        t("old_ack_excluded_after_rebind", FT#endpoint_tx_input{credit_valid = true, credit_packet = Two}, #{"credit_drop" => true, "source_take" => false}),
        t("replacement_publication", FT#endpoint_tx_input{source_valid = true}, Q, 18, #{"source_take" => true, "tx_sequence" => 1}),
        t("replacement_packet_handoff", FT#endpoint_tx_input{data_tx_ready = true}, #{"tx_valid" => true, "tx_frame" => Q}),
        r("replacement_network_capture", FR#endpoint_rx_input{data_valid = true, data_packet = Fresh}, Q, 18, #{"data_take" => true, "ack_valid" => false}),
        r("replacement_native_capture", FR#endpoint_rx_input{destination_ready = true}, #{"destination_take" => true, "destination_frame" => Q, "ack_valid" => false}),
        r("replacement_ack_handoff", FR#endpoint_rx_input{ack_tx_ready = true}, #{"ack_valid" => true, "ack_sequence" => 1}),
        t("replacement_credit_release", FT#endpoint_tx_input{credit_valid = true, credit_packet = Fresh}, #{"credit_drop" => false}),
        t("capture_before_premature_ack", FT#endpoint_tx_input{source_valid = true}, D, 19, #{"source_take" => true, "tx_sequence" => 2}),
        t("premature_ack_closes_before_handoff", FT#endpoint_tx_input{data_tx_ready = true, credit_valid = true, credit_packet = packet(F, 2)}, #{"status" => invalid, "active" => false, "tx_valid" => false, "credit_ready" => false, "tx_frame" => D}),
        r("future_sequence_closes_before_capture", FR#endpoint_rx_input{data_valid = true, data_packet = packet(F, 3), destination_ready = true}, D, 19, #{"status" => invalid, "active" => false, "data_ready" => false, "data_take" => false, "ack_valid" => false}),
        r("closed_rx_drains_future_packet", FR#endpoint_rx_input{data_valid = true, data_packet = packet(F, 3)}, #{"status" => closed, "data_drop" => true, "destination_frame" => Q}),
        t("closed_tx_drains_credit", FT#endpoint_tx_input{credit_valid = true, credit_packet = packet(F, 2)}, #{"status" => closed, "credit_drop" => true, "tx_frame" => D}),
        r("fence_fixture_rx_rebind", GR#endpoint_rx_input{op = bind}, #{"status" => accepted}),
        t("fence_fixture_tx_rebind", GT#endpoint_tx_input{op = bind}, #{"status" => accepted}),
        t("stale_fence_preserves_replacement", GT#endpoint_tx_input{op = fence, binding = F}, #{"status" => stale, "active" => true}),
        r("exact_rx_fence", GR#endpoint_rx_input{op = fence, data_valid = true, data_packet = packet(G, 1)}, E, 20, #{"status" => accepted, "active" => false, "data_take" => false, "destination_frame" => Q}),
        t("exact_tx_fence", GT#endpoint_tx_input{op = fence, source_valid = true}, E, 20, #{"status" => accepted, "active" => false, "source_take" => false, "tx_frame" => D}),
        {rx, "cold_rx_forgets_old_namespace", GR, 0, 0, true, #{}},
        {tx, "cold_tx_forgets_old_namespace", GT, 0, 0, true, #{}},
        r("cold_rx_storage_cleared", CR, #{"status" => closed, "destination_frame" => 0, "destination_slot" => 0, "bound_namespace" => 0}),
        t("cold_tx_storage_cleared", CT, #{"status" => closed, "tx_frame" => 0, "tx_slot" => 0, "bound_namespace" => 0}),
        r("new_namespace_rx_bind", CR#endpoint_rx_input{op = bind}, #{"status" => accepted, "bound_namespace" => 8}),
        t("new_namespace_tx_bind", CT#endpoint_tx_input{op = bind}, #{"status" => accepted, "bound_namespace" => 8}),
        t("new_namespace_publication", CT#endpoint_tx_input{source_valid = true}, E, 20, #{"source_take" => true}),
        t("new_namespace_handoff", CT#endpoint_tx_input{data_tx_ready = true}, #{"tx_valid" => true, "tx_frame" => E}),
        r("new_namespace_network_capture", CR#endpoint_rx_input{data_valid = true, data_packet = packet(C, 1)}, E, 20, #{"data_take" => true}),
        r("new_namespace_native_capture", CR#endpoint_rx_input{destination_ready = true, ack_tx_ready = true}, #{"destination_take" => true, "ack_valid" => false, "destination_frame" => E}),
        r("new_namespace_ack", CR#endpoint_rx_input{ack_tx_ready = true}, #{"ack_valid" => true}),
        t("new_namespace_release", CT#endpoint_tx_input{credit_valid = true, credit_packet = packet(C, 1)}, #{"credit_drop" => false}),
        t("final_tx_idle", CT, #{"active" => true, "source_take" => false, "tx_valid" => false}),
        r("final_rx_idle", CR, #{"active" => true, "destination_valid" => false, "ack_valid" => false})
    ] ++ generation_gap_schedule().

%% A consumed RX-only bind cannot strand a new group behind mismatched generation counters.
-spec generation_gap_schedule() -> [event()].
generation_gap_schedule() ->
    Partial = binding(9, 1, 30, 40), Fresh = binding(9, 2, 31, 41),
    Gap = binding(9, 7, 32, 42), Last = binding(9, (1 bsl 64) - 1, 33, 43),
    Wrapped = binding(9, 1, 34, 44),
    PT = tx(Partial), PR = rx(Partial), FT = tx(Fresh), FR = rx(Fresh),
    GT = tx(Gap), GR = rx(Gap), LT = tx(Last), LR = rx(Last),
    A = payload(6), Packet = packet(Fresh, 1),
    [
        {tx, "gap_cold_tx", PT, 0, 0, true, #{}},
        {rx, "gap_cold_rx", PR, 0, 0, true, #{}},
        r("rx_only_bind_consumes_generation", PR#endpoint_rx_input{op = bind}, #{"status" => accepted, "bound_generation" => 1}),
        r("owner_loss_fences_rx_only_binding", PR#endpoint_rx_input{op = fence}, #{"status" => accepted, "active" => false}),
        t("tx_remains_unbound_after_partial_start", PT, #{"status" => closed, "bound_generation" => 0}),
        r("fresh_group_rx_after_partial_start", FR#endpoint_rx_input{op = bind}, #{"status" => accepted, "bound_generation" => 2}),
        t("fresh_group_tx_skips_consumed_generation", FT#endpoint_tx_input{op = bind}, #{"status" => accepted, "bound_generation" => 2}),
        r("partial_group_data_remains_stale", FR#endpoint_rx_input{data_valid = true, data_packet = packet(Partial, 1)}, A, 21, #{"data_drop" => true, "data_take" => false}),
        t("partial_group_ack_remains_stale", FT#endpoint_tx_input{credit_valid = true, credit_packet = packet(Partial, 1)}, #{"credit_drop" => true}),
        t("gap_recovery_captures_fresh_publication", FT#endpoint_tx_input{source_valid = true}, A, 21, #{"source_take" => true}),
        t("gap_recovery_handoff", FT#endpoint_tx_input{data_tx_ready = true}, #{"tx_valid" => true, "tx_frame" => A}),
        r("gap_recovery_network_capture", FR#endpoint_rx_input{data_valid = true, data_packet = Packet}, A, 21, #{"data_take" => true}),
        r("gap_recovery_native_capture", FR#endpoint_rx_input{destination_ready = true}, #{"destination_take" => true, "destination_frame" => A}),
        r("gap_recovery_ack_handoff", FR#endpoint_rx_input{ack_tx_ready = true}, #{"ack_valid" => true}),
        t("gap_recovery_ack_release", FT#endpoint_tx_input{credit_valid = true, credit_packet = Packet}, #{"credit_drop" => false}),
        t("gap_fence_tx", FT#endpoint_tx_input{op = fence}, #{"status" => accepted, "active" => false}),
        r("gap_fence_rx", FR#endpoint_rx_input{op = fence}, #{"status" => accepted, "active" => false}),
        r("larger_gap_rx", GR#endpoint_rx_input{op = bind}, #{"status" => accepted, "bound_generation" => 7}),
        t("larger_gap_tx", GT#endpoint_tx_input{op = bind}, #{"status" => accepted, "bound_generation" => 7}),
        t("last_generation_fence_tx", GT#endpoint_tx_input{op = fence}, #{"status" => accepted}),
        r("last_generation_fence_rx", GR#endpoint_rx_input{op = fence}, #{"status" => accepted}),
        r("maximum_generation_rx", LR#endpoint_rx_input{op = bind}, #{"status" => accepted, "bound_generation" => (1 bsl 64) - 1}),
        t("maximum_generation_tx", LT#endpoint_tx_input{op = bind}, #{"status" => accepted, "bound_generation" => (1 bsl 64) - 1}),
        r("generation_never_wraps_rx", (rx(Wrapped))#endpoint_rx_input{op = bind}, #{"status" => exhausted, "active" => false}),
        t("generation_never_wraps_tx", (tx(Wrapped))#endpoint_tx_input{op = bind}, #{"status" => exhausted, "active" => false})
    ].
