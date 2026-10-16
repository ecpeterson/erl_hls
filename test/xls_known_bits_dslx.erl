-module(xls_known_bits_dslx).
-moduledoc "Generated DSLX witnesses for compressed entry payloads; expected frames use the independent BEAM ABI codec.".
-export([write/1]).

-doc "Writes a generated fixture, a total entry-observation probe, and finite source-derived codec/failure witnesses. The probe masks uncommitted data/effects on failure but retains its exact code.".
-spec write(file:filename()) -> ok.
write(Stage) ->
    Source = xls_parse:to_xls("test/xls_known_bits_fixture.erl"),
    {ok, Probe} = file:read_file("test_data/xls_known_bits_probe.inc.x"),
    Cases = [{V, S, Signed} || V <- [0, 1, 16#1234, 16#ffff],
        {S, Signed} <- [{0, -16}, {31, -1}, {21, 15}]],
    file:write_file(filename:join(Stage, "known_bits.x"),
        [Source, Probe, [witness(I, C) || {I, C} <- lists:enumerate(Cases)],
        "\n#[test]\nfn masked_failure_is_retained() {\n",
        "  let c = Cell { value: u16:1, denominator: u16:0, ..zero!<Cell>() };\n",
        "  let o = enter(Phase::ACTIVE, Phase::ACTIVE, c);\n",
        "  assert_eq(hls_failure::kind(o.failure), hls_failure::Kind::BADARITH);\n}\n"]).

%% BEAM evaluation defines source order and the original emitted frame fields.
-spec witness(pos_integer(), tuple()) -> iodata().
witness(Index, {Value, Small, Signed}) ->
    Cell = {cell, Value, Small, Signed, 1},
    {Cell, Actions} = xls_known_bits_fixture:active(enter, active, Cell),
    ["\n#[test]\nfn codec_", integer_to_list(Index), "() {\n",
        "  let c = Cell { value: u16:", integer_to_list(Value),
        ", small: u5:", integer_to_list(Small), ", signed: s5:", integer_to_list(Signed),
        ", denominator: u16:1 };\n",
        "  let o = enter(Phase::ACTIVE, Phase::ACTIVE, c);\n",
        "  assert_eq(o.failure, hls_failure::NONE);\n",
        "  assert_eq(o.data, c);\n",
        "  assert_eq(entry_effect_count(o.effects), u8:2);\n",
        [effect(N, A) || {N, A} <- lists:enumerate(0, Actions)], "}\n"].

%% Stream-order constants deliberately avoid duplicating the compiler slice codec.
-spec effect(non_neg_integer(), tuple()) -> iodata().
effect(Index, {cast, Port, Message}) ->
    Packed = xls_known_bits_fixture:pack(Message), Width = bit_size(Packed), <<Bits:Width>> = Packed,
    ["  assert_eq(entry_effect(o.effects, u8:", integer_to_list(Index), "), Egress { port: OutputPort::",
        string:uppercase(atom_to_list(Port)), ", frame: axis::pack(Tag::PACKET as u8, ",
        "hls_bits::frame_payload(hls_bits::from_stream(uN[", integer_to_list(Width), "]:",
        integer_to_list(Bits), "))) });\n"].
