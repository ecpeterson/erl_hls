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
        concat(
            case Positions of
                [] -> ["u1:0"];
                _ -> [["frame[", n(J), "+:u1]"] || J <- lists:reverse(Positions)]
            end
        ),
        ";\n",
        "let decoded = ",
        concat([
            case maps:find(J, Inverse) of
                {ok, I} -> ["payload[", n(I), "+:u1]"];
                error -> ["u1:", n((Value bsr J) band 1)]
            end
         || J <- lists:seq(FrameBits - 1, 0, -1)
        ]),
        ";\n",
        "(encoded, decoded, canonical, encoded_ready && canonical, frame_valid && canonical, frame_valid && !canonical,\n",
        " decoded_ready && payload_canonical, payload_valid && payload_canonical, payload_valid && !payload_canonical) }\n"
    ].

%% Static wiring concatenations contain no runtime index or selection logic.
-spec concat([iolist()]) -> iolist().
concat(Parts) -> ["(", lists:join(" ++ ", Parts), ")"].

%% Decimal dimensions do not carry runtime data into generated source.
-spec n(integer()) -> string().
n(N) -> integer_to_list(N).
