-module(hls_protocol_class_selection_tests).
-moduledoc "Canonical source-class selection checks only deliberate mismatches; retained record codec faults remain visible.".
-include_lib("eunit/include/eunit.hrl").

%% Different source constants disambiguate ports sharing a tag and destination with one packing call.
-spec constant_selection_test() -> ok.
constant_selection_test() ->
    Link = encoder([constant_class(2, first, 7), constant_class(5, second, 9)]),
    {Selected, 1} = counted(fun() -> hls_protocol_mixed:encode(Link, {token, 9}) end),
    ?assertEqual({5, (9 bsl 32) bor (17 bsl 24) bor 1}, Selected),
    ?assertEqual(Selected, hls_protocol_mixed:encode(Link, second, {token, 9})),
    ?assertError({no_protocol_class, token}, hls_protocol_mixed:encode(Link, {token, 8})).

%% A record valid for two distinct class slots is ambiguous, even if its ordinary bytes agree.
-spec ambiguous_selection_test() -> ok.
ambiguous_selection_test() ->
    First = constant_class(2, first, 7),
    Link = encoder([First, First#{slot := 5, port := second}]),
    ?assertError({ambiguous_protocol_classes, token, [2, 5]}, hls_protocol_mixed:encode(Link, {token, 7})).

%% Invalid record shapes and undeclared tags never invoke the source codec.
-spec malformed_selection_test() -> ok.
malformed_selection_test() ->
    Link = encoder([constant_class(2, first, 7)]),
    {ok, 0} = counted(fun() ->
        ?assertError({invalid_protocol_message, not_a_record}, hls_protocol_mixed:encode(Link, not_a_record)),
        ?assertError({invalid_protocol_message, {}}, hls_protocol_mixed:encode(Link, {})),
        ?assertError({no_protocol_class, unknown}, hls_protocol_mixed:encode(Link, {unknown, 7})),
        ok
    end).

%% A source codec crash or inconsistent checked width must not be treated as an absent candidate.
-spec packer_failure_test() -> ok.
packer_failure_test() ->
    Class = constant_class(2, first, 7),
    ?assertError({invalid_hls_record_value, token, {broken, 7}},
        hls_protocol_mixed:encode(encoder([Class#{tag := broken}]), {broken, 7})),
    ?assertError({badmatch, 8}, hls_protocol_mixed:encode(encoder([Class#{message_bits := 16}]), {token, 7})).

%% Both alternatives use a destination selector deliberately unrelated to a source tag enumeration.
-spec constant_class(byte(), atom(), byte()) -> hls_protocol_mixed:codec_class().
constant_class(Slot, Port, Value) ->
    Codec = hls_protocol_codec:plan(#{message_bits => 8, payload_bits => 0,
        fields => [#{type => {hls_type, hls_nums, uN, [8]}, message_bit_offset => 0,
            constant => <<Value:8>>}]}, 17),
    Record = hls_record_codec:bind(token, [{value, hls_nums:u8()}]),
    #{slot => Slot, port => Port, tag => token, codec => Codec, message_bits => 8,
        source_record => Record, destination_record => Record}.

%% A standalone class-selection view has no transport session or physical capture metadata.
-spec encoder([hls_protocol_mixed:codec_class()]) -> hls_protocol_mixed:encoder_link().
encoder(Classes) -> #{source_module => ?MODULE, classes => Classes}.

%% Observe only this caller's public record-packing boundary; provider calls do not inflate the count.
-spec counted(fun(() -> Value)) -> {Value, non_neg_integer()}.
counted(Action) ->
    {module, hls_record_codec} = code:ensure_loaded(hls_record_codec),
    {Collector, Monitor} = spawn_monitor(fun() -> collect(0) end),
    Session = trace:session_create(protocol_class_packing, Collector, []),
    try
        1 = trace:process(Session, self(), true, [call]),
        1 = trace:function(Session, {hls_record_codec, pack, 2}, [], []),
        Result = Action(),
        1 = trace:process(Session, self(), false, [call]),
        Ref = trace:delivered(Session, self()),
        receive {trace_delivered, _, Ref} -> ok
        after 5000 -> error(codec_trace_delivery_timeout) end,
        Collector ! {collect, self(), Ref},
        receive {Ref, Count} -> {Result, Count}
        after 5000 -> error(codec_trace_collection_timeout) end
    after
        trace:session_destroy(Session),
        exit(Collector, kill),
        receive {'DOWN', Monitor, process, Collector, _} -> ok
        after 5000 -> error(codec_trace_cleanup_timeout) end
    end.

%% Keep no user records; only observed packing calls contribute to this finite witness.
-spec collect(non_neg_integer()) -> ok.
collect(Count) ->
    receive
        %% One call crosses the retained record-codec boundary.
        {trace, _, call, {hls_record_codec, pack, _}} -> collect(Count + 1);
        %% Delivery synchronization guarantees earlier call events have arrived.
        {collect, Pid, Ref} -> Pid ! {Ref, Count}, ok
    end.
