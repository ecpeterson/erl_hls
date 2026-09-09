-module(hls_reduction_tests).

-include_lib("eunit/include/eunit.hrl").

-export([reduce/3]).

count_reduction_test() ->
    {ok, Reduction0} = open({count, 3}),
    {pending, Reduction1} = count(11, Reduction0),
    {pending, Reduction2} = count(5, Reduction1),
    ?assertMatch(
        #{population := {count, 3}, received := 2, remaining := 1},
        hls_reduction:info(Reduction2)
    ),
    ?assertEqual(
        {complete, {reduction_complete, sum, epoch, 19}},
        count(3, Reduction2)
    ).

count_mode_counts_equal_values_test() ->
    {ok, Reduction0} = open({count, 2}),
    {pending, Reduction1} = count(4, Reduction0),
    ?assertEqual(
        {complete, {reduction_complete, sum, epoch, 8}},
        count(4, Reduction1)
    ).

members_complete_in_any_order_and_use_exact_keys_test() ->
    {ok, Reduction0} = open({members, [north, south, 1, 1.0]}),
    {pending, Reduction1} = member(1.0, 8, Reduction0),
    {pending, Reduction2} = member(north, 1, Reduction1),
    {pending, Reduction3} = member(1, 4, Reduction2),
    ?assertEqual(
        {complete, {reduction_complete, sum, epoch, 15}},
        member(south, 2, Reduction3)
    ).

mismatch_does_not_advance_test() ->
    {ok, Reduction} = open({count, 2}),
    ?assertEqual(
        mismatch,
        hls_reduction:contribute(?MODULE, other, epoch, 1, Reduction)
    ),
    ?assertEqual(
        mismatch,
        hls_reduction:contribute(?MODULE, sum, future, 1, Reduction)
    ),
    {pending, Next} = count(3, Reduction),
    ?assertMatch(#{received := 1, remaining := 1},
        hls_reduction:info(Next)).

member_rejections_do_not_advance_test() ->
    {ok, Reduction0} = open({members, [north, south]}),
    {pending, Reduction1} = member(north, 3, Reduction0),
    ?assertEqual(
        {error, {duplicate_member, north}},
        member(north, 100, Reduction1)
    ),
    ?assertEqual(
        {error, {unexpected_member, east}},
        member(east, 100, Reduction1)
    ),
    ?assertEqual(
        {error, wrong_mode},
        count(100, Reduction1)
    ),
    ?assertEqual(
        {complete, {reduction_complete, sum, epoch, 8}},
        member(south, 5, Reduction1)
    ).

population_shape_rejections_test_() ->
    TooMany = lists:seq(1, 256),
    Invalid = [
        {sum, {count, 0}, {commutative_monoid, 0}, invalid_population},
        {sum, {count, 256}, {commutative_monoid, 0}, invalid_population},
        {sum, {members, []}, {commutative_monoid, 0}, invalid_population},
        {sum, {members, [north, north]},
            {commutative_monoid, 0}, invalid_population},
        {sum, {members, TooMany},
            {commutative_monoid, 0}, invalid_population},
        {17, {count, 1}, {commutative_monoid, 0}, invalid_name},
        {sum, {count, 1}, not_a_monoid, invalid_monoid}
    ],
    [?_assertEqual(
        {error, Reason},
        hls_reduction:open(Name, epoch, Population, Operator)
    ) || {Name, Population, Operator, Reason} <- Invalid].

open(Population) ->
    hls_reduction:open(
        sum, epoch, Population, {commutative_monoid, 0}
    ).

count(Value, Reduction) ->
    hls_reduction:contribute(?MODULE, sum, epoch, Value, Reduction).

member(Member, Value, Reduction) ->
    hls_reduction:contribute(
        ?MODULE, sum, epoch, Member, Value, Reduction
    ).

reduce(sum, Left, Right) ->
    Left + Right.
