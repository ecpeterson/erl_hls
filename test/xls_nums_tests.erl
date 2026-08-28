-module(xls_nums_tests).

-include_lib("eunit/include/eunit.hrl").

u32_shift_semantics_test() ->
    ?assertEqual(16#80000000, xls_nums:u32_shl(16#40000000, 1)),
    ?assertEqual(0, xls_nums:u32_shl(16#80000000, 1)),
    ?assertEqual(1, xls_nums:u32_shr(16#80000000, 31)).

u32_shift_rejects_out_of_domain_values_test() ->
    ?assertError(badarg, xls_nums:u32_shl(-1, 1)),
    ?assertError(badarg, xls_nums:u32_shl(16#100000000, 1)),
    ?assertError(badarg, xls_nums:u32_shl(1, -1)),
    ?assertError(badarg, xls_nums:u32_shl(1, 32)),
    ?assertError(badarg, xls_nums:u32_shr(1, 32)).

generic_erlang_shifts_are_not_lowered_test() ->
    ?assertError(
        {unsupported_erlang_shift, 'bsl'},
        xls_parse:op('bsl', ["value", "1"])
    ),
    ?assertError(
        {unsupported_erlang_shift, 'bsr'},
        xls_parse:op('bsr', ["value", "1"])
    ).
