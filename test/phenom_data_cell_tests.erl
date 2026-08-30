-module(phenom_data_cell_tests).

-include_lib("eunit/include/eunit.hrl").

-define(NORTH_MASK, 1).
-define(EAST_MASK, 2).
-define(WEST_MASK, 4).
-define(SOUTH_MASK, 8).
-define(ALL_DIRECTIONS, 15).
-define(SEED, 16#6d2b79f5).
-define(FIRST_RANDOM, 16#40aec71f).

source_orders_test_() ->
    Orders = permutations([
        ?NORTH_MASK,
        ?EAST_MASK,
        ?WEST_MASK,
        ?SOUTH_MASK
    ]),
    [
        {iolist_to_binary(io_lib:format("order ~p", [Order])), fun() ->
            Final = apply_queries(Order, configured_cell(?FIRST_RANDOM + 1)),
            ?assertEqual(
                {data_cell, 0, ?ALL_DIRECTIONS, ?FIRST_RANDOM + 1,
                    1, ?FIRST_RANDOM},
                Final
            )
        end}
        || Order <- Orders
    ].

fourth_query_draws_exactly_once_test() ->
    Initial = configured_cell(?FIRST_RANDOM),
    {collecting, First, consume} = query(?NORTH_MASK, Initial),
    {collecting, Second, consume} = query(?EAST_MASK, First),
    {collecting, Third, consume} = query(?WEST_MASK, Second),
    ?assertMatch(
        {data_cell, 0, _, ?FIRST_RANDOM, 0, ?SEED},
        Third
    ),
    {reporting, Final, consume} = query(?SOUTH_MASK, Third),
    %% The comparison is strict: equality with the draw is not an event.
    ?assertEqual(
        {data_cell, 0, ?ALL_DIRECTIONS, ?FIRST_RANDOM,
            0, ?FIRST_RANDOM},
        Final
    ).

reporting_entry_labels_recipient_edges_test() ->
    Cell = {data_cell, 7, ?ALL_DIRECTIONS, ?FIRST_RANDOM + 1,
        1, ?FIRST_RANDOM},
    {Cell, Actions} = phenom_data_cell:handle_enter(
        collecting,
        reporting,
        Cell
    ),
    ?assertEqual([
        {cast, north, {phenom_data, 7, ?SOUTH_MASK, 1}},
        {cast, east, {phenom_data, 7, ?WEST_MASK, 1}},
        {cast, west, {phenom_data, 7, ?EAST_MASK, 1}},
        {cast, south, {phenom_data, 7, ?NORTH_MASK, 1}}
    ], Actions).

first_next_step_query_starts_new_join_test() ->
    Reporting = {data_cell, 4, ?ALL_DIRECTIONS, 123, 1, ?FIRST_RANDOM},
    ?assertEqual(
        {collecting, {data_cell, 5, ?EAST_MASK, 123, 0,
            ?FIRST_RANDOM}, consume},
        phenom_data_cell:handle_cast(
            {phenom_query, 5, ?EAST_MASK},
            reporting,
            Reporting
        )
    ).

lookahead_queries_replay_after_reporting_test() ->
    {PID, Neighbors, Ref} = start_cell(),
    try
        ok = phenom_data_cell:configure(PID, ?SEED, ?FIRST_RANDOM + 1),
        offer(PID, 1, [north, east, west, south]),
        Before = phenom_data_cell:runtime_info(PID),
        ?assertEqual(collecting, maps:get(phase, Before)),
        ?assertEqual(4, maps:get(postponed, Before)),

        offer(PID, 0, [south, west, east, north]),
        expect_report_batches(Ref, [{0, 1}, {1, 0}]),

        After = phenom_data_cell:runtime_info(PID),
        ?assertEqual(reporting, maps:get(phase, After)),
        ?assertEqual(0, maps:get(postponed, After)),
        ?assertEqual(0, maps:get(committed, maps:get(mailbox, After))),
        ?assertMatch(
            {data_cell, 1, ?ALL_DIRECTIONS, ?FIRST_RANDOM + 1,
                0, _SecondRandom},
            maps:get(data, After)
        )
    after
        stop_cell(PID),
        stop_collectors(Ref, Neighbors)
    end.

queries_before_configuration_are_retained_test() ->
    {PID, Neighbors, Ref} = start_cell(),
    try
        offer(PID, 0, [north, east, west, south]),
        Before = phenom_data_cell:runtime_info(PID),
        ?assertEqual(configuring, maps:get(phase, Before)),
        ?assertEqual(4, maps:get(postponed, Before)),
        ok = phenom_data_cell:configure(PID, ?SEED, 0),
        expect_report_batch(Ref, 0, 0)
    after
        stop_cell(PID),
        stop_collectors(Ref, Neighbors)
    end.

duplicate_source_stops_cell_test() ->
    assert_query_failure([
        {phenom_query, 0, ?NORTH_MASK},
        {phenom_query, 0, ?NORTH_MASK}
    ]).

invalid_source_stops_cell_test() ->
    assert_query_failure([{phenom_query, 0, 3}]).

stale_step_stops_cell_test() ->
    assert_query_failure([{phenom_query, 16#ffffffff, ?NORTH_MASK}]).

configuration_rejects_zero_seed_test() ->
    Cell = {data_cell, 0, 0, 0, 0, 0},
    ?assertEqual(
        {configuring, Cell, fail},
        phenom_data_cell:handle_cast(
            {phenom_config, 0, 123},
            configuring,
            Cell
        )
    ).

cpu_api_rejects_bad_configuration_test() ->
    ?assertError(badarg, phenom_data_cell:configure(self(), 0, 1)),
    ?assertError(badarg,
        phenom_data_cell:configure(self(), ?SEED, 16#100000000)).

lowerable_source_and_shared_wire_tags_test() ->
    XLS = iolist_to_binary(
        xls_parse:to_xls("src/examples/phenom_data_cell.erl")
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(XLS, <<"enum Phase : u8">>)
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(XLS, <<"PHENOM_QUERY = u8:8">>)
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(XLS, <<"PHENOM_DATA = u8:9">>)
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(XLS, <<"Phase::REPORTING">>)
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(XLS, <<"u32:0xffffffff">>)
    ),
    ?assertEqual(8, phenom_data_cell:pack_tag(phenom_query)),
    ?assertEqual(9, phenom_data_cell:pack_tag(phenom_data)).

apply_queries(Sources, Cell0) ->
    {Phase, Cell} = lists:foldl(
        fun(Source, {_Phase, CellIn}) ->
            case query(Source, CellIn) of
                {NextPhase, CellOut, consume} -> {NextPhase, CellOut}
            end
        end,
        {collecting, Cell0},
        Sources
    ),
    ?assertEqual(reporting, Phase),
    Cell.

query(Source, Cell) ->
    phenom_data_cell:handle_cast(
        {phenom_query, 0, Source},
        collecting,
        Cell
    ).

configured_cell(Threshold) ->
    {data_cell, 0, 0, Threshold, 0, ?SEED}.

assert_query_failure(Messages) ->
    {PID, Neighbors, Ref} = start_cell(),
    unlink(PID),
    try
        ok = phenom_data_cell:configure(PID, ?SEED, 0),
        Monitor = monitor(process, PID),
        lists:foreach(fun(Message) -> xls_statem:cast(PID, Message) end,
            Messages),
        receive
            {'DOWN', Monitor, process, PID,
                    {xls_statem_failure, _Message}} ->
                ok
        after 1000 ->
            error(data_cell_did_not_stop)
        end
    after
        stop_cell(PID),
        stop_collectors(Ref, Neighbors)
    end.

start_cell() ->
    {Neighbors, Ref} = start_collectors(),
    {ok, PID} = phenom_data_cell:start_link(Neighbors),
    {PID, Neighbors, Ref}.

start_collectors() ->
    Parent = self(),
    Ref = make_ref(),
    Pairs = [
        {Direction, spawn_link(fun() -> collector(Parent, Ref, Direction) end)}
        || Direction <- [north, east, west, south]
    ],
    {maps:from_list(Pairs), Ref}.

collector(Parent, Ref, Direction) ->
    receive
        {'$gen_cast', Message} ->
            Parent ! {Ref, Direction, Message},
            collector(Parent, Ref, Direction);
        stop ->
            ok
    end.

expect_report_batch(Ref, Step, Present) ->
    Expected = expected_report_batch(Step, Present),
    ?assertEqual(Expected, lists:sort(receive_batch(Ref, 4, []))).

expect_report_batches(Ref, Steps) ->
    Expected = lists:sort(lists:append([
        expected_report_batch(Step, Present)
        || {Step, Present} <- Steps
    ])),
    Count = length(Steps) * 4,
    ?assertEqual(Expected, lists:sort(receive_batch(Ref, Count, []))).

expected_report_batch(Step, Present) ->
    lists:sort([
        {north, {phenom_data, Step, ?SOUTH_MASK, Present}},
        {east, {phenom_data, Step, ?WEST_MASK, Present}},
        {west, {phenom_data, Step, ?EAST_MASK, Present}},
        {south, {phenom_data, Step, ?NORTH_MASK, Present}}
    ]).

receive_batch(_Ref, 0, Messages) ->
    Messages;
receive_batch(Ref, Remaining, Messages) ->
    receive
        {Ref, Direction, Message} ->
            receive_batch(Ref, Remaining - 1, [
                {Direction, Message} | Messages
            ])
    after 1000 ->
        error({missing_data_report, Remaining})
    end.

offer(PID, Step, Directions) ->
    lists:foreach(
        fun(Direction) ->
            ok = phenom_data_cell:offer_query(PID, Step, Direction)
        end,
        Directions
    ).

stop_cell(PID) ->
    case is_process_alive(PID) of
        true -> phenom_data_cell:stop(PID);
        false -> ok
    end.

stop_collectors(_Ref, Neighbors) ->
    lists:foreach(fun(PID) -> PID ! stop end, maps:values(Neighbors)).

permutations([]) ->
    [[]];
permutations(Items) ->
    [
        [Item | Rest]
        || Item <- Items,
           Rest <- permutations(lists:delete(Item, Items))
    ].
