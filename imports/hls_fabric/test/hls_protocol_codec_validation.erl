-module(hls_protocol_codec_validation).
-moduledoc "Finite RTL witnesses for source-bound frame permutations and canonical-frame rejection.".
-export([prepare/1, prepare_layouts/1]).

-doc "Compiles the complete two-phase fixture, derives captures from that program and writes four codec modules and self-checking benches to a fresh directory. Checks payload bit bases, extremes, all five-bit payloads, every forbidden fixed-bit flip and every valid/ready combination. This is a finite source-to-RTL witness, not a connected-protocol proof.".
-spec prepare(file:filename()) -> ok.
prepare(Stage) ->
    ok = file:make_dir(Stage),
    Channels = [#{source => a, port => Tag, tag => Tag, destination => {actor, b}}
        || Tag <- [unaligned, full, constant, small]],
    Program = xls_actor_program:from_file("test/hls_protocol_capture_fixture.erl", []),
    #{channels := Captures} = hls_protocol_capture:plan(#{channels => Channels}, #{a => Program}),
    lists:foreach(fun(Channel = #{port := Tag}) -> write_case(Stage, atom_to_list(Tag), Channel, hls_protocol_capture_fixture) end, Captures).

-doc "Writes native codec witnesses at one-word and three-word ordinary capacities from the same small source. Both runs check source packing independently of the generated frame permutation, all fixed-bit rejections, and every ready/valid combination. Creates a fresh stage; this finite witness does not qualify connected progress.".
-spec prepare_layouts(file:filename()) -> ok.
prepare_layouts(Stage) ->
    ok = file:make_dir(Stage),
    lists:foreach(fun(Words) ->
        Directory = filename:join(Stage, "words" ++ integer_to_list(Words)),
        ok = file:make_dir(Directory),
        Layout = hls_frame_layout:new(Words),
        ok = file:write_file(filename:join(Directory, "frame_config.x"), hls_frame_layout:config_dslx(Layout), [exclusive]),
        Channels = [#{source => a, port => Tag, tag => Tag, destination => {actor, b}}
            || Tag <- [narrow, constant, small]],
        Program = xls_actor_program:from_file("test/hls_protocol_frame_fixture.erl", [], Layout),
        #{channels := Captures} = hls_protocol_capture:plan(#{channels => Channels}, #{a => Program}),
        lists:foreach(fun(Channel = #{port := Tag}) ->
            write_case(Directory, atom_to_list(Tag), Channel, hls_protocol_frame_fixture)
        end, Captures)
    end, [1, 3]).

%% RTL and host codecs are checked against independent record packing and explicit physical header bytes.
-spec write_case(file:filename(), string(), map(), module()) -> ok.
write_case(Stage, Name, Channel = #{source_operation := Op, port := Tag}, SourceModule) ->
    Codec = hls_protocol_codec_plan:plan(Channel, Op),
    #{frame_layout := Layout, payload_bits := Bits, physical_width := Width, mask := Mask, value := Value} = Codec,
    FrameBits = hls_frame_layout:frame_bits(Layout),
    Module = "codec_" ++ Name,
    ok = xls_protocol_codec:write(Codec, Module, filename:join(Stage, Module ++ ".x")),
    Payloads = case Bits of
        N when N =< 5 -> lists:seq(0, (1 bsl N) - 1);
        N -> [0, (1 bsl N) - 1 | [1 bsl I || I <- lists:seq(0, N - 1)]]
    end,
    Checks = [begin
        Frame = oracle_frame(SourceModule, Tag, Payload, Bits, FrameBits, Op),
        Frame = hls_protocol_codec:decode(Codec, Payload),
        {ok, Payload} = hls_protocol_codec:encode(Codec, Frame),
        ["frame=", literal(FrameBits, Frame), "; payload=", literal(Width, Payload), "; handshake(1,1); #1;\n",
         "if (canonical !== 1'b1 || encoded !== ", literal(Width, Payload),
         " || decoded !== ", literal(FrameBits, Frame), ") $fatal(1, \"roundtrip ", Name, "\");\n"]
    end || Payload <- Payloads],
    Rejections = [begin
        Bad = Value bxor (1 bsl I),
        {error, invalid_frame} = hls_protocol_codec:encode(Codec, Bad),
        ["frame=", literal(FrameBits, Bad), "; handshake(0,1); #1; if (canonical !== 1'b0) $fatal(1, \"canonical bit ",
            integer_to_list(I), "\");\n"]
    end || I <- lists:seq(0, FrameBits - 1), Mask band (1 bsl I) =/= 0],
    DummyCheck = case Bits of
        0 -> ["frame=", literal(FrameBits, Value), "; payload=1'b1; handshake(1,0);\n"];
        _ -> []
    end,
    Source = ["module tb;\nreg [", integer_to_list(FrameBits - 1), ":0] frame; reg [", integer_to_list(Width - 1),
        ":0] payload; wire [", integer_to_list(Width - 1), ":0] encoded; wire [", integer_to_list(FrameBits - 1), ":0] decoded; wire canonical;\n",
        "reg frame_valid, encoded_ready, payload_valid, decoded_ready;\n",
        "wire frame_ready, encoded_valid, encode_fault, payload_ready, decoded_valid, decode_fault;\n",
        Module, " dut(.frame(frame),.payload(payload),.frame_valid(frame_valid),.encoded_ready(encoded_ready),\n",
        ".payload_valid(payload_valid),.decoded_ready(decoded_ready),\n",
        ".out({encoded,decoded,canonical,frame_ready,encoded_valid,encode_fault,payload_ready,decoded_valid,decode_fault}));\n", handshake(), "initial begin\n", Checks, Rejections, DummyCheck,
        "$display(\"PASS ", Name, " payloads=", integer_to_list(length(Payloads)),
        " fixed_flips=", integer_to_list(length(Rejections)),
        " control_combinations=16 dummy_rejection=", integer_to_list(case Bits of 0->1;_->0 end),
        "\"); $finish; end\nendmodule\n"],
    file:write_file(filename:join(Stage, Name ++ "_tb.sv"), Source, [exclusive]).

%% Independent backpressure never consumes a bad input; faults are valid-qualified and need owner handling.
-spec handshake() -> iolist().
handshake() ->
    ["task handshake(input expected_frame, input expected_payload); integer controls; begin\n",
     "for (controls=0; controls<16; controls=controls+1) begin\n",
     "{frame_valid,encoded_ready,payload_valid,decoded_ready}=controls[3:0]; #1;\n",
     "if (frame_ready !== (encoded_ready && expected_frame) ||\n",
     "    encoded_valid !== (frame_valid && expected_frame) ||\n",
     "    encode_fault !== (frame_valid && !expected_frame) ||\n",
     "    payload_ready !== (decoded_ready && expected_payload) ||\n",
     "    decoded_valid !== (payload_valid && expected_payload) ||\n",
     "    decode_fault !== (payload_valid && !expected_payload)) $fatal(1, \"handshake/fault\");\n",
     "end end endtask\n"].

%% The literal width prevents implicit Verilog sign extension or host integer truncation.
-spec literal(pos_integer(), non_neg_integer()) -> iolist().
literal(Width, Value) -> [integer_to_list(Width), "'h", integer_to_list(Value, 16)].

%% Compact bit zero is the first physical stream bit; fixture records supply an independent packing oracle.
-spec oracle_frame(module(), atom(), non_neg_integer(), non_neg_integer(), pos_integer(), byte()) -> non_neg_integer().
oracle_frame(Module, Tag, Payload, Bits, FrameBits, Op) ->
    Dynamic = << <<((Payload bsr I) band 1):1>> || I <- lists:seq(0, Bits - 1) >>,
    Record = case {Tag, Dynamic} of
        {unaligned, <<Epoch:13/little, Value:46/little>>} -> {unaligned, 5, Epoch, Value, 1};
        {full, <<Value:96/little>>} -> {full, Value};
        {narrow, <<Value:25/little>>} -> {narrow, 5, Value, 1};
        {constant, <<>>} -> {constant, 6};
        {small, <<Value:5/little>>} -> {small, Value}
    end,
    Packed = Module:pack(Record),
    Words = (bit_size(Packed) + 31) div 32,
    Padding = FrameBits - 32 - bit_size(Packed),
    binary:decode_unsigned(<<Words:8, 0:16, Op:8, Packed/bitstring, 0:Padding>>, little).
