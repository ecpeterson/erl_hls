-module(phi_halo_cell_tests).

-include_lib("eunit/include/eunit.hrl").

-define(NORTH_MASK, 1).
-define(EAST_MASK, 2).
-define(WEST_MASK, 4).
-define(SOUTH_MASK, 8).
-define(ALL_DIRECTIONS, 15).
-define(PRESENT_MASK, 1).
-define(QUIET_MASK, 2).
-define(PRNG_SEED, 16#6d2b79f5).
-define(PRNG_FIRST, 16#40aec71f).
-define(PRNG_SECOND, 16#91e00c19).

configuration_requires_nonzero_seed_test() ->
    {ok, configuring, Empty} = phi_halo_cell:init([]),
    ?assertEqual(
        {Empty, []},
        phi_halo_cell:handle_enter(configuring, configuring, Empty)
    ),
    ?assertEqual(
        {configuring, Empty, fail},
        phi_halo_cell:handle_cast({phi_config, 0}, configuring, Empty)
    ),
    ?assertError(badarg, phi_halo_cell:configure(self(), 0)),
    ?assertError(
        badarg,
        phi_halo_cell:configure(self(), 16#100000000)
    ).

repeated_diffusion_precedes_comparison_and_flipping_test() ->
    with_cell(fun repeated_diffusion_comparison_and_flipping/2).

early_messages_retry_at_protocol_boundaries_test() ->
    with_cell(fun staged_next_phase_messages/2).

full_next_epoch_batch_uses_reserved_progress_slot_test() ->
    with_cell(fun full_staged_diffusion_epoch/2).

full_comparison_batch_uses_reserved_progress_slot_test() ->
    with_cell(fun full_staged_comparison/2).

comparison_entry_labels_recipient_edges_test() ->
    with_cell(fun comparison_entry_labels_recipient_edges/2).

coin_gates_selected_anyon_output_test() ->
    with_cell(fun coin_gates_selected_anyon_output/2).

measurement_coordinate_reaches_correction_test() ->
    {ok, configuring, Empty} = phi_halo_cell:init([]),
    {measuring, Initial, consume} = phi_halo_cell:handle_cast(
        {phi_config, ?PRNG_SEED},
        configuring,
        Empty
    ),
    {gathering, Updated, consume} = phi_halo_cell:handle_cast(
        {phenom_anyon, 0, 1, 16#1234, 16#abcd},
        measuring,
        Initial
    ),
    ?assertMatch(
        {cell, 0, 0, [0, 0], [0, 0], 0,
            0, 0, 0, 0, 1, ?PRNG_SEED, 16#1234, 16#abcd, 0, 0},
        Updated
    ),
    {_AfterFlip, Actions} = phi_halo_cell:handle_enter(
        comparing,
        flipping,
        Updated
    ),
    ?assertEqual(
        expected_anyon_actions(0, none, 16#1234, 16#abcd),
        Actions
    ).

status_is_suppressed_initially_and_reports_post_move_occupancy_test() ->
    {CardinalCollectors, Ref} = start_collectors(),
    %% Sharing one collector makes the actor's status-before-request effect
    %% order observable through Erlang's per-sender signal ordering.
    StatusAndSyndrome = maps:get(status, CardinalCollectors),
    Collectors = CardinalCollectors#{syndrome => StatusAndSyndrome},
    {ok, PID} = phi_halo_cell:start_link(),
    try
        ok = phi_halo_cell:connect(PID, Collectors),
        ok = phi_halo_cell:configure(PID, ?PRNG_SEED),
        expect_port_cast(Ref, status, {phenom_request, 0}),
        assert_no_neighbor_cast(Ref),

        %% Quiet is carried independently of occupancy. One incoming move
        %% then creates the cell's post-step anyon.
        ok = hls_statem:cast(PID, {
            phenom_anyon, 0, ?QUIET_MASK, 16#1234, 16#abcd
        }),
        expect_neighbor_batch(Ref, {phi, 0, [0, 0]}),
        four_phis(PID, 0, [0, 0]),
        expect_neighbor_batch(Ref, {phi, 1, [0, 0]}),
        four_phis(PID, 1, [0, 0]),
        expect_comparison_batch(Ref, 0, 0),
        four_phi0s(PID, 0, 0),
        expect_anyon_batch(Ref, 0, none),
        offer_anyons(PID, 0, [true, false, false, false]),

        expect_port_cast(Ref, status, {
            phi_status,
            0,
            16#1234,
            16#abcd,
            ?PRESENT_MASK bor ?QUIET_MASK
        }),
        expect_port_cast(Ref, status, {phenom_request, 1})
    after
        stop_cell(PID),
        stop_collectors(Ref, CardinalCollectors)
    end.

measurement_gates_diffusion_and_toggles_anyon_test() ->
    {CardinalCollectors, Ref} = start_collectors(),
    Parent = self(),
    Syndrome = spawn_link(fun() ->
        collector_loop(Parent, Ref, syndrome)
    end),
    Collectors = CardinalCollectors#{syndrome => Syndrome},
    {ok, PID} = phi_halo_cell:start_link(),
    try
        ok = phi_halo_cell:connect(PID, Collectors),
        assert_no_neighbor_cast(Ref),
        ok = phi_halo_cell:configure(PID, ?PRNG_SEED),
        expect_port_cast(Ref, syndrome, {phenom_request, 0}),

        four_phis(PID, 0, [0, 0]),
        Waiting = phi_halo_cell:runtime_info(PID),
        ?assertEqual(measuring, maps:get(phase, Waiting)),
        ?assertEqual(4, maps:get(postponed, Waiting)),
        ?assertEqual(4, maps:get(committed, maps:get(mailbox, Waiting))),
        ?assertMatch(
            {cell, 0, 0, [0, 0], [0, 0], 0,
                0, 0, 0, 0, 0, ?PRNG_SEED, 0, 0, 0, 0},
            maps:get(data, Waiting)
        ),
        assert_no_neighbor_cast(Ref),

        ok = phi_halo_cell:offer_measurement(PID, 0, true),
        expect_neighbor_sequences(Ref, [
            {phi, 0, [0, 0]},
            {phi, 1, [65536, 0]}
        ]),
        Running = phi_halo_cell:runtime_info(PID),
        ?assertEqual(gathering, maps:get(phase, Running)),
        ?assertEqual(0, maps:get(postponed, Running)),
        ?assertEqual(0, maps:get(committed, maps:get(mailbox, Running))),
        ?assertMatch(
            {cell, 0, 1, [65536, 0], [0, 0], 0,
                0, 0, 0, 0, 1, ?PRNG_SEED, 0, 0, 0, 0},
            maps:get(data, Running)
        )
    after
        stop_cell(PID),
        stop_collectors(Ref, Collectors)
    end.

comparison_source_orders_test_() ->
    Unique = comparison_messages([
        {north, 14},
        {east, 18},
        {west, 17},
        {south, 16}
    ]),
    Tied = comparison_messages([
        {north, 14},
        {east, 18},
        {west, 18},
        {south, 16}
    ]),
    Negative = comparison_messages([
        {north, -4},
        {east, -1},
        {west, -3},
        {south, -2}
    ]),
    NegativeTied = comparison_messages([
        {north, -(1 bsl 31)},
        {east, -1},
        {west, -1},
        {south, -2}
    ]),
    comparison_order_tests(unique, Unique, 18, ?EAST_MASK) ++
        comparison_order_tests(tied, Tied, 18, 0) ++
        comparison_order_tests(negative, Negative, -1, ?EAST_MASK) ++
        comparison_order_tests(negative_tied, NegativeTied, -1, 0).

duplicate_comparison_source_stops_cell_test() ->
    {PID, Collectors, Ref} = start_cell(),
    unlink(PID),
    try
        enter_comparing(PID, Ref, [0, 0], [0, 0]),
        ok = phi_halo_cell:offer_phi0(PID, 0, north, 12),
        Monitor = monitor(process, PID),
        ok = phi_halo_cell:offer_phi0(PID, 0, north, 99),
        receive
            {'DOWN', Monitor, process, PID,
                    {hls_statem_failure, {phi0, 0, ?NORTH_MASK, 99}}} ->
                ok
        after 1000 ->
            error(cell_did_not_stop_on_duplicate_comparison_source)
        end
    after
        stop_cell(PID),
        stop_collectors(Ref, Collectors)
    end.

invalid_comparison_sources_fail_test_() ->
    [
        {iolist_to_binary(io_lib:format("source mask ~p", [Source])), fun() ->
            Cell = comparison_cell(),
            ?assertEqual(
                {comparing, Cell, fail},
                phi_halo_cell:handle_cast(
                    {phi0, 0, Source, 12},
                    comparing,
                    Cell
                )
            )
        end}
        || Source <- [0, 3, 16]
    ].

directional_coin_moves_test_() ->
    [
        {atom_to_binary(Direction), fun() ->
            DirectionMask = direction_mask(Direction),
            Cell = flipping_cell(1, DirectionMask, ?PRNG_FIRST),
            {Updated, Actions} = phi_halo_cell:handle_enter(
                comparing,
                flipping,
                Cell
            ),
            ?assertEqual(
                {cell, 0, 2, [15, 15], [0, 0], 0,
                    ?ALL_DIRECTIONS, 18, DirectionMask, 0, 0,
                    ?PRNG_SECOND, 0, 0, 0, 0},
                Updated
            ),
            ?assertEqual(
                expected_anyon_actions(0, Direction, 0, 0),
                Actions
            )
        end}
        || Direction <- [north, east, west, south]
    ].

coin_advances_when_no_move_is_eligible_test_() ->
    Cases = [
        {tails, 1, ?EAST_MASK, ?PRNG_SEED, ?PRNG_FIRST, 1},
        {no_anyon, 0, ?EAST_MASK, ?PRNG_FIRST, ?PRNG_SECOND, 0},
        {tied_maximum, 1, 0, ?PRNG_FIRST, ?PRNG_SECOND, 1}
    ],
    [
        {atom_to_binary(Name), fun() ->
            Cell = flipping_cell(Anyon, Direction, Random0),
            {Updated, Actions} = phi_halo_cell:handle_enter(
                comparing,
                flipping,
                Cell
            ),
            ?assertMatch(
                {cell, 0, 2, [15, 15], [0, 0], 0,
                    ?ALL_DIRECTIONS, 18, Direction, 0,
                    ExpectedAnyon, Random1, 0, 0, 0, 0},
                Updated
            ),
            ?assertEqual(expected_anyon_actions(0, none, 0, 0), Actions)
        end}
        || {Name, Anyon, Direction, Random0, Random1, ExpectedAnyon} <- Cases
    ].

local_departure_and_arrivals_combine_by_parity_test() ->
    Cell = flipping_cell(1, ?EAST_MASK, ?PRNG_FIRST),
    {Departed, _Actions} = phi_halo_cell:handle_enter(
        comparing,
        flipping,
        Cell
    ),
    {measuring, Advanced, consume} = apply_anyons(
        [true, false, true, true],
        Departed
    ),
    ?assertMatch(
        {cell, 1, 0, [15, 15], [0, 0], 0,
            ?ALL_DIRECTIONS, 18, ?EAST_MASK, 0, 1, ?PRNG_SECOND, 0, 0,
            0, 1},
        Advanced
    ).

configuration_delays_initial_entry_test() ->
    {CardinalCollectors, Ref} = start_collectors(),
    {ok, PID} = phi_halo_cell:start_link(),
    Collectors = add_zero_measurement_source(
        PID,
        CardinalCollectors,
        Ref
    ),
    try
        Info = phi_halo_cell:runtime_info(PID),
        ?assertNot(maps:get(connected, Info)),
        assert_no_neighbor_cast(Ref),
        ok = phi_halo_cell:connect(PID, Collectors),
        assert_no_neighbor_cast(Ref),
        ok = phi_halo_cell:configure(PID, ?PRNG_SEED),
        expect_neighbor_batch(Ref, {phi, 0, [0, 0]})
    after
        case is_process_alive(PID) of
            true -> phi_halo_cell:stop(PID);
            false -> ok
        end,
        stop_collectors(Ref, Collectors)
    end.

configuration_may_precede_connection_test() ->
    {CardinalCollectors, Ref} = start_collectors(),
    {ok, PID} = phi_halo_cell:start_link(),
    Collectors = add_zero_measurement_source(
        PID,
        CardinalCollectors,
        Ref
    ),
    try
        ok = phi_halo_cell:configure(PID, ?PRNG_SEED),
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
    {CardinalCollectors, Ref} = start_collectors(),
    {ok, PID} = phi_halo_cell:start_link(),
    Collectors = add_zero_measurement_source(
        PID,
        CardinalCollectors,
        Ref
    ),
    try
        four_phis(PID, 0, [16, 32]),
        Before = phi_halo_cell:runtime_info(PID),
        ?assertEqual(disconnected, maps:get(lifecycle, Before)),
        ?assertEqual(4, maps:get(committed, maps:get(mailbox, Before))),
        ?assertMatch(
            {cell, 0, 0, [0, 0], [0, 0], 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
            maps:get(data, Before)),
        assert_no_neighbor_cast(Ref),

        ok = phi_halo_cell:connect(PID, Collectors),
        assert_no_neighbor_cast(Ref),
        ok = phi_halo_cell:configure(PID, ?PRNG_SEED),
        expect_neighbor_sequences(Ref, [
            {phi, 0, [0, 0]},
            {phi, 1, [3, 6]}
        ]),

        After = phi_halo_cell:runtime_info(PID),
        ?assertEqual(connected, maps:get(lifecycle, After)),
        ?assertEqual(gathering, maps:get(phase, After)),
        ?assertEqual(0, maps:get(committed, maps:get(mailbox, After))),
        ?assertMatch(
            {cell, 0, 1, [3, 6], [0, 0], 0,
                0, 0, 0, 0, 0, ?PRNG_SEED, 0, 0, 0, 0},
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
    MeasurementSources = [
        spawn_link(fun() -> zero_measurement_loop(PID) end)
        || PID <- Cells
    ],
    [NorthWest, NorthEast, SouthWest, SouthEast] = Cells,
    [NorthWestMeasurement, NorthEastMeasurement,
        SouthWestMeasurement, SouthEastMeasurement] = MeasurementSources,
    try
        %% In a 2x2 periodic mesh, north and south reach the same cell, as do
        %% east and west; the four named ports still represent four edges.
        ok = phi_halo_cell:connect(
            NorthWest,
            torus_neighbors(
                NorthEast,
                SouthWest,
                NorthWestMeasurement
            )
        ),
        ok = phi_halo_cell:connect(
            NorthEast,
            torus_neighbors(
                NorthWest,
                SouthEast,
                NorthEastMeasurement
            )
        ),
        ok = phi_halo_cell:connect(
            SouthWest,
            torus_neighbors(
                SouthEast,
                NorthWest,
                SouthWestMeasurement
            )
        ),
        ok = phi_halo_cell:connect(
            SouthEast,
            torus_neighbors(
                SouthWest,
                NorthEast,
                SouthEastMeasurement
            )
        ),
        lists:foreach(
            fun({PID, Seed}) -> ok = phi_halo_cell:configure(PID, Seed) end,
            lists:zip(Cells, lists:seq(1, length(Cells)))
        ),
        lists:foreach(fun(PID) -> await_step(PID, 2) end, Cells)
    after
        lists:foreach(fun stop_cell/1, Cells),
        lists:foreach(fun(PID) -> PID ! stop end, MeasurementSources)
    end.

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
        {'DOWN', Monitor, process, PID, {hls_statem_failure, _Message}} -> ok
    after 1000 ->
        error(cell_did_not_stop_on_invalid_diffusion_epoch)
    end,
    stop_collectors(Ref, Collectors).

boolean_anyon_api_encodes_move_test() ->
    with_cell(fun(PID, Ref) ->
        enter_comparing(PID, Ref, [0, 0], [0, 0]),
        four_phi0s(PID, 0, 0),
        expect_anyon_batch(Ref, 0, none),
        ok = phi_halo_cell:offer_anyon(PID, 0, true),
        ?assertMatch(
            {cell, 0, 2, [0, 0], [0, 0], 0,
                ?ALL_DIRECTIONS, 0, 0, 1, 1, ?PRNG_FIRST, 0, 0, 0, 0},
            maps:get(data, phi_halo_cell:runtime_info(PID))
        )
    end).

invalid_anyon_word_stops_cell_in_flipping_test() ->
    {PID, Collectors, Ref} = start_cell(),
    unlink(PID),
    try
        enter_comparing(PID, Ref, [0, 0], [0, 0]),
        four_phi0s(PID, 0, 0),
        expect_anyon_batch(Ref, 0, none),
        ?assertEqual(
            flipping,
            maps:get(phase, phi_halo_cell:runtime_info(PID))
        ),

        Monitor = monitor(process, PID),
        ok = hls_statem:cast(PID, {anyon_move, 0, 2}),
        receive
            {'DOWN', Monitor, process, PID,
                    {hls_statem_failure, _Message}} ->
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
        "src/examples/phi_decoder/phi_halo_cell.erl.x"
    ),
    Generated = iolist_to_binary(
        xls_parse:to_xls("src/examples/phi_decoder/phi_halo_cell.erl")
    ),
    ?assertEqual(Expected, Generated),
    ?assertNotEqual(
        nomatch,
        binary:match(Generated, <<"pub proc Service">>)
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(Generated, <<"PHI_STATUS = u8:17">>)
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(Generated, <<"STATUS = u8:6">>)
    ),
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
        5,
        length(binary:matches(Dispatch, <<"Phase::GATHERING =>">>))
    ),
    ?assertEqual(
        4,
        length(binary:matches(Dispatch, <<"Phase::FLIPPING =>">>))
    ),
    ?assertEqual(
        5,
        length(binary:matches(Dispatch, <<"Phase::COMPARING =>">>))
    ),
    ?assertEqual(
        5,
        length(binary:matches(Dispatch, <<"Phase::MEASURING =>">>))
    ),
    ?assertEqual(
        5,
        length(binary:matches(Dispatch, <<"Phase::CONFIGURING =>">>))
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
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(
            Generated,
            <<"Tag::PHI0 as u8) && frame.header.payload_words == u8:3">>
        )
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(
            Generated,
            <<"Tag::PHENOM_ANYON as u8) && "
              "frame.header.payload_words == u8:3">>
        )
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(
            Generated,
            <<"Tag::PHI_CORRECTION as u8) && "
              "frame.header.payload_words == u8:3">>
        )
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(
            Generated,
            <<"Tag::PHI_CONFIG as u8) && "
              "frame.header.payload_words == u8:1">>
        )
    ).

message_wire_abi_test() ->
    Phi = {phi, 16#01020304, [16#11121314, 16#21222324]},
    Move = {anyon_move, 16#31323334, 1},
    Phi0 = {phi0, 16#41424344, ?SOUTH_MASK, 16#51525354},
    Measurement = {phenom_anyon, 16#61626364, 1, 16#7172, 16#8182},
    Correction = {phi_correction, 16#91929394, 16#a1a2, 16#b1b2,
        ?WEST_MASK},
    Config = {phi_config, 16#c1c2c3c4},
    Status = {phi_status, 16#d1d2d3d4, 16#e1e2, 16#f1f2,
        ?PRESENT_MASK bor ?QUIET_MASK},
    ?assertEqual(3, phi_halo_cell:pack_tag(phi)),
    ?assertEqual(4, phi_halo_cell:pack_tag(anyon_move)),
    ?assertEqual(5, phi_halo_cell:pack_tag(phi0)),
    ?assertEqual(phi, phi_halo_cell:unpack_tag(3)),
    ?assertEqual(anyon_move, phi_halo_cell:unpack_tag(4)),
    ?assertEqual(phi0, phi_halo_cell:unpack_tag(5)),
    ?assertEqual(6, phi_halo_cell:pack_tag(phenom_config)),
    ?assertEqual(7, phi_halo_cell:pack_tag(phenom_request)),
    ?assertEqual(8, phi_halo_cell:pack_tag(phenom_query)),
    ?assertEqual(9, phi_halo_cell:pack_tag(phenom_data)),
    ?assertEqual(10, phi_halo_cell:pack_tag(phenom_anyon)),
    ?assertEqual(11, phi_halo_cell:pack_tag(phi_correction)),
    ?assertEqual(12, phi_halo_cell:pack_tag(phi_config)),
    ?assertEqual(17, phi_halo_cell:pack_tag(phi_status)),
    ?assertEqual(phenom_config, phi_halo_cell:unpack_tag(6)),
    ?assertEqual(phenom_request, phi_halo_cell:unpack_tag(7)),
    ?assertEqual(phenom_query, phi_halo_cell:unpack_tag(8)),
    ?assertEqual(phenom_data, phi_halo_cell:unpack_tag(9)),
    ?assertEqual(phenom_anyon, phi_halo_cell:unpack_tag(10)),
    ?assertEqual(phi_correction, phi_halo_cell:unpack_tag(11)),
    ?assertEqual(phi_config, phi_halo_cell:unpack_tag(12)),
    ?assertEqual(phi_status, phi_halo_cell:unpack_tag(17)),
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
    ),
    PackedPhi0 = phi_halo_cell:pack(Phi0),
    ?assertEqual(
        <<
            16#41424344:32/unsigned-little-integer,
            ?SOUTH_MASK:32/unsigned-little-integer,
            16#51525354:32/unsigned-little-integer
        >>,
        PackedPhi0
    ),
    ?assertEqual(
        {Phi0, <<>>},
        phi_halo_cell:unpack(phi0, PackedPhi0)
    ),
    PackedMeasurement = phi_halo_cell:pack(Measurement),
    ?assertEqual(
        <<
            16#61626364:32/unsigned-little-integer,
            1:32/unsigned-little-integer,
            16#7172:16/unsigned-little-integer,
            16#8182:16/unsigned-little-integer
        >>,
        PackedMeasurement
    ),
    ?assertEqual(
        {Measurement, <<>>},
        phi_halo_cell:unpack(phenom_anyon, PackedMeasurement)
    ),
    PackedCorrection = phi_halo_cell:pack(Correction),
    ?assertEqual(
        <<
            16#91929394:32/unsigned-little-integer,
            16#a1a2:16/unsigned-little-integer,
            16#b1b2:16/unsigned-little-integer,
            ?WEST_MASK:32/unsigned-little-integer
        >>,
        PackedCorrection
    ),
    ?assertEqual(
        {Correction, <<>>},
        phi_halo_cell:unpack(phi_correction, PackedCorrection)
    ),
    PackedConfig = phi_halo_cell:pack(Config),
    ?assertEqual(
        <<16#c1c2c3c4:32/unsigned-little-integer>>,
        PackedConfig
    ),
    ?assertEqual(
        {Config, <<>>},
        phi_halo_cell:unpack(phi_config, PackedConfig)
    ),
    PackedStatus = phi_halo_cell:pack(Status),
    ?assertEqual(
        <<
            16#d1d2d3d4:32/unsigned-little-integer,
            16#e1e2:16/unsigned-little-integer,
            16#f1f2:16/unsigned-little-integer,
            (?PRESENT_MASK bor ?QUIET_MASK):32/unsigned-little-integer
        >>,
        PackedStatus
    ),
    ?assertEqual(
        {Status, <<>>},
        phi_halo_cell:unpack(phi_status, PackedStatus)
    ).

two_layer_relaxation_coefficients_test() ->
    Initial = {cell, 0, 0, [40, 20], [0, 0], 0,
        0, 0, 0, 0, 0, ?PRNG_SEED, 0, 0, 0, 0},
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
        {cell, 0, 1, [33, 19], [0, 0], 0,
            0, 0, 0, 0, 0, ?PRNG_SEED, 0, 0, 0, 0},
        RoundOne
    ),

    Message1 = {phi, 1, [8, 12]},
    {gathering, Fifth, consume} =
        phi_halo_cell:handle_cast(Message1, gathering, RoundOne),
    {gathering, Sixth, consume} =
        phi_halo_cell:handle_cast(Message1, gathering, Fifth),
    {gathering, Seventh, consume} =
        phi_halo_cell:handle_cast(Message1, gathering, Sixth),
    {comparing, Compared, consume} =
        phi_halo_cell:handle_cast(Message1, gathering, Seventh),
    ?assertEqual(
        {cell, 0, 2, [28, 18], [0, 0], 0,
            0, 0, 0, 0, 0, ?PRNG_SEED, 0, 0, 0, 0},
        Compared
    ),

    %% Comparison observes the final layer-zero value; it does not perform a
    %% third relaxation update.
    {flipping, Final, consume} = apply_comparisons(
        comparison_messages([
            {north, 11},
            {east, 14},
            {west, 13},
            {south, 10}
        ]),
        Compared
    ),
    ?assertMatch(
        {cell, 0, 2, [28, 18], [0, 0], 0,
            ?ALL_DIRECTIONS, 14, ?EAST_MASK, 0, 0, ?PRNG_SEED, 0, 0,
            0, 0},
        Final
    ).

repeated_diffusion_comparison_and_flipping(PID, Ref) ->
    expect_neighbor_batch(Ref, {phi, 0, [0, 0]}),

    ok = phi_halo_cell:offer_phi(PID, 0, [32, 48]),
    ok = phi_halo_cell:offer_phi(PID, 0, [64, 80]),
    ok = phi_halo_cell:offer_phi(PID, 0, [16, 32]),
    ok = phi_halo_cell:offer_phi(PID, 0, [48, 64]),
    expect_neighbor_batch(Ref, {phi, 1, [7, 11]}),
    AfterRoundOne = phi_halo_cell:runtime_info(PID),
    ?assertEqual(gathering, maps:get(phase, AfterRoundOne)),

    four_phis(PID, 1, [16, 32]),
    expect_comparison_batch(Ref, 0, 9),
    AfterDiffusion = phi_halo_cell:runtime_info(PID),
    ?assertEqual(comparing, maps:get(phase, AfterDiffusion)),
    ?assertMatch(
        {cell, 0, 2, [9, 15], [0, 0], 0,
            0, 0, 0, 0, 0, ?PRNG_SEED, 0, 0, 0, 0},
        maps:get(data, AfterDiffusion)
    ),

    offer_comparisons(PID, [
        {north, 14},
        {east, 18},
        {west, 17},
        {south, 16}
    ]),
    expect_anyon_batch(Ref, 0, none),
    AfterComparison = phi_halo_cell:runtime_info(PID),
    ?assertEqual(flipping, maps:get(phase, AfterComparison)),
    ?assertMatch(
        {cell, 0, 2, [9, 15], [0, 0], 0,
            ?ALL_DIRECTIONS, 18, ?EAST_MASK, 0, 0, ?PRNG_FIRST, 0, 0,
            0, 0},
        maps:get(data, AfterComparison)
    ),

    four_anyons(PID, 0, false),
    expect_status_and_neighbor_batch(
        Ref,
        {phi_status, 0, 0, 0, 0},
        {phi, 2, [9, 15]}
    ),

    Info = phi_halo_cell:runtime_info(PID),
    ?assertEqual(gathering, maps:get(phase, Info)),
    ?assertEqual(0, maps:get(postponed, Info)),
    ?assertEqual(0, maps:get(committed, maps:get(mailbox, Info))),
    ?assertMatch(
        {cell, 1, 0, [9, 15], [0, 0], 0,
            ?ALL_DIRECTIONS, 18, ?EAST_MASK, 0, 0, ?PRNG_FIRST, 0, 0,
            0, 1},
        maps:get(data, Info)
    ),
    assert_no_neighbor_cast(Ref).

coin_gates_selected_anyon_output(PID, Ref) ->
    enter_comparing(PID, Ref, [0, 0], [0, 0]),
    offer_comparisons(PID, [
        {north, 14},
        {east, 18},
        {west, 17},
        {south, 16}
    ]),
    %% The first draw is tails. One incoming move creates a local anyon for
    %% the following decoder step without conflating arrival with departure.
    expect_anyon_batch(Ref, 0, none),
    offer_anyons(PID, 0, [true, false, false, false]),
    expect_status_and_neighbor_batch(
        Ref,
        {phi_status, 0, 0, 0, ?PRESENT_MASK},
        {phi, 2, [0, 0]}
    ),

    four_phis(PID, 2, [0, 0]),
    expect_neighbor_batch(Ref, {phi, 3, [65536, 0]}),
    four_phis(PID, 3, [0, 0]),
    expect_comparison_batch(Ref, 1, 114688),

    %% The second draw is heads. The protocol chooses the unique adjacent
    %% maximum; it does not require that maximum to exceed the local field.
    offer_comparisons(PID, 1, [
        {north, 10},
        {east, 13},
        {west, 12},
        {south, 11}
    ]),
    expect_anyon_batch(Ref, 1, east),
    Flipping = phi_halo_cell:runtime_info(PID),
    ?assertEqual(flipping, maps:get(phase, Flipping)),
    ?assertMatch(
        {cell, 1, 2, [114688, 3277], [0, 0], 0,
            ?ALL_DIRECTIONS, 13, ?EAST_MASK, 0, 0, ?PRNG_SECOND, 0, 0,
            0, 1},
        maps:get(data, Flipping)
    ),

    four_anyons(PID, 1, false),
    expect_status_and_neighbor_batch(
        Ref,
        {phi_status, 1, 0, 0, 0},
        {phi, 4, [114688, 3277]}
    ),
    ?assertMatch(
        {cell, 2, 0, [114688, 3277], [0, 0], 0,
            ?ALL_DIRECTIONS, 13, ?EAST_MASK, 0, 0, ?PRNG_SECOND, 0, 0,
            0, 1},
        maps:get(data, phi_halo_cell:runtime_info(PID))
    ).

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
    expect_neighbor_batch(Ref, {phi, 1, [7, 11]}),
    AfterRepeat = phi_halo_cell:runtime_info(PID),
    ?assertEqual(gathering, maps:get(phase, AfterRepeat)),
    ?assertEqual(0, maps:get(postponed, AfterRepeat)),
    ?assertMatch(
        {cell, 0, 1, [7, 11], [8, 12], 1,
            0, 0, 0, 0, 0, ?PRNG_SEED, 0, 0, 0, 0},
        maps:get(data, AfterRepeat)
    ),

    %% An early flipping message crosses two boundaries: gathering releases
    %% it into comparing, which postpones it again until flipping. The early
    %% comparison message is consumed immediately after comparison entry.
    ok = phi_halo_cell:offer_anyon(PID, 0, false),
    ok = phi_halo_cell:offer_phi0(PID, 0, north, 14),
    ok = phi_halo_cell:offer_phi(PID, 1, [8, 12]),
    ok = phi_halo_cell:offer_phi(PID, 1, [8, 12]),
    BeforeComparison = phi_halo_cell:runtime_info(PID),
    ?assertEqual(gathering, maps:get(phase, BeforeComparison)),
    ?assertEqual(2, maps:get(postponed, BeforeComparison)),

    ok = phi_halo_cell:offer_phi(PID, 1, [8, 12]),
    expect_comparison_batch(Ref, 0, 8),
    AfterEntry = phi_halo_cell:runtime_info(PID),
    ?assertEqual(comparing, maps:get(phase, AfterEntry)),
    ?assertEqual(1, maps:get(postponed, AfterEntry)),
    ?assertMatch(
        {cell, 0, 2, [8, 11], [0, 0], 0,
            ?NORTH_MASK, 14, ?NORTH_MASK, 0, 0, ?PRNG_SEED, 0, 0,
            0, 0},
        maps:get(data, AfterEntry)
    ),

    offer_comparisons(PID, [
        {east, 18},
        {west, 17},
        {south, 16}
    ]),
    expect_anyon_batch(Ref, 0, none),
    AfterFlip = phi_halo_cell:runtime_info(PID),
    ?assertEqual(flipping, maps:get(phase, AfterFlip)),
    ?assertEqual(0, maps:get(postponed, AfterFlip)),
    ?assertMatch(
        {cell, 0, 2, [8, 11], [0, 0], 0,
            ?ALL_DIRECTIONS, 18, ?EAST_MASK, 1, 0, ?PRNG_FIRST, 0, 0,
            0, 0},
        maps:get(data, AfterFlip)
    ),

    %% The symmetric case occurs while this cell waits for anyon updates. The
    %% next step starts at diffusion epoch 2, not decoder step 1 on the wire.
    ok = phi_halo_cell:offer_phi(PID, 2, [8, 12]),
    ok = phi_halo_cell:offer_anyon(PID, 0, false),
    ok = phi_halo_cell:offer_anyon(PID, 0, false),
    BeforeGather = phi_halo_cell:runtime_info(PID),
    ?assertEqual(flipping, maps:get(phase, BeforeGather)),
    ?assertEqual(1, maps:get(postponed, BeforeGather)),

    ok = phi_halo_cell:offer_anyon(PID, 0, false),
    expect_status_and_neighbor_batch(
        Ref,
        {phi_status, 0, 0, 0, 0},
        {phi, 2, [8, 11]}
    ),
    AfterGather = phi_halo_cell:runtime_info(PID),
    ?assertEqual(gathering, maps:get(phase, AfterGather)),
    ?assertEqual(0, maps:get(postponed, AfterGather)),
    ?assertMatch(
        {cell, 1, 0, [8, 11], [8, 12], 1,
            ?ALL_DIRECTIONS, 18, ?EAST_MASK, 0, 0, ?PRNG_FIRST, 0, 0,
            0, 1},
        maps:get(data, AfterGather)
    ).

full_staged_diffusion_epoch(PID, Ref) ->
    expect_neighbor_batch(Ref, {phi, 0, [0, 0]}),

    %% Four next-epoch messages can occupy the queue while the fifth slot
    %% remains available to make progress on the current epoch.
    four_phis(PID, 1, [8, 12]),
    Staged = phi_halo_cell:runtime_info(PID),
    ?assertEqual(4, maps:get(postponed, Staged)),
    ?assertEqual(4, maps:get(committed, maps:get(mailbox, Staged))),

    four_phis(PID, 0, [0, 0]),
    expect_comparison_sequences(Ref, {phi, 1, [0, 0]}, 0, 1),
    Complete = phi_halo_cell:runtime_info(PID),
    ?assertEqual(comparing, maps:get(phase, Complete)),
    ?assertEqual(0, maps:get(postponed, Complete)),
    ?assertEqual(0, maps:get(committed, maps:get(mailbox, Complete))),
    ?assertMatch(
        {cell, 0, 2, [1, 2], [0, 0], 0,
            0, 0, 0, 0, 0, ?PRNG_SEED, 0, 0, 0, 0},
        maps:get(data, Complete)
    ).

full_staged_comparison(PID, Ref) ->
    expect_neighbor_batch(Ref, {phi, 0, [0, 0]}),
    four_phis(PID, 0, [0, 0]),
    expect_neighbor_batch(Ref, {phi, 1, [0, 0]}),

    %% A complete comparison batch can wait in four slots while each final
    %% diffusion message uses and releases the fifth progress slot.
    offer_comparisons(PID, [
        {north, 1},
        {east, 2},
        {west, 3},
        {south, 4}
    ]),
    Staged = phi_halo_cell:runtime_info(PID),
    ?assertEqual(4, maps:get(postponed, Staged)),
    ?assertEqual(4, maps:get(committed, maps:get(mailbox, Staged))),

    four_phis(PID, 1, [0, 0]),
    expect_comparison_and_anyon_sequences(Ref, 0, 0),
    Complete = phi_halo_cell:runtime_info(PID),
    ?assertEqual(flipping, maps:get(phase, Complete)),
    ?assertEqual(0, maps:get(postponed, Complete)),
    ?assertEqual(0, maps:get(committed, maps:get(mailbox, Complete))),
    ?assertMatch(
        {cell, 0, 2, [0, 0], [0, 0], 0,
            ?ALL_DIRECTIONS, 4, ?SOUTH_MASK, 0, 0, ?PRNG_FIRST, 0, 0,
            0, 0},
        maps:get(data, Complete)
    ).

comparison_entry_labels_recipient_edges(PID, Ref) ->
    enter_comparing(PID, Ref, [0, 0], [0, 0]),
    ?assertEqual(
        comparing,
        maps:get(phase, phi_halo_cell:runtime_info(PID))
    ),
    assert_no_neighbor_cast(Ref).

comparison_order_tests(Kind, Messages, Best, BestDirection) ->
    [
        {iolist_to_binary(io_lib:format(
            "~p comparison order ~p",
            [Kind, [Source || {phi0, 0, Source, _Value} <- Ordered]]
        )), fun() ->
            {flipping, Final, consume} = apply_comparisons(
                Ordered,
                comparison_cell()
            ),
            ?assertMatch(
                {cell, 0, 2, [15, 15], [0, 0], 0,
                    ?ALL_DIRECTIONS, Best, BestDirection, 0, 0, ?PRNG_SEED,
                    0, 0, 0, 0},
                Final
            )
        end}
        || Ordered <- permutations(Messages)
    ].

comparison_cell() ->
    {cell, 0, 2, [15, 15], [0, 0], 0,
        0, 0, 0, 0, 0, ?PRNG_SEED, 0, 0, 0, 0}.

flipping_cell(Anyon, Direction, RandomState) ->
    {cell, 0, 2, [15, 15], [0, 0], 0,
        ?ALL_DIRECTIONS, 18, Direction, 0, Anyon, RandomState, 0, 0,
        0, 0}.

comparison_messages(SourcesAndValues) ->
    [
        {phi0, 0, direction_mask(Source), Value}
        || {Source, Value} <- SourcesAndValues
    ].

apply_comparisons([Message], Cell) ->
    phi_halo_cell:handle_cast(Message, comparing, Cell);
apply_comparisons([Message | Rest], Cell) ->
    {comparing, Next, consume} =
        phi_halo_cell:handle_cast(Message, comparing, Cell),
    apply_comparisons(Rest, Next).

apply_anyons([Present], Cell) ->
    phi_halo_cell:handle_cast(
        {anyon_move, 0, present_word(Present)},
        flipping,
        Cell
    );
apply_anyons([Present | Rest], Cell) ->
    {flipping, Next, consume} = phi_halo_cell:handle_cast(
        {anyon_move, 0, present_word(Present)},
        flipping,
        Cell
    ),
    apply_anyons(Rest, Next).

permutations([]) ->
    [[]];
permutations(Items) ->
    [
        [Item | Rest]
        || Item <- Items,
           Rest <- permutations(lists:delete(Item, Items))
    ].

enter_comparing(PID, Ref, RoundZeroValues, RoundOneValues) ->
    expect_neighbor_batch(Ref, {phi, 0, [0, 0]}),
    RoundOnePhi = relax([0, 0], RoundZeroValues),
    four_phis(PID, 0, RoundZeroValues),
    expect_neighbor_batch(Ref, {phi, 1, RoundOnePhi}),
    FinalPhi = relax(RoundOnePhi, RoundOneValues),
    four_phis(PID, 1, RoundOneValues),
    expect_comparison_batch(Ref, 0, hd(FinalPhi)).

relax([P0, P1], [Value0, Value1]) ->
    Sum0 = Value0 * 4,
    Sum1 = Value1 * 4,
    New0 = round_nearest(18 * P0 + 2 * P1 + Sum0, 24),
    New1 = round_nearest(P0 + 15 * P1 + Sum1, 20),
    [New0, New1].

round_nearest(Numerator, Denominator) when Numerator >= 0 ->
    (Numerator + Denominator div 2) div Denominator;
round_nearest(Numerator, Denominator) ->
    -round_nearest(-Numerator, Denominator).

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
    {CardinalCollectors, Ref} = start_collectors(),
    MeasurementSource = spawn_link(fun() ->
        unbound_zero_measurement_loop(Ref)
    end),
    Collectors = CardinalCollectors#{syndrome => MeasurementSource},
    {ok, PID} = phi_halo_cell:start_link(Collectors),
    MeasurementSource ! {target, PID},
    ok = phi_halo_cell:configure(PID, ?PRNG_SEED),
    {PID, Collectors, Ref}.

add_zero_measurement_source(PID, Collectors, Ref) ->
    MeasurementSource = spawn_link(fun() ->
        zero_measurement_loop(PID, Ref)
    end),
    Collectors#{syndrome => MeasurementSource}.

unbound_zero_measurement_loop(Ref) ->
    %% An immediate start can cast its first request before start_link/1
    %% returns the cell PID. Selective receive leaves that request queued until
    %% the caller supplies the target.
    receive
        {target, PID} -> zero_measurement_loop(PID, Ref)
    end.

zero_measurement_loop(PID) ->
    receive
        {'$gen_cast', {phenom_request, Step}} ->
            ok = phi_halo_cell:offer_measurement(PID, Step, false),
            zero_measurement_loop(PID);
        {'$gen_cast', {phi_correction, _, _, _, _}} ->
            zero_measurement_loop(PID);
        {'$gen_cast', {phi_status, _, _, _, _}} ->
            zero_measurement_loop(PID);
        stop ->
            ok
    end.

zero_measurement_loop(PID, Ref) ->
    receive
        {'$gen_cast', {phenom_request, Step}} ->
            ok = phi_halo_cell:offer_measurement(PID, Step, false),
            zero_measurement_loop(PID, Ref);
        {'$gen_cast', {phi_correction, _, _, _, _}} ->
            zero_measurement_loop(PID, Ref);
        {'$gen_cast', {phi_status, _, _, _, _}} ->
            zero_measurement_loop(PID, Ref);
        {stop, Stopper} ->
            Stopper ! {collector_stopped, Ref, syndrome},
            ok
    end.

torus_neighbors(Horizontal, Vertical, MeasurementSource) ->
    #{
        north => Vertical,
        east => Horizontal,
        west => Horizontal,
        south => Vertical,
        syndrome => MeasurementSource,
        correction => MeasurementSource,
        status => MeasurementSource
    }.

await_step(PID, Step) ->
    await_step(PID, Step, 1000).

await_step(_PID, Step, 0) ->
    error({cell_did_not_reach_decoder_step, Step});
await_step(PID, Step, Attempts) ->
    Info = phi_halo_cell:runtime_info(PID),
    case maps:get(data, Info) of
        {cell, CurrentStep, _Round, _Phi, _Sum, _PhiReceived,
                _Seen, _Best, _Direction, _MovesReceived, _Anyon, _Random,
                _X, _Y, _NoiseQuiet, _StatusValid}
                when CurrentStep >= Step ->
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
    Ports = [north, east, west, south, correction, status],
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

expect_port_cast(Ref, Port, Expected) ->
    receive
        {neighbor_cast, Ref, Port, Expected} ->
            ok;
        {neighbor_cast, Ref, OtherPort, Other} ->
            error({unexpected_neighbor_cast,
                OtherPort, Port, Expected, Other})
    after 1000 ->
        error({missing_neighbor_cast, Port, Expected})
    end.

expect_status_and_neighbor_batch(Ref, Status, Neighbor) ->
    Expected = #{
        north => Neighbor,
        east => Neighbor,
        west => Neighbor,
        south => Neighbor,
        status => Status
    },
    expect_port_messages(Ref, Expected).

expect_port_messages(_Ref, Expected) when map_size(Expected) =:= 0 ->
    ok;
expect_port_messages(Ref, Expected) ->
    receive
        {neighbor_cast, Ref, Port, Message} ->
            case maps:take(Port, Expected) of
                {Message, Remaining} ->
                    expect_port_messages(Ref, Remaining);
                {Other, _Remaining} ->
                    error({unexpected_neighbor_cast, Port, Other, Message});
                error ->
                    error({duplicate_neighbor_cast, Port, Message})
            end
    after 1000 ->
        error({missing_neighbor_casts, Expected})
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

expect_comparison_batch(Ref, Step, Value) ->
    expect_remaining_neighbor_sequences(
        Ref,
        maps:map(
            fun(_Port, Message) -> [Message] end,
            comparison_outputs(Step, Value)
        )
    ).

expect_comparison_sequences(Ref, Prefix, Step, Value) ->
    expect_remaining_neighbor_sequences(
        Ref,
        maps:map(
            fun(_Port, Message) -> [Prefix, Message] end,
            comparison_outputs(Step, Value)
        )
    ).

expect_comparison_and_anyon_sequences(Ref, Step, Value) ->
    Anyon = {anyon_move, Step, 0},
    Remaining = maps:map(
        fun(_Port, Message) -> [Message, Anyon] end,
        comparison_outputs(Step, Value)
    ),
    expect_remaining_neighbor_sequences(Ref, Remaining).

expect_anyon_batch(Ref, Step, Selected) ->
    Cardinal = maps:map(
        fun(_Port, Message) -> [Message] end,
        anyon_outputs(Step, Selected)
    ),
    Remaining = case Selected of
        none -> Cardinal;
        _ -> Cardinal#{correction => [
            {phi_correction, Step, 0, 0, correction_direction(Selected)}
        ]}
    end,
    expect_remaining_neighbor_sequences(Ref, Remaining).

comparison_outputs(Step, Value) ->
    #{
        north => {phi0, Step, ?SOUTH_MASK, Value},
        east => {phi0, Step, ?WEST_MASK, Value},
        west => {phi0, Step, ?EAST_MASK, Value},
        south => {phi0, Step, ?NORTH_MASK, Value}
    }.

anyon_outputs(Step, Selected) ->
    maps:from_list([
        {Port, {anyon_move, Step, selected_word(Port, Selected)}}
        || Port <- [north, east, west, south]
    ]).

expected_anyon_actions(Step, Selected, X, Y) ->
    Outputs = anyon_outputs(Step, Selected),
    [
        {cast, Port, maps:get(Port, Outputs)}
        || Port <- [north, east, west, south]
    ] ++ [{cast_if, Selected =/= none, correction, {phi_correction,
        Step, X, Y, correction_direction(Selected)}}].

correction_direction(none) -> 0;
correction_direction(Direction) -> direction_mask(Direction).

selected_word(Port, Port) -> 1;
selected_word(_Port, _Selected) -> 0.

present_word(false) -> 0;
present_word(true) -> 1.

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

offer_anyons(PID, Step, Presents) ->
    lists:foreach(
        fun(Present) ->
            ok = phi_halo_cell:offer_anyon(PID, Step, Present)
        end,
        Presents
    ).

four_phis(PID, Epoch, Values) ->
    ok = phi_halo_cell:offer_phi(PID, Epoch, Values),
    ok = phi_halo_cell:offer_phi(PID, Epoch, Values),
    ok = phi_halo_cell:offer_phi(PID, Epoch, Values),
    ok = phi_halo_cell:offer_phi(PID, Epoch, Values).

four_phi0s(PID, Step, Value) ->
    offer_comparisons(PID, Step, [
        {north, Value},
        {east, Value},
        {west, Value},
        {south, Value}
    ]).

offer_comparisons(PID, SourcesAndValues) ->
    offer_comparisons(PID, 0, SourcesAndValues).

offer_comparisons(PID, Step, SourcesAndValues) ->
    lists:foreach(
        fun({Source, Value}) ->
            ok = phi_halo_cell:offer_phi0(PID, Step, Source, Value)
        end,
        SourcesAndValues
    ).

direction_mask(north) -> ?NORTH_MASK;
direction_mask(east) -> ?EAST_MASK;
direction_mask(west) -> ?WEST_MASK;
direction_mask(south) -> ?SOUTH_MASK.

stop_collectors(Ref, Collectors) ->
    maps:foreach(
        fun(_Port, PID) -> PID ! {stop, self()} end,
        Collectors
    ),
    Ports = maps:keys(Collectors),
    lists:foreach(
        fun(Port) ->
            receive
                {collector_stopped, Ref, Port} -> ok
            end
        end,
        Ports
    ),
    flush_neighbor_casts(Ref).

flush_neighbor_casts(Ref) ->
    receive
        {neighbor_cast, Ref, _Port, _Message} ->
            flush_neighbor_casts(Ref)
    after 0 ->
        ok
    end.
