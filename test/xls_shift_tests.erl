-module(xls_shift_tests).
-include_lib("eunit/include/eunit.hrl").

shift_control_oracle_test_() ->
    [?_assertEqual({0, Expected}, xls_control_failure_dslx:oracle(Mode, X, Y))
        || {Mode, X, Y, Expected} <- [
            {59, 16#ffffffff, 255, 16#ffffffff},
            {60, 16#ffffffff, 255, 16#fffffffe},
            {59, 1, 128, 0}, {60, 1, 128, 0},
            {61, 16#fffffffc, 0, 16#ffffffff},
            {62, 16#ffffffff, 0, 16#ffffffff}, {62, 1, 0, 0},
            {63, 16#ffffffff, 0, 16#ffffffff},
            {64, 16#fffffffc, 0, 16#ffffffff},
            {65, 16#ffffffff, 0, 16#ffffffff},
            {66, 16#ffffffff, 255, 16#ffffffff},
            {67, 16#7fffffff, 1, 16#7fffffff},
            {68, 1, 128, 1}, {69, 1, 0, 0}, {70, 0, 1, 2}]].

constant_shift_normalization_test_() ->
    [?_assertEqual(Expected, lower(Expression)) || {Expression, Expected} <- [
        {"1 bsl 32", <<"4294967296">>},
        {"8 bsl -2", <<"2">>},
        {"-8 bsl -2", <<"-2">>},
        {"1 bsr -8", <<"256">>},
        {"1 bsl +3", <<"8">>}]].

dynamic_shift_requires_typed_value_test() ->
    ?assertError({untyped_shift_value, 1, {use, hls_type, as, 2}}, lower("1 bsl X")),
    %% A literal value must not silently become a one-bit shifter merely
    %% because the result is cast after the shift.
    ?assertError({untyped_shift_value, 1, {use, hls_type, as, 2}},
        lower("hls_nums:wrap(hls_nums:u32(), 1 bsl X)")).

lower(Expression) ->
    {ok, Tokens, _} = erl_scan:string("probe(X) -> " ++ Expression ++ "."),
    {ok, {function, _, _, _, [Clause]}} = erl_parse:parse_form(Tokens),
    #{result := Result} = xls_parse:clause_outcome(Clause, ["x"], state, #{}),
    iolist_to_binary(xls_parse:print(Result)).
