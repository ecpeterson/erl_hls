-module(hls_vec_tests).
-include_lib("eunit/include/eunit.hrl").

fixed_point_composition_and_wire_order_test() ->
    Type = hls_vec:vector(hls_fixed:signed(16, 8), 3),
    ?assertEqual(48, hls_type:width(Type)),
    ?assertEqual([0, 0, 0], hls_type:zero(Type)),
    ?assertEqual("s16[3]", lists:flatten(hls_type:print_type(Type))),
    Values = [256, -128, 3],
    Bytes = <<3:16/signed-little, -128:16/signed-little, 256:16/signed-little>>,
    ?assertEqual(Bytes, hls_type:pack(Values, Type)),
    ?assertEqual({Values, <<42>>}, hls_type:unpack(<<Bytes/binary, 42>>, Type)),
    ?assertError(badarg, hls_type:pack([256, -128], Type)),
    ?assertError(badarg, hls_type:pack([256, -128, 3, 4], Type)),
    ?assertError(badarg, hls_type:pack([256, -128, 32768], Type)),
    ?assertError(function_clause,
        hls_type:width({hls_type, hls_vec, vector, [hls_nums:s16(), 0]})).

vector_operations_test() ->
    ?assertEqual(-128, hls_vec:nth(2, [127, -128, 10])),
    ?assertEqual([127, 3, 10], hls_vec:set(2, [127, -128, 10], 3)),
    ?assertEqual(678, hls_vec:dot(hls_nums:s32(), [127, -128, 10], [2, -3, 4])),
    ?assertEqual(128, hls_vec:dot(hls_nums:s16(), [-128], [-1])),
    ?assertError(function_clause, hls_vec:dot(hls_nums:s32(), [1, 2], [1])).
