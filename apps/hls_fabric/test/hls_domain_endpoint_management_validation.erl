-module(hls_domain_endpoint_management_validation).
-moduledoc "Builds a finite management-parser RTL witness with controlled endpoint metadata. Native endpoint steps supply issue-edge and retained observations; the RTL testbench supplies those observations as explicit inputs, not compiled endpoint feedback. Exact responses, command pulses, stalls and session boundaries are checked by the external runner.".
-include_lib("hls_runtime/include/hls_domain_channel_endpoints.hrl").

%% Bundle publication is separate from normal XLS compilation and simulation.
-export([write/1]).

%% The fixture owns two native reference states, not a second endpoint implementation.
-type models() :: #{tx := #endpoint_tx_state{}, rx := #endpoint_rx_state{}}.
%% Numeric named pins use the emitter's own ordering only at the final packing boundary.
-type pins() :: #{string() => non_neg_integer()}.
%% Script construction retains exact expected mutations and framed responses.
-type fixture() :: #{interface := hls_domain_endpoint_wire:interface(),
    models := models(), session := hls_nums:u64(), request := hls_nums:u32(),
    rows := [map()], mutations := [map()]}.

-doc "Writes a fresh parser-only source bundle and machine-readable finite script. Native kernels generate controlled metadata and expected responses without compiling endpoint RTL. The normal compile_source_build boundary and tools/hls_fabric/test_domain_endpoint_management.py execute separately. Existing directories and unmet native expectations reject; no XLS or simulation subprocess runs here.".
-spec write(file:filename()) -> map().
write(Directory) ->
    Codecs = codecs(),
    #{files := ParserFiles, result := Parser = #{interface := Interface, unit := Unit}} =
        hls_domain_endpoints_stream:emit(#{endpoints => [#{id => 8, kind => tx}, #{id => 61, kind => rx}],
            codecs => Codecs}),
    Trace = trace(Parser, Interface),
    Files = hls_generated_files:merge([ParserFiles, reference_sources(), #{
        "endpoint-management-trace.json" => json:encode(Trace),
        "interface.etf" => term_to_binary(Parser)
    }]),
    _ = hls_generated_files:write(#{files => Files, result => Parser}, Directory),
    #{libraries := Libraries} = hls_build_support:layout([]),
    ok = hls_artifact_bundle:snapshot(Directory, Libraries),
    hls_artifact_bundle:finish(Directory, [Unit], #{
        kind => independent_endpoint_management_witness,
        evidence => <<"Finite parser simulation inputs with controlled endpoint observations">>,
        script_rows => length(maps:get(rows, Trace)),
        expected_mutations => length(maps:get(mutations, Trace)),
        state_bit_budget => maps:get(state_bit_budget, Parser), packet_words => 16
    }).

%% Retain source declarations and reference generation beside the immutable source-build manifest.
-spec reference_sources() -> hls_generated_files:files().
reference_sources() ->
    Sources = [{Name, hls_source:library_file(hls_runtime, "fabric/runtime/domain/" ++ Name)}
        || Name <- ["hls_domain_channel_tx.erl", "hls_domain_channel_rx.erl", "hls_domain_channel_binding.erl"]] ++
        [{"hls_domain_channel_endpoints.hrl", filename:join([code:lib_dir(hls_runtime), "include", "hls_domain_channel_endpoints.hrl"])},
         {"hls_domain_endpoint_management_validation.erl", filename:absname(?FILE)}],
    maps:from_list([begin {ok, Bytes} = file:read_file(Path), {"evidence/native/" ++ Name, Bytes} end
        || {Name, Path} <- Sources]).

%% Parsing source declarations supplies codecs without compiling an endpoint service a second time.
-spec codecs() -> hls_domain_endpoint_wire:codecs().
codecs() ->
    Source = hls_source:library_file(hls_runtime, "fabric/runtime/domain/hls_domain_channel_tx.erl"),
    {ok, Parsed} = hls_source:parse_file(Source),
    Forms = hls_records:resolve(Parsed),
    Input = maps:from_list(hls_records:fields(hls_records:find(Forms, endpoint_tx_input))),
    Output = maps:from_list(hls_records:fields(hls_records:find(Forms, endpoint_tx_output))),
    #{operation => maps:get(op, Input), status => maps:get(status, Output), binding => maps:get(binding, Input)}.

