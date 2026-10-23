-module(hls_protocol_mixed_tests).
-include_lib("eunit/include/eunit.hrl").

%% Crossing operation numbering belongs to the destination; use a deliberately different selector.
-spec destination_selector_test() -> ok.
destination_selector_test() ->
    M=hls_protocol_network_fixture,Op=17,?assertNotEqual(Op,M:pack_tag(value)),
    C=hls_protocol_codec:plan(#{message_bits=>32,payload_bits=>32,
        fields=>[#{type=>{hls_type,hls_nums,uN,[32]},message_bit_offset=>0,capture_bit_offset=>0}]},Op),
    L=#{source_module=>M,destination_module=>M,
        classes=>[#{slot=>2,port=>early,tag=>value,codec=>C,message_bits=>32}]},
    {2,Frame}=hls_protocol_mixed:encode(L,early,{value,16#12345678}),
    ?assertEqual(Op,(Frame bsr 24) band 255),
    ?assertEqual({value,16#12345678},hls_protocol_mixed:decode(L,2,Frame)),
    ?assertError({badmatch,{error,invalid_frame}},hls_protocol_mixed:decode(L,2,Frame bxor (1 bsl 8))).

%% A constant-only source class cannot transmit a different value even when its payload width is zero.
-spec omitted_constant_test() -> ok.
omitted_constant_test() ->
    M=hls_protocol_network_fixture,
    C=hls_protocol_codec:plan(#{message_bits=>8,payload_bits=>0,
        fields=>[#{type=>{hls_type,hls_nums,uN,[8]},message_bit_offset=>0,constant=><<7>>}]},M:pack_tag(go)),
    L=#{source_module=>M,destination_module=>M,
        classes=>[#{slot=>0,port=>open,tag=>go,codec=>C,message_bits=>8}]},
    {0,Frame}=hls_protocol_mixed:encode(L,open,{go,7}),
    ?assertEqual({go,7},hls_protocol_mixed:decode(L,0,Frame)),
    ?assertError({badmatch,{error,invalid_frame}},hls_protocol_mixed:encode(L,open,{go,8})).
