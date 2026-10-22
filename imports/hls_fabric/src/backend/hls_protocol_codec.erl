-module(hls_protocol_codec).
-moduledoc "Lossless projection between a source-bound ordinary frame and a typed capture payload. This is a wire codec, not receipt eligibility or a network lifetime proof.".
-export([plan/2, encode/2, decode/2, write/3]).

-doc "Builds a bit permutation for one capture channel and its ordinary operation byte. Header, padding and source-constant fields use the shared entry ABI; dynamic fields remain exact, including partial bytes. Compact bit zero is the first dynamic physical stream bit. Rejects inconsistent capture offsets, overlapping fields or payloads wider than the ordinary 96-bit frame. The caller must establish source/schema/route provenance before omitting fields.".
-spec plan(map(), 0..255) -> map().
plan(#{fields:=Fields, message_bits:=MessageBits, payload_bits:=PayloadBits}, Op)
        when Op >= 0, Op < 256 ->
    {MessageBits,PayloadBits}=lists:foldl(fun check_field/2,{0,0},Fields),
    Bound=xls_message_bits:frame(Op,[bound(F)||F<-Fields]),
    Positions=lists:append([case maps:is_key(constant,F) of
        true->[];
        false->[32+wire_bit(J)||J<-lists:seq(maps:get(message_bit_offset,F),
            maps:get(message_bit_offset,F)+hls_type:width(maps:get(type,F))-1)]
    end||F<-Fields]),
    PayloadBits=length(Positions),
    Dynamic=lists:foldl(fun(J,M)->M bor (1 bsl J) end,0,Positions),
    true=length(lists:usort(Positions))=:=PayloadBits,
    true=(Dynamic bxor maps:get(mask,Bound))=:=(1 bsl 128)-1,
    Bound#{frame_positions=>Positions,payload_bits=>PayloadBits,
        physical_width=>max(1,PayloadBits),operation=>Op}.

-doc "Projects a canonical ordinary frame, rejecting a wrong operation, header, padding or omitted constant field. Runtime receipt guards and generation matching are separate checks. The integer frame is the ordinary 128-bit DSLX representation.".
-spec encode(map(), non_neg_integer()) -> {ok,non_neg_integer()} | {error,invalid_frame}.
encode(#{mask:=Mask,value:=Value,frame_positions:=Positions},Frame)
        when Frame >= 0, Frame < (1 bsl 128) ->
    case Frame band Mask =:= Value of
        true->{ok,lists:foldl(fun({I,J},Bits)->Bits bor (((Frame bsr J) band 1) bsl I) end,
            0,lists:enumerate(0,Positions))};
        false->{error,invalid_frame}
    end;
encode(_,_) -> {error,invalid_frame}.

-doc "Restores the exact ordinary frame from a canonical compact payload. A constant-only channel uses a zero-valued dummy wire; nonzero dummy or excess payload bits are rejected. This does not validate semantic payload values.".
-spec decode(map(), non_neg_integer()) -> non_neg_integer().
decode(#{value:=Value,frame_positions:=Positions,payload_bits:=Width},Payload)
        when Payload >= 0, Payload < (1 bsl Width) ->
    lists:foldl(fun({I,J},Frame)->Frame bor (((Payload bsr I) band 1) bsl J) end,
        Value,lists:enumerate(0,Positions));
decode(_,_) -> error(invalid_capture_payload).

-doc "Writes a combinational DSLX function for ready/valid encode and decode to a new file. Invalid input asserts fault and cannot handshake; the owner must handle that fault. Decode rejects a nonzero constant-only dummy bit. The tuple result is encoded, decoded, canonical, frame_ready, encoded_valid, encode_fault, payload_ready, decoded_valid, decode_fault. This function owns no storage or arbitration; producers hold valid input stable while stalled. Name must be a simple DSLX identifier.".
-spec write(map(),string(),file:filename()) -> ok.
write(#{mask:=Mask,value:=Value,frame_positions:=Positions,physical_width:=Width,payload_bits:=Bits},Name,Path) ->
    match=re:run(Name,"^[a-zA-Z_][a-zA-Z0-9_]*$",[{capture,none}]),
    Inverse=maps:from_list([{J,I}||{I,J}<-lists:enumerate(0,Positions)]),
    Source=["import axis;\nconst_assert!(axis::FRAME_BITS == u32:128);\n",
        "pub fn ",Name,"(frame: bits[128], payload: bits[",n(Width),"], frame_valid: bool, encoded_ready: bool, payload_valid: bool, decoded_ready: bool) ->\n",
        "(bits[",n(Width),"], bits[128], bool, bool, bool, bool, bool, bool, bool) {\n",
        "let canonical = (frame & bits[128]:",n(Mask),") == bits[128]:",n(Value),";\n",
        "let payload_canonical = ",case Bits of 0->"payload == u1:0";_->"true" end,";\n",
        "let encoded = ",concat(case Positions of []->["u1:0"];_->[["frame[",n(J),"+:u1]"]||J<-lists:reverse(Positions)] end),";\n",
        "let decoded = ",concat([case maps:find(J,Inverse) of
            {ok,I}->["payload[",n(I),"+:u1]"];
            error->["u1:",n((Value bsr J) band 1)]
        end||J<-lists:seq(127,0,-1)]),";\n",
        "(encoded, decoded, canonical, encoded_ready && canonical, frame_valid && canonical, frame_valid && !canonical,\n",
        " decoded_ready && payload_canonical, payload_valid && payload_canonical, payload_valid && !payload_canonical) }\n"],
    file:write_file(Path,Source,[exclusive]).

%% Source stream offsets are checked rather than trusting duplicated derived metadata.
-spec check_field(map(),{non_neg_integer(),non_neg_integer()}) -> {non_neg_integer(),non_neg_integer()}.
check_field(F=#{type:=Type,message_bit_offset:=Wire},{Wire,At}) ->
    Width=hls_type:width(Type),
    case maps:find(constant,F) of
        {ok,Bits}->Width=bit_size(Bits),{Wire+Width,At};
        error->At=maps:get(capture_bit_offset,F),{Wire+Width,At+Width}
    end.

%% Reuse the compiler's canonical header/padding algebra instead of hand-coding that ABI.
-spec bound(map()) -> map().
bound(F=#{type:=Type}) ->
    Domain=case maps:find(constant,F) of {ok,Bits}->{values,[Bits]};error->unknown end,
    #{type=>Type,domain=>Domain}.

%% Each complete frame byte is little-endian numerically, with stream bits MSB-first within it.
-spec wire_bit(non_neg_integer()) -> non_neg_integer().
wire_bit(Stream) -> 8*(Stream div 8)+7-(Stream rem 8).

%% Static wiring concatenations contain no runtime index or selection logic.
-spec concat([iolist()]) -> iolist().
concat(Parts) -> ["(",lists:join(" ++ ",Parts),")"].

%% Decimal dimensions do not carry runtime data into generated source.
-spec n(integer()) -> string().
n(N) -> integer_to_list(N).
