-module(phi_halo_cell_tests).

-include_lib("eunit/include/eunit.hrl").

autonomous_two_phase_test() ->
    with_cell(fun two_phases/1).

mailbox_stages_future_halos_test() ->
    with_cell(fun staged_future_phase/1).

invalid_epoch_stops_cell_test() ->
    {ok, PID} = phi_halo_cell:start_link(),
    unlink(PID),
    ?assertEqual({ok, 0, [0, 0]}, phi_halo_cell:receive_halo(PID, 1000)),
    Monitor = monitor(process, PID),
    ok = phi_halo_cell:offer(PID, 2, [0, 0]),
    receive
        {'DOWN', Monitor, process, PID, {xls_statem_failure, _Message}} -> ok
    after 1000 ->
        error(cell_did_not_stop_on_invalid_epoch)
    end.

transpiles_uniform_bounded_machine_test() ->
    XLS = iolist_to_binary(
        xls_parse:to_xls("src/examples/phi_halo_cell.erl")
    ),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"enum Phase">>)),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"enum Directive">>)),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"struct MailboxSlot">>)),
    ?assertNotEqual(
        nomatch,
        binary:match(XLS, <<"recv_if_non_blocking">>)
    ),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"axis::ReservedRx">>)),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"admission_pending">>)),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"Tag::HALO">>)),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"invalid_conclusion">>)),
    ?assertNotEqual(nomatch, binary:match(XLS, <<" << 3">>)),
    ?assertNotEqual(nomatch, binary:match(XLS, <<" >> 4">>)),
    ?assertEqual(nomatch, binary:match(XLS, <<"DIFFUSE">>)),
    ?assertEqual(nomatch, binary:match(XLS, <<"HALO_N">>)).

with_cell(Test) ->
    {ok, PID} = phi_halo_cell:start_link(),
    try
        ?assertEqual(
            {ok, 0, [0, 0]},
            phi_halo_cell:receive_halo(PID, 1000)
        ),
        Test(PID)
    after
        case is_process_alive(PID) of
            true -> phi_halo_cell:stop(PID);
            false -> ok
        end
    end.

two_phases(PID) ->
    ok = phi_halo_cell:offer(PID, 0, [32, 48]),
    ok = phi_halo_cell:offer(PID, 0, [64, 80]),
    ok = phi_halo_cell:offer(PID, 0, [16, 32]),
    ok = phi_halo_cell:offer(PID, 0, [48, 64]),
    ?assertEqual({ok, 1, [15, 14]},
        phi_halo_cell:receive_halo(PID, 1000)),

    four_equal_halos(PID, 1, [16, 32]),
    ?assertEqual({ok, 2, [20, 18]},
        phi_halo_cell:receive_halo(PID, 1000)),

    Info = phi_halo_cell:runtime_info(PID),
    ?assertEqual(gather_even, maps:get(phase, Info)),
    ?assertEqual(0, maps:get(postponed, Info)),
    ?assertEqual(0, maps:get(committed, maps:get(mailbox, Info))).

staged_future_phase(PID) ->
    ok = phi_halo_cell:offer(PID, 0, [16, 32]),
    ok = phi_halo_cell:offer(PID, 1, [16, 32]),
    ok = phi_halo_cell:offer(PID, 0, [32, 48]),
    ok = phi_halo_cell:offer(PID, 1, [16, 32]),
    ok = phi_halo_cell:offer(PID, 0, [48, 64]),
    ok = phi_halo_cell:offer(PID, 1, [16, 32]),
    ok = phi_halo_cell:offer(PID, 1, [16, 32]),

    Before = phi_halo_cell:runtime_info(PID),
    ?assertEqual(gather_even, maps:get(phase, Before)),
    ?assertEqual(4, maps:get(postponed, Before)),
    ?assertEqual(4, maps:get(committed, maps:get(mailbox, Before))),

    ok = phi_halo_cell:offer(PID, 0, [64, 80]),
    ?assertEqual({ok, 1, [15, 14]},
        phi_halo_cell:receive_halo(PID, 1000)),
    ?assertEqual({ok, 2, [20, 18]},
        phi_halo_cell:receive_halo(PID, 1000)),

    After = phi_halo_cell:runtime_info(PID),
    ?assertEqual(gather_even, maps:get(phase, After)),
    ?assertEqual(0, maps:get(postponed, After)),
    ?assertEqual(0, maps:get(committed, maps:get(mailbox, After))).

four_equal_halos(PID, Epoch, Values) ->
    ok = phi_halo_cell:offer(PID, Epoch, Values),
    ok = phi_halo_cell:offer(PID, Epoch, Values),
    ok = phi_halo_cell:offer(PID, Epoch, Values),
    ok = phi_halo_cell:offer(PID, Epoch, Values).
