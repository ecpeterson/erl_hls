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

early_diffuse_and_future_halo_do_not_block_test_() ->
    {setup,
        fun() ->
            {ok, PID} = phi_halo_cell:start_link(),
            PID
        end,
        fun(PID) ->
            phi_halo_cell:stop(PID)
        end,
        fun(PID) ->
            [?_test(adverse_arrival_order(PID))]
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
    ok = phi_halo_cell:offer_north(PID, 0, [16, 32]),
    ok = phi_halo_cell:offer_north(PID, 1, [16, 32]),
    ok = phi_halo_cell:offer_east(PID, 0, [32, 48]),
    ok = phi_halo_cell:offer_east(PID, 1, [16, 32]),
    ok = phi_halo_cell:offer_west(PID, 0, [48, 64]),
    ok = phi_halo_cell:offer_south(PID, 0, [64, 80]),
    ok = phi_halo_cell:offer_west(PID, 1, [16, 32]),
    ok = phi_halo_cell:offer_south(PID, 1, [16, 32]),

    BeforeDiffuse = phi_halo_cell:runtime_info(PID),
    ?assertEqual(ready, maps:get(state_name, BeforeDiffuse)),
    ?assertEqual(4, maps:get(postponed, BeforeDiffuse)),
    ?assertEqual(
        4,
        maps:get(committed, maps:get(mailbox, BeforeDiffuse))
    ),
    ?assertEqual({1, [15, 14]}, phi_halo_cell:diffuse(PID, 0, 5)),

    BeforeSecondDiffuse = phi_halo_cell:runtime_info(PID),
    ?assertEqual(ready, maps:get(state_name, BeforeSecondDiffuse)),
    ?assertEqual(0, maps:get(postponed, BeforeSecondDiffuse)),
    ?assertEqual(
        0,
        maps:get(committed, maps:get(mailbox, BeforeSecondDiffuse))
    ),
    ?assertEqual({2, [16, 18]}, phi_halo_cell:diffuse(PID, 1, 1)).

adverse_arrival_order(PID) ->
    %% The future north halo is older than the blocked diffuse call.  Both must
    %% be skipped so that the younger current-epoch halos can complete phase 0.
    ok = phi_halo_cell:offer_north(PID, 0, [16, 32]),
    ok = phi_halo_cell:offer_north(PID, 1, [16, 32]),
    Diffuse0 = phi_halo_cell:send_diffuse(PID, 0, 5),
    ok = phi_halo_cell:offer_east(PID, 0, [32, 48]),
    ok = phi_halo_cell:offer_east(PID, 1, [16, 32]),
    ok = phi_halo_cell:offer_west(PID, 0, [48, 64]),
    ok = phi_halo_cell:offer_west(PID, 1, [16, 32]),
    ok = phi_halo_cell:offer_south(PID, 0, [64, 80]),
    ok = phi_halo_cell:offer_south(PID, 1, [16, 32]),

    ?assertEqual(
        {reply, {1, [15, 14]}},
        phi_halo_cell:receive_diffuse(Diffuse0, 1000)
    ),
    ReadyForSecondDiffuse = phi_halo_cell:runtime_info(PID),
    ?assertEqual(ready, maps:get(state_name, ReadyForSecondDiffuse)),
    ?assertEqual(0, maps:get(postponed, ReadyForSecondDiffuse)),
    ?assertEqual(
        0,
        maps:get(committed, maps:get(mailbox, ReadyForSecondDiffuse))
    ),
    ?assertEqual({2, [16, 18]}, phi_halo_cell:diffuse(PID, 1, 1)).
