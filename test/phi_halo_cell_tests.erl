-module(phi_halo_cell_tests).

-include_lib("eunit/include/eunit.hrl").

repeated_diffusion_precedes_flipping_test() ->
    with_cell(fun repeated_diffusion_and_flipping/2).

early_messages_retry_at_protocol_boundaries_test() ->
    with_cell(fun staged_next_phase_messages/2).

full_next_epoch_batch_uses_reserved_progress_slot_test() ->
    with_cell(fun full_staged_diffusion_epoch/2).

deferred_connection_delays_initial_entry_test() ->
    {Collectors, Ref} = start_collectors(),
    {ok, PID} = phi_halo_cell:start_link(),
    try
        Info = phi_halo_cell:runtime_info(PID),
        ?assertNot(maps:get(connected, Info)),
        assert_no_neighbor_cast(Ref),
        ok = phi_halo_cell:connect(PID, Collectors),
        expect_neighbor_batch(Ref, {phi, 0, [0, 0]})
    after
        case is_process_alive(PID) of
            true -> phi_halo_cell:stop(PID);
            false -> ok
        end,
        stop_collectors(Ref, Collectors)
    end.

early_phi_casts_wait_for_initial_entry_test() ->
    {Collectors, Ref} = start_collectors(),
    {ok, PID} = phi_halo_cell:start_link(),
    try
        four_phis(PID, 0, [16, 32]),
        Before = phi_halo_cell:runtime_info(PID),
        ?assertEqual(disconnected, maps:get(lifecycle, Before)),
        ?assertEqual(4, maps:get(committed, maps:get(mailbox, Before))),
        ?assertMatch({cell, 0, 0, [0, 0], [0, 0], 0, 0, 0},
            maps:get(data, Before)),
        assert_no_neighbor_cast(Ref),

        ok = phi_halo_cell:connect(PID, Collectors),
        expect_neighbor_sequences(Ref, [
            {phi, 0, [0, 0]},
            {phi, 1, [8, 6]}
        ]),

        After = phi_halo_cell:runtime_info(PID),
        ?assertEqual(connected, maps:get(lifecycle, After)),
        ?assertEqual(gathering, maps:get(phase, After)),
        ?assertEqual(0, maps:get(committed, maps:get(mailbox, After))),
        ?assertMatch({cell, 0, 1, [8, 6], [0, 0], 0, 0, 0},
            maps:get(data, After))
    after
        case is_process_alive(PID) of
            true -> phi_halo_cell:stop(PID);
            false -> ok
        end,
        stop_collectors(Ref, Collectors)
    end.

deferred_degree_four_cycle_completes_multiple_steps_test() ->
    Cells = [
        begin
            {ok, PID} = phi_halo_cell:start_link(),
            unlink(PID),
            PID
        end
        || _ <- lists:seq(1, 4)
    ],
    [NorthWest, NorthEast, SouthWest, SouthEast] = Cells,
    try
        %% In a 2x2 periodic mesh, north and south reach the same cell, as do
        %% east and west; the four named ports still represent four edges.
        ok = phi_halo_cell:connect(
            NorthWest,
            torus_neighbors(NorthEast, SouthWest)
        ),
        ok = phi_halo_cell:connect(
            NorthEast,
            torus_neighbors(NorthWest, SouthEast)
        ),
        ok = phi_halo_cell:connect(
            SouthWest,
            torus_neighbors(SouthEast, NorthWest)
        ),
        ok = phi_halo_cell:connect(
            SouthEast,
            torus_neighbors(SouthWest, NorthEast)
        ),
        lists:foreach(fun(PID) -> await_step(PID, 2) end, Cells)
    after
        lists:foreach(fun stop_cell/1, Cells)
    end.

all_causal_final_round_interleavings_test_() ->
    [
        {iolist_to_binary(io_lib:format("~p", [Schedule])),
            fun() -> exercise_interleaving(Schedule) end}
        || Schedule <- causal_schedules(4, 4)
    ].

