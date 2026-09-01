-module(phenom_syndrome_cell_tests).

-include_lib("eunit/include/eunit.hrl").
-include("phi_protocol.hrl").

-define(PRNG_SEED, 16#6d2b79f5).
-define(PRNG_FIRST, 16#40aec71f).
-define(PRNG_SECOND, 16#91e00c19).
-define(HALF_THRESHOLD, 16#80000000).
-define(U32_MASK, 16#ffffffff).
-define(COORD_X, 16#1234).
-define(COORD_Y, 16#abcd).

query_entry_labels_recipient_edges_test() ->
    Cell = collecting_cell(?PRNG_SEED, 0),
    ?assertEqual(
        {Cell, [
            {cast, north, #phenom_query{
                step = 0,
                source = ?PHI_SOUTH_MASK
            }},
            {cast, east, #phenom_query{
                step = 0,
                source = ?PHI_WEST_MASK
            }},
            {cast, west, #phenom_query{
                step = 0,
                source = ?PHI_EAST_MASK
            }},
            {cast, south, #phenom_query{
                step = 0,
                source = ?PHI_NORTH_MASK
            }}
        ]},
        phenom_syndrome_cell:handle_enter(waiting, collecting, Cell)
    ).

response_order_does_not_change_parity_test() ->
    Responses = [
        {north, true},
        {east, false},
        {west, true},
        {south, true}
    ],
    lists:foreach(
        fun(Permutation) ->
            Cell0 = collecting_cell(
                ?PRNG_SEED,
                0,
                ?COORD_X,
                ?COORD_Y
            ),
            {announcing, Cell1, consume} = apply_responses(
                Permutation,
                0,
                Cell0
            ),
            ?assertEqual(
                syndrome(0, ?PHI_ALL_DIRECTIONS, 1, 0, 1,
                    ?PRNG_FIRST, 0, ?COORD_X, ?COORD_Y),
                Cell1
            ),
            ?assertEqual(
                {Cell1, [{cast, phi, #phenom_anyon{
                    step = 0,
                    flags = ?PHENOM_PRESENT_MASK,
                    x = ?COORD_X,
                    y = ?COORD_Y
                }}]},
                phenom_syndrome_cell:handle_enter(
                    collecting,
                    announcing,
                    Cell1
                )
            )
        end,
        permutations(Responses)
    ).

measurement_error_appears_at_both_boundaries_test() ->
    Cell0 = collecting_cell(?PRNG_SEED, ?HALF_THRESHOLD),
    {announcing, First, consume} = apply_responses(
        all_absent(),
        0,
        Cell0
    ),
    %% The first random word is below the threshold, so the current
    %% measurement toggles the otherwise empty data parity.
    ?assertEqual(
        syndrome(0, ?PHI_ALL_DIRECTIONS, 0, 1, 1,
            ?PRNG_FIRST, ?HALF_THRESHOLD, 0, 0),
        First
    ),

    {collecting, Second0, consume} = phenom_syndrome_cell:handle_cast(
        #phenom_request{step = 1},
        announcing,
        First
    ),
    {announcing, Second, consume} = apply_responses(
        all_absent(),
        1,
        Second0
    ),
    %% The second word is above the threshold. The falling edge of the prior
    %% measurement error therefore supplies this round's detection event.
    ?assertEqual(
        syndrome(1, ?PHI_ALL_DIRECTIONS, 0, 0, 1,
            ?PRNG_SECOND, ?HALF_THRESHOLD, 0, 0),
        Second
    ).

prng_advances_once_when_join_completes_test() ->
    Cell0 = collecting_cell(?PRNG_SEED, ?HALF_THRESHOLD),
    {collecting, Cell1, consume} = offer_direct(north, false, 0, Cell0),
    {collecting, Cell2, consume} = offer_direct(east, false, 0, Cell1),
    {collecting, Cell3, consume} = offer_direct(west, false, 0, Cell2),
    ?assertMatch(
        {syndrome, 0, _, 0, 0, 0, 0, 0,
            ?PRNG_SEED, ?HALF_THRESHOLD, 0, 0, 0, 0, 0},
        Cell3
    ),
    {announcing, Cell4, consume} = offer_direct(south, false, 0, Cell3),
    ?assertMatch(
        {syndrome, 0, ?PHI_ALL_DIRECTIONS, 0, 1, 1, 0, 0,
            ?PRNG_FIRST, ?HALF_THRESHOLD, 0, 0, 0, 0, 0},
        Cell4
    ).

duplicate_invalid_and_stale_data_fail_test() ->
    Cell0 = collecting_cell(?PRNG_SEED, 0),
    {collecting, Cell1, consume} = offer_direct(north, false, 0, Cell0),
    ?assertEqual(
        {collecting, Cell1, fail},
        offer_direct(north, true, 0, Cell1)
    ),
    lists:foreach(
        fun(Source) ->
            ?assertEqual(
                {collecting, Cell0, fail},
                phenom_syndrome_cell:handle_cast(
                    #phenom_data{
                        step = 0,
                        source = Source,
                        flags = 0
                    },
                    collecting,
                    Cell0
                )
            )
        end,
        [0, 3, 16]
    ),
    ?assertEqual(
        {collecting, Cell0, fail},
        phenom_syndrome_cell:handle_cast(
            #phenom_data{
                step = 0,
                source = ?PHI_NORTH_MASK,
                flags = 4
            },
            collecting,
            Cell0
        )
    ),
    ?assertEqual(
        {collecting, Cell0, fail},
        phenom_syndrome_cell:handle_cast(
            #phenom_data{
                step = 16#ffffffff,
                source = ?PHI_NORTH_MASK,
                flags = 0
            },
            collecting,
            Cell0
        )
    ).

