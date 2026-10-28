-module(hls_frame_layout_tests).
-moduledoc "Checks canonical header packing, selectable payload bounds, known bits and source-to-renderer layout propagation.".
-include_lib("eunit/include/eunit.hrl").

%% Capacity validation belongs to one public constructor, including noninteger options.
-spec capacity_test() -> ok.
capacity_test() ->
    ?assertEqual(hls_frame_layout:new(3), hls_frame_layout:default()),
    [?assertError({hls_diagnostic, #{stage := frame_layout, code := invalid_frame_payload_words,
        context := #{value := Value}}}, hls_frame_layout:new(Value))
        || Value <- [0, -1, 256, 3.0, <<"3">>]],
    [?assertEqual(#{name => canonical_actor_v1, header_bits => 32,
        payload_words => Words, payload_bits => Words * 32,
        frame_bits => (Words + 1) * 32, parameterized => true},
        hls_frame_layout:descriptor(hls_frame_layout:new(Words))) || Words <- [1, 3, 5, 255]],
    ok.

%% Header serialization follows the shared typed schema, not host integer field shifts.
-spec header_schema_test() -> ok.
header_schema_test() ->
    Header = #{payload_words => 5, txid => 17, flags => 192, op => 253},
    ?assertEqual(<<5, 17, 192, 253>>, hls_frame_layout:pack_header(Header)),
    ?assertEqual(Header, hls_frame_layout:unpack_header(<<5, 17, 192, 253>>)),
    ?assertEqual([0, 8, 16, 24], [hls_frame_layout:header_offset(Name)
        || {Name, _} <- hls_frame_layout:header_fields()]),
    ?assertError(badarg, hls_frame_layout:pack_header(Header#{op := 256})).

%% Empty, sub-byte and full-capacity payloads share one physical-to-numeric conversion.
-spec frame_roundtrip_test() -> ok.
frame_roundtrip_test() ->
    [begin
        Layout = hls_frame_layout:new(Words),
        Capacity = hls_frame_layout:payload_bits(Layout),
        [begin
            Packed = hls_frame_layout:pack(Layout, #{op => 9, txid => 7, flags => 2}, Payload),
            ?assertEqual((Words + 1) * 32, bit_size(Packed)),
            Expected = {#{payload_words => (bit_size(Payload) + 31) div 32,
                op => 9, txid => 7, flags => 2}, hls_codec:align(Payload, 32)},
            ?assertEqual(Expected, hls_frame_layout:unpack(Layout, Packed)),
            ?assertEqual(Expected, hls_frame_layout:unpack_integer(Layout,
                hls_frame_layout:pack_integer(Layout, #{op => 9, txid => 7, flags => 2}, Payload)))
        end || Payload <- [<<>>, <<16#13ab:13/little>>, <<1:Capacity/little>>]],
        OverCapacity = Capacity + 1,
        ?assertError({frame_payload_too_wide, OverCapacity, Capacity},
            hls_frame_layout:pack(Layout, 9, <<0:(Capacity + 1)>>))
    end || Words <- [1, 3, 5]],
    ok.

%% Declared length and nonzero bytes beyond it cannot silently change the host value.
-spec malformed_frame_test() -> ok.
malformed_frame_test() ->
    Layout = hls_frame_layout:new(3),
    ?assertError({frame_payload_too_wide, 128, 96},
        hls_frame_layout:unpack(Layout, <<4, 0, 0, 9, 0:96>>)),
    ?assertError(nonzero_frame_padding,
        hls_frame_layout:unpack(Layout, <<1, 0, 0, 9, 0:32, 1:64/little>>)),
    ?assertError(badarg, hls_frame_layout:unpack_integer(Layout, 1 bsl 128)),
    ?assertError(badarg, hls_frame_layout:unpack_integer(Layout, -1)).

%% Known payload bits retain physical order; header and every unused capacity bit are known.
-spec known_bits_test() -> ok.
known_bits_test() ->
    Fields = [#{type => hls_nums:uN(3), domain => {values, [<<5:3>>]}},
        #{type => hls_nums:uN(10), domain => unknown}],
    MaskStream = <<7:3, 0:10>>,
    ValueStream = <<5:3, 0:10>>,
    [begin
        Layout = hls_frame_layout:new(Words),
        Capacity = hls_frame_layout:payload_bits(Layout),
        Bound = xls_message_bits:frame(9, Fields, Layout),
        ?assertEqual(hls_frame_layout:bounds(Layout, 9, MaskStream, ValueStream), Bound),
        #{mask := Mask, value := Value} = Bound,
        ?assertEqual(hls_frame_layout:pack_integer(Layout, 9, ValueStream), Value),
        ?assertEqual(hls_codec:unsigned(<<255, 255, 255, 255, MaskStream/bitstring,
            ((1 bsl (Capacity - 13)) - 1):(Capacity - 13)>>), Mask),
        Full = hls_frame_layout:bounds(Layout, 9, <<8191:13>>, ValueStream),
        ?assertEqual((1 bsl hls_frame_layout:frame_bits(Layout)) - 1, maps:get(mask, Full))
    end || Words <- [3, 5]],
    ok.

%% Little-endian byte permutations must handle the final partial byte rather than pad fields.
-spec stream_bit_positions_test() -> ok.
stream_bit_positions_test() ->
    [begin
        Stream = <<(1 bsl Bit):Width/little>>,
        Position = hls_codec:stream_bit_index(Width, Bit),
        <<_:Position, Set:1, _/bitstring>> = Stream,
        ?assertEqual(1, Set),
        ?assertEqual(Bit, hls_codec:stream_bit_index(Width, Position))
    end || Width <- [1, 3, 8, 13, 16, 31], Bit <- lists:seq(0, Width - 1)],
    ok.

%% A wide source is rejected by default but selected layout reaches artifact, plan and facts together.
-spec selected_actor_layout_test() -> ok.
selected_actor_layout_test() ->
    File = "test_data/xls_frame_layout_fixture.erl",
    ?assertError({hls_diagnostic, #{stage := actor_source, code := message_too_wide,
        context := #{width := 128, max_width := 96}}}, xls_actor_program:from_file(File, [])),
    Layout = hls_frame_layout:new(5),
    Program = xls_actor_program:from_file(File, [], Layout),
    Spec = xls_actor_program:spec(Program),
    ?assertEqual(Layout, maps:get(frame_layout, Spec)),
    ?assertEqual(4, maps:get(message, maps:get(message_words, Spec))),
    Plan = xls_actor_program:plan(Program),
    ?assertEqual(Layout, maps:get(frame_layout, maps:get(protocol,
        xls_statem_plan:select(Plan, [{idle, enter}])))),
    ?assertEqual(ok, xls_statem_plan:validate(File, [], Plan)),
    {_, Facts} = xls_message_facts:from_file(File, [], Layout),
    ?assertEqual(ok, xls_message_facts:validate(File, [], Facts)),
    ?assertEqual(#{mask => (1 bsl 192) - 1,
        value => hls_frame_layout:pack_integer(Layout, 3, <<1:64/little, 2:64/little>>)},
        xls_message_facts:frame_bits(Facts, [out])),
    Text = iolist_to_binary(xls_parse:to_xls(File, #{frame_payload_words => 5})),
    ?assertNotEqual(nomatch, binary:match(Text, <<"const_assert!(axis::FRAME_BITS == u32:192)">>)).

%% Reply effects hold a complete selected frame; ownership bookkeeping stays its separate format.
-spec retained_reply_layout_test() -> ok.
retained_reply_layout_test() ->
    Layout = hls_frame_layout:new(5),
    Spec = xls_parse:actor_artifact("test/hls_statem_reply_fixture.erl", [], Layout),
    Text = iolist_to_binary(xls_statem_codegen:emit(Spec)),
    ?assertNotEqual(nomatch, binary:match(Text, <<"ENTRY_EFFECT_PAYLOAD_BITS = u32:192">>)),
    ?assertNotEqual(nomatch, binary:match(Text, <<"effects.payloads as bits[axis::FRAME_BITS]">>)),
    ?assertEqual(xls_statem_reply_codegen:width(Spec),
        xls_statem_reply_codegen:width(Spec#{frame_layout := hls_frame_layout:default()})).

%% The repository's default support file is generated by the same schema used in bundles.
-spec default_config_test() -> ok.
default_config_test() ->
    {ok, Default} = file:read_file("priv/xls/lib/frame_config.x"),
    ?assertEqual(Default, iolist_to_binary(xls_frame_layout:config(hls_frame_layout:default()))).
