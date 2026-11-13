-module(hls_domain_board_control_validation).
-moduledoc "Builds a finite board-control RTL witness from retained network metadata. Exact framed replies and routed packet bytes are independent expected vectors; downstream parser sessions and sparse process observations are controlled inputs. Native domain/endpoint behavior, DMA cancellation and physical carrier recovery remain outside this witness.".

%% The retained network's first role supplies the native phase codec and inspection capability.
-export([write/2]).

%% Public scalar observations are controlled independently of the board control state machine.
-type observation() :: #{string() => non_neg_integer()}.
%% A finite script action owns explicit request/reply bytes and named coverage obligations.
-type action() :: map().

-doc "Writes a fresh standalone control source bundle from an existing network source bundle. Uses the first retained role, its native phase codec and actual none/process inspection profile. No application source is recompiled and no external tool runs. Compile the resulting source-build normally, then run tools/test_domain_board_control.py; run both inspection profiles for complete finite coverage.".
-spec write(file:filename(), file:filename()) -> map().
write(NetworkDirectory, Directory) ->
    {ok, NetworkBytes} = file:read_file(filename:join(NetworkDirectory, "interface.etf")),
    {ok, DomainBytes} = file:read_file(filename:join([NetworkDirectory, "evidence", "domain-interface.etf"])),
    [#{network := Network = #{domain_index := Index}} | _] = binary_to_term(NetworkBytes),
    #{domains := Domains} = binary_to_term(DomainBytes),
    [#{interface := #{codecs := #{phase := Phase}}, actors := Actors}] =
        [D || D = #{index := I} <- Domains, I =:= Index],
    [Foreign | _] = lists:append([Is || #{index := I, actors := Is} <- Domains, I =/= Index]),
    #{files := Files, result := Result = #{unit := OriginalUnit}} =
        hls_domain_board_control:emit(Network, #{role => Index + 1, phase => Phase}),
    Unit = OriginalUnit#{rtl := [<<"board_control/core.v">>, <<"board_control/control.sv">>]},
    Trace = trace(Result, Phase, hd(Actors), Foreign),
    {ok, Source} = file:read_file(?FILE),
    Output = hls_generated_files:merge([Files, #{
        "board-control-trace.json" => json:encode(Trace), "interface.etf" => term_to_binary(Result),
        "evidence/network-interface.etf" => NetworkBytes, "evidence/domain-interface.etf" => DomainBytes,
        "evidence/hls_domain_board_control_validation.erl" => Source}]),
    _ = hls_generated_files:write(#{files => Output, result => Result}, Directory),
    #{libraries := Libraries} = hls_build_support:layout([]),
    ok = hls_artifact_bundle:snapshot(Directory, Libraries),
    hls_artifact_bundle:finish(Directory, [Unit], #{kind => board_control_finite_witness,
        inspection => maps:get(inspection, Result), actions => length(maps:get(actions, Trace)),
        state_bits => 723, state_bit_budget => 768}).

%% Native phase packing is retained; all protocol status/word layouts are explicit expected bytes.
-spec trace(hls_domain_board_control:result(), hls_type:descriptor(), non_neg_integer(), non_neg_integer()) -> map().
trace(#{control := #{top_module := Module, inputs := Inputs, outputs := Outputs},
        inspection := Inspection, role := Role}, Phase, Actor, Foreign) ->
    <<Ready:3>> = hls_type:pack(ready, Phase),
    <<Failed:3>> = hls_type:pack(failed, Phase),
    Session = (1 bsl 40) + 7, Incarnation = (1 bsl 48) + 9,
    Snapshot = 16#fedcba98765432100123456789abcdef,
    Initial = #{"domain_session" => 0, "endpoint_session" => 0, "domain_current" => Incarnation,
        "domain_phase" => Ready, "domain_attached" => 0, "endpoint_attached" => 0,
        "domain_wire_fault" => 0, "endpoint_wire_fault" => 0, "router_fault" => 0,
        "carrier_fault" => 0, "carrier_armed" => 1},
    First = attach(Initial, Session), Second = attach(First, Session + 1),
    Partial = Second#{"domain_session" := Session + 2}, Complete = attach(Partial, Session + 3),
    Fault = Complete#{"domain_phase" := Failed, "domain_wire_fault" := 1, "endpoint_wire_fault" := 1,
        "router_fault" := 1, "carrier_fault" := 16#81, "carrier_armed" := 0},
    FaultAttached = attach(Fault, Session + 4),
    DomainFrame = [0, 4, 2, 3, 4, 16#deadbeef], EndpointFrame = [2, 4, 4, 0, 3, 16#f00dcafe],
    Actions = [#{action => reset, label => <<"cold_reset">>, observation => Initial,
        covers => [<<"cold_reset_masks_controls">>]},
        query("initial_status", 1, Initial, Role),
        #{action => forward, label => <<"forward_domain_full_route">>, request => words(DomainFrame), target => 1,
            covers => [<<"route_preserving_ingress">>, <<"independent_payload_stalls">>]},
        #{action => forward, label => <<"forward_endpoint_full_route">>, request => words(EndpointFrame), target => 2,
            covers => [<<"route_preserving_ingress">>, <<"independent_payload_stalls">>]},
        exchange("unknown_route_drain", [16#10004, 3, 0, 2, 4], [], 0, 0, [<<"unknown_route_silent_drain">>]),
        inspection("unattached_inspection", 0, Incarnation, Actor, 19,
            case Inspection of process -> 4; none -> 5 end, 0, [<<"inspection_error_zeroes_snapshot">>]),
        establish("fresh_session", 2, Session, 0, First, Role, Session, 1),
        establish("exact_session_replay", 3, Session, 1, First, Role, 0, 0),
        establish("older_session_rejected", 4, Session - 1, 2, First, Role, 0, 0),
        establish("zero_session_rejected", 5, 0, 2, First, Role, 0, 0),
        establish("unacknowledged_session", 6, Session + 1, 4, First, Role, Session + 1, 0),
        establish("fresh_retry_after_no_ack", 7, Session + 1, 0, Second, Role, Session + 1, 1),
        establish("one_parser_acknowledges", 8, Session + 2, 4, Partial, Role, Session + 2, 2),
        establish("not_fresh_for_both_parsers", 9, Session + 2, 2, Partial, Role, 0, 0),
        (establish("locked_packet_delays_establish", 10, Session + 3, 0, Complete, Role, Session + 3, 1))#{
            action := locked, covers := [<<"establish_waits_for_packet_boundary">>, <<"strict_session_advance">>]},
        (query("three_way_packet_lock", 11, Complete, Role))#{action := mux,
            covers := [<<"packet_locked_output_arbitration">>, <<"response_stability_under_stall">>]}
    ] ++ inspections(Inspection, Session + 3, Incarnation, Actor, Foreign, Snapshot) ++ [
        (inspection("malformed_inspection_header", Session + 3, Incarnation, Actor, 25, 3, 0,
            [<<"malformed_local_framing">>, <<"inspection_error_zeroes_snapshot">>]))#{
                request := words([3, 16#106] ++ pair(Session + 3) ++ pair(Incarnation) ++ [Actor, 25])}
    ] ++ malformed(Complete, Role) ++ [
        #{action => observe, label => <<"physical_fault_remains_latched">>, observation => Fault,
            covers => [<<"physical_fault_survives_session_change">>]},
        query("physical_fault_before_bootstrap", 79, Fault, Role),
        (establish("bootstrap_during_physical_fault", 80, Session + 4, 0, FaultAttached, Role, Session + 4, 1))#{
            covers := [<<"physical_fault_survives_session_change">>, <<"session_reset_is_transport_only">>]},
        query("physical_fault_still_reported", 81, FaultAttached, Role),
        inspection("failed_domain_is_not_inspectable", Session + 4, Incarnation, Actor, 82,
            case Inspection of process -> 2; none -> 5 end, 0, [<<"inspection_error_zeroes_snapshot">>]),
        #{action => quiet, label => <<"finite_quiet_tail">>, cycles => 5, covers => [<<"finite_quiet_tail">>]}
    ],
    Observations = [P || P = {Name, _} <- Inputs, maps:is_key(Name, Initial)],
    Serialized = [case Action of
        #{observation := O} -> Action#{observation := maps:from_list([{b(Name), Value} || {Name, Value} <- maps:to_list(O)])};
        _ -> Action
    end || Action <- Actions],
    #{version => 1, evidence => <<"finite_board_control_rtl_witness">>, inspection => Inspection,
        profile => #{module => b(Module), inputs => ports(Inputs), outputs => ports(Outputs),
            observations => ports(Observations), state_bits => 723, state_bit_budget => 768},
        role => Role, actor => Actor, snapshot => hex(Snapshot),
        native_frames => #{domain => words(DomainFrame), endpoint => words(EndpointFrame)},
        actions => Serialized, coverage => coverage(Actions), expected_session_pulses => 6,
        limits => <<"Finite standalone control comparison. Domain/endpoint parser observations are controlled; sparse native observation is a selected public-input model. Actual endpoint ownership, host DMA bank quiescence, malformed partial DMA cancellation and physical carrier recovery are not executed or proved.">>}.