invalid_configuration_and_request_steps_fail_test() ->
    {ok, configuring, Initial} = phenom_syndrome_cell:init([]),
    ?assertEqual(
        {configuring, Initial, fail},
        phenom_syndrome_cell:handle_cast(
            #phenom_config{seed = 0, threshold = 0, x = 0, y = 0},
            configuring,
            Initial
        )
    ),
    ?assertEqual(
        {configuring, Initial, fail},
        phenom_syndrome_cell:handle_cast(
            #phenom_config{
                seed = ?PRNG_SEED,
                threshold = 0,
                x = 16#10000,
                y = 0
            },
            configuring,
            Initial
        )
    ),
    Collecting = collecting_cell(?PRNG_SEED, 0),
    ?assertEqual(
        {collecting, Collecting, fail},
        phenom_syndrome_cell:handle_cast(
            #phenom_request{step = 0},
            collecting,
            Collecting
        )
    ),
    ?assertEqual(
        {collecting, Collecting, postpone},
        phenom_syndrome_cell:handle_cast(
            #phenom_request{step = 1},
            collecting,
            Collecting
        )
    ).

early_next_request_replays_after_announcement_test() ->
    Outputs = maps:from_list([
        {north, self()},
        {east, self()},
        {west, self()},
        {south, self()},
        {phi, self()}
    ]),
    {ok, PID} = phenom_syndrome_cell:start_link(Outputs),
    try
        ok = phenom_syndrome_cell:configure(
            PID,
            ?PRNG_SEED,
            0,
            ?COORD_X,
            ?COORD_Y
        ),
        ok = phenom_syndrome_cell:offer_request(PID, 0),
        expect_query_batch(0),

        ok = phenom_syndrome_cell:offer_request(PID, 1),
        Before = phenom_syndrome_cell:runtime_info(PID),
        ?assertEqual(collecting, maps:get(phase, Before)),
        ?assertEqual(1, maps:get(postponed, Before)),

        ok = phenom_syndrome_cell:offer_data(PID, 0, north, true),
        ok = phenom_syndrome_cell:offer_data(PID, 0, east, false),
        ok = phenom_syndrome_cell:offer_data(PID, 0, west, true),
        ok = phenom_syndrome_cell:offer_data(PID, 0, south, true),

        expect_cast(#phenom_anyon{
            step = 0,
            flags = ?PHENOM_PRESENT_MASK,
            x = ?COORD_X,
            y = ?COORD_Y
        }),
        expect_query_batch(1),
        After = phenom_syndrome_cell:runtime_info(PID),
        ?assertEqual(collecting, maps:get(phase, After)),
        ?assertEqual(0, maps:get(postponed, After)),
        ?assertEqual(
            {syndrome, 1, 0, 0, 0, 0, 1, 0,
                ?PRNG_FIRST, 0, ?COORD_X, ?COORD_Y, 0, 0, 0},
            maps:get(data, After)
        )
    after
        stop_if_alive(PID)
    end.