%% Aggregate vectors contain only selected endpoint metadata and management command pins.
-spec trace(hls_domain_endpoints_stream:result(), hls_domain_endpoint_wire:interface()) -> map().
trace(#{inputs := Inputs, outputs := Outputs, state_bit_budget := StateBits}, Interface) ->
    Models = #{tx => hls_domain_channel_tx:new(), rx => hls_domain_channel_rx:new()},
    Initial = #{interface => Interface, models => Models, session => 0, request => 1, rows => [], mutations => []},
    Final = schedule(Initial),
    MetaPins = [P || P = {Name, _} <- Inputs, string:find(Name, "_observed_") =/= nomatch],
    ControlPins = [P || P = {Name, _} <- Outputs,
        lists:prefix("endpoint_8_", Name) orelse lists:prefix("endpoint_61_", Name)],
    Rows = lists:reverse(maps:get(rows, Final)),
    Mutations = [#{label => maps:get(label, M),
        commands => hex(pack(ControlPins, maps:get(commands, M))),
        before => hex(pack(MetaPins, maps:get(before, M))),
        issue => hex(pack(MetaPins, maps:get(issue, M))),
        'after' => hex(pack(MetaPins, maps:get('after', M)))} || M <- lists:reverse(maps:get(mutations, Final))],
    #{version => 1, evidence => <<"finite_endpoint_management_parser_witness">>,
        profile => #{module => <<"endpoint_management">>, inputs => profile(Inputs), outputs => profile(Outputs),
            state_bit_budget => StateBits, payload_words => 14, packet_words => 16},
        initial_metadata => hex(pack(MetaPins, metadata(Models, Interface))),
        mutations => Mutations, rows => Rows, coverage => coverage(Rows),
        limits => <<"Controlled metadata inputs reflect native issue-edge results. This does not execute endpoint RTL, domain lifecycle, host coordination or a carrier, and is not a formal or physical qualification.">>}.