four_named_outputs_receive_one_cast_each_test() ->
    with_cell(fun(_PID, Ref) ->
        expect_neighbor_batch(Ref, {phi, 0, [0, 0]}),
        assert_no_neighbor_cast(Ref)
    end).

invalid_diffusion_epoch_stops_cell_test() ->
    {PID, Collectors, Ref} = start_cell(),
    unlink(PID),
    expect_neighbor_batch(Ref, {phi, 0, [0, 0]}),
    Monitor = monitor(process, PID),
    ok = phi_halo_cell:offer_phi(PID, 2, [0, 0]),
    receive
        {'DOWN', Monitor, process, PID, {xls_statem_failure, _Message}} -> ok
    after 1000 ->
        error(cell_did_not_stop_on_invalid_diffusion_epoch)
    end,
    stop_collectors(Ref, Collectors).

boolean_anyon_api_encodes_move_test() ->
    with_cell(fun(PID, Ref) ->
        expect_neighbor_batch(Ref, {phi, 0, [0, 0]}),
        four_phis(PID, 0, [0, 0]),
        expect_neighbor_batch(Ref, {phi, 1, [0, 0]}),
        four_phis(PID, 1, [0, 0]),
        expect_neighbor_batch(Ref, {anyon_move, 0, 0}),
        ok = phi_halo_cell:offer_anyon(PID, 0, true),
        ?assertMatch(
            {cell, 0, 2, [0, 0], [0, 0], 0, 1, 1},
            maps:get(data, phi_halo_cell:runtime_info(PID))
        )
    end).

invalid_anyon_word_stops_cell_in_flipping_test() ->
    {PID, Collectors, Ref} = start_cell(),
    unlink(PID),
    try
        expect_neighbor_batch(Ref, {phi, 0, [0, 0]}),
        four_phis(PID, 0, [0, 0]),
        expect_neighbor_batch(Ref, {phi, 1, [0, 0]}),
        four_phis(PID, 1, [0, 0]),
        expect_neighbor_batch(Ref, {anyon_move, 0, 0}),
        ?assertEqual(
            flipping,
            maps:get(phase, phi_halo_cell:runtime_info(PID))
        ),

        Monitor = monitor(process, PID),
        ok = xls_statem:cast(PID, {anyon_move, 0, 2}),
        receive
            {'DOWN', Monitor, process, PID,
                    {xls_statem_failure, _Message}} ->
                ok
        after 1000 ->
            error(cell_did_not_stop_on_invalid_anyon_word)
        end
    after
        stop_cell(PID),
        stop_collectors(Ref, Collectors)
    end.

generated_dslx_matches_checked_in_artifact_test() ->
    {ok, Expected} = file:read_file(
        "src/examples/phi_halo_cell.erl.x"
    ),
    Generated = iolist_to_binary(
        xls_parse:to_xls("src/examples/phi_halo_cell.erl")
    ),
    ?assertEqual(Expected, Generated),
    {DispatchStart, _DispatchMarkerLength} = binary:match(
        Generated,
        <<"fn dispatch">>
    ),
    Dispatch = binary:part(
        Generated,
        DispatchStart,
        byte_size(Generated) - DispatchStart
    ),
    %% Multiple clauses for a message and phase still produce one ordered
    %% selector per {message tag, phase} pair.
    ?assertEqual(
        2,
        length(binary:matches(Dispatch, <<"Phase::GATHERING =>">>))
    ),
    ?assertEqual(
        2,
        length(binary:matches(Dispatch, <<"Phase::FLIPPING =>">>))
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(
            Generated,
            <<"Tag::PHI as u8) && frame.header.payload_words == u8:3">>
        )
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(
            Generated,
            <<"Tag::ANYON_MOVE as u8) && "
              "frame.header.payload_words == u8:2">>
        )
    ).

