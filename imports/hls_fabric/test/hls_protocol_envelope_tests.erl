-module(hls_protocol_envelope_tests).
-moduledoc "Independent fixed-byte vectors for shared transport envelopes and their owner-side rejection rules. These are codec tests, not link or hardware witnesses.".
-include_lib("eunit/include/eunit.hrl").

%% Unequal bytes across every field distinguish numeric low-bit order from record order.
-spec packet_vector_test() -> ok.
packet_vector_test() ->
    Packet = packet(),
    Bytes = <<16#ff,16#ee,16#dd,16#cc,16#bb,16#aa,16#99,16#88,
        16#77,16#66,16#55,16#44,16#33,16#22,16#11,16#00,
        16#f1,16#ee,16#dd,16#cc,16#bb,16#aa,16#99,
        16#88,16#77,16#66,16#55,16#44,16#33,16#22,16#11,16#01>>,
    ?assertEqual(Bytes, hls_protocol_envelope:pack_packet(Packet)),
    ?assertEqual(Packet, hls_protocol_envelope:unpack_packet(Bytes)),
    ?assertEqual({{4,0,0}, Bytes}, hls_protocol_bridge_wire:packet(Packet)),
    ?assertEqual({packet, Packet}, hls_protocol_bridge_wire:event(
        maps:get(session, Packet), {16#84,0,0}, Bytes)).

%% The raw codec owns widths; policy restrictions on kind/session/sequence remain in the wire owner.
-spec packet_widths_test() -> ok.
packet_widths_test() ->
    Widths = [{frame,128}, {slot,8}, {link,16}, {sequence,32}, {session,64}, {kind,8}],
    ?assertEqual(Widths, [{Name, hls_type:width(Type)}
        || {Name, Type} <- hls_protocol_envelope:fields(packet)]),
    Zero = maps:from_list([{Name, 0} || {Name, _} <- Widths]),
    Maximum = maps:from_list([{Name, (1 bsl Bits)-1} || {Name, Bits} <- Widths]),
    ?assertEqual(<<0:256>>, hls_protocol_envelope:pack_packet(Zero)),
    Ones = binary:copy(<<255>>, 32),
    ?assertEqual(Ones, hls_protocol_envelope:pack_packet(Maximum)),
    ?assertEqual(Maximum, hls_protocol_envelope:unpack_packet(Ones)),
    lists:foreach(fun({Name, Bits}) ->
        ?assertException(error, _, hls_protocol_envelope:pack_packet(Zero#{Name := -1})),
        ?assertException(error, _, hls_protocol_envelope:pack_packet(Zero#{Name := 1 bsl Bits}))
    end, Widths),
    ?assertException(error, _, hls_protocol_envelope:unpack_packet(<<0:248>>)),
    ?assertException(error, _, hls_protocol_envelope:unpack_packet(<<0:264>>)).

%% Truncation sends exactly the declared ordinary words, each in little-endian order.
-spec rectangle_vectors_test() -> ok.
rectangle_vectors_test() ->
    Rectangle = rectangle(),
    Prefix = <<16#34,16#12,16#45,16#23,16#67,16#45,16#78,16#56,2,0,0,0>>,
    Payloads = [<<>>, <<16#98,16#ba,16#dc,16#fe>>,
        <<16#98,16#ba,16#dc,16#fe,16#ef,16#cd,16#ab,16#89>>,
        <<16#98,16#ba,16#dc,16#fe,16#ef,16#cd,16#ab,16#89,16#67,16#45,16#23,16#01>>],
    lists:foreach(fun({Words, Payload}) ->
        Value = Rectangle#{header := (16#9a bsl 24) bor Words},
        Expected = <<Prefix/binary, Words, 0, 0, 16#9a, Payload/binary>>,
        ?assertEqual(Expected, hls_protocol_envelope:pack_rectangle(Value, Words)),
        ?assertEqual(16+4*Words, byte_size(Expected)),
        Spatial = <<16#1234:16,16#2345:16,16#4567:16,16#5678:16,
            2:2, Words:8, 0:16, 16#9a:8, (maps:get(payload, Rectangle) band ((1 bsl (Words*32))-1)):96>>,
        ?assertEqual(Expected, hls_partition_wire:control_payload(Spatial))
    end, lists:enumerate(0, Payloads)).

%% Field bounds are schema constraints; rectangle ordering and reserved bits are decoder policy.
-spec rectangle_widths_test() -> ok.
rectangle_widths_test() ->
    Widths = [{x0,16}, {y0,16}, {x1,16}, {y1,16}, {target,32}, {header,32}, {payload,96}],
    ?assertEqual(Widths, [{Name, hls_type:width(Type)}
        || {Name, Type} <- hls_protocol_envelope:fields(rectangle)]),
    Maximum = maps:from_list([{Name, (1 bsl Bits)-1} || {Name, Bits} <- Widths]),
    ?assertEqual(binary:copy(<<255>>, 28), hls_protocol_envelope:pack_rectangle(Maximum, 3)),
    lists:foreach(fun({Name, Bits}) ->
        ?assertException(error, _, hls_protocol_envelope:pack_rectangle(Maximum#{Name := -1}, 3)),
        ?assertException(error, _, hls_protocol_envelope:pack_rectangle(Maximum#{Name := 1 bsl Bits}, 3))
    end, Widths),
    ?assertException(error, _, hls_protocol_envelope:pack_rectangle(rectangle(), -1)),
    ?assertException(error, _, hls_protocol_envelope:pack_rectangle(rectangle(), 4)).

%% Host packet framing continues to reject stale sessions and reserved or malformed actor envelopes.
-spec bridge_rejections_test() -> ok.
bridge_rejections_test() ->
    Packet = #{session := Session} = packet(),
    Bytes = hls_protocol_envelope:pack_packet(Packet),
    ?assertException(error, _, hls_protocol_bridge_wire:event(Session+1, {16#84,0,0}, Bytes)),
    lists:foreach(fun(Invalid) ->
        ?assertException(error, _, hls_protocol_bridge_wire:packet(Invalid)),
        ?assertException(error, _, hls_protocol_bridge_wire:event(Session, {16#84,0,0},
            hls_protocol_envelope:pack_packet(Invalid)))
    end, [Packet#{sequence := 16#ffffffff}, Packet#{kind := 2}, Packet#{kind := 0}, Packet#{kind := 3}]),
    ?assertException(error, _, hls_protocol_bridge_wire:packet(Packet#{session := 0})),
    lists:foreach(fun(Length) ->
        ?assertException(error, _, hls_protocol_bridge_wire:event(Session, {16#84,0,0},
            binary:copy(<<0>>, Length)))
    end, [0, 31, 33]),
    Ack = Packet#{kind := 2, frame := 0},
    {{4,0,0}, AckBytes} = hls_protocol_bridge_wire:packet(Ack),
    ?assertEqual({packet, Ack}, hls_protocol_bridge_wire:event(Session, {16#84,0,0}, AckBytes)).

%% Checked-in DSLX is the reproducible public schema artifact, not a second handwritten layout.
-spec generated_library_test() -> ok.
generated_library_test() ->
    Path = filename:join(code:priv_dir(hls_lowering), "xls/lib/protocol_envelope.x"),
    {ok, Source} = file:read_file(Path),
    ?assertEqual(Source, iolist_to_binary(xls_protocol_envelope:emit())).

%% Fields are deliberately distinct and include high bits in every non-policy-constrained word.
-spec packet() -> map().
packet() -> #{kind => 1, session => 16#1122334455667788, sequence => 16#99aabbcc,
    link => 16#ddee, slot => 16#f1, frame => 16#00112233445566778899aabbccddeeff}.

%% The rectangle fixture uses unequal ordered bounds and all three nonzero payload words.
-spec rectangle() -> map().
rectangle() -> #{x0 => 16#1234, y0 => 16#2345, x1 => 16#4567, y1 => 16#5678,
    target => 2, header => 16#9a000003, payload => 16#0123456789abcdeffedcba98}.

%% Native-to-envelope conversion cannot silently drop undeclared or out-of-capacity bits.
-spec rectangle_padding_rejection_test() -> ok.
rectangle_padding_rejection_test() ->
    lists:foreach(fun(Capacity) ->
        Clean = <<0:64, 0:2, 1:8, 0:16, 7:8, 19:Capacity>>,
        ?assertEqual(<<0:96, 1:8, 0:16, 7:8, 19:32/little>>,
            hls_partition_wire:control_payload(Clean)),
        BadLength = <<0:64, 0:2, 4:8, 0:16, 7:8, 0:Capacity>>,
        ?assertException(error, _, hls_partition_wire:control_payload(BadLength)),
        case Capacity > 32 of
            true ->
                BadPadding = <<0:64, 0:2, 1:8, 0:16, 7:8, (1 bsl 32):Capacity>>,
                ?assertException(error, _, hls_partition_wire:control_payload(BadPadding));
            false -> ok
        end
    end, [32, 96]).