%% Each case has an externally visible response, command assertion or bounded absence check.
-spec schedule(fixture()) -> fixture().
schedule(S0) ->
    Binding = #endpoint_binding{namespace = 16#123456780000000b, generation = 1,
        source_incarnation = 17, destination_incarnation = 33},
    S1 = open(add(S0, #{action => <<"reset">>, label => <<"cold_parser_only">>, covers => []}), 41, "initial_session"),
    {S2, Empty} = command(S1, "rx_initial_inspect", 61, inspect),
    S3 = add(S2, #{action => <<"hold">>, label => <<"blocked_response_slot">>, cycles => 4, ready => 1,
        covers => [<<"response_stability_under_stall">>]}),
    {S4, BoundRx} = command(S3, "rx_bind_behind_stalled_response", 61, {bind, Binding}),
    S5 = add(S4, #{action => <<"hold">>, label => <<"full_rx_cannot_issue_or_accept">>, cycles => 4, ready => 0,
        covers => [<<"independent_command_response_stalls">>, <<"single_receive_slot_backpressure">>]}),
    S6 = receive_reply(S5, "drain_old_response_before_bind", Empty, false, []),
    S7 = receive_reply(S6, "discard_rx_bind_reply", BoundRx, true, [<<"lost_bind_reply">>]),
    S8 = exchange(S7, "rx_inspect_reconciles_lost_reply", 61, inspect, [<<"lost_response_inspect_reconciliation">>]),
    S9 = exchange(S8, "tx_bind_confirmed_receiver", 8, {bind, Binding}, [<<"tx_receiver_confirmation_only_bind_edge">>]),
    S10 = exchange(S9, "tx_inspect_has_no_receiver_pulse", 8, inspect, [<<"tx_receiver_confirmation_only_bind_edge">>]),
    S11 = exchange(S10, "rx_exact_fence", 61, {fence, Binding}, [<<"rx_inspect_bind_fence">>]),
    S12 = exchange(S11, "rx_closed_binding_retained", 61, inspect, [<<"rx_inspect_bind_fence">>]),
    Stale = request(40, 900, 8, {fence, Binding}, maps:get(interface, S12)),
    S13 = quiet(send(S12, "stale_session_cannot_fence", Stale, [<<"stale_session_drop">>]),
        "stale_session_no_response", 0, 1, [<<"stale_session_drop">>]),
    StaleLong = oversized(request(40, 901, 8, inspect, maps:get(interface, S13))),
    S14 = quiet(send(S13, "malformed_stale_session", StaleLong, []),
        "malformed_stale_is_not_current_authority", 0, 1, [<<"stale_malformed_session_drop">>]),
    {S15, Unknown} = unknown(S14, Binding),
    S16 = receive_reply(S15, "unknown_endpoint_invalid_response", Unknown, false, [<<"unknown_id_no_mutation">>]),
    {S17, _Abandoned} = command(S16, "response_abandoned_by_session_reset", 8, inspect),
    S18 = add(S17, #{action => <<"hold">>, label => <<"hold_before_new_session">>, cycles => 3, ready => 1, covers => []}),
    S19 = open(S18, 42, "session_reset_preserves_endpoints"),
    S20 = quiet(S19, "old_session_response_cleared", 0, 1, [<<"session_reset_only_parser">>]),
    S21 = exchange(S20, "tx_binding_survives_session_reset", 8, inspect, [<<"session_reset_only_parser">>]),
    S22 = lists:foldl(fun({Label, Change}, S) -> malformed(S, Label, Change) end, S21, [
        {"reserved_header_txid", fun(W) -> header(W, lists:nth(2, W) bor (1 bsl 8)) end},
        {"reserved_header_flags", fun(W) -> header(W, lists:nth(2, W) bor (1 bsl 16)) end},
        {"wrong_route", fun([_Route | Rest]) -> [3 | Rest] end},
        {"zero_request", fun([R, H, L, U, _Q, E]) -> [R, H, L, U, 0, E] end},
        {"invalid_operation", fun(W) -> header(W, (129 bsl 24) bor 4) end},
        {"short_declared_count", fun(W) -> header(W, 3) end},
        {"long_declared_count", fun(W) -> header(W, 5) ++ [0] end},
        {"oversized_count_retains_session", fun oversized/1},
        {"early_last_after_session", fun(W) -> lists:sublist(W, 4) end},
        {"late_last", fun(W) -> W ++ [0] end}
    ]),
    Short = lists:sublist(request(maps:get(session, S22), 902, 8, inspect, maps:get(interface, S22)), 3),
    S23 = quiet(send(S22, "truncated_session_prefix", Short, []),
        "incomplete_session_has_no_authority", 0, 1, [<<"truncated_session_prefix_drop">>]),
    S24 = exchange(S23, "tx_still_bound_after_bad_frames", 8, inspect, [<<"session_reset_only_parser">>]),
    S25 = exchange(S24, "tx_final_fence", 8, {fence, Binding}, [<<"tx_fence_has_no_receiver_pulse">>]),
    quiet(S25, "finite_quiet_tail", 0, 1, [<<"finite_quiet_tail">>]).

%% Valid commands derive same-edge observations from the native kernel before preparing their reply.
-spec command(fixture(), string(), hls_nums:u32(), hls_domain_endpoint_wire:command()) -> {fixture(), [non_neg_integer()]}.
command(S = #{interface := Interface, models := Models, session := Session, request := Sequence}, Label, Id, Command) ->
    Role = role(Id),
    {NextState, Issued} = native(Role, Command, maps:get(Role, Models), Interface),
    NextModels = Models#{Role := NextState},
    S1 = case Command of
        inspect -> S;
        {_, Binding} ->
            accepted = maps:get(status, Issued),
            Mutation = #{label => b(Label), commands => controls(Id, Command),
                before => metadata(Models, Interface),
                issue => maps:merge(metadata(Models, Interface), observed(Id, Issued, Interface)),
                'after' => metadata(NextModels, Interface)},
            Binding = maps:get(binding, Issued),
            S#{models := NextModels, mutations := [Mutation | maps:get(mutations, S)]}
    end,
    {send(S1#{request := Sequence + 1}, Label, request(Session, Sequence, Id, Command, Interface), []),
        response(Session, Sequence, Id, Issued, Interface)}.

%% A complete exchange checks exact response bytes after independently stalled output words.
-spec exchange(fixture(), string(), hls_nums:u32(), hls_domain_endpoint_wire:command(), [binary()]) -> fixture().
exchange(S, Label, Id, Command, Covers) ->
    {Next, Reply} = command(S, Label, Id, Command),
    receive_reply(Next, Label ++ "_response", Reply, false, Covers).

%% Unknown static IDs receive canonical invalid evidence without reaching a native endpoint.
-spec unknown(fixture(), #endpoint_binding{}) -> {fixture(), [non_neg_integer()]}.
unknown(S = #{interface := Interface, session := Session, request := Sequence}, Binding) ->
    [_R, H, Lo, Hi, Q, _Id | Rest] = request(Session, Sequence, 8, {bind, Binding}, Interface),
    Packet = [2, H, Lo, Hi, Q, 99 | Rest],
    Snapshot = #{status => invalid, binding => #endpoint_binding{}, packet_sequence => 0, active => false, fault => false},
    {send(S#{request := Sequence + 1}, "unknown_bind_id", Packet, []),
        response(Session, Sequence, 99, Snapshot, Interface)}.

%% Every malformed current-session case closes, rejects same-session reset, then opens a strictly newer session.
-spec malformed(fixture(), string(), fun(([non_neg_integer()]) -> [non_neg_integer()])) -> fixture().
malformed(S = #{session := Session, request := Sequence, interface := Interface}, Label, Change) ->
    Packet = Change(request(Session, Sequence, 8, inspect, Interface)),
    S1 = quiet(send(S#{request := Sequence + 1}, Label, Packet, []), Label ++ "_closed", 1, 0,
        [<<"malformed_current_session_closes">>, <<"count_route_reserved_boundaries">>]),
    S2 = add(S1, #{action => <<"session">>, label => b(Label ++ "_same_session_cannot_reopen"),
        session => Session, fault => 1, attached => 0, covers => [<<"strict_session_advance">>]}),
    open(S2, Session + 1, Label ++ "_new_session").

%% Oversized declared lengths still carry the complete session prefix before bounded drain.
-spec oversized([non_neg_integer()]) -> [non_neg_integer()].
oversized([Route, _Header | Payload]) -> [Route, 15 | Payload ++ lists:duplicate(11, 0)].

%% A changed header preserves the original session and request payload for adversarial framing.
-spec header([non_neg_integer()], non_neg_integer()) -> [non_neg_integer()].
header([Route, _Old | Payload], New) -> [Route, New | Payload].

%% Session reset is a parser-only action; the testbench asserts no endpoint command or metadata reset.
-spec open(fixture(), hls_nums:u64(), string()) -> fixture().
open(S, Session, Label) -> add(S#{session := Session}, #{action => <<"session">>, label => b(Label),
    session => Session, fault => 0, attached => 1, covers => [<<"session_reset_only_parser">>]}).

%% Input words include route/header and are separated by deterministic valid gaps in the testbench.
-spec send(fixture(), string(), [non_neg_integer()], [binary()]) -> fixture().
send(S, Label, Words, Covers) -> add(S, #{action => <<"send">>, label => b(Label),
    words => [hex(W) || W <- Words], covers => [<<"independent_command_response_stalls">> | Covers]}).

%% Discard marks a reply unavailable to the simulated caller even though the witness still checks its bytes.
-spec receive_reply(fixture(), string(), [non_neg_integer()], boolean(), [binary()]) -> fixture().
receive_reply(S, Label, Words, Discard, Covers) -> add(S, #{action => <<"receive">>, label => b(Label),
    words => [hex(W) || W <- Words], discard => Discard, covers => Covers}).

%% A bounded quiet period verifies status, attachment and absence of extra response frames.
-spec quiet(fixture(), string(), 0 | 1, 0 | 1, [binary()]) -> fixture().
quiet(S, Label, Fault, Attached, Covers) -> add(S, #{action => <<"quiet">>, label => b(Label),
    cycles => 4, fault => Fault, attached => Attached, covers => Covers}).

%% Script order is retained independently of expected native mutation order.
-spec add(fixture(), map()) -> fixture().
add(S = #{rows := Rows}, Row) -> S#{rows := [Row | Rows]}.

%% Native TX binds receive only the explicit assertion supplied by this management command.
-spec native(tx | rx, hls_domain_endpoint_wire:command(), #endpoint_tx_state{} | #endpoint_rx_state{}, hls_domain_endpoint_wire:interface()) ->
    {#endpoint_tx_state{} | #endpoint_rx_state{}, map()}.
native(tx, Command, State = #endpoint_tx_state{}, _Interface) ->
    {Op, Binding} = operation(Command),
    Confirm = Op =:= bind,
    Input = #endpoint_tx_input{op = Op, binding = Binding, local_ready = true, local_incarnation = 17,
        receiver_active = Confirm, receiver_binding = case Confirm of true -> Binding; false -> #endpoint_binding{} end},
    #endpoint_tx_output{state = Next, status = Status} = hls_domain_channel_tx:step(Input, State),
    {Next, snapshot(Next#endpoint_tx_state.binding, Next#endpoint_tx_state.sequence, Next#endpoint_tx_state.active, Status)};
native(rx, Command, State = #endpoint_rx_state{}, _Interface) ->
    {Op, Binding} = operation(Command),
    #endpoint_rx_output{state = Next, status = Status} = hls_domain_channel_rx:step(
        #endpoint_rx_input{op = Op, binding = Binding, local_ready = true, local_incarnation = 33}, State),
    {Next, snapshot(Next#endpoint_rx_state.binding, Next#endpoint_rx_state.sequence, Next#endpoint_rx_state.active, Status)}.

%% Inspection advances no ownership; the native ordinary tick supplies its passive status.
-spec operation(hls_domain_endpoint_wire:command()) -> {endpoint_operation(), #endpoint_binding{}}.
operation(inspect) -> {tick, #endpoint_binding{}};
operation({Op, Binding}) -> {Op, Binding}.

%% Native reference execution has no compiled source failure and therefore supplies fault=false.
-spec snapshot(#endpoint_binding{}, hls_nums:u32(), boolean(), endpoint_status()) -> map().
snapshot(Binding, Sequence, Active, Status) -> #{binding => Binding, packet_sequence => Sequence,
    active => Active, status => Status, fault => false}.

%% Passive metadata reflects a normal tick after the command edge, not a latched accepted status.
-spec metadata(models(), hls_domain_endpoint_wire:interface()) -> pins().
metadata(Models, Interface) -> maps:merge(observe_role(tx, Models, Interface), observe_role(rx, Models, Interface)).

%% Both model roles remain under the fixture's explicit local ready/incarnation assumptions.
-spec observe_role(tx | rx, models(), hls_domain_endpoint_wire:interface()) -> pins().
observe_role(Role, Models, Interface) ->
    {_, Snapshot} = native(Role, inspect, maps:get(Role, Models), Interface),
    observed(id(Role), Snapshot, Interface).

%% Same-edge result fields use the parser's retained public observation pin names.
-spec observed(hls_nums:u32(), map(), hls_domain_endpoint_wire:interface()) -> pins().
observed(Id, #{binding := Binding, packet_sequence := Sequence, status := Status, active := Active, fault := Fault}, Interface) ->
    Prefix = "endpoint_" ++ integer_to_list(Id) ++ "_observed_",
    maps:merge(binding_pins(Prefix ++ "bound_", Binding), #{Prefix ++ "packet_sequence" => Sequence,
        Prefix ++ "status" => status(Status, Interface), Prefix ++ "active" => bit(Active), Prefix ++ "fault" => bit(Fault)}).

%% Compare every raw command output; nonselected controls and TX receiver evidence are zero.
-spec controls(hls_nums:u32(), hls_domain_endpoint_wire:command()) -> pins().
controls(Id, {Op, Binding}) ->
    lists:foldl(fun({Endpoint, Kind}, Acc) ->
        Prefix = "endpoint_" ++ integer_to_list(Endpoint) ++ "_",
        Selected = Endpoint =:= Id,
        Request = case Selected of true -> Binding; false -> #endpoint_binding{} end,
        Pins = maps:merge(binding_pins(Prefix, Request), #{Prefix ++ "bind_request" => bit(Selected andalso Op =:= bind),
            Prefix ++ "fence" => bit(Selected andalso Op =:= fence)}),
        Extra = case Kind of
            rx -> #{};
            tx -> Confirm = Selected andalso Op =:= bind,
                maps:merge(binding_pins(Prefix ++ "receiver_", case Confirm of true -> Binding; false -> #endpoint_binding{} end),
                    #{Prefix ++ "receiver_active" => bit(Confirm)})
        end,
        maps:merge(Acc, maps:merge(Pins, Extra))
    end, #{}, [{8, tx}, {61, rx}]).

%% Binding identities are expanded only into already named mechanical pins.
-spec binding_pins(string(), #endpoint_binding{}) -> pins().
binding_pins(P, #endpoint_binding{namespace = N, generation = G, source_incarnation = S, destination_incarnation = D}) ->
    #{P ++ "namespace" => N, P ++ "generation" => G, P ++ "source_incarnation" => S, P ++ "destination_incarnation" => D}.

%% Runtime request encoding supplies source-derived binding bytes and exact fixed header lengths.
-spec request(hls_nums:u64(), hls_nums:u32(), hls_nums:u32(), hls_domain_endpoint_wire:command(), hls_domain_endpoint_wire:interface()) -> [non_neg_integer()].
request(Session, Sequence, Id, Command, Interface) ->
    {Tag, Payload} = hls_domain_endpoint_wire:command(Session, Sequence, Id, Command, Interface),
    [2, (Tag bsl 24) bor (byte_size(Payload) div 4) | words(Payload)].

%% Expected responses are packed independently of generated DSLX and checked against the runtime decoder when known.
-spec response(hls_nums:u64(), hls_nums:u32(), hls_nums:u32(), map(), hls_domain_endpoint_wire:interface()) -> [non_neg_integer()].
response(Session, Sequence, Id, #{binding := Binding, packet_sequence := PacketSequence,
        status := Status, active := Active, fault := Fault}, Interface = #{codecs := #{binding := Type}}) ->
    Packed = hls_type:pack(Binding, Type),
    Flags = status(Status, Interface) bor (bit(Active) bsl 8) bor (bit(Fault) bsl 9),
    Payload = <<Session:64/little, Sequence:32/little, Id:32/little, Flags:32/little, Packed/binary, PacketSequence:32/little>>,
    case Id of 99 -> ok; _ -> _ = hls_domain_endpoint_wire:observation({129, 0, 0}, Payload, Interface) end,
    [2, (129 bsl 24) bor 14 | words(Payload)].

%% Word vectors preserve the physical little-endian framing without JSON precision loss.
-spec words(binary()) -> [non_neg_integer()].
words(Bytes) -> [W || <<W:32/little>> <= Bytes].

%% Shared atom encoding comes only from the actual native source descriptor.
-spec status(endpoint_status(), hls_domain_endpoint_wire:interface()) -> non_neg_integer().
status(Atom, #{codecs := #{status := Type}}) -> Width = hls_type:width(Type), <<Code:Width>> = hls_type:pack(Atom, Type), Code.

%% Every compared vector is checked against the emitted named pin widths before serialization.
-spec pack([{string(), pos_integer()}], pins()) -> non_neg_integer().
pack(Pins, Values) -> lists:foldl(fun({Name, Width}, Acc) ->
    Value = maps:get(Name, Values), true = Value >= 0 andalso Value < (1 bsl Width), (Acc bsl Width) bor Value
end, 0, Pins).

%% Trace consumers use the emitted pin order, not independently guessed wire widths.
-spec profile([{string(), pos_integer()}]) -> [map()].
profile(Pins) -> [#{name => b(Name), width => Width} || {Name, Width} <- Pins].

%% Each named scenario points to actual bounded script rows checked by the external runner.
-spec coverage([map()]) -> map().
coverage(Rows) -> lists:foldl(fun({Index, #{covers := Names}}, Acc) -> lists:foldl(fun(Name, M) ->
    maps:update_with(Name, fun(Indices) -> Indices ++ [Index] end, [Index], M)
end, Acc, lists:usort(Names)) end, #{}, lists:enumerate(0, Rows)).

%% Fixture endpoint identities never come from a packet direction field.
-spec role(8 | 61) -> tx | rx.
role(8) -> tx;
role(61) -> rx.

%% The same two IDs identify controlled metadata in the generated RTL testbench.
-spec id(tx | rx) -> 8 | 61.
id(tx) -> 8;
id(rx) -> 61.

%% Named pin booleans have the ordinary one-bit representation.
-spec bit(boolean()) -> 0 | 1.
bit(true) -> 1;
bit(false) -> 0.

%% Wide vectors remain exact in JSON consumers without floating-point conversion.
-spec hex(non_neg_integer()) -> binary().
hex(Value) -> integer_to_binary(Value, 16).

%% Human labels and manifest names are UTF-8 bytes.
-spec b(string()) -> binary().
b(Value) -> unicode:characters_to_binary(Value).
