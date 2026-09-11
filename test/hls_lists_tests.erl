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

exact_length_required_test() ->
    Descriptor = hls_lists:list(hls_nums:u32(), 3),
    lists:foreach(fun(Value) ->
        ?assertError(badarg, hls_type:pack(Value, Descriptor))
    end, [[], [1, 2], [1, 2, 3, 4], [1, 2 | 3], <<1, 2, 3>>, invalid]).

nested_shape_required_even_when_total_width_matches_test() ->
    Descriptor = hls_lists:list(hls_lists:list(hls_nums:u8(), 2), 2),
    ?assertEqual(<<4, 3, 2, 1>>, hls_type:pack([[1, 2], [3, 4]], Descriptor)),
    ?assertError(badarg, hls_type:pack([[1], [2, 3, 4]], Descriptor)),
    ?assertError(badarg, hls_type:pack([[1, 2, 3], [4]], Descriptor)),
    ?assertError(badarg, hls_type:pack([[1, 2], [3, 256]], Descriptor)).

zero_width_elements_still_require_exact_length_test() ->
    Empty = hls_lists:list(hls_nums:u8(), 0),
    ?assertEqual(<<>>, hls_type:pack([], Empty)),
    Descriptor = hls_lists:list(Empty, 2),
    ?assertEqual(<<>>, hls_type:pack([[], []], Descriptor)),
    ?assertError(badarg, hls_type:pack([[]], Descriptor)),
    ?assertError(badarg, hls_type:pack([[], [], []], Descriptor)).

sublist_cpu_semantics_test() ->
    Descriptor = hls_lists:list(hls_nums:u32(), 5),
    ?assertEqual(
        [20, 30, 0, 0, 0],
        hls_lists:sublist(Descriptor, [10, 20, 30, 40, 50], 2, 2)
    ).