request_before_configuration_is_replayed_test() ->
    Outputs = maps:from_list([
        {north, self()},
        {east, self()},
        {west, self()},
        {south, self()},
        {phi, self()}
    ]),
    {ok, PID} = phenom_syndrome_cell:start_link(Outputs),
    try
        ok = phenom_syndrome_cell:offer_request(PID, 0),
        Before = phenom_syndrome_cell:runtime_info(PID),
        ?assertEqual(configuring, maps:get(phase, Before)),
        ?assertEqual(1, maps:get(postponed, Before)),
        ok = phenom_syndrome_cell:configure(PID, ?PRNG_SEED, 0),
        expect_query_batch(0),
        ?assertEqual(
            collecting,
            maps:get(phase, phenom_syndrome_cell:runtime_info(PID))
        )
    after
        stop_if_alive(PID)
    end.

cpu_api_rejects_bad_configuration_test() ->
    ?assertError(
        badarg,
        phenom_syndrome_cell:configure(self(), 0, 1)
    ),
    ?assertError(
        badarg,
        phenom_syndrome_cell:configure(
            self(),
            ?PRNG_SEED,
            16#100000000
        )
    ),
    ?assertError(
        badarg,
        phenom_syndrome_cell:configure(
            self(),
            ?PRNG_SEED,
            0,
            -1,
            0
        )
    ),
    ?assertError(
        badarg,
        phenom_syndrome_cell:configure(
            self(),
            ?PRNG_SEED,
            0,
            0,
            16#10000
        )
    ).

cutoff_freezes_prng_after_first_quiet_round_test() ->
    Outputs = maps:from_list([
        {north, self()},
        {east, self()},
        {west, self()},
        {south, self()},
        {phi, self()}
    ]),
    {ok, PID} = phenom_syndrome_cell:start_link(Outputs),
    try
        ok = phenom_syndrome_cell:configure(
            PID,
            ?PRNG_SEED,
            ?U32_MASK,
            ?COORD_X,
            ?COORD_Y
        ),
        ok = phenom_syndrome_cell:noise_cutoff(PID, 1),

        run_round(PID, 0),
        expect_cast(#phenom_anyon{
            step = 0,
            flags = ?PHENOM_PRESENT_MASK,
            x = ?COORD_X,
            y = ?COORD_Y
        }),

        run_round(PID, 1),
        expect_cast(#phenom_anyon{
            step = 1,
            flags = ?PHENOM_PRESENT_MASK,
            x = ?COORD_X,
            y = ?COORD_Y
        }),

        run_round(PID, 2),
        expect_cast(#phenom_anyon{
            step = 2,
            flags = 0,
            x = ?COORD_X,
            y = ?COORD_Y
        }),
        Info = phenom_syndrome_cell:runtime_info(PID),
        ?assertMatch(
            {syndrome, 2, ?PHI_ALL_DIRECTIONS, 0, 0, 0, 0, 0,
                ?PRNG_FIRST, ?U32_MASK, ?COORD_X, ?COORD_Y,
                1, 0, 1},
            maps:get(data, Info)
        )
    after
        stop_if_alive(PID)
    end.

