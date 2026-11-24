-module(xls_protocol_codec).
-moduledoc "Renders combinational DSLX codecs from the retained frame permutation used by runtime hls_protocol_codec. xls_protocol_partition installs these crossing codecs after planning; rendering owns no source analysis, storage or arbitration.".

%% Compact codec source rendering.
-export([emit/2]).

%% Exclusive codec output.
-export([write/3]).

-doc "Writes a combinational DSLX function for ready/valid encode and decode to a new file. Invalid input asserts fault and cannot handshake; the owner must handle that fault. Decode rejects a nonzero constant-only dummy bit. The tuple result is encoded, decoded, canonical, frame_ready, encoded_valid, encode_fault, payload_ready, decoded_valid, decode_fault. This function owns no storage or arbitration; producers hold valid input stable while stalled. Name must be a simple DSLX identifier.".
-spec write(hls_protocol_codec:plan(), string(), file:filename()) -> ok | {error, file:posix()}.
write(Plan, Name, Path) ->
    file:write_file(Path, emit(Plan, Name), [exclusive]).

-doc "Returns the combinational ready/valid codec as DSLX bytes without writing files. Preserves canonical-frame checks, constant-only dummy validation and the write/3 tuple interface; Name must be a simple DSLX identifier.".
-spec emit(hls_protocol_codec:plan(), string()) -> iodata().
emit(
    #{
        frame_layout := FrameLayout,
        mask := Mask,
        value := Value,
        frame_positions := Positions,
        physical_width := Width,
        payload_bits := Bits
    },
    Name
) ->
    FrameBits = hls_frame_layout:frame_bits(FrameLayout),
    match = re:run(Name, "^[a-zA-Z_][a-zA-Z0-9_]*$", [{capture, none}]),
    Inverse = maps:from_list([{J, I} || {I, J} <- lists:enumerate(0, Positions)]),
    [
        "import axis;\nconst_assert!(axis::FRAME_BITS == u32:",
        n(FrameBits),
        ");\n",
        "pub fn ",
        Name,
        "(frame: bits[",
        n(FrameBits),
        "], payload: bits[",
        n(Width),
        "], frame_valid: bool, encoded_ready: bool, payload_valid: bool, decoded_ready: bool) ->\n",
        "(bits[",
        n(Width),
        "], bits[",
        n(FrameBits),
        "], bool, bool, bool, bool, bool, bool, bool) {\n",
        "let canonical = (frame & bits[",
        n(FrameBits),
        "]:",
        n(Mask),
        ") == bits[",
        n(FrameBits),
        "]:",
        n(Value),
        ";\n",
        "let payload_canonical = ",
        case Bits of
            0 -> "payload == u1:0";
            _ -> "true"
        end,
        ";\n",
        "let encoded = ",
        wiring(
            case Positions of
                [] -> [{constant, 0}];
                _ -> [{source, frame, J} || J <- lists:reverse(Positions)]
            end
        ),
        ";\n",
        "let decoded = ",
        wiring([
            case maps:find(J, Inverse) of
                {ok, I} -> {source, payload, I};
                error -> {constant, (Value bsr J) band 1}
            end
         || J <- lists:seq(FrameBits - 1, 0, -1)
        ]),
        ";\n",
        "(encoded, decoded, canonical, encoded_ready && canonical, frame_valid && canonical, frame_valid && !canonical,\n",
        " decoded_ready && payload_canonical, payload_valid && payload_canonical, payload_valid && !payload_canonical) }\n"
    ].

%% Wiring bits are listed most-significant first; source indices name unchanged input bits.
-type wiring_bit() :: {source, frame | payload, non_neg_integer()} | {constant, 0 | 1}.
%% A chunk preserves one descending source slice or a complete constant bitstring.
-type chunk() ::
    {slice, frame | payload, non_neg_integer(), pos_integer()}
    | {literal, pos_integer(), non_neg_integer()}.

%% Coalesce fixed spans and use a balanced tree: wide frame padding must not create
%% hundreds of nested parametric concat widths for the DSLX type checker.
-spec wiring([wiring_bit(), ...]) -> iodata().
wiring(Bits) -> concat([fragment(Chunk) || Chunk <- chunks(Bits, [])]).

%% Only descending adjacent indices can become a slice; byte-bit reversals stay explicit.
-spec chunks([wiring_bit()], [chunk()]) -> [chunk()].
chunks([{source, Name, Index} | Rest], [{slice, Name, Low, Width} | Acc]) when Index + 1 =:= Low ->
    chunks(Rest, [{slice, Name, Index, Width + 1} | Acc]);
chunks([{constant, Bit} | Rest], [{literal, Width, Value} | Acc]) ->
    chunks(Rest, [{literal, Width + 1, (Value bsl 1) bor Bit} | Acc]);
chunks([{source, Name, Index} | Rest], Acc) ->
    chunks(Rest, [{slice, Name, Index, 1} | Acc]);
chunks([{constant, Bit} | Rest], Acc) ->
    chunks(Rest, [{literal, 1, Bit} | Acc]);
chunks([], Acc) ->
    lists:reverse(Acc).

%% Every emitted fragment is constant wiring; no runtime shift, index or selection is added.
-spec fragment(chunk()) -> iodata().
fragment({slice, Name, Low, Width}) ->
    [atom_to_list(Name), "[", n(Low), "+:bits[", n(Width), "]]"];
fragment({literal, Width, Value}) ->
    ["bits[", n(Width), "]:0x", integer_to_list(Value, 16)].

%% Parenthesization changes type-inference depth, not concatenation order.
-spec concat([iodata(), ...]) -> iodata().
concat([Part]) ->
    Part;
concat(Parts) ->
    {Left, Right} = lists:split(length(Parts) div 2, Parts),
    ["(", concat(Left), " ++ ", concat(Right), ")"].

%% Decimal dimensions do not carry runtime data into generated source.
-spec n(integer()) -> string().
n(N) -> integer_to_list(N).