%% Successful parser attachment clears host parser faults but preserves physical faults and domain lifetime.
-spec attach(observation(), hls_nums:u64()) -> observation().
attach(Observation, Session) -> Observation#{"domain_session" := Session, "endpoint_session" := Session,
    "domain_attached" := 1, "endpoint_attached" := 1, "domain_wire_fault" := 0, "endpoint_wire_fault" := 0}.

%% Fixed response health bits are independent of generated DSLX expression text.
-spec health(observation()) -> hls_nums:u32().
health(O) -> maps:get("domain_phase", O) bor (maps:get("domain_attached", O) bsl 3) bor
    (maps:get("endpoint_attached", O) bsl 4) bor (maps:get("domain_wire_fault", O) bsl 5) bor
    (maps:get("endpoint_wire_fault", O) bsl 6) bor (maps:get("router_fault", O) bsl 7) bor
    (maps:get("carrier_fault", O) bsl 8) bor (maps:get("carrier_armed", O) bsl 16).

%% Status responses echo request identity and snapshot both observed parser sessions and current domain lifetime.
-spec status(non_neg_integer(), 0..5, observation(), 1 | 2) -> [hls_nums:u32()].
status(Request, Status, O, Role) -> [4, 16#8000000b, Request, Status, 1, Role] ++
    pair(maps:get("domain_session", O)) ++ pair(maps:get("endpoint_session", O)) ++
    pair(maps:get("domain_current", O)) ++ [health(O)].

%% A query cannot mutate sessions even when host or physical faults are present.
-spec query(string(), hls_nums:u32(), observation(), 1 | 2) -> action().
query(Label, Request, O, Role) -> exchange(Label, [4, 1, Request], status(Request, 0, O, Role), 0, 0,
    [<<"status_snapshot">>, <<"response_stability_under_stall">>]).

%% Explicit pulse/ack expectations define only the external observation model, not a parser reference FSM.
-spec establish(string(), hls_nums:u32(), hls_nums:u64(), 0..5, observation(), 1 | 2, hls_nums:u64(), 0..2) -> action().
establish(Label, Request, Session, Status, O, Role, Pulse, Ack) ->
    exchange(Label, [4, 16#01000003, Request] ++ pair(Session), status(Request, Status, O, Role), Pulse, Ack,
        [<<"strict_session_advance">>, <<"two_parser_acknowledgment">>, <<"session_reset_is_transport_only">>]).

%% Enabled inspection preserves sparse native zero responses; unavailable capability reports unsupported.
-spec inspections(none | process, hls_nums:u64(), hls_nums:u64(), non_neg_integer(), non_neg_integer(), non_neg_integer()) -> [action()].
inspections(Mode, Session, Incarnation, Actor, Foreign, Snapshot) ->
    Status = case Mode of process -> 0; none -> 5 end,
    Value = case Mode of process -> Snapshot; none -> 0 end,
    Coverage = case Mode of process -> <<"inspection_native_sparse_snapshot">>; none -> <<"inspection_unsupported">> end,
    [inspection("selected_inspection", Session, Incarnation, Actor, 20, Status, Value, [Coverage]),
     inspection("foreign_sparse_address", Session, Incarnation, Foreign, 21, Status, 0, [Coverage]),
     inspection("stale_inspection_session", Session - 1, Incarnation, Actor, 22,
        case Mode of process -> 4; none -> 5 end, 0, [<<"inspection_error_zeroes_snapshot">>, Coverage]),
     inspection("wrong_domain_incarnation", Session, Incarnation - 1, Actor, 23,
        case Mode of process -> 2; none -> 5 end, 0, [<<"inspection_error_zeroes_snapshot">>, Coverage]),
     inspection("zero_domain_incarnation", Session, 0, Actor, 24,
        case Mode of process -> 2; none -> 5 end, 0, [<<"inspection_error_zeroes_snapshot">>, Coverage])].

%% Exact echo fields and the 128-bit observation are checked at the public output stream.
-spec inspection(string(), hls_nums:u64(), hls_nums:u64(), hls_nums:u32(), hls_nums:u32(), 0..5, non_neg_integer(), [binary()]) -> action().
inspection(Label, Session, Incarnation, Actor, Request, Status, Snapshot, Covers) ->
    Prefix = pair(Session) ++ pair(Incarnation) ++ [Actor],
    exchange(Label, [3, 6] ++ Prefix ++ [Request],
        [3, 16#8000000b, Request, Status] ++ Prefix ++ wide(Snapshot, 4), 0, 0, Covers).

%% Malformed local commands respond once with zero uncaptured fields and never pulse transport reset.
-spec malformed(observation(), 1 | 2) -> [action()].
malformed(O, Role) -> [exchange(Label, Packet, status(Request, 3, O, Role), 0, 0,
    [<<"malformed_local_framing">>]) || {Label, Packet, Request} <- [
        {"route_only", [4], 0}, {"zero_length", [4, 0], 0},
        {"zero_request", [4, 1, 0], 0}, {"reserved_header", [4, 16#00ffff01, 31], 31},
        {"short_declared_payload", [4, 16#01000003, 32], 32},
        {"overlong_payload", [4, 1, 33, 0], 33},
        {"oversize_payload", [4, 7, 34, 0, 0, 0, 0, 0, 0], 0},
        {"unsupported_operation", [4, 16#02000003, 35, 1, 0], 35}
    ]].

%% Ordinary local request/reply exchange; an empty expected response requires quiet drain instead.
-spec exchange(string(), [hls_nums:u32()], [hls_nums:u32()], hls_nums:u64(), 0..2, [binary()]) -> action().
exchange(Label, Request, Response, Pulse, Ack, Covers) -> #{action => exchange, label => b(Label),
    request => words(Request), response => words(Response), pulse => Pulse, ack => Ack, covers => Covers}.

%% Native integer packing establishes little-word order without a second bit-concatenation convention.
-spec pair(hls_nums:u64()) -> [hls_nums:u32()].
pair(Value) -> wide(Value, 2).

%% Fixed-width wire values are split through the same ordinary integer byte order as their specification.
-spec wide(non_neg_integer(), pos_integer()) -> [hls_nums:u32()].
wide(Value, Count) -> true = Value >= 0 andalso Value < (1 bsl (32 * Count)),
    [Word || <<Word:32/little>> <= <<Value:(32 * Count)/little>>].

%% Word strings preserve full unsigned values in every JSON reader.
-spec words([hls_nums:u32()]) -> [binary()].
words(Words) -> [hex(Word) || Word <- Words].

%% Retained vector metadata supplies exact public names and widths.
-spec ports([{string(), pos_integer()}]) -> [map()].
ports(Ports) -> [#{name => b(Name), width => Width} || {Name, Width} <- Ports].

%% Coverage names resolve to actual retained finite action indices.
-spec coverage([action()]) -> map().
coverage(Actions) -> lists:foldl(fun({Index, #{covers := Names}}, Acc) -> lists:foldl(fun(Name, Map) ->
    maps:update_with(Name, fun(Is) -> Is ++ [Index] end, [Index], Map)
end, Acc, Names) end, #{}, lists:enumerate(0, Actions)).

%% Arbitrarily wide observation bytes remain lossless in JSON.
-spec hex(non_neg_integer()) -> binary().
hex(Value) -> integer_to_binary(Value, 16).

%% Human labels are portable UTF-8 JSON strings.
-spec b(string()) -> binary().
b(Value) -> unicode:characters_to_binary(Value).