lowerable_source_and_shared_wire_tags_test() ->
    XLS = iolist_to_binary(
        xls_parse:to_xls("src/examples/phi_decoder/phenom_syndrome_cell.erl")
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(XLS, <<"PHENOM_REQUEST = u8:7">>)
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(XLS, <<"PHENOM_ANYON = u8:10">>)
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(XLS, <<"NOISE_CUTOFF = u8:15">>)
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(XLS, <<"Phase::ANNOUNCING">>)
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(XLS, <<" << u32:13">>)
    ),
    ?assertNotEqual(
        nomatch,
        binary:match(XLS, <<
            "struct Phenomanyon {\n"
            "  step : u32,\n"
            "  flags : u32,\n"
            "  x : u16,\n"
            "  y : u16,"
        >>)
    ),
    ?assertEqual(7, phenom_syndrome_cell:pack_tag(phenom_request)),
    ?assertEqual(10, phenom_syndrome_cell:pack_tag(phenom_anyon)),
    ?assertEqual(15, phenom_syndrome_cell:pack_tag(noise_cutoff)),
    Interface = hls_actor_interface:from_module(phenom_syndrome_cell),
    ?assertEqual(
        [phenom_anyon],
        hls_actor_interface:output_schemas(Interface, phi)
    ).

collecting_cell(Seed, Threshold) ->
    collecting_cell(Seed, Threshold, 0, 0).

collecting_cell(Seed, Threshold, X, Y) ->
    {ok, configuring, Initial} = phenom_syndrome_cell:init([]),
    {waiting, Configured, consume} = phenom_syndrome_cell:handle_cast(
        #phenom_config{
            seed = Seed,
            threshold = Threshold,
            x = X,
            y = Y
        },
        configuring,
        Initial
    ),
    {collecting, Collecting, consume} = phenom_syndrome_cell:handle_cast(
        #phenom_request{step = 0},
        waiting,
        Configured
    ),
    Collecting.

syndrome(Step, Seen, Parity, PreviousMeasurement, Announcement, Random,
        Threshold, X, Y) ->
    {syndrome, Step, Seen, Parity, PreviousMeasurement, Announcement,
        0, 0, Random, Threshold, X, Y, 0, 0, 0}.

apply_responses([Response], Step, Cell) ->
    offer_direct(Response, Step, Cell);
apply_responses([Response | Rest], Step, Cell0) ->
    {collecting, Cell1, consume} = offer_direct(Response, Step, Cell0),
    apply_responses(Rest, Step, Cell1).

offer_direct({Direction, Present}, Step, Cell) ->
    offer_direct(Direction, Present, Step, Cell).

offer_direct(Direction, Present, Step, Cell) ->
    PresentWord = case Present of
        false -> 0;
        true -> 1
    end,
    phenom_syndrome_cell:handle_cast(
        #phenom_data{
            step = Step,
            source = direction_mask(Direction),
            flags = PresentWord
        },
        collecting,
        Cell
    ).

all_absent() ->
    [{north, false}, {east, false}, {west, false}, {south, false}].

run_round(PID, Step) ->
    ok = phenom_syndrome_cell:offer_request(PID, Step),
    expect_query_batch(Step),
    lists:foreach(
        fun(Direction) ->
            ok = phenom_syndrome_cell:offer_data(PID, Step, Direction, false)
        end,
        [north, east, west, south]
    ).

direction_mask(north) -> ?PHI_NORTH_MASK;
direction_mask(east) -> ?PHI_EAST_MASK;
direction_mask(west) -> ?PHI_WEST_MASK;
direction_mask(south) -> ?PHI_SOUTH_MASK.

permutations([]) ->
    [[]];
permutations(Items) ->
    [
        [Item | Rest]
        || Item <- Items,
           Rest <- permutations(Items -- [Item])
    ].

expect_query_batch(Step) ->
    lists:foreach(
        fun(Source) ->
            expect_cast(#phenom_query{step = Step, source = Source})
        end,
        [
            ?PHI_SOUTH_MASK,
            ?PHI_WEST_MASK,
            ?PHI_EAST_MASK,
            ?PHI_NORTH_MASK
        ]
    ).

expect_cast(Message) ->
    receive
        {'$gen_cast', Message} -> ok
    after 1000 ->
        error({missing_cast, Message})
    end.

stop_if_alive(PID) ->
    case is_process_alive(PID) of
        true -> phenom_syndrome_cell:stop(PID);
        false -> ok
    end.
