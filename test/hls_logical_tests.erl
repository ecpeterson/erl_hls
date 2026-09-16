-module(hls_logical_tests).
-include_lib("eunit/include/eunit.hrl").

widths_and_codec_laws_test() ->
    lists:foreach(fun(Width) ->
        lists:foreach(fun({Type, Signedness}) ->
            Wire = Width,
            ?assertEqual(Width, hls_type:value_width(Type)),
            ?assertEqual(Wire, hls_type:width(Type)),
            {Min, Max} = case Signedness of
                unsigned -> {0, (1 bsl Width) - 1};
                signed -> {-(1 bsl (Width - 1)), (1 bsl (Width - 1)) - 1}
            end,
            lists:foreach(fun(Value) ->
                Packed = hls_type:pack_exact(Value, Type),
                ?assertEqual(<<Value:Wire/little>>, Packed),
                ?assertEqual({Value, <<42>>}, hls_type:unpack(hls_codec:join([Packed, <<42>>]), Type))
            end, lists:usort([Min, Max, 0])),
            ?assertError(badarg, hls_type:pack(Min - 1, Type)),
            ?assertError(badarg, hls_type:pack(Max + 1, Type)),
            lists:foreach(fun(Value) ->
                Wrapped = hls_nums:wrap(Type, Value),
                ?assert(Wrapped >= Min andalso Wrapped =< Max),
                ?assertEqual(Wrapped, hls_type:normalize(Type, Wrapped)),
                ?assertEqual(0, (Value - Wrapped) rem (1 bsl Width))
            end, [Min - 1, Max + 1, -(1 bsl 1000) - 129, (1 bsl 1000) + 129])
        end, [{hls_nums:uN(Width), unsigned}, {hls_nums:sN(Width), signed}])
    end, [1, 2, 3, 7, 8, 9, 15, 16, 17, 31, 32, 33, 63, 64, 65, 127]).

padding_is_not_value_test() ->
    lists:foreach(fun(Byte) ->
        ?assertEqual({Byte bsr 5, <<>>}, hls_type:unpack(<<Byte>>, hls_bits:padded(hls_nums:uN(3), 8))),
        Signed = case Byte bsr 5 of N when N < 4 -> N; N -> N - 8 end,
        ?assertEqual({Signed, <<>>}, hls_type:unpack(<<Byte>>, hls_bits:padded(hls_nums:sN(3), 8))),
        ?assertEqual({Byte bsr 7 =:= 1, <<>>}, hls_type:unpack(<<Byte>>, hls_bits:padded(hls_bool:bool(), 8)))
    end, lists:seq(0, 255)).

boolean_test() ->
    Type = hls_bool:bool(),
    ?assertEqual(1, hls_type:value_width(Type)),
    ?assertEqual(1, hls_type:width(Type)),
    ?assertEqual(false, hls_type:zero(Type)),
    ?assertEqual("bool", hls_type:print_type(Type)),
    ?assertEqual(<<0:1>>, hls_type:pack_exact(false, Type)),
    ?assertEqual(<<1:1>>, hls_type:pack_exact(true, Type)),
    [?assertError(badarg, hls_type:pack(Value, Type)) || Value <- [0, 1, undefined, <<1>>]].

packed_fragments_test() ->
    %% Aggregates are native Erlang bitstrings, even across byte boundaries.
    lists:foreach(fun({AWidth, BWidth}) ->
        lists:foreach(fun({A, B}) ->
            Packed = <<A:AWidth/little, B:BWidth/little>>,
            APart = <<A:AWidth/little>>, BPart = <<B:BWidth/little>>,
            ?assertEqual(Packed, hls_codec:join([APart, BPart])),
            ?assertEqual({APart, BPart}, hls_codec:split(Packed, AWidth))
        end, [{A, B} || A <- [0, 1, (1 bsl AWidth)-1],
            B <- [0, 1, (1 bsl BWidth)-1]])
    end, [{A, B} || A <- lists:seq(1, 17), B <- lists:seq(1, 17)]).

explicit_padding_test() ->
    Type = hls_bits:padded(hls_nums:sN(3), 5),
    ?assertEqual(3, hls_type:value_width(Type)),
    ?assertEqual(5, hls_type:width(Type)),
    ?assertEqual(<<7:3, 0:2>>, hls_type:pack(-1, Type)),
    ?assertEqual({-1, <<>>}, hls_type:unpack(<<31:5>>, Type)),
    ?assertError({padding_too_narrow, 2, 3}, hls_bits:padded(hls_nums:uN(3), 2)),
    Nested = hls_vec:vector(Type, 3),
    ?assertEqual(<<3:3, 0:2, 4:3, 0:2, 7:3, 0:2>>,
        hls_type:pack([-1, -4, 3], Nested)),
    ?assertEqual(15, hls_type:width(Nested)),
    ?assertEqual(9, hls_type:value_width(Nested)).

unaligned_float_and_fixed_test() ->
    Value = {mixed, 5, -1.25, true, -129, -513, 7},
    Expected = <<5:3/little, -1.25:32/little-float, 1:1, -129:9/little,
        -513:16/little, 7:3>>,
    ?assertEqual(Expected, hls_logical_fixture:pack(Value)),
    ?assertEqual({Value, <<2:3>>},
        hls_logical_fixture:unpack(mixed, <<Expected/bitstring, 2:3>>)).

nested_wire_order_test() ->
    Type = hls_vec:vector(hls_vec:vector(hls_nums:sN(5), 2), 2),
    Value = [[-16, 15], [-1, 1]],
    ?assertEqual(20, hls_type:value_width(Type)),
    ?assertEqual(20, hls_type:width(Type)),
    ?assertEqual(<<1:5, -1:5, 15:5, -16:5>>, hls_type:pack(Value, Type)),
    ?assertEqual({Value, <<42>>},
        hls_type:unpack(<<1:5, -1:5, 15:5, -16:5, 42>>, Type)),
    Empty = hls_lists:list(hls_bool:bool(), 0),
    ?assertEqual(<<>>, hls_type:pack([], Empty)),
    ?assertEqual(0, hls_type:value_width(Empty)).

record_wire_order_test() ->
    Value = {step, true, 7, -129},
    Packed = <<1:1, 7:3, -129:9/little>>,
    ?assertEqual(13, hls_logical_fixture:pack_width(step)),
    ?assertEqual(Packed, hls_logical_fixture:pack(Value)),
    ?assertEqual({Value, <<42>>}, hls_logical_fixture:unpack(step, <<Packed/bitstring, 42>>)),
    ?assertEqual({Value, <<>>}, hls_logical_fixture:unpack(step, Packed)),
    ?assertError(badarg, hls_logical_fixture:pack({step, true, 8, 0})).

cpu_actor_test() ->
    {ok, PID} = hls_gs:start_link(hls_logical_fixture, [], []),
    try
        ?assertEqual({result, true, 5, -129}, gen_server:call(PID, {read, 0})),
        ?assertEqual({result, false, 4, 127}, gen_server:call(PID, {step, true, 7, -256})),
        ?assertEqual({result, false, 4, 127}, gen_server:call(PID, {step, false, 0, 1})),
        ?assertEqual({result, true, 5, -130}, gen_server:call(PID, {step, true, 1, 255}))
    after gen_server:stop(PID) end.
