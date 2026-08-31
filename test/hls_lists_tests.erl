-module(hls_lists_tests).

-include_lib("eunit/include/eunit.hrl").

wire_order_roundtrip_test() ->
    Descriptor = hls_lists:list(hls_nums:u32(), 3),
    Packed = hls_type:pack([3, 4, 0], Descriptor),
    ?assertEqual(<<0:32/little, 4:32/little, 3:32/little>>, Packed),
    ?assertEqual({[3, 4, 0], <<>>}, hls_type:unpack(Packed, Descriptor)).

descriptor_zero_test() ->
    Descriptor = hls_lists:list(hls_nums:u32(), 3),
    ?assertEqual([0, 0, 0], hls_type:zero(Descriptor)).

sublist_cpu_semantics_test() ->
    Descriptor = hls_lists:list(hls_nums:u32(), 5),
    ?assertEqual(
        [20, 30, 0, 0, 0],
        hls_lists:sublist(Descriptor, [10, 20, 30, 40, 50], 2, 2)
    ).
