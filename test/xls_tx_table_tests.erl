-module(xls_tx_table_tests).

-include_lib("eunit/include/eunit.hrl").

split_phase_lifecycle_test() ->
    Peer = peer(peer_one, 4),
    ProtocolEpoch = 17,
    Table0 = xls_tx_table:new(2),
    {ok, Ref, Table1} = xls_tx_table:open(
        transaction_spec(
            Peer,
            owner_one,
            read,
            ProtocolEpoch,
            [read_reply],
            infinity,
            request_meta
        ),
        Table0
    ),

    ?assertEqual(
        {error, not_sent},
        xls_tx_table:complete(
            Peer,
            Ref,
            ProtocolEpoch,
            read_reply,
            premature_payload,
            Table1
        )
    ),
    ?assertMatch({ok, #{state := reserved}},
        xls_tx_table:lookup(Ref, Table1)),
    ?assertEqual(
        {error, not_completed},
        xls_tx_table:retire(Ref, Table1)
    ),

    {ok, Table2} = xls_tx_table:mark_sent(Ref, Table1),
    ?assertEqual(
        {error, {invalid_state, sent}},
        xls_tx_table:mark_sent(Ref, Table2)
    ),
    ?assertEqual(
        {error, not_completed},
        xls_tx_table:retire(Ref, Table2)
    ),
    ?assertEqual(
        {error, {peer_mismatch, Peer}},
        xls_tx_table:complete(
            peer(peer_two, 4),
            Ref,
            ProtocolEpoch,
            read_reply,
            wrong_peer_payload,
            Table2
        )
    ),
    ?assertEqual(
        {error, {peer_mismatch, Peer}},
        xls_tx_table:complete(
            peer(peer_one, 5),
            Ref,
            ProtocolEpoch,
            read_reply,
            wrong_incarnation_payload,
            Table2
        )
    ),
    ?assertEqual(
        {error, {epoch_mismatch, ProtocolEpoch}},
        xls_tx_table:complete(
            Peer,
            Ref,
            ProtocolEpoch + 1,
            read_reply,
            wrong_epoch_payload,
            Table2
        )
    ),
    ?assertEqual(
        {error, {unexpected_reply, [read_reply]}},
        xls_tx_table:complete(
            Peer,
            Ref,
            ProtocolEpoch,
            wrong_reply,
            wrong_tag_payload,
            Table2
        )
    ),

    {ok, Completed, Table3} = xls_tx_table:complete(
        Peer,
        Ref,
        ProtocolEpoch,
        read_reply,
        reply_payload,
        Table2
    ),
    ?assertEqual(owner_one, maps:get(request_owner, Completed)),
    ?assertEqual(request_meta, maps:get(meta, Completed)),
    ?assertEqual(completed, maps:get(state, Completed)),
    ?assertEqual(
        {reply, read_reply, reply_payload},
        maps:get(completion, Completed)
    ),
    ?assertEqual({ok, Completed}, xls_tx_table:lookup(Ref, Table3)),
    ?assertEqual(
        {error, already_completed},
        xls_tx_table:complete(
            Peer,
            Ref,
            ProtocolEpoch,
            read_reply,
            duplicate_payload,
            Table3
        )
    ),
    ?assertEqual(
        #{
            capacity => 2,
            free => 1,
            occupied => 1,
            reserved => 0,
            sent => 0,
            completed => 1
        },
        xls_tx_table:info(Table3)
    ),

    {ok, Completed, Table4} = xls_tx_table:retire(Ref, Table3),
    ?assertEqual(error, xls_tx_table:lookup(Ref, Table4)),
    ?assertEqual(
        {error, unknown_transaction},
        xls_tx_table:retire(Ref, Table4)
    ),
    ?assertEqual(
        #{
            capacity => 2,
            free => 2,
            occupied => 0,
            reserved => 0,
            sent => 0,
            completed => 0
        },
        xls_tx_table:info(Table4)
    ).

