-module(hls_protocol_codec_tests).
-include_lib("eunit/include/eunit.hrl").

%% Unaligned identity bits must not change byte order of a later multi-byte value.
-spec unaligned_roundtrip_test() -> ok.
unaligned_roundtrip_test() ->
    Fields=[field(id,3,<<5:3>>),field(epoch,13,dynamic),field(value,46,dynamic),field(flag,1,<<1:1>>)],
    C=codec(Fields,17),
    lists:foreach(fun({E,V})->
        Bits=[<<5:3>>,hls_type:pack_exact(E,type(13)),hls_type:pack_exact(V,type(46)),<<1:1>>],
        Frame=frame(17,Bits),{ok,P}=hls_protocol_codec:encode(C,Frame),
        ?assertEqual(Frame,hls_protocol_codec:decode(C,P))
    end,[{0,0},{1,1},{8191,(1 bsl 46)-1},{16#1234,16#123456789ab}]).

%% Every source-visible bit survives, even when little-endian integer widths have partial bytes.
-spec dynamic_bit_basis_test() -> ok.
dynamic_bit_basis_test() ->
    C=codec([field(a,7,dynamic),field(b,9,dynamic),field(c,17,dynamic)],9),
    lists:foreach(fun(Bits)->
        F=frame(9,[Bits]),{ok,P}=hls_protocol_codec:encode(C,F),
        ?assertEqual(F,hls_protocol_codec:decode(C,P))
    end,[<<V:33>>||V<-[0,(1 bsl 33)-1|[1 bsl I||I<-lists:seq(0,32)]]]).

%% Dropped fields must be true constants, not assumed bounds on unknown producers.
-spec malformed_frame_test() -> ok.
malformed_frame_test() ->
    C=codec([field(id,8,<<7>>),field(value,8,dynamic)],8),F=frame(8,[<<7,99>>]),
    lists:foreach(fun(I)->?assertEqual({error,invalid_frame},hls_protocol_codec:encode(C,F bxor (1 bsl I))) end,
        [0,8,16,24,32,48,127]),
    ?assertEqual({error,invalid_frame},hls_protocol_codec:encode(C,1 bsl 128)).

%% Constant-only messages require no payload state; their physical dummy bit is always zero.
-spec constant_only_test() -> ok.
constant_only_test() ->
    C=codec([field(id,3,<<6:3>>)],4),F=frame(4,[<<6:3>>]),
    ?assertEqual({ok,0},hls_protocol_codec:encode(C,F)),
    ?assertEqual(F,hls_protocol_codec:decode(C,0)),
    ?assertError(invalid_capture_payload,hls_protocol_codec:decode(C,1)).

%% Unknown payload bits cannot be hidden outside the declared compact representation.
-spec excess_compact_bits_test() -> ok.
excess_compact_bits_test() ->
    C=codec([field(a,5,dynamic)],3),
    ?assertError(invalid_capture_payload,hls_protocol_codec:decode(C,32)).

%% Stale duplicated offset metadata fails before code generation.
-spec stale_offsets_test() -> ok.
stale_offsets_test() ->
    F=#{name=>a,type=>type(8),message_bit_offset=>1,capture_bit_offset=>0},
    ?assertError(function_clause,hls_protocol_codec:plan(#{fields=>[F],message_bits=>8,payload_bits=>8},3)).

%% Low-level codec unit fixtures describe layouts directly; source derivation has separate end-to-end tests.
-spec codec([map()],non_neg_integer()) -> map().
codec(Fields,Op) ->
    {Layout,{Wire,Stored}}=lists:mapfoldl(fun(F=#{type:=Type},{W,S})->
        Width=hls_type:width(Type),
        case maps:is_key(constant,F) of
            true->{F#{message_bit_offset=>W},{W+Width,S}};
            false->{F#{message_bit_offset=>W,capture_bit_offset=>S},{W+Width,S+Width}}
        end
    end,{0,0},Fields),
    hls_protocol_codec:plan(#{fields=>Layout,message_bits=>Wire,payload_bits=>Stored},Op).

%% Raw physical source bitstrings concatenate before padding and numeric frame conversion.
-spec frame(non_neg_integer(),[bitstring()]) -> non_neg_integer().
frame(Op,Parts) ->
    Stream = << <<B/bitstring>>||B<-Parts >>,N=bit_size(Stream),
    <<Payload:96/little>> = <<Stream/bitstring,0:(96-N)>>,
    (Payload bsl 32) bor (Op bsl 24) bor ((N+31) div 32).

%% Built-in typed fields exercise ordinary provider packing, not application-specific payloads.
-spec field(atom(),pos_integer(),bitstring()|dynamic) -> map().
field(Name,W,dynamic) -> #{name=>Name,type=>type(W)};
field(Name,W,Bits) -> #{name=>Name,type=>type(W),constant=>Bits}.

%% The compiler's integer type descriptor includes non-byte-aligned physical widths.
-spec type(pos_integer()) -> tuple().
type(W) -> {hls_type,hls_nums,uN,[W]}.
