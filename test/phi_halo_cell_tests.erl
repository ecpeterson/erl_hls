-module(phi_halo_cell_tests).

-include_lib("eunit/include/eunit.hrl").

cpu_two_phase_test_() ->
    {setup,
        fun() ->
            {ok, PID} = phi_halo_cell:start_link(),
            PID
        end,
        fun(PID) ->
            phi_halo_cell:stop(PID)
        end,
        fun(PID) ->
            [?_test(two_valid_phases(PID))]
        end}.

cpu_u32_wraparound_matches_dslx_test_() ->
    {setup,
        fun() ->
            {ok, PID} = phi_halo_cell:start_link(),
            PID
        end,
        fun(PID) ->
            phi_halo_cell:stop(PID)
        end,
        fun(PID) ->
            [?_test(two_modular_phases(PID))]
        end}.

mailbox_stages_future_halos_test_() ->
    {setup,
        fun() ->
            {ok, PID} = phi_halo_cell:start_link(),
            PID
        end,
        fun(PID) ->
            phi_halo_cell:stop(PID)
        end,
        fun(PID) ->
            [?_test(staged_future_phase(PID))]
        end}.

transpiles_directional_casts_and_fixed_point_shifts_test() ->
    XLS = iolist_to_binary(
        xls_parse:to_xls("src/examples/phi_halo_cell.erl")
    ),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"Tag::HALO_N =>">>)),
    ?assertNotEqual(nomatch, binary:match(XLS, <<"halon_from_bits">>)),
    ?assertNotEqual(
        nomatch,
        binary:match(XLS, <<"values: raw[32:96] as u32[2]">>)
    ),
    ?assertNotEqual(nomatch, binary:match(XLS, <<" << 3">>)),
    ?assertNotEqual(nomatch, binary:match(XLS, <<" >> 4">>)),
    ?assertEqual(nomatch, binary:match(XLS, <<"Tag::HALON =>">>)).

two_valid_phases(PID) ->
    %% Directional arrival order is not part of the kernel: all four halos are
    %% identified by their record tag and joined by the ready mask.  These are
    %% deliberately small raw Q16.16 values so the integer arithmetic is clear.
    ok = phi_halo_cell:offer_east(PID, 0, [32, 48]),
    ok = phi_halo_cell:offer_south(PID, 0, [64, 80]),
    ok = phi_halo_cell:offer_north(PID, 0, [16, 32]),
    ok = phi_halo_cell:offer_west(PID, 0, [48, 64]),
    ?assertEqual({1, [15, 14]}, phi_halo_cell:diffuse(PID, 0, 5)),

    ok = phi_halo_cell:offer_west(PID, 1, [16, 32]),
    ok = phi_halo_cell:offer_north(PID, 1, [16, 32]),
    ok = phi_halo_cell:offer_south(PID, 1, [16, 32]),
    ok = phi_halo_cell:offer_east(PID, 1, [16, 32]),
    ?assertEqual({2, [16, 18]}, phi_halo_cell:diffuse(PID, 1, 1)).

two_modular_phases(PID) ->
    zero_halos(PID, 0),
    ?assertEqual(
        {1, [16#20000000, 0]},
        phi_halo_cell:diffuse(PID, 0, 16#20000000)
    ),
    zero_halos(PID, 1),
    ?assertEqual(
        {2, [16#04000000, 16#04000000]},
        phi_halo_cell:diffuse(PID, 1, 0)
    ).

zero_halos(PID, Epoch) ->
    ok = phi_halo_cell:offer_north(PID, Epoch, [0, 0]),
    ok = phi_halo_cell:offer_east(PID, Epoch, [0, 0]),
    ok = phi_halo_cell:offer_west(PID, Epoch, [0, 0]),
    ok = phi_halo_cell:offer_south(PID, Epoch, [0, 0]).

staged_future_phase(PID) ->
    Mailbox0 = commit_halos([
        {north, 0, [16, 32]},
        {north, 1, [16, 32]},
        {east, 0, [32, 48]},
        {east, 1, [16, 32]},
        {west, 0, [48, 64]},
        {south, 0, [64, 80]},
        {west, 1, [16, 32]},
        {south, 1, [16, 32]}
    ]),

    Mailbox1 = dispatch_phase(PID, 0, 4, Mailbox0),
    ?assertEqual(4, maps:get(committed, xls_mailbox:info(Mailbox1))),
    ?assertEqual({1, [15, 14]}, phi_halo_cell:diffuse(PID, 0, 5)),

    Mailbox2 = dispatch_phase(PID, 1, 4, Mailbox1),
    ?assertEqual(0, maps:get(committed, xls_mailbox:info(Mailbox2))),
    ?assertEqual({2, [16, 18]}, phi_halo_cell:diffuse(PID, 1, 1)).

commit_halos(Halos) ->
    lists:foldl(
        fun({Direction, Phase, Values}, Mailbox0) ->
            {ok, Reservation, Mailbox1} =
                xls_mailbox:reserve(0, Direction, Mailbox0),
            Message = #{
                direction => Direction,
                phase => Phase,
                values => Values
            },
            {ok, Mailbox2} = xls_mailbox:commit(
                Reservation, Message, Mailbox1
            ),
            Mailbox2
        end,
        xls_mailbox:new(length(Halos)),
        Halos
    ).

dispatch_phase(_PID, _Phase, 0, Mailbox) ->
    Mailbox;
dispatch_phase(PID, Phase, Count, Mailbox0) ->
    Matcher = fun
        (#{phase := MessagePhase}) when MessagePhase =:= Phase -> true;
        (_) -> false
    end,
    {ok, Selection, 1, Message} = xls_mailbox:select(
        [Matcher], Mailbox0
    ),
    {ok, Message, Mailbox1} = xls_mailbox:consume(Selection, Mailbox0),
    ok = offer_halo(PID, Message),
    dispatch_phase(PID, Phase, Count - 1, Mailbox1).

offer_halo(PID, #{direction := north, phase := Phase, values := Values}) ->
    phi_halo_cell:offer_north(PID, Phase, Values);
offer_halo(PID, #{direction := east, phase := Phase, values := Values}) ->
    phi_halo_cell:offer_east(PID, Phase, Values);
offer_halo(PID, #{direction := west, phase := Phase, values := Values}) ->
    phi_halo_cell:offer_west(PID, Phase, Values);
offer_halo(PID, #{direction := south, phase := Phase, values := Values}) ->
    phi_halo_cell:offer_south(PID, Phase, Values).
