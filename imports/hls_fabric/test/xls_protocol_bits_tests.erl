-module(xls_protocol_bits_tests).
-moduledoc "Exhaustive small bit permutations check rendered DSLX wiring against the numeric projection.".
-include_lib("eunit/include/eunit.hrl").

%% Mixed constants, gaps, descending slices and repeated bits all preserve order.
-spec projections_test() -> ok.
projections_test() ->
    Alphabet = [0, 1, {payload, 0}, {payload, 1}, {payload, 2}],
    Plans = [[] | [[A, B, C, D] || A <- Alphabet, B <- Alphabet, C <- Alphabet, D <- Alphabet]],
    lists:foreach(fun(Bits) ->
        Text = binary_to_list(iolist_to_binary(xls_protocol_bits:expression("payload", Bits))),
        lists:foreach(fun(Value) ->
            ?assertEqual(hls_protocol_projection:evaluate(Bits, Value), evaluate(Text, Value))
        end, lists:seq(0, 7))
    end, Plans).

%% Adjacent wiring should stay small even when a packet has many bits.
-spec compact_test() -> ok.
compact_test() ->
    Plan = lists:duplicate(32, 0) ++ [{payload, J} || J <- lists:seq(0, 95)],
    ?assertEqual(<<"(payload[0+:bits[96]] ++ bits[32]:0)">>,
        iolist_to_binary(xls_protocol_bits:expression("payload", Plan))).

%% Interpret the emitted literals and slices independently, in DSLX high-first order.
-spec evaluate(string(), non_neg_integer()) -> non_neg_integer().
evaluate("u1:0", _) -> 0;
evaluate(Text, Payload) ->
    Parts = string:split(lists:sublist(Text, 2, length(Text)-2), " ++ ", all),
    lists:foldl(fun(Part, Acc) ->
        case re:run(Part, "^bits\\[([0-9]+)\\]:([0-9]+)$", [{capture, all_but_first, list}]) of
            {match, [Width, Literal]} -> (Acc bsl list_to_integer(Width)) bor list_to_integer(Literal);
            nomatch ->
                {Reversed, Slice} = case lists:prefix("rev(", Part) of
                    true -> {true, lists:sublist(Part, 5, length(Part)-5)};
                    false -> {false, Part}
                end,
                {match, [At, Width]} = re:run(Slice, "^payload\\[([0-9]+)\\+:bits\\[([0-9]+)\\]\\]$",
                    [{capture, all_but_first, list}]),
                N = list_to_integer(Width),
                Bits = (Payload bsr list_to_integer(At)) band ((1 bsl N) - 1),
                Value = case Reversed of
                    false -> Bits;
                    true -> lists:foldl(fun(I, V) -> (V bsl 1) bor ((Bits bsr I) band 1) end, 0, lists:seq(0, N-1))
                end,
                (Acc bsl N) bor Value
        end
    end, 0, Parts).
