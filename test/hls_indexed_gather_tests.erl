-module(hls_indexed_gather_tests).
-moduledoc "Witnesses for indexed result order, membership and complete-only visibility.".
-include_lib("eunit/include/eunit.hrl").

%% Every permutation returns member order, including equal and zero-valued members.
-spec arrival_order_test() -> ok.
arrival_order_test() ->
    lists:foreach(fun(Order) ->
        {pending, Gather} = hls_indexed_gather:open(sample, 42, 5, 16#1b, absent),
        {complete, {gather_complete, sample, 42, 16#1b, [0, same, absent, same, last]}} =
            lists:foldl(fun({Member, Value}, {pending, State}) ->
                hls_indexed_gather:offer(sample, 42, Member, Value, State)
            end, {pending, Gather}, Order)
    end, permutations([{0, 0}, {1, same}, {3, same}, {4, last}])).

%% Padding does not manufacture contributions, and empty membership needs no offer.
-spec empty_and_missing_test() -> ok.
empty_and_missing_test() ->
    ?assertEqual({complete, {gather_complete, empty, 0, 0, [zero, zero]}},
        hls_indexed_gather:open(empty, 0, 2, 0, zero)),
    {pending, Open} = hls_indexed_gather:open(sample, 0, 2, 3, 0),
    {pending, Half} = hls_indexed_gather:offer(sample, 0, 1, 0, Open),
    ?assertEqual(#{name => sample, key => 0, capacity => 2, expected => 3,
        seen => 2, remaining => 1}, hls_indexed_gather:info(Half)),
    ?assertEqual({complete, {gather_complete, sample, 0, 3, [7, 0]}},
        hls_indexed_gather:offer(sample, 0, 0, 7, Half)).

%% Rejected arrivals leave the original incomplete collection available for valid input.
-spec rejected_offers_test() -> ok.
rejected_offers_test() ->
    {pending, Open} = hls_indexed_gather:open(sample, 16#ffffffff, 3, 5, absent),
    {pending, Half} = hls_indexed_gather:offer(sample, 16#ffffffff, 2, final, Open),
    ?assertEqual(mismatch, hls_indexed_gather:offer(sample, 0, 0, bad, Half)),
    ?assertEqual(mismatch, hls_indexed_gather:offer(other, 16#ffffffff, 0, bad, Half)),
    ?assertEqual({error, {duplicate_member, 2}},
        hls_indexed_gather:offer(sample, 16#ffffffff, 2, bad, Half)),
    lists:foreach(fun(Member) ->
        ?assertEqual({error, {unexpected_member, Member}},
            hls_indexed_gather:offer(sample, 16#ffffffff, Member, bad, Half))
    end, [-1, 1, 3, invalid]),
    ?assertEqual({complete, {gather_complete, sample, 16#ffffffff, 5,
            [first, absent, final]}},
        hls_indexed_gather:offer(sample, 16#ffffffff, 0, first, Half)).

%% Capacity and membership are validated at the untyped runtime boundary.
-spec invalid_open_test() -> ok.
invalid_open_test() ->
    ?assertEqual({error, invalid_name}, hls_indexed_gather:open(1, 0, 3, 7, zero)),
    lists:foreach(fun(Capacity) ->
        ?assertEqual({error, invalid_capacity},
            hls_indexed_gather:open(sample, 0, Capacity, 0, zero))
    end, [0, 256, bad]),
    lists:foreach(fun(Mask) ->
        ?assertEqual({error, invalid_members},
            hls_indexed_gather:open(sample, 0, 3, Mask, zero))
    end, [-1, 8, bad]).

%% Exhaust the small arrival-order space without random-seed dependence.
-spec permutations([T]) -> [[T]].
permutations([]) -> [[]];
permutations(Values) -> [[Value | Tail] || Value <- Values,
    Tail <- permutations(lists:delete(Value, Values))].
