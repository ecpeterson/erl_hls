-module(hls_mailbox_tests).

-include_lib("eunit/include/eunit.hrl").

reservation_consumes_and_consume_returns_capacity_test() ->
    Mailbox0 = hls_mailbox:new(2, 7),
    {ok, ReservationA, Mailbox1} =
        hls_mailbox:reserve(7, source_a, Mailbox0),
    {ok, ReservationB, Mailbox2} =
        hls_mailbox:reserve(7, source_b, Mailbox1),
    ?assertEqual(0, maps:get(available, hls_mailbox:info(Mailbox2))),
    ?assertEqual(
        {error, full, Mailbox2},
        hls_mailbox:reserve(7, source_c, Mailbox2)
    ),

    {ok, Mailbox3} = hls_mailbox:commit(ReservationA, first, Mailbox2),
    ?assertEqual(
        {error, already_committed, Mailbox3},
        hls_mailbox:commit(ReservationA, duplicate, Mailbox3)
    ),
    {ok, Mailbox4} = hls_mailbox:commit(ReservationB, second, Mailbox3),
    {ok, Selection, 1, first} = hls_mailbox:select(
        [fun(_Message) -> true end], Mailbox4
    ),
    {ok, first, Mailbox5} = hls_mailbox:consume(Selection, Mailbox4),
    ?assertEqual(1, maps:get(available, hls_mailbox:info(Mailbox5))),
    {ok, _ReservationC, _Mailbox6} =
        hls_mailbox:reserve(7, source_c, Mailbox5).

cancel_releases_and_protects_reused_slot_test() ->
    Mailbox0 = hls_mailbox:new(1, 2),
    {ok, OldReservation, Mailbox1} =
        hls_mailbox:reserve(2, source, Mailbox0),
    ?assertEqual(0, maps:get(available, hls_mailbox:info(Mailbox1))),
    {ok, Mailbox2} = hls_mailbox:cancel(OldReservation, Mailbox1),
    ?assertEqual(1, maps:get(available, hls_mailbox:info(Mailbox2))),
    ?assertEqual(
        {error, invalid_reservation, Mailbox2},
        hls_mailbox:cancel(OldReservation, Mailbox2)
    ),

    {ok, NewReservation, Mailbox3} =
        hls_mailbox:reserve(2, source, Mailbox2),
    ?assertEqual(
        {error, invalid_reservation, Mailbox3},
        hls_mailbox:cancel(OldReservation, Mailbox3)
    ),
    {ok, Mailbox4} = hls_mailbox:commit(NewReservation, retained, Mailbox3),
    ?assertEqual(
        {error, invalid_reservation, Mailbox4},
        hls_mailbox:cancel(NewReservation, Mailbox4)
    ),
    {ok, _Selection, 1, retained} = hls_mailbox:select(
        [fun(_Message) -> true end], Mailbox4
    ).

commit_order_defines_arrival_age_test() ->
    Mailbox0 = hls_mailbox:new(2),
    {ok, ReservationA, Mailbox1} =
        hls_mailbox:reserve(0, source_a, Mailbox0),
    {ok, ReservationB, Mailbox2} =
        hls_mailbox:reserve(0, source_b, Mailbox1),
    {ok, Mailbox3} = hls_mailbox:commit(
        ReservationB, committed_first, Mailbox2
    ),
    {ok, Mailbox4} = hls_mailbox:commit(
        ReservationA, committed_second, Mailbox3
    ),
    {ok, _Selection, 1, committed_first} = hls_mailbox:select(
        [fun(_Message) -> true end], Mailbox4
    ).