message_wire_abi_test() ->
    Phi = {phi, 16#01020304, [16#11121314, 16#21222324]},
    Move = {anyon_move, 16#31323334, 1},
    ?assertEqual(3, phi_halo_cell:pack_tag(phi)),
    ?assertEqual(4, phi_halo_cell:pack_tag(anyon_move)),
    ?assertEqual(phi, phi_halo_cell:unpack_tag(3)),
    ?assertEqual(anyon_move, phi_halo_cell:unpack_tag(4)),
    PackedPhi = phi_halo_cell:pack(Phi),
    ?assertEqual(
        <<
            16#01020304:32/unsigned-little-integer,
            16#21222324:32/unsigned-little-integer,
            16#11121314:32/unsigned-little-integer
        >>,
        PackedPhi
    ),
    ?assertEqual({Phi, <<>>}, phi_halo_cell:unpack(phi, PackedPhi)),
    PackedMove = phi_halo_cell:pack(Move),
    ?assertEqual(
        <<
            16#31323334:32/unsigned-little-integer,
            1:32/unsigned-little-integer
        >>,
        PackedMove
    ),
    ?assertEqual(
        {Move, <<>>},
        phi_halo_cell:unpack(anyon_move, PackedMove)
    ).

two_layer_relaxation_coefficients_test() ->
    Initial = {cell, 0, 0, [40, 20], [0, 0], 0, 0, 0},
    Message0 = {phi, 0, [8, 12]},
    {gathering, First, consume} =
        phi_halo_cell:handle_cast(Message0, gathering, Initial),
    {gathering, Second, consume} =
        phi_halo_cell:handle_cast(Message0, gathering, First),
    {gathering, Third, consume} =
        phi_halo_cell:handle_cast(Message0, gathering, Second),
    {repeat_phase, RoundOne, consume} =
        phi_halo_cell:handle_cast(Message0, gathering, Third),
    ?assertEqual(
        {cell, 0, 1, [19, 19], [0, 0], 0, 0, 0},
        RoundOne
    ),

    Message1 = {phi, 1, [8, 12]},
    {gathering, Fifth, consume} =
        phi_halo_cell:handle_cast(Message1, gathering, RoundOne),
    {gathering, Sixth, consume} =
        phi_halo_cell:handle_cast(Message1, gathering, Fifth),
    {gathering, Seventh, consume} =
        phi_halo_cell:handle_cast(Message1, gathering, Sixth),
    ?assertEqual(
        {flipping, {cell, 0, 2, [12, 17], [0, 0], 0, 0, 0}, consume},
        phi_halo_cell:handle_cast(Message1, gathering, Seventh)
    ).

repeated_diffusion_and_flipping(PID, Ref) ->
    expect_neighbor_batch(Ref, {phi, 0, [0, 0]}),

    ok = phi_halo_cell:offer_phi(PID, 0, [32, 48]),
    ok = phi_halo_cell:offer_phi(PID, 0, [64, 80]),
    ok = phi_halo_cell:offer_phi(PID, 0, [16, 32]),
    ok = phi_halo_cell:offer_phi(PID, 0, [48, 64]),
    expect_neighbor_batch(Ref, {phi, 1, [20, 11]}),
    AfterRoundOne = phi_halo_cell:runtime_info(PID),
    ?assertEqual(gathering, maps:get(phase, AfterRoundOne)),

    four_phis(PID, 1, [16, 32]),
    expect_neighbor_batch(Ref, {anyon_move, 0, 0}),
    ?assertEqual(flipping, maps:get(phase, phi_halo_cell:runtime_info(PID))),

    four_anyons(PID, 0, false),
    expect_neighbor_batch(Ref, {phi, 2, [15, 15]}),

    Info = phi_halo_cell:runtime_info(PID),
    ?assertEqual(gathering, maps:get(phase, Info)),
    ?assertEqual(0, maps:get(postponed, Info)),
    ?assertEqual(0, maps:get(committed, maps:get(mailbox, Info))),
    ?assertMatch({cell, 1, 0, [15, 15], [0, 0], 0, 0, 0},
        maps:get(data, Info)),
    assert_no_neighbor_cast(Ref).

staged_next_phase_messages(PID, Ref) ->
    expect_neighbor_batch(Ref, {phi, 0, [0, 0]}),

    %% A faster neighbor can begin the next diffusion epoch while this cell is
    %% still gathering the current one.
    ok = phi_halo_cell:offer_phi(PID, 1, [8, 12]),
    ok = phi_halo_cell:offer_phi(PID, 0, [32, 48]),
    ok = phi_halo_cell:offer_phi(PID, 0, [64, 80]),
    ok = phi_halo_cell:offer_phi(PID, 0, [16, 32]),
    BeforeRepeat = phi_halo_cell:runtime_info(PID),
    ?assertEqual(gathering, maps:get(phase, BeforeRepeat)),
    ?assertEqual(1, maps:get(postponed, BeforeRepeat)),

    ok = phi_halo_cell:offer_phi(PID, 0, [48, 64]),
    expect_neighbor_batch(Ref, {phi, 1, [20, 11]}),
    AfterRepeat = phi_halo_cell:runtime_info(PID),
    ?assertEqual(gathering, maps:get(phase, AfterRepeat)),
    ?assertEqual(0, maps:get(postponed, AfterRepeat)),
    ?assertMatch({cell, 0, 1, [20, 11], [8, 12], 1, 0, 0},
        maps:get(data, AfterRepeat)),

    %% An early flipping message survives the final diffusion round.
    ok = phi_halo_cell:offer_anyon(PID, 0, false),
    ok = phi_halo_cell:offer_phi(PID, 1, [8, 12]),
    ok = phi_halo_cell:offer_phi(PID, 1, [8, 12]),
    BeforeFlip = phi_halo_cell:runtime_info(PID),
    ?assertEqual(gathering, maps:get(phase, BeforeFlip)),
    ?assertEqual(1, maps:get(postponed, BeforeFlip)),

    ok = phi_halo_cell:offer_phi(PID, 1, [8, 12]),
    expect_neighbor_batch(Ref, {anyon_move, 0, 0}),
    AfterFlip = phi_halo_cell:runtime_info(PID),
    ?assertEqual(flipping, maps:get(phase, AfterFlip)),
    ?assertEqual(0, maps:get(postponed, AfterFlip)),
    ?assertMatch({cell, 0, 2, [11, 11], [0, 0], 0, 1, 0},
        maps:get(data, AfterFlip)),

    %% The symmetric case occurs while this cell waits for anyon updates. The
    %% next step starts at diffusion epoch 2, not decoder step 1 on the wire.
    ok = phi_halo_cell:offer_phi(PID, 2, [8, 12]),
    ok = phi_halo_cell:offer_anyon(PID, 0, false),
    ok = phi_halo_cell:offer_anyon(PID, 0, false),
    BeforeGather = phi_halo_cell:runtime_info(PID),
    ?assertEqual(flipping, maps:get(phase, BeforeGather)),
    ?assertEqual(1, maps:get(postponed, BeforeGather)),

    ok = phi_halo_cell:offer_anyon(PID, 0, false),
    expect_neighbor_batch(Ref, {phi, 2, [11, 11]}),
    AfterGather = phi_halo_cell:runtime_info(PID),
    ?assertEqual(gathering, maps:get(phase, AfterGather)),
    ?assertEqual(0, maps:get(postponed, AfterGather)),
    ?assertMatch({cell, 1, 0, [11, 11], [8, 12], 1, 0, 0},
        maps:get(data, AfterGather)).

full_staged_diffusion_epoch(PID, Ref) ->
    expect_neighbor_batch(Ref, {phi, 0, [0, 0]}),

    %% Four next-epoch messages can occupy the queue while the fifth slot
    %% remains available to make progress on the current epoch.
    four_phis(PID, 1, [8, 12]),
    Staged = phi_halo_cell:runtime_info(PID),
    ?assertEqual(4, maps:get(postponed, Staged)),
    ?assertEqual(4, maps:get(committed, maps:get(mailbox, Staged))),

    four_phis(PID, 0, [0, 0]),
    expect_neighbor_sequences(Ref, [
        {phi, 1, [0, 0]},
        {anyon_move, 0, 0}
    ]),
    Complete = phi_halo_cell:runtime_info(PID),
    ?assertEqual(flipping, maps:get(phase, Complete)),
    ?assertEqual(0, maps:get(postponed, Complete)),
    ?assertEqual(0, maps:get(committed, maps:get(mailbox, Complete))),
    ?assertMatch({cell, 0, 2, [4, 2], [0, 0], 0, 0, 0},
        maps:get(data, Complete)).

exercise_interleaving(Schedule) ->
    with_cell(fun(PID, Ref) ->
        expect_neighbor_batch(Ref, {phi, 0, [0, 0]}),
        four_phis(PID, 0, [16, 32]),
        expect_neighbor_batch(Ref, {phi, 1, [8, 6]}),
        lists:foreach(
            fun
                (phi) -> phi_halo_cell:offer_phi(PID, 1, [16, 32]);
                (anyon) -> phi_halo_cell:offer_anyon(PID, 0, false)
            end,
            Schedule
        ),
        expect_neighbor_sequences(
            Ref,
            [{anyon_move, 0, 0}, {phi, 2, [11, 10]}]
        ),
        Info = phi_halo_cell:runtime_info(PID),
        ?assertEqual(gathering, maps:get(phase, Info)),
        ?assertEqual(0, maps:get(postponed, Info)),
        ?assertEqual(0, maps:get(committed, maps:get(mailbox, Info)))
    end).

with_cell(Test) ->
    {PID, Collectors, Ref} = start_cell(),
    try
        Test(PID, Ref)
    after
        case is_process_alive(PID) of
            true -> phi_halo_cell:stop(PID);
            false -> ok
        end,
        stop_collectors(Ref, Collectors)
    end.

start_cell() ->
    {Collectors, Ref} = start_collectors(),
    {ok, PID} = phi_halo_cell:start_link(Collectors),
    {PID, Collectors, Ref}.

torus_neighbors(Horizontal, Vertical) ->
    #{
        north => Vertical,
        east => Horizontal,
        west => Horizontal,
        south => Vertical
    }.

await_step(PID, Step) ->
    await_step(PID, Step, 1000).

await_step(_PID, Step, 0) ->
    error({cell_did_not_reach_decoder_step, Step});
await_step(PID, Step, Attempts) ->
    Info = phi_halo_cell:runtime_info(PID),
    case maps:get(data, Info) of
        {cell, CurrentStep, _Round, _Phi, _Sum, _PhiReceived,
                _MovesReceived, _Anyon} when CurrentStep >= Step ->
            ok;
        _ ->
            receive after 1 -> ok end,
            await_step(PID, Step, Attempts - 1)
    end.

stop_cell(PID) ->
    case is_process_alive(PID) of
        true -> phi_halo_cell:stop(PID);
        false -> ok
    end.

start_collectors() ->
    Ports = [north, east, west, south],
    Parent = self(),
    Ref = make_ref(),
    Collectors = maps:from_list([
        {Port, spawn_link(fun() -> collector_loop(Parent, Ref, Port) end)}
        || Port <- Ports
    ]),
    {Collectors, Ref}.

collector_loop(Parent, Ref, Port) ->
    receive
        {'$gen_cast', Message} ->
            Parent ! {neighbor_cast, Ref, Port, Message},
            collector_loop(Parent, Ref, Port);
        {stop, Stopper} ->
            Stopper ! {collector_stopped, Ref, Port},
            ok
    end.

expect_neighbor_batch(Ref, Expected) ->
    expect_neighbor_batch(Ref, Expected, [north, east, west, south]).

expect_neighbor_batch(_Ref, _Expected, []) ->
    ok;
expect_neighbor_batch(Ref, Expected, Remaining) ->
    receive
        {neighbor_cast, Ref, Port, Expected} ->
            true = lists:member(Port, Remaining),
            expect_neighbor_batch(
                Ref,
                Expected,
                lists:delete(Port, Remaining)
            );
        {neighbor_cast, Ref, Port, Other} ->
            error({unexpected_neighbor_cast, Port, Expected, Other})
    after 1000 ->
        error({missing_neighbor_casts, Expected, Remaining})
    end.

expect_neighbor_sequences(Ref, Sequence) ->
    Remaining = maps:from_list([
        {Port, Sequence} || Port <- [north, east, west, south]
    ]),
    expect_remaining_neighbor_sequences(Ref, Remaining).

expect_remaining_neighbor_sequences(_Ref, Remaining)
        when map_size(Remaining) =:= 0 ->
    ok;
expect_remaining_neighbor_sequences(Ref, Remaining) ->
    receive
        {neighbor_cast, Ref, Port, Message} ->
            case Remaining of
                #{Port := [Message]} ->
                    expect_remaining_neighbor_sequences(
                        Ref,
                        maps:remove(Port, Remaining)
                    );
                #{Port := [Message | Rest]} ->
                    expect_remaining_neighbor_sequences(
                        Ref,
                        Remaining#{Port := Rest}
                    );
                #{Port := Expected} ->
                    error({unexpected_neighbor_sequence, Port,
                        Expected, Message});
                _ ->
                    error({duplicate_neighbor_sequence, Port, Message})
            end
    after 1000 ->
        error({missing_neighbor_sequences, Remaining})
    end.

assert_no_neighbor_cast(Ref) ->
    receive
        {neighbor_cast, Ref, Port, Message} ->
            error({duplicate_neighbor_cast, Port, Message})
    after 20 ->
        ok
    end.

four_anyons(PID, Step, Present) ->
    ok = phi_halo_cell:offer_anyon(PID, Step, Present),
    ok = phi_halo_cell:offer_anyon(PID, Step, Present),
    ok = phi_halo_cell:offer_anyon(PID, Step, Present),
    ok = phi_halo_cell:offer_anyon(PID, Step, Present).

four_phis(PID, Epoch, Values) ->
    ok = phi_halo_cell:offer_phi(PID, Epoch, Values),
    ok = phi_halo_cell:offer_phi(PID, Epoch, Values),
    ok = phi_halo_cell:offer_phi(PID, Epoch, Values),
    ok = phi_halo_cell:offer_phi(PID, Epoch, Values).

causal_schedules(PhiRemaining, AnyonRemaining) ->
    causal_schedules(PhiRemaining, AnyonRemaining, 0, []).

causal_schedules(0, 0, _OutstandingPhi, Prefix) ->
    [lists:reverse(Prefix)];
causal_schedules(PhiRemaining, AnyonRemaining, OutstandingPhi, Prefix) ->
    PhiSchedules = case PhiRemaining > 0 of
        true ->
            causal_schedules(
                PhiRemaining - 1,
                AnyonRemaining,
                OutstandingPhi + 1,
                [phi | Prefix]
            );
        false ->
            []
    end,
    AnyonSchedules = case AnyonRemaining > 0 andalso OutstandingPhi > 0 of
        true ->
            causal_schedules(
                PhiRemaining,
                AnyonRemaining - 1,
                OutstandingPhi - 1,
                [anyon | Prefix]
            );
        false ->
            []
    end,
    PhiSchedules ++ AnyonSchedules.

stop_collectors(Ref, Collectors) ->
    maps:foreach(
        fun(_Port, PID) -> PID ! {stop, self()} end,
        Collectors
    ),
    lists:foreach(
        fun(Port) ->
            receive
                {collector_stopped, Ref, Port} -> ok
            end
        end,
        [north, east, west, south]
    ),
    flush_neighbor_casts(Ref).

flush_neighbor_casts(Ref) ->
    receive
        {neighbor_cast, Ref, _Port, _Message} ->
            flush_neighbor_casts(Ref)
    after 0 ->
        ok
    end.
