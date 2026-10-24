-module(xls_struct_codec_dslx).
-moduledoc "Finite generated struct-codec witnesses against independent BEAM field packing; no arbitrary-value or compiler correctness claim.".
-export([write/1]).

%% Host values retain record tags while generated DSLX uses nominal structs.
-type sample() :: {sample, integer(), integer(), [non_neg_integer()],
    {pair, non_neg_integer(), integer()}, bitstring(), non_neg_integer()}.

-doc "Writes standalone stream/LSB codec witnesses into an existing directory. Expected stream bits come from hls_record; LSB expectations concatenate independently packed fields. Includes nested records, signed/padded fields, vectors, zero-width fields and empty structs.".
-spec write(file:filename()) -> ok.
write(Stage) ->
    Pair = [{first, hls_nums:uN(9)}, {second, hls_bits:padded(hls_nums:sN(3), 5)}],
    Fields = [{signed_value, hls_nums:sN(5)},
        {padded_value, hls_bits:padded(hls_nums:sN(3), 7)},
        {values, hls_vec:vector(hls_bits:padded(hls_nums:uN(3), 5), 2)},
        {nested, {hls_type, hls_record, pair, Pair}},
        {empty_bits, hls_bits:bits(0)}, {tail, hls_nums:uN(9)}],
    Samples = [{sample, -7, -3, [1, 6], {pair, 257, -2}, <<>>, 389},
        {sample, 15, 3, [7, 0], {pair, 42, 1}, <<>>, 17}],
    Source = ["import hls_bits;\n\n",
        codecs("Pair", "pair", Pair, stream),
        codecs("StreamCell", "stream_cell", Fields, stream),
        codecs("LsbCell", "lsb_cell", Fields, lsb),
        codecs("EmptyStream", "empty_stream", [], stream),
        codecs("EmptyLsb", "empty_lsb", [], lsb),
        [witness(Index, Sample, Fields) || {Index, Sample} <- lists:enumerate(Samples)],
        empty_witness()],
    ok = file:write_file(filename:join(Stage, "struct_codecs.x"), Source).

%% Every consumer uses the public numeric layout and independently named codecs.
-spec codecs(string(), string(), hls_record:fields(), stream | lsb) -> iodata().
codecs(Type, Stem, Fields, Order) ->
    Layout = xls_struct_codec:layout(Fields, Order),
    [xls_struct_codec:declaration(Type, Layout), "\n",
        xls_struct_codec:encoder(Type, "bits_from_" ++ Stem, Layout), "\n",
        xls_struct_codec:decoder(Type, Stem ++ "_from_bits", Layout), "\n"].

%% Exact packed constants constrain both directions; trailing physical bits must not enter stream fields.
-spec witness(pos_integer(), sample(), hls_record:fields()) -> iodata().
witness(Index, Sample, Fields) ->
    Packed = hls_record:pack(Sample, sample, Fields),
    Wider = <<Packed/bitstring, 16#5a3:11>>,
    ["// Fixed host-derived witness; inner padding and field order remain observable.\n",
        "#[test]\nfn host_codec_", integer_to_list(Index), "() {\n",
        "  let streamed = ", value("StreamCell", Sample), ";\n",
        "  let local = ", value("LsbCell", Sample), ";\n",
        "  let expected_stream = ", packed_literal(Packed), ";\n",
        "  let expected_lsb = ", lsb_expected(Sample, Fields), ";\n",
        "  assert_eq(bits_from_stream_cell(streamed), expected_stream);\n",
        "  assert_eq(stream_cell_from_bits(expected_stream), streamed);\n",
        "  assert_eq(stream_cell_from_bits(", packed_literal(Wider), "), streamed);\n",
        "  assert_eq(bits_from_lsb_cell(local), expected_lsb);\n",
        "  assert_eq(lsb_cell_from_bits(expected_lsb), local);\n",
        "}\n\n"].

%% First fields occupy low numeric slices; each field's host provider owns its internal wire order.
-spec lsb_expected(sample(), hls_record:fields()) -> iodata().
lsb_expected(Sample, Fields) ->
    Packed = [packed_literal(hls_type:pack(Value, Type))
        || {Value, {_, Type}} <- lists:zip(tl(tuple_to_list(Sample)), Fields)],
    lists:join(" ++ ", lists:reverse(Packed)).

%% Erlang's little-integer interpretation matches the existing DSLX physical-bit boundary.
-spec packed_literal(bitstring()) -> iodata().
packed_literal(Bits) ->
    ["bits[", integer_to_list(bit_size(Bits)), "]:", integer_to_list(hls_codec:unsigned(Bits))].

%% Typed values are written directly, without using either generated decoder as an oracle.
-spec value(string(), sample()) -> iodata().
value(Type, {sample, Signed, Padded, Values, {pair, First, Second}, <<>>, Tail}) ->
    [Type, " { signed_value: sN[5]:", integer_to_list(Signed),
        ", padded_value: sN[3]:", integer_to_list(Padded),
        ", values: [", lists:join(", ", [["uN[3]:", integer_to_list(V)] || V <- Values]),
        "], nested: Pair { first: uN[9]:", integer_to_list(First),
        ", second: sN[3]:", integer_to_list(Second), " }, empty_bits: (bits[0]:0,), tail: uN[9]:",
        integer_to_list(Tail), " }"].

%% Empty structs contain no payload; stream decoding ignores every physical padding bit.
-spec empty_witness() -> iodata().
empty_witness() ->
    ["// Zero-width records remain distinct nominal values with no wire payload.\n",
        "#[test]\nfn empty_codecs() {\n",
        "  let stream = EmptyStream {};\n",
        "  let local = EmptyLsb {};\n",
        "  assert_eq(bits_from_empty_stream(stream), bits[0]:0);\n",
        "  assert_eq(empty_stream_from_bits(bits[0]:0), stream);\n",
        "  assert_eq(empty_stream_from_bits(bits[11]:1443), stream);\n",
        "  assert_eq(bits_from_empty_lsb(local), bits[0]:0);\n",
        "  assert_eq(empty_lsb_from_bits(bits[0]:0), local);\n",
        "}\n"].