associative_oldest_matching_and_clause_priority_test() ->
    Mailbox0 = commit_messages([
        #{kind => ignored, value => 1},
        #{kind => wanted, value => 3},
        #{kind => wanted, value => 2}
    ]),
    Clauses = [
        fun(#{value := 2}) -> true; (_) -> false end,
        fun(#{kind := wanted}) -> true; (_) -> false end
    ],
    {ok, Selection, 2, #{value := 3} = Message} =
        hls_mailbox:select(Clauses, Mailbox0),
    {ok, Message, Mailbox1} = hls_mailbox:consume(Selection, Mailbox0),
    {ok, _Selection2, 1, #{value := 2}} =
        hls_mailbox:select(Clauses, Mailbox1),

    IgnoredOnly = [fun(#{kind := ignored}) -> true; (_) -> false end],
    {ok, _Selection3, 1, #{value := 1}} =
        hls_mailbox:select(IgnoredOnly, Mailbox1).

current_future_phase_interleaving_test() ->
    Mailbox0 = commit_messages([
        #{phase => 1, source => west, name => future_west_old},
        #{phase => 0, source => east, name => current_east_old},
        #{phase => 1, source => north, name => future_north},
        #{phase => 0, source => west, name => current_west_new},
        #{phase => 1, source => east, name => future_east_new}
    ]),

    {ok, CurrentEastSelection, 1, #{name := current_east_old} = CurrentEast} =
        hls_mailbox:select([phase_clause(0)], Mailbox0),
    {ok, CurrentEast, Mailbox1} =
        hls_mailbox:consume(CurrentEastSelection, Mailbox0),
    {ok, CurrentWestSelection, 1, #{name := current_west_new} = CurrentWest} =
        hls_mailbox:select([phase_clause(0)], Mailbox1),
    {ok, CurrentWest, Mailbox2} =
        hls_mailbox:consume(CurrentWestSelection, Mailbox1),

    {ok, FutureWestSelection, 1, #{name := future_west_old} = FutureWest} =
        hls_mailbox:select([phase_clause(1)], Mailbox2),
    {ok, FutureWest, Mailbox3} =
        hls_mailbox:consume(FutureWestSelection, Mailbox2),
    {ok, FutureNorthSelection, 1, #{name := future_north} = FutureNorth} =
        hls_mailbox:select([phase_clause(1)], Mailbox3),
    {ok, FutureNorth, Mailbox4} =
        hls_mailbox:consume(FutureNorthSelection, Mailbox3),
    {ok, _FutureEastSelection, 1, #{name := future_east_new}} =
        hls_mailbox:select([phase_clause(1)], Mailbox4).

all_neighbor_phase_interleavings_test_() ->
    {timeout, 10, fun() ->
        Sources = [north, east, west, south],
        Interleavings = phase_interleavings([
            [{Source, 0}, {Source, 1}]
            || Source <- Sources
        ]),
        ?assertEqual(2520, length(Interleavings)),
        lists:foreach(fun assert_phase_interleaving/1, Interleavings)
    end}.

foreign_mailbox_tokens_are_rejected_test() ->
    MailboxA0 = hls_mailbox:new(1),
    {ok, ReservationA, MailboxA1} =
        hls_mailbox:reserve(0, source, MailboxA0),
    {ok, MailboxA2} =
        hls_mailbox:commit(ReservationA, from_a, MailboxA1),
    {ok, SelectionA, 1, from_a} = hls_mailbox:select(
        [fun(_Message) -> true end], MailboxA2
    ),

    MailboxB0 = hls_mailbox:new(1),
    {ok, ReservationB, MailboxB1} =
        hls_mailbox:reserve(0, source, MailboxB0),
    ?assertEqual(
        {error, invalid_reservation, MailboxB1},
        hls_mailbox:commit(ReservationA, foreign, MailboxB1)
    ),
    ?assertEqual(
        {error, invalid_reservation, MailboxB1},
        hls_mailbox:cancel(ReservationA, MailboxB1)
    ),
    {ok, MailboxB2} =
        hls_mailbox:commit(ReservationB, from_b, MailboxB1),
    ?assertEqual(
        {error, stale_selection, MailboxB2},
        hls_mailbox:consume(SelectionA, MailboxB2)
    ),
    {ok, _SelectionB, 1, from_b} = hls_mailbox:select(
        [fun(_Message) -> true end], MailboxB2
    ).

cancel_owner_reclaims_only_incomplete_messages_test() ->
    Mailbox0 = hls_mailbox:new(4),
    {ok, CommittedA, Mailbox1} =
        hls_mailbox:reserve(0, source_a, Mailbox0),
    {ok, IncompleteA, Mailbox2} =
        hls_mailbox:reserve(0, source_a, Mailbox1),
    {ok, CommittedB, Mailbox3} =
        hls_mailbox:reserve(0, source_b, Mailbox2),
    {ok, Mailbox4} =
        hls_mailbox:commit(CommittedA, delivered_a, Mailbox3),
    {ok, Mailbox5} =
        hls_mailbox:commit(CommittedB, delivered_b, Mailbox4),

    {1, Mailbox6} = hls_mailbox:cancel_owner(source_a, Mailbox5),
    Info = hls_mailbox:info(Mailbox6),
    ?assertEqual(2, maps:get(committed, Info)),
    ?assertEqual(0, maps:get(reserved, Info)),
    ?assertEqual(2, maps:get(available, Info)),
    ?assertEqual(
        {error, invalid_reservation, Mailbox6},
        hls_mailbox:commit(IncompleteA, late, Mailbox6)
    ),
    {0, Mailbox6} = hls_mailbox:cancel_owner(source_a, Mailbox6),
    {ok, First, 1, delivered_a} = hls_mailbox:select(
        [fun(_Message) -> true end], Mailbox6
    ),
    {ok, delivered_a, Mailbox7} = hls_mailbox:consume(First, Mailbox6),
    {ok, _Second, 1, delivered_b} = hls_mailbox:select(
        [fun(_Message) -> true end], Mailbox7
    ).

reset_invalidates_old_generation_state_test() ->
    Mailbox0 = hls_mailbox:new(2, 4),
    {ok, ReservedOnly, Mailbox1} =
        hls_mailbox:reserve(4, source_a, Mailbox0),
    {ok, Committed, Mailbox2} =
        hls_mailbox:reserve(4, source_b, Mailbox1),
    {ok, Mailbox3} = hls_mailbox:commit(Committed, old_message, Mailbox2),
    {ok, OldSelection, 1, old_message} = hls_mailbox:select(
        [fun(_Message) -> true end], Mailbox3
    ),

    Mailbox4 = hls_mailbox:reset(Mailbox3),
    Info = hls_mailbox:info(Mailbox4),
    ?assertEqual(5, maps:get(generation, Info)),
    ?assertEqual(0, maps:get(occupied, Info)),
    ?assertEqual(none, hls_mailbox:select(
        [fun(_Message) -> true end], Mailbox4
    )),
    Stale = {stale_generation, 5, 4},
    ?assertEqual(
        {error, Stale, Mailbox4},
        hls_mailbox:reserve(4, source_c, Mailbox4)
    ),
    ?assertEqual(
        {error, Stale, Mailbox4},
        hls_mailbox:commit(ReservedOnly, late_message, Mailbox4)
    ),
    ?assertEqual(
        {error, Stale, Mailbox4},
        hls_mailbox:cancel(ReservedOnly, Mailbox4)
    ),
    ?assertEqual(
        {error, Stale, Mailbox4},
        hls_mailbox:consume(OldSelection, Mailbox4)
    ),
    {ok, _NewReservation, _Mailbox5} =
        hls_mailbox:reserve(5, source_c, Mailbox4).

consumed_selection_cannot_target_reused_slot_test() ->
    Mailbox0 = hls_mailbox:new(1),
    {ok, Reservation0, Mailbox1} =
        hls_mailbox:reserve(0, source, Mailbox0),
    {ok, Mailbox2} = hls_mailbox:commit(Reservation0, old, Mailbox1),
    {ok, OldSelection, 1, old} = hls_mailbox:select(
        [fun(_Message) -> true end], Mailbox2
    ),
    {ok, old, Mailbox3} = hls_mailbox:consume(OldSelection, Mailbox2),
    {ok, Reservation1, Mailbox4} =
        hls_mailbox:reserve(0, source, Mailbox3),
    {ok, Mailbox5} = hls_mailbox:commit(Reservation1, new, Mailbox4),
    ?assertEqual(
        {error, stale_selection, Mailbox5},
        hls_mailbox:consume(OldSelection, Mailbox5)
    ).

invalid_constructor_arguments_test() ->
    ?assertError(badarg, hls_mailbox:new(0)),
    ?assertError(badarg, hls_mailbox:new(1, -1)).

commit_messages(Messages) ->
    lists:foldl(
        fun(Message, Mailbox0) ->
            Generation = maps:get(generation, hls_mailbox:info(Mailbox0)),
            Owner = maps:get(source, Message, test_source),
            {ok, Reservation, Mailbox1} =
                hls_mailbox:reserve(Generation, Owner, Mailbox0),
            {ok, Mailbox2} =
                hls_mailbox:commit(Reservation, Message, Mailbox1),
            Mailbox2
        end,
        hls_mailbox:new(length(Messages)),
        Messages
    ).

phase_clause(ExpectedPhase) ->
    fun
        (#{phase := MessagePhase}) when MessagePhase =:= ExpectedPhase -> true;
        (_) -> false
    end.

assert_phase_interleaving(Order) ->
    Mailbox0 = commit_messages([
        #{source => Source, phase => Phase}
        || {Source, Phase} <- Order
    ]),
    {Current, Mailbox1} = take_phase(0, 4, Mailbox0, []),
    {Future, Mailbox2} = take_phase(1, 4, Mailbox1, []),
    ?assertEqual(
        [Source || {Source, 0} <- Order],
        [Source || #{source := Source} <- Current]
    ),
    ?assertEqual(
        [Source || {Source, 1} <- Order],
        [Source || #{source := Source} <- Future]
    ),
    ?assertEqual(none, hls_mailbox:select([phase_clause(0)], Mailbox2)),
    ?assertEqual(none, hls_mailbox:select([phase_clause(1)], Mailbox2)).

take_phase(_Phase, 0, Mailbox, Acc) ->
    {lists:reverse(Acc), Mailbox};
take_phase(Phase, Count, Mailbox0, Acc) ->
    {ok, Selection, 1, Message} =
        hls_mailbox:select([phase_clause(Phase)], Mailbox0),
    {ok, Message, Mailbox1} = hls_mailbox:consume(Selection, Mailbox0),
    take_phase(Phase, Count - 1, Mailbox1, [Message | Acc]).

phase_interleavings(Queues) ->
    case lists:all(fun(Queue) -> Queue =:= [] end, Queues) of
        true ->
            [[]];
        false ->
            [
                [Head | Tail]
                || {Index, [Head | Rest]} <- lists:enumerate(Queues),
                   Tail <- phase_interleavings(
                       replace_nth(Index, Rest, Queues)
                   )
            ]
    end.

replace_nth(Index, Value, Values) ->
    {Before, [_Old | After]} = lists:split(Index - 1, Values),
    Before ++ [Value | After].
