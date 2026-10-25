-module(hls_protocol_startup_tests).
-include_lib("eunit/include/eunit.hrl").

%% Unaligned signed and unsigned fields retain their ordinary physical stream order.
-spec exact_frame_test() -> ok.
exact_frame_test() ->
    Artifact = artifact([{id, "hls_nums:uN(3)"}, {value, "hls_nums:sN(13)"},
        {flag, "hls_bool:bool()"}]),
    [Frame, Frame] = hls_protocol_schema:frames(Artifact,
        [{message, 5, -21, true}, {message, 5, -21, true}]),
    Parts = [hls_type:pack_exact(5, {hls_type, hls_nums, uN, [3]}),
        hls_type:pack_exact(-21, {hls_type, hls_nums, sN, [13]}),
        hls_type:pack_exact(true, {hls_type, hls_bool, bool, []})],
    Stream = << <<Bits/bitstring>> || Bits <- Parts >>,
    <<Payload:96/little>> = <<Stream/bitstring, 0:(96-bit_size(Stream))>>,
    ?assertEqual((Payload bsl 32) bor (3 bsl 24) bor 1, Frame).

%% Empty configuration adds no messages; empty records retain the canonical operation header.
-spec empty_test() -> ok.
empty_test() ->
    Artifact = artifact([]),
    ?assertEqual([], hls_protocol_schema:frames(Artifact, [])),
    ?assertEqual([3 bsl 24], hls_protocol_schema:frames(Artifact, [{message}])).

%% Record tags, arities and host representation must match the complete receiving schema.
-spec rejects_bad_records_test() -> ok.
rejects_bad_records_test() ->
    Artifact = artifact([{n, "hls_nums:u8()"}]),
    lists:foreach(fun(Message) ->
        ?assertError({invalid_startup_record, Message},
            hls_protocol_schema:frames(Artifact, [Message]))
    end, [bad, {other, 1}, {message}, {message, 1, 2}]),
    ?assertException(error, _, hls_protocol_schema:frames(Artifact, [{message, 256}])),
    ?assertException(error, _, hls_protocol_schema:frames(Artifact, [{message, 1.0}])).

%% The ordinary compiler rejects over-capacity schemas before a startup artifact exists.
-spec rejects_wide_payload_test() -> ok.
rejects_wide_payload_test() ->
    ?assertError({xls_message_too_wide, message, 97, 96},
        artifact([{n, "hls_nums:uN(97)"}])).

%% Obtain the receiving schema through fresh complete source lowering, not an artifact map.
-spec artifact([{atom(), string()}]) -> hls_local_actor:artifact().
artifact(Fields) -> hls_protocol_schema_test_source:compile([{message, Fields}]).
