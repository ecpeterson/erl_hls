-module(phi_direction_tests).

-include_lib("eunit/include/eunit.hrl").

%% The grid policy agrees with an ordered-list oracle around every bucket edge.
-spec grid_rank_selection_test() -> ok.
grid_rank_selection_test() ->
    lists:foreach(
        fun(Mask) ->
            lists:foreach(
                fun(Random) ->
                    ?assertEqual(reference(Mask, Random), phi_direction:select_grid(Mask, Random))
                end,
                draws()
            )
        end,
        lists:seq(0, 15)
    ).

%% The line's multiplication-free specialization retains the same valid-mask choices.
-spec line_rank_selection_test() -> ok.
line_rank_selection_test() ->
    lists:foreach(
        fun(Mask) ->
            lists:foreach(
                fun(Random) ->
                    ?assertEqual(reference(Mask, Random), phi_direction:select_line(Mask, Random))
                end,
                draws()
            )
        end,
        [0, 2, 4, 6]
    ).

%% Invalid line masks still mean no direction; a high unrelated bit is not discarded.
-spec invalid_line_masks_test() -> ok.
invalid_line_masks_test() ->
    Masks = (lists:seq(0, 15) -- [0, 2, 4, 6]) ++ [16, 18, 20, 22, 1 bsl 31, (1 bsl 32)-1],
    lists:foreach(
        fun(Mask) ->
            lists:foreach(fun(Random) -> ?assertEqual(0, phi_direction:select_line(Mask, Random)) end, draws())
        end,
        Masks
    ).

%% The historical grid policy only reads its four direction bits, even for unusual masks.
-spec grid_ignores_high_mask_bits_test() -> ok.
grid_ignores_high_mask_bits_test() ->
    lists:foreach(
        fun({Mask, High}) ->
            lists:foreach(
                fun(Random) ->
                    ?assertEqual(reference(Mask, Random), phi_direction:select_grid(Mask bor High, Random))
                end,
                draws()
            )
        end,
        [{Mask, High} || Mask <- lists:seq(0, 15), High <- [16, 1 bsl 31, 16#fffffff0]]
    ).

%% Independent list indexing defines the winner order without cumulative bit counts.
-spec reference(non_neg_integer(), non_neg_integer()) -> non_neg_integer().
reference(Mask, Random) ->
    Winners = [Bit || Bit <- [1, 2, 4, 8], Mask band Bit =/= 0],
    case Winners of
        [] -> 0;
        _ -> lists:nth(1 + ((Random band 16#7fffffff) * length(Winners) div (1 bsl 31)), Winners)
    end.

%% Include both coin values, every rank discontinuity and a dispersed deterministic sample.
-spec draws() -> [non_neg_integer()].
draws() ->
    Limit = 1 bsl 31,
    Boundaries = [
        (Rank * Limit + Count - 1) div Count + Offset
        || Count <- [2, 3, 4], Rank <- lists:seq(1, Count - 1), Offset <- [-1, 0, 1]
    ],
    Samples = [0, 1, Limit-2, Limit-1] ++ Boundaries ++
        [(Index * 16#9e3779b9) band (Limit-1) || Index <- lists:seq(1, 64)],
    lists:usort([Sample bor Coin || Sample <- Samples, Coin <- [0, Limit]]).
