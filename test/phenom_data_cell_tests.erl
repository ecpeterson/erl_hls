-module(phenom_data_cell_tests).

-include_lib("eunit/include/eunit.hrl").

-define(NORTH_MASK, 1).
-define(EAST_MASK, 2).
-define(WEST_MASK, 4).
-define(SOUTH_MASK, 8).
-define(ALL_DIRECTIONS, 15).
-define(SEED, 16#6d2b79f5).
-define(FIRST_RANDOM, 16#40aec71f).
-define(U32_MASK, 16#ffffffff).

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
                cell(0, ?ALL_DIRECTIONS, ?FIRST_RANDOM + 1,
                    1, ?FIRST_RANDOM, 0, 0, y, 0, 0),
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
        {data_cell, 0, _, ?FIRST_RANDOM, 0, ?SEED,
            0, 0, i, 0, 0, 0, 0, 0, 0},
        Third
    ),
    {reporting, Final, consume} = query(?SOUTH_MASK, Third),
    %% The comparison is strict: equality with the draw is not an event.
    ?assertEqual(
        cell(0, ?ALL_DIRECTIONS, ?FIRST_RANDOM,
            0, ?FIRST_RANDOM, 0, 0, i, 0, 0),
        Final
    ).

reporting_entry_labels_recipient_edges_test() ->
    Cell = cell(7, ?ALL_DIRECTIONS, ?FIRST_RANDOM + 1,
        1, ?FIRST_RANDOM, 13, 17, y, 0, 0),
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
    Reporting = cell(4, ?ALL_DIRECTIONS, 123, 1, ?FIRST_RANDOM,
        13, 17, y, 0, 0),
    ?assertEqual(
        {collecting, cell(5, ?EAST_MASK, 123, 0,
            ?FIRST_RANDOM, 13, 17, y, 0, 0), consume},
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
                0, _SecondRandom, 0, 0, y, 0, 0,
                0, 0, 0, 0},
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
    Cell = cell(0, 0, 0, 0, 0, 0, 0, i, 0, 0),
    ?assertEqual(
        {configuring, Cell, fail},
        phenom_data_cell:handle_cast(
            {phenom_config, 0, 123, 0, 0},
            configuring,
            Cell
        )
    ).

cpu_api_rejects_bad_configuration_test() ->
    ?assertError(badarg, phenom_data_cell:configure(self(), 0, 1)),
    ?assertError(badarg,
        phenom_data_cell:configure(self(), ?SEED, 16#100000000)),
    ?assertError(badarg,
        phenom_data_cell:configure(self(), ?SEED, 1, 16#10000, 0)),
    ?assertError(badarg,
        phenom_data_cell:configure(self(), ?SEED, 1, 0, 16#10000)).

cumulative_pauli_queries_are_ordered_and_coordinate_aware_test() ->
    {PID, Neighbors, Ref} = start_cell(),
    try
        ok = phenom_data_cell:configure(PID, ?SEED, ?U32_MASK, 13, 17),

        offer(PID, 0, [north, east, west, south]),
        expect_report_batch(Ref, 0, 1),
        ok = phenom_data_cell:noise_cutoff(PID, 1),
        offer(PID, 1, [north, east, west, south]),
        expect_report_batch(Ref, 1, 0, 1),

        ok = phenom_data_cell:pauli_query(PID, 101, x),
        ok = phenom_data_cell:pauli_query(PID, 102, z),
        expect_measurement_replies(Ref, [
            {pauli_reply, 101, 13, 17, 1},
            {pauli_reply, 102, 13, 17, 1}
        ]),

        %% A Pauli-Y correction cancels the physical Y modulo global phase.
        ok = phenom_data_cell:pauli_update(PID, y),
        ok = phenom_data_cell:pauli_query(PID, 103, x),
        ok = phenom_data_cell:pauli_query(PID, 104, z),
        expect_measurement_replies(Ref, [
            {pauli_reply, 103, 13, 17, 0},
            {pauli_reply, 104, 13, 17, 0}
        ]),

        Info = phenom_data_cell:runtime_info(PID),
        ?assertEqual(replying, maps:get(phase, Info)),
        ?assertMatch(
            {data_cell, 1, ?ALL_DIRECTIONS, ?U32_MASK, 0,
                ?FIRST_RANDOM, 13, 17, i, 104, 0,
                2, 1, 0, 1},
            maps:get(data, Info)
        )
    after
        stop_cell(PID),
        stop_collectors(Ref, Neighbors)
    end.

measurement_query_phase_and_payload_validation_test() ->
    Reporting = controlled_cell(4, ?ALL_DIRECTIONS, 0, 0, ?FIRST_RANDOM,
        13, 17, y, 0, 0, 0, 1),
    Valid = {pauli_query, 91, x},
    {replying, Replying, consume} = phenom_data_cell:handle_cast(
        Valid,
        reporting,
        Reporting
    ),
    ?assertEqual(
        controlled_cell(4, ?ALL_DIRECTIONS, 0, 0, ?FIRST_RANDOM,
            13, 17, y, 91, 1, 2, 1),
        Replying
    ),
    ?assertEqual(
        {repeat_phase, controlled_cell(4, ?ALL_DIRECTIONS, 0, 0,
            ?FIRST_RANDOM, 13, 17, y, 92, 1, 2, 1), consume},
        phenom_data_cell:handle_cast(
            {pauli_query, 92, z},
            replying,
            Replying
        )
    ),
    Collecting = controlled_cell(4, 0, 0, 0, ?FIRST_RANDOM,
        13, 17, y, 0, 0, 0, 1),
    {replying, CollectingReply, consume} =
        phenom_data_cell:handle_cast(
            {pauli_query, 93, x},
            collecting,
            Collecting
        ),
    ?assertMatch(
        {data_cell, 4, 0, 0, 0, ?FIRST_RANDOM, 13, 17, y,
            93, 1, 1, 1, 0, 0},
        CollectingReply
    ),
    EnabledReporting = cell(4, ?ALL_DIRECTIONS, 0, 0, ?FIRST_RANDOM,
        13, 17, y, 0, 0),
    lists:foreach(
        fun({Message, Phase, Cell}) ->
            ?assertMatch(
                {Phase, Cell, fail},
                phenom_data_cell:handle_cast(Message, Phase, Cell)
            )
        end,
        [
            {{pauli_query, 1, x}, reporting, EnabledReporting},
            {{pauli_query, 1, invalid}, reporting, Reporting}
        ]
    ).

early_measurement_query_stops_cell_test() ->
    {PID, Neighbors, Ref} = start_cell(),
    unlink(PID),
    try
        ok = phenom_data_cell:configure(PID, ?SEED, 0),
        Monitor = monitor(process, PID),
        hls_statem:cast(PID, {pauli_query, 1, x}),
        receive
            {'DOWN', Monitor, process, PID,
                    {hls_statem_failure, {pauli_query, 1, x}}} ->
                ok
        after 1000 ->
            error(data_cell_accepted_early_measurement_query)
        end
    after
        stop_cell(PID),
        stop_collectors(Ref, Neighbors)
    end.

lowerable_source_and_shared_wire_tags_test() ->
    XLS = iolist_to_binary(
        xls_parse:to_xls("src/examples/phi_decoder/phenom_data_cell.erl")
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
        binary:match(XLS, <<"Phase::REPLYING">>)
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(XLS, <<"PAULI_QUERY = u8:13">>)
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(XLS, <<"PAULI_REPLY = u8:14">>)
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(XLS, <<"NOISE_CUTOFF = u8:15">>)
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(XLS, <<"PAULI_UPDATE = u8:16">>)
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(XLS, <<"u32:0xffffffff">>)
    ),
    ?assertEqual(8, phenom_data_cell:pack_tag(phenom_query)),
    ?assertEqual(9, phenom_data_cell:pack_tag(phenom_data)),
    ?assertEqual(13, phenom_data_cell:pack_tag(pauli_query)),
    ?assertEqual(14, phenom_data_cell:pack_tag(pauli_reply)),
    ?assertEqual(15, phenom_data_cell:pack_tag(noise_cutoff)),
    ?assertEqual(16, phenom_data_cell:pack_tag(pauli_update)),
    Query = {pauli_query, 16#01020304, x},
    PackedQuery = phenom_data_cell:pack(Query),
    ?assertEqual(
        <<
            16#01020304:32/unsigned-little-integer,
            2:32/unsigned-little-integer
        >>,
        PackedQuery
    ),
    ?assertEqual(
        {Query, <<>>},
        phenom_data_cell:unpack(pauli_query, PackedQuery)
    ),
    Reply = {pauli_reply, 16#21222324, 16#3132, 16#4142, 1},
    PackedReply = phenom_data_cell:pack(Reply),
    ?assertEqual(
        <<
            16#21222324:32/unsigned-little-integer,
            16#3132:16/unsigned-little-integer,
            16#4142:16/unsigned-little-integer,
            1:32/unsigned-little-integer
        >>,
        PackedReply
    ),
    ?assertEqual(
        {Reply, <<>>},
        phenom_data_cell:unpack(pauli_reply, PackedReply)
    ),
    Interface = hls_actor_interface:from_module(phenom_data_cell),
    ?assertEqual(
        [pauli_reply],
        hls_actor_interface:output_schemas(Interface, measurement)
    ),
    ?assert(lists:member(
        pauli_query,
        hls_actor_interface:dispatched_schemas(Interface)
    )).

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
    cell(0, 0, Threshold, 0, ?SEED, 0, 0, i, 0, 0).

cell(Step, Seen, Threshold, Event, Random, X, Y, Pauli, RequestId,
        Anticommutes) ->
    controlled_cell(Step, Seen, Threshold, Event, Random, X, Y, Pauli,
        RequestId, Anticommutes, 0, 0).

controlled_cell(Step, Seen, Threshold, Event, Random, X, Y, Pauli,
        RequestId, Anticommutes, Resume, NoiseDisabled) ->
    {data_cell, Step, Seen, Threshold, Event, Random, X, Y, Pauli,
        RequestId, Anticommutes, Resume, NoiseDisabled, 0, 0}.

assert_query_failure(Messages) ->
    {PID, Neighbors, Ref} = start_cell(),
    unlink(PID),
    try
        ok = phenom_data_cell:configure(PID, ?SEED, 0),
        Monitor = monitor(process, PID),
        lists:foreach(fun(Message) -> hls_statem:cast(PID, Message) end,
            Messages),
        receive
            {'DOWN', Monitor, process, PID,
                    {hls_statem_failure, _Message}} ->
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
        || Direction <- [north, east, west, south, measurement]
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
    expect_report_batch(Ref, Step, Present, 0).

expect_report_batch(Ref, Step, Present, Quiet) ->
    Expected = expected_report_batch(Step, Present, Quiet),
    ?assertEqual(Expected, lists:sort(receive_batch(Ref, 4, []))).

expect_report_batches(Ref, Steps) ->
    Expected = lists:sort(lists:append([
        expected_report_batch(Step, Present, 0)
        || {Step, Present} <- Steps
    ])),
    Count = length(Steps) * 4,
    ?assertEqual(Expected, lists:sort(receive_batch(Ref, Count, []))).

expect_measurement_replies(Ref, Replies) ->
    ?assertEqual(
        [{measurement, Reply} || Reply <- Replies],
        lists:reverse(receive_batch(Ref, length(Replies), []))
    ).

expected_report_batch(Step, Present, Quiet) ->
    Flags = Present bor (Quiet bsl 1),
    lists:sort([
        {north, {phenom_data, Step, ?SOUTH_MASK, Flags}},
        {east, {phenom_data, Step, ?WEST_MASK, Flags}},
        {west, {phenom_data, Step, ?EAST_MASK, Flags}},
        {south, {phenom_data, Step, ?NORTH_MASK, Flags}}
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