capacity_is_released_only_on_retirement_test() ->
    Incarnation = 42,
    Table0 = xls_tx_table:new(2, Incarnation),
    {ok, RefOne = {Incarnation, Slot, GenerationOne}, Table1} =
        xls_tx_table:open(
            transaction_spec(
                peer(peer_one, 1),
                owner_one,
                first,
                0,
                any,
                infinity,
                undefined
            ),
            Table0
        ),
    {ok, _RefTwo, Table2} = xls_tx_table:open(
        transaction_spec(
            peer(peer_two, 1),
            owner_two,
            second,
            0,
            any,
            infinity,
            undefined
        ),
        Table1
    ),

    {ok, Canceled, Table3} =
        xls_tx_table:cancel(RefOne, caller_canceled, Table2),
    ?assertEqual({canceled, caller_canceled}, maps:get(completion, Canceled)),
    ?assertEqual(
        {error, full},
        xls_tx_table:open(
            transaction_spec(
                peer(peer_three, 1),
                owner_three,
                third,
                0,
                any,
                infinity,
                undefined
            ),
            Table3
        )
    ),

    {ok, Canceled, Table4} = xls_tx_table:retire(RefOne, Table3),
    {ok, RefReused = {Incarnation, Slot, GenerationTwo}, Table5} =
        xls_tx_table:open(
            transaction_spec(
                peer(peer_three, 1),
                owner_three,
                third,
                0,
                any,
                infinity,
                undefined
            ),
            Table4
        ),
    ?assertEqual(GenerationOne + 1, GenerationTwo),
    ?assertEqual(
        {error, stale_transaction},
        xls_tx_table:complete(
            peer(peer_one, 1),
            RefOne,
            0,
            reply,
            stale_payload,
            Table5
        )
    ),
    ?assertMatch({ok, #{ref := RefReused, state := reserved}},
        xls_tx_table:lookup(RefReused, Table5)),
    ?assertEqual(
        #{
            capacity => 2,
            free => 0,
            occupied => 2,
            reserved => 2,
            sent => 0,
            completed => 0
        },
        xls_tx_table:info(Table5)
    ).

deadline_domains_and_terminal_uniqueness_test() ->
    PeerOne = peer(peer_one, 2),
    Table0 = xls_tx_table:new(4),
    {ok, RefA, Table1} = xls_tx_table:open(
        transaction_spec(PeerOne, owner_a, a, 1, any, {fabric_cycle, 100}, a_meta),
        Table0
    ),
    {ok, RefB, Table2} = xls_tx_table:open(
        transaction_spec(
            peer(peer_two, 2),
            owner_b,
            b,
            1,
            any,
            {fabric_cycle, 50},
            b_meta
        ),
        Table1
    ),
    {ok, RefC, Table3} = xls_tx_table:open(
        transaction_spec(PeerOne, owner_c, c, 1, any, {fabric_cycle, 50}, c_meta),
        Table2
    ),
    {ok, RefD, Table4} = xls_tx_table:open(
        transaction_spec(
            peer(peer_three, 2),
            owner_d,
            d,
            1,
            any,
            {protocol_epoch, 50},
            d_meta
        ),
        Table3
    ),
    {ok, Table5} = xls_tx_table:mark_sent(RefA, Table4),
    {ok, Table6} = xls_tx_table:mark_sent(RefB, Table5),
    {ok, Table7} = xls_tx_table:mark_sent(RefD, Table6),

    {[], Table7} = xls_tx_table:expire(fabric_cycle, 49, Table7),
    {Expired, Table8} = xls_tx_table:expire(fabric_cycle, 50, Table7),
    ?assertEqual([RefB, RefC], [maps:get(ref, Tx) || Tx <- Expired]),
    ?assertEqual(
        [
            {timeout, reply, fabric_cycle},
            {timeout, admission, fabric_cycle}
        ],
        [maps:get(completion, Tx) || Tx <- Expired]
    ),
    {[], Table8} = xls_tx_table:expire(fabric_cycle, 50, Table8),
    ?assertEqual(
        {error, already_completed},
        xls_tx_table:complete(
            peer(peer_two, 2),
            RefB,
            1,
            reply,
            late_payload,
            Table8
        )
    ),
    ?assertMatch({ok, #{state := sent}}, xls_tx_table:lookup(RefD, Table8)),

    {Canceled, Table9} = xls_tx_table:cancel_peer(
        PeerOne,
        bridge_down,
        Table8
    ),
    ?assertEqual([RefA], [maps:get(ref, Tx) || Tx <- Canceled]),
    ?assertEqual(
        [{canceled, bridge_down}],
        [maps:get(completion, Tx) || Tx <- Canceled]
    ),
    ?assertEqual(
        #{
            capacity => 4,
            free => 0,
            occupied => 4,
            reserved => 0,
            sent => 1,
            completed => 3
        },
        xls_tx_table:info(Table9)
    ),

    Table10 = retire_all([RefA, RefB, RefC], Table9),
    ?assertEqual(
        #{
            capacity => 4,
            free => 3,
            occupied => 1,
            reserved => 0,
            sent => 1,
            completed => 0
        },
        xls_tx_table:info(Table10)
    ).

