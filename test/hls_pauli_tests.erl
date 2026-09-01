-module(hls_pauli_tests).

-include_lib("eunit/include/eunit.hrl").

constants_and_membership_test() ->
    ?assertEqual(i, hls_pauli:i()),
    ?assertEqual(x, hls_pauli:x()),
    ?assertEqual(y, hls_pauli:y()),
    ?assertEqual(z, hls_pauli:z()),
    lists:foreach(
        fun(Pauli) -> ?assert(hls_pauli:is_pauli(Pauli)) end,
        [i, x, y, z]
    ),
    ?assertNot(hls_pauli:is_pauli(a)),
    ?assertNot(hls_pauli:is_pauli(0)).

projective_multiplication_test() ->
    Table = [
        {i, i, i}, {i, x, x}, {i, y, y}, {i, z, z},
        {x, i, x}, {x, x, i}, {x, y, z}, {x, z, y},
        {y, i, y}, {y, x, z}, {y, y, i}, {y, z, x},
        {z, i, z}, {z, x, y}, {z, y, x}, {z, z, i}
    ],
    lists:foreach(
        fun({Left, Right, Product}) ->
            ?assertEqual(Product, hls_pauli:multiply(Left, Right))
        end,
        Table
    ).

anticommutation_test() ->
    Paulis = [i, x, y, z],
    Anticommuting = lists:sort([
        {x, y}, {x, z},
        {y, x}, {y, z},
        {z, x}, {z, y}
    ]),
    Actual = lists:sort([
        {Left, Right}
        || Left <- Paulis,
           Right <- Paulis,
           hls_pauli:anticommutes(Left, Right)
    ]),
    ?assertEqual(Anticommuting, Actual).

type_and_codec_test() ->
    Type = hls_pauli:pauli(),
    ?assertEqual(32, hls_type:width(Type)),
    ?assertEqual("u32", hls_type:print_type(Type)),
    ?assertEqual(i, hls_type:zero(Type)),
    Encodings = [{i, 0}, {x, 2}, {y, 3}, {z, 1}],
    lists:foreach(
        fun({Pauli, Code}) ->
            Packed = <<Code:32/little-unsigned-integer>>,
            ?assertEqual(Packed, hls_type:pack(Pauli, Type)),
            ?assertEqual(
                {Pauli, <<16#aa, 16#bb>>},
                hls_type:unpack(<<Packed/binary, 16#aa, 16#bb>>, Type)
            )
        end,
        Encodings
    ),
    ?assertError(badarg, hls_type:pack(a, Type)),
    ?assertError(
        badarg,
        hls_type:unpack(<<4:32/little-unsigned-integer>>, Type)
    ).

pauli_operations_transpile_test() ->
    Clause = parse_clause(
        "probe(Left, Right) ->\n"
        "  Product = hls_pauli:multiply(Left, Right),\n"
        "  {Product, hls_pauli:anticommutes(Left, Right),\n"
        "   hls_pauli:is_pauli(Product),\n"
        "   hls_type:as(hls_pauli:pauli(), 0)}."
    ),
    DSLX = lower(Clause, ["left", "right"]),
    ?assertNotEqual(
        nomatch,
        binary:match(DSLX, <<"(Left_1 ^ Right_1)">>)
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(DSLX, <<"& u32:1) == u32:1">>)
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(DSLX, <<"(Product_1 <= u32:3)">>)
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(DSLX, <<"(0 as u32)">>)
    ).

pauli_constants_transpile_test() ->
    Clause = parse_clause(
        "probe() ->\n"
        "  {hls_pauli:i(), hls_pauli:x(),\n"
        "   hls_pauli:y(), hls_pauli:z()}."
    ),
    DSLX = lower(Clause, []),
    lists:foreach(
        fun(Literal) ->
            ?assertNotEqual(nomatch, binary:match(DSLX, Literal))
        end,
        [<<"u32:0">>, <<"u32:2">>, <<"u32:3">>, <<"u32:1">>]
    ).

lower(Clause, Arguments) ->
    {Body, Result} = xls_parse:branch_from_clause(
        Clause,
        Arguments,
        state,
        fun(Reference) -> Reference end,
        "failure",
        #{}
    ),
    iolist_to_binary(xls_parse:print([Body, Result])).

parse_clause(Source) ->
    {ok, Tokens, _EndLocation} = erl_scan:string(Source),
    {ok, {function, _Line, probe, _Arity, [Clause]}} =
        erl_parse:parse_form(Tokens),
    Clause.
