-module(xls_entry_storage_dslx).
-moduledoc false.
-export([write/1]).

-doc "Writes field-sharing codec witnesses against compiled Erlang callback results.".
-spec write(file:filename()) -> ok.
write(Stage) ->
    Generated = xls_parse:to_xls("test/xls_entry_storage_fixture.erl"),
    Cases = [{Phase, Key, Positive, Negative, Flag, Tail}
        || Phase <- [repeated, independent, conditional], Key <- [0, 16#ffff, 16#fffffffd],
           {Positive, Negative, Flag, Tail} <- [{0, 0, false, 0}, {31, -16, true, 65535}, {17, 9, true, 16#1234}]],
    file:write_file(filename:join(Stage, "xls_entry_storage.x"),
        [Generated, [witness(Index, Case) || {Index, Case} <- lists:enumerate(Cases)]]).

%% Expected wire bits come from the independent BEAM-side record codec.
-spec witness(pos_integer(), tuple()) -> iodata().
witness(Index, {Phase, Key, Positive, Negative, Flag, Tail}) ->
    Sample = {sample, Positive, Negative, Flag},
    Cell = {cell, Key, Sample, Tail},
    {Cell, Actions} = xls_entry_storage_fixture:Phase(enter, Phase, Cell),
    PhaseName = string:uppercase(atom_to_list(Phase)),
    ["\n#[test]\nfn shared_fields_", integer_to_list(Index), "() {\n",
        "  let cell = Cell { key: u32:", integer_to_list(Key), ", sample: Sample { positive: u5:",
        integer_to_list(Positive), ", negative: s5:", integer_to_list(Negative), ", flag: ",
        atom_to_list(Flag), " }, tail: u16:", integer_to_list(Tail), " };\n",
        "  let outcome = enter(Phase::", PhaseName, ", Phase::", PhaseName, ", cell);\n",
        "  assert_eq(outcome.failure, hls_failure::NONE);\n",
        "  assert_eq(outcome.data, cell);\n",
        "  assert_eq(entry_effect_count(outcome.effects), u8:3);\n",
        [effect(N, Action) || {N, Action} <- lists:enumerate(0, Actions)], "}\n"].

%% Check frame tag, length, exact payload and routed order for every output.
-spec effect(non_neg_integer(), tuple()) -> iodata().
effect(Index, {cast, Port, Message}) ->
    Packed = xls_entry_storage_fixture:pack(Message),
    Width = bit_size(Packed),
    <<Bits:Width>> = Packed,
    ["  assert_eq(entry_effect(outcome.effects, u8:", integer_to_list(Index), "), Egress {\n",
        "    port: OutputPort::", string:uppercase(atom_to_list(Port)), ",\n",
        "    frame: axis::pack(Tag::PACKET as u8, hls_bits::frame_payload(hls_bits::from_stream(uN[",
        integer_to_list(Width), "]:", integer_to_list(Bits), "))) });\n"].
