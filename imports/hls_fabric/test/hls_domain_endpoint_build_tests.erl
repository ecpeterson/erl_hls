-module(hls_domain_endpoint_build_tests).
-moduledoc "Source-emission checks for independent mailbox endpoints. Capacity, pin identity and retained-payload wiring are checked without external tools; these are not RTL execution or physical reset witnesses.".
-include_lib("eunit/include/eunit.hrl").

%% Compile each source service once; the application frame remains twenty words in both.
-spec endpoint_emission_test_() -> term().
endpoint_emission_test_() -> {timeout, 120, fun endpoint_emission/0}.

%% A large TX request must not widen the destination application's data frame.
-spec endpoint_emission() -> ok.
endpoint_emission() ->
    Tx = hls_domain_endpoint_build:emit(tx, 20),
    Rx = hls_domain_endpoint_build:emit(rx, 20, 20),
    check(Tx, tx, 28, 871, 586),
    check(Rx, rx, 20, 614, 588),
    #{files := TxFiles} = Tx,
    #{files := RxFiles} = Rx,
    ?assertEqual([], [Path || Path <- maps:keys(TxFiles), maps:is_key(Path, RxFiles)]),
    ?assertEqual(map_size(TxFiles) + map_size(RxFiles),
        map_size(hls_generated_files:merge([TxFiles, RxFiles]))),
    TxText = bytes(TxFiles, "endpoint_tx/endpoint_tx.x"),
    RxText = bytes(RxFiles, "endpoint_rx/endpoint_rx.x"),
    includes(TxText, "source_ready: take, source_take: take"),
    includes(TxText, "tx_slot: s.slot, tx_frame: s.frame"),
    includes(TxText, "receiver_active: io.receiver_active"),
    includes(TxText, "let take = live && observed.source_take"),
    includes(RxText, "destination_slot: s.slot, destination_frame: s.frame"),
    includes(RxText, "let take = live && observed.data_take"),
    includes(RxText, "ack_valid: live && observed.ack_valid"),
    ok.

%% Explicit undersized controller profiles reject before attempting source compilation.
-spec narrow_controller_test() -> ok.
narrow_controller_test() ->
    ?assertError({endpoint_controller_too_narrow, 20, 28},
        hls_domain_endpoint_build:emit(tx, 20, 20)),
    ?assertError({endpoint_controller_too_narrow, 19, 20},
        hls_domain_endpoint_build:emit(rx, 20, 19)),
    ok.

%% Metadata exposes the actual source widths and its failure register in the state budget.
-spec check(hls_generated_files:output(hls_domain_endpoint_build:result()),
    hls_domain_endpoint_build:direction(), pos_integer(), pos_integer(), pos_integer()) -> ok.
check(#{files := Files, result := Result}, Direction, ControllerWords, InputBits, OutputBits) ->
    #{inputs := Inputs, outputs := Outputs, codecs := Codecs,
        source_service := Service, state_budget := Budget} = Result,
    Name = "endpoint_" ++ atom_to_list(Direction),
    ?assertMatch(#{frame_payload_words := 20, frame_bits := 672, storage_bits := 1003,
        cold_reset_pin := "reset", local_ready_pin := "local_ready",
        local_incarnation_pin := "local_incarnation"}, Result),
    ?assertEqual(ControllerWords, maps:get(controller_words, Result)),
    ?assertEqual(ControllerWords, maps:get(controller_minimum_words, Result)),
    ?assertEqual(32 + 32 * ControllerWords, maps:get(controller_frame_bits, Result)),
    ?assertEqual(InputBits, maps:get(controller_input_bits, Result)),
    ?assertEqual(OutputBits, maps:get(controller_output_bits, Result)),
    ?assertEqual(InputBits, hls_type:width(maps:get(input, Codecs))),
    ?assertEqual(OutputBits, hls_type:width(maps:get(output, Codecs))),
    ?assertEqual(256, hls_type:width(maps:get(binding, Codecs))),
    ?assertEqual(288, hls_type:width(maps:get(packet, Codecs))),
    ?assertMatch(#{kernel_bits := 291, failure_bits := 32, payload_bits := 672,
        slot_bits := 8, total_bits := 1003, payload_registers := 1, writers := 1,
        retention := outside_local_domain_reset}, Budget),
    ?assert(lists:member({"failure", 32}, Outputs)),
    ?assert(lists:member({"local_incarnation", 64}, Inputs)),
    ?assertNot(lists:keymember("source_live", 1, Inputs)),
    ?assertNot(lists:keymember("destination_live", 1, Inputs)),
    ?assertNot(lists:keymember("domain_reset", 1, Inputs)),
    Names = [N || {N, _} <- Inputs ++ Outputs],
    ?assertEqual(length(Names), length(lists:usort(Names))),
    {Inbound, Outbound} = case Direction of
        tx -> {"credit_", "tx_"};
        rx -> {"data_", "ack_"}
    end,
    packet_pins(Inbound, Inputs),
    packet_pins(Outbound, Outputs),
    lists:foreach(fun(Path) -> ?assert(lists:prefix(Name ++ "/", Path)) end, maps:keys(Files)),
    Controller = bytes(Files, Name ++ "/" ++ Name ++ "_controller.x"),
    ?assertEqual(hls_generated_files:hash(Controller), maps:get(dslx_sha256, Service)),
    ?assert(is_list(maps:get(failure_sites, Service))),
    maps:foreach(fun(Path, Hash) ->
        ?assertEqual(Hash, hls_generated_files:hash(
            maps:get(Name ++ "/" ++ binary_to_list(Path), Files)))
    end, maps:get(dependency_sha256, Service)),
    Config = bytes(Files, Name ++ "/frame_config.x"),
    includes(Config, ["PAYLOAD_WORDS = u32:", integer_to_list(ControllerWords)]),
    Wrapper = bytes(Files, Name ++ "/" ++ Name ++ ".x"),
    includes(Wrapper, "pub type Frame = bits[672]"),
    ?assertEqual(nomatch, binary:match(Wrapper, <<"state: if io.reset">>)),
    includes(Wrapper, "init { initial_state() }"),
    includes(Wrapper, "local_ready: io.local_ready, local_incarnation: io.local_incarnation"),
    ?assertEqual(nomatch, binary:match(Wrapper, <<"@@">>)),
    Adapter = bytes(Files, Name ++ "/" ++ Name ++ ".sv"),
    includes(Adapter, ".reset(reset)"),
    ok.

%% Packet ingress and egress both preserve every identity field at its native width.
-spec packet_pins(string(), [{string(), pos_integer()}]) -> ok.
packet_pins(Prefix, Pins) ->
    lists:foreach(fun(Field) ->
        ?assert(lists:member({Prefix ++ Field, 64}, Pins))
    end, ["namespace", "generation", "source_incarnation", "destination_incarnation"]),
    ?assert(lists:member({Prefix ++ "sequence", 32}, Pins)),
    ok.

%% Generated-file values may be byte strings or nested IO data.
-spec bytes(hls_generated_files:files(), string()) -> binary().
bytes(Files, Path) -> iolist_to_binary(maps:get(Path, Files)).

%% Check interface-critical fragments without retaining full generated-source snapshots.
-spec includes(binary(), iodata()) -> ok.
includes(Text, Fragment) ->
    ?assertNotEqual(nomatch, binary:match(Text, iolist_to_binary(Fragment))),
    ok.