same_peer_and_tag_complete_by_reference_test() ->
    Peer = peer(shared_peer, 9),
    ProtocolEpoch = 22,
    Table0 = xls_tx_table:new(2),
    {ok, RefOne, Table1} = xls_tx_table:open(
        transaction_spec(Peer, owner_one, request, ProtocolEpoch, [reply], infinity, one),
        Table0
    ),
    {ok, RefTwo, Table2} = xls_tx_table:open(
        transaction_spec(Peer, owner_two, request, ProtocolEpoch, [reply], infinity, two),
        Table1
    ),
    {ok, Table3} = xls_tx_table:mark_sent(RefOne, Table2),
    {ok, Table4} = xls_tx_table:mark_sent(RefTwo, Table3),

    {ok, Second, Table5} = xls_tx_table:complete(
        Peer,
        RefTwo,
        ProtocolEpoch,
        reply,
        second_payload,
        Table4
    ),
    ?assertEqual(owner_two, maps:get(request_owner, Second)),
    ?assertEqual(
        {reply, reply, second_payload},
        maps:get(completion, Second)
    ),
    ?assertMatch({ok, #{state := sent}},
        xls_tx_table:lookup(RefOne, Table5)),

    {ok, First, Table6} = xls_tx_table:complete(
        Peer,
        RefOne,
        ProtocolEpoch,
        reply,
        first_payload,
        Table5
    ),
    ?assertEqual(owner_one, maps:get(request_owner, First)),
    ?assertEqual(
        {reply, reply, first_payload},
        maps:get(completion, First)
    ),
    ?assertEqual(
        #{
            capacity => 2,
            free => 0,
            occupied => 2,
            reserved => 0,
            sent => 0,
            completed => 2
        },
        xls_tx_table:info(Table6)
    ),
    Table7 = retire_all([RefTwo, RefOne], Table6),
    ?assertEqual(
        #{
            capacity => 2,
            free => 2,
            occupied => 0,
            reserved => 0,
            sent => 0,
            completed => 0
        },
        xls_tx_table:info(Table7)
    ).

