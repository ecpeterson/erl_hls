-module(hls_reduction_tests).

-include_lib("eunit/include/eunit.hrl").

-export([reduce/3]).

count_reduction_completes_on_exact_count_test() ->
    {ok, Reduction0} = count_reduction(3),
    {pending, Reduction1} = hls_reduction:contribute(
        ?MODULE, sum, epoch_7, 11, Reduction0
    ),
    {pending, Reduction2} = hls_reduction:contribute(
        ?MODULE, sum, epoch_7, 5, Reduction1
    ),
    ?assertEqual(
        {complete, {reduction_complete, sum, epoch_7, 19}},
        hls_reduction:contribute(?MODULE, sum, epoch_7, 3, Reduction2)
    ),
    ?assertMatch(
        #{
            population := {count, 3},
            received := 2,
            remaining := 1
        },
        hls_reduction:info(Reduction2)
    ).

count_mode_deliberately_counts_duplicate_values_test() ->
    {ok, Reduction0} = count_reduction(2),
    {pending, Reduction1} = hls_reduction:contribute(
        ?MODULE, sum, epoch_7, 4, Reduction0
    ),
    ?assertEqual(
        {complete, {reduction_complete, sum, epoch_7, 8}},
        hls_reduction:contribute(?MODULE, sum, epoch_7, 4, Reduction1)
    ).

member_reduction_accepts_any_expected_order_test() ->
    {ok, Reduction0} = member_reduction([north, east, west, south]),
    {pending, Reduction1} = member_contribute(west, 4, Reduction0),
    {pending, Reduction2} = member_contribute(north, 1, Reduction1),
    {pending, Reduction3} = member_contribute(south, 8, Reduction2),
    ?assertEqual(
        {complete, {reduction_complete, sum, epoch_7, 15}},
        member_contribute(east, 2, Reduction3)
    ).

mismatched_identity_is_distinct_and_preserves_state_test_() ->
    {ok, Reduction} = count_reduction(2),
    [
        ?_assertEqual(mismatch,
            hls_reduction:contribute(
                ?MODULE, other, epoch_7, 1, Reduction
            )),
        ?_assertEqual(mismatch,
            hls_reduction:contribute(
                ?MODULE, sum, epoch_8, 1, Reduction
            ))
    ].

duplicate_member_is_rejected_without_advancing_test() ->
    {ok, Reduction0} = member_reduction([north, south]),
    {pending, Reduction1} = member_contribute(north, 3, Reduction0),
    ?assertEqual(
        {error, {duplicate_member, north}},
        member_contribute(north, 100, Reduction1)
    ),
    ?assertEqual(
        {complete, {reduction_complete, sum, epoch_7, 8}},
        member_contribute(south, 5, Reduction1)
    ).

unexpected_member_is_rejected_without_advancing_test() ->
    {ok, Reduction} = member_reduction([north, south]),
    ?assertEqual(
        {error, {unexpected_member, east}},
        member_contribute(east, 100, Reduction)
    ),
    ?assertMatch(
        #{received := 0, remaining := 2},
        hls_reduction:info(Reduction)
    ).

contribution_shape_must_match_population_mode_test_() ->
    {ok, Count} = count_reduction(2),
    {ok, Members} = member_reduction([north, south]),
    [
        ?_assertEqual(
            {error, wrong_mode},
            member_contribute(north, 1, Count)
        ),
        ?_assertEqual(
            {error, wrong_mode},
            hls_reduction:contribute(?MODULE, sum, epoch_7, 1, Members)
        )
    ].

population_must_be_nonempty_bounded_and_unique_test_() ->
    TooMany = lists:seq(1, 256),
    [
        ?_assertEqual(
            {error, invalid_population},
            hls_reduction:open(sum, key, {count, 0},
                {commutative_monoid, 0})
        ),
        ?_assertEqual(
            {error, invalid_population},
            hls_reduction:open(sum, key, {count, 256},
                {commutative_monoid, 0})
        ),
        ?_assertEqual(
            {error, invalid_population},
            hls_reduction:open(sum, key, {members, []},
                {commutative_monoid, 0})
        ),
        ?_assertEqual(
            {error, invalid_population},
            hls_reduction:open(sum, key, {members, [north, north]},
                {commutative_monoid, 0})
        ),
        ?_assertEqual(
            {error, invalid_population},
            hls_reduction:open(sum, key, {members, TooMany},
                {commutative_monoid, 0})
        )
    ].

name_and_monoid_are_validated_test_() ->
    [
        ?_assertEqual(
            {error, invalid_name},
            hls_reduction:open(17, key, {count, 1},
                {commutative_monoid, 0})
        ),
        ?_assertEqual(
            {error, invalid_monoid},
            hls_reduction:open(sum, key, {count, 1}, not_a_monoid)
        ),
        ?_assertEqual(
            {error, invalid_monoid},
            hls_reduction:open(sum, key, {count, 1},
                {commutative_monoid, 0, extra})
        )
    ].

member_identity_uses_exact_map_key_equality_test() ->
    {ok, Reduction0} = member_reduction([1, 1.0]),
    {pending, Reduction1} = hls_reduction:contribute(
        ?MODULE, sum, epoch_7, 1, 3, Reduction0
    ),
    ?assertEqual(
        {complete, {reduction_complete, sum, epoch_7, 7}},
        hls_reduction:contribute(
            ?MODULE, sum, epoch_7, 1.0, 4, Reduction1
        )
    ).

count_reduction(Count) ->
    hls_reduction:open(
        sum,
        epoch_7,
        {count, Count},
        {commutative_monoid, 0}
    ).

member_reduction(Members) ->
    hls_reduction:open(
        sum,
        epoch_7,
        {members, Members},
        {commutative_monoid, 0}
    ).

member_contribute(Member, Value, Reduction) ->
    hls_reduction:contribute(
        ?MODULE, sum, epoch_7, Member, Value, Reduction
    ).

-spec reduce(sum, number(), number()) -> number().
reduce(sum, Left, Right) ->
    Left + Right.