deadline_then_reuse_rejects_late_reply_test() ->
    Incarnation = 100,
    Peer = peer(peer_one, 3),
    Table0 = xls_tx_table:new(1, Incarnation),
    {ok, OldRef = {Incarnation, Slot, OldGeneration}, Table1} =
        xls_tx_table:open(
            transaction_spec(
                Peer,
                old_owner,
                request,
                8,
                [reply],
                {fabric_cycle, 10},
                old
            ),
            Table0
        ),
    {ok, Table2} = xls_tx_table:mark_sent(OldRef, Table1),
    {[], Table2} = xls_tx_table:expire(fabric_cycle, 9, Table2),
    {[TimedOut], Table3} = xls_tx_table:expire(fabric_cycle, 10, Table2),
    ?assertEqual({timeout, reply, fabric_cycle},
        maps:get(completion, TimedOut)),
    {[], Table3} = xls_tx_table:expire(fabric_cycle, 10, Table3),
    {ok, TimedOut, Table4} = xls_tx_table:retire(OldRef, Table3),

    {ok, NewRef = {Incarnation, Slot, NewGeneration}, Table5} =
        xls_tx_table:open(
            transaction_spec(Peer, new_owner, request, 8, [reply], infinity, new),
            Table4
        ),
    ?assertEqual(OldGeneration + 1, NewGeneration),
    {ok, Table6} = xls_tx_table:mark_sent(NewRef, Table5),
    ?assertEqual(
        {error, stale_transaction},
        xls_tx_table:complete(
            Peer,
            OldRef,
            8,
            reply,
            delayed_old_payload,
            Table6
        )
    ),
    ?assertMatch({ok, #{ref := NewRef, state := sent}},
        xls_tx_table:lookup(NewRef, Table6)),
    FutureRef = {Incarnation, Slot, NewGeneration + 5},
    ?assertEqual(
        {error, unknown_transaction},
        xls_tx_table:mark_sent(FutureRef, Table6)
    ),
    ?assertEqual(
        {error, unknown_transaction},
        xls_tx_table:retire(FutureRef, Table6)
    ),
    ?assertEqual(
        {error, stale_transaction},
        xls_tx_table:cancel(OldRef, late_cancel, Table6)
    ),
    ?assertEqual(
        {error, stale_transaction},
        xls_tx_table:retire(OldRef, Table6)
    ).

peer_and_owner_cancellation_are_incarnation_scoped_test() ->
    Owner = owner_one,
    PeerV1 = peer(peer_one, 1),
    PeerV2 = peer(peer_one, 2),
    Table0 = xls_tx_table:new(3),
    {ok, RefA, Table1} = xls_tx_table:open(
        transaction_spec(PeerV1, Owner, a, 0, any, infinity, a),
        Table0
    ),
    {ok, RefB, Table2} = xls_tx_table:open(
        transaction_spec(PeerV1, owner_two, b, 0, any, infinity, b),
        Table1
    ),
    {ok, RefC, Table3} = xls_tx_table:open(
        transaction_spec(PeerV2, Owner, c, 0, any, infinity, c),
        Table2
    ),

    {CanceledPeer, Table4} = xls_tx_table:cancel_peer(
        PeerV1,
        peer_down,
        Table3
    ),
    ?assertEqual([RefA, RefB], [
        maps:get(ref, Tx) || Tx <- CanceledPeer
    ]),
    ?assertMatch({ok, #{ref := RefC, state := reserved}},
        xls_tx_table:lookup(RefC, Table4)),

    {OwnerEntries, Table5} = xls_tx_table:cancel_owner(
        Owner,
        owner_down,
        Table4
    ),
    ?assertEqual([RefA, RefC], [maps:get(ref, Tx) || Tx <- OwnerEntries]),
    ?assertEqual(
        [
            {canceled, peer_down},
            {canceled, owner_down}
        ],
        [maps:get(completion, Tx) || Tx <- OwnerEntries]
    ),
    {OwnerEntries, Table5} =
        xls_tx_table:cancel_owner(Owner, owner_down, Table5),
    ?assertEqual(
        {error, already_completed},
        xls_tx_table:cancel(RefA, duplicate_cancel, Table5)
    ),
    Table6 = retire_all([RefA, RefB, RefC], Table5),
    ?assertEqual(
        #{
            capacity => 3,
            free => 3,
            occupied => 0,
            reserved => 0,
            sent => 0,
            completed => 0
        },
        xls_tx_table:info(Table6)
    ).

table_incarnation_prevents_restart_aba_test() ->
    Peer = peer(peer, 5),
    OldTable0 = xls_tx_table:new(1, 10),
    {ok, OldRef = {10, 0, 1}, OldTable1} = xls_tx_table:open(
        transaction_spec(Peer, old_owner, request, 4, [reply], infinity, old),
        OldTable0
    ),
    {ok, _OldTable2} = xls_tx_table:mark_sent(OldRef, OldTable1),

    NewTable0 = xls_tx_table:new(1, 11),
    {ok, NewRef = {11, 0, 1}, NewTable1} = xls_tx_table:open(
        transaction_spec(Peer, new_owner, request, 4, [reply], infinity, new),
        NewTable0
    ),
    {ok, NewTable2} = xls_tx_table:mark_sent(NewRef, NewTable1),
    ?assertEqual(
        {error, stale_transaction},
        xls_tx_table:mark_sent(OldRef, NewTable2)
    ),
    ?assertEqual(
        {error, stale_transaction},
        xls_tx_table:cancel(OldRef, old_owner_down, NewTable2)
    ),
    ?assertEqual(
        {error, stale_transaction},
        xls_tx_table:complete(
            Peer,
            OldRef,
            4,
            reply,
            delayed_old_payload,
            NewTable2
        )
    ),
    ?assertMatch({ok, #{ref := NewRef, state := sent}},
        xls_tx_table:lookup(NewRef, NewTable2)),
    {ok, Completed, NewTable3} = xls_tx_table:complete(
        Peer,
        NewRef,
        4,
        reply,
        new_payload,
        NewTable2
    ),
    ?assertEqual(
        {reply, reply, new_payload},
        maps:get(completion, Completed)
    ),
    ?assertEqual(
        #{
            capacity => 1,
            free => 0,
            occupied => 1,
            reserved => 0,
            sent => 0,
            completed => 1
        },
        xls_tx_table:info(NewTable3)
    ).

retire_all([], Table) ->
    Table;
retire_all([Ref | Rest], Table0) ->
    {ok, _Transaction, Table1} = xls_tx_table:retire(Ref, Table0),
    retire_all(Rest, Table1).

peer(Endpoint, Generation) ->
    {Endpoint, Generation}.

transaction_spec(Peer, RequestOwner, RequestTag, ProtocolEpoch, ExpectedReplies,
        Deadline, Meta) ->
    #{
        peer => Peer,
        request_owner => RequestOwner,
        request_tag => RequestTag,
        protocol_epoch => ProtocolEpoch,
        expected_replies => ExpectedReplies,
        deadline => Deadline,
        meta => Meta
    }.
