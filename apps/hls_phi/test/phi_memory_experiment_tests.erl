-module(phi_memory_experiment_tests).

-include_lib("eunit/include/eunit.hrl").
-include("phi_protocol.hrl").

-define(DISTANCE, 3).
-define(CUTOFF_STEP, 7).
-define(LINE_Y, 4).
-define(REQUEST_ID, 16#cafe).

%% Both decoder planes map periodic edge corrections onto the physical data checkerboard.
-spec correction_updates_follow_physical_checkerboard_test() -> ok.
correction_updates_follow_physical_checkerboard_test() ->
    Cases = [
        {x, 0, 0, ?PHI_NORTH_MASK, {0, 5}, z},
        {x, 2, 0, ?PHI_EAST_MASK, {0, 0}, z},
        {x, 2, 1, ?PHI_WEST_MASK, {2, 2}, z},
        {x, 1, 2, ?PHI_SOUTH_MASK, {1, 5}, z},
        {z, 2, 1, ?PHI_NORTH_MASK, {0, 2}, x},
        {z, 2, 1, ?PHI_EAST_MASK, {0, 3}, x},
        {z, 1, 2, ?PHI_WEST_MASK, {1, 5}, x},
        {z, 2, 2, ?PHI_SOUTH_MASK, {0, 0}, x}
    ],
    lists:foreach(
        fun({Plane, X, Y, Direction, Coordinate, Pauli}) ->
            Correction = #phi_correction{
                step = 9,
                x = X,
                y = Y,
                direction = Direction
            },
            ?assertEqual(
                {Coordinate, Pauli},
                phi_noise_topology:correction_update(
                    Plane, Correction, ?DISTANCE
                )
            )
        end,
        Cases
    ).

%% Initialization emits one cutoff covering the full noise domain.
-spec new_experiment_emits_one_whole_fabric_cutoff_test() -> ok.
new_experiment_emits_one_whole_fabric_cutoff_test() ->
    {State, Commands} = new_experiment(),
    ?assertEqual(draining, maps:get(phase, State)),
    ?assertEqual([
        {control_router, noise, {0, 0, 2, 5}, #noise_cutoff{
            first_quiet_step = ?CUTOFF_STEP
        }}
    ], Commands).

%% A partial, occupied or nonquiet status round cannot open the readout fence.
-spec incomplete_and_nonzero_status_rounds_do_not_query_test() -> ok.
incomplete_and_nonzero_status_rounds_do_not_query_test() ->
    {State0, _Cutoff} = new_experiment(),
    Coordinates = coordinates(),
    {Prefix, [Last]} = lists:split(length(Coordinates) - 1, Coordinates),
    {State1, []} = status_coordinates(
        x_decoder_events,
        ?CUTOFF_STEP,
        ?PHENOM_QUIET_MASK,
        Prefix,
        State0
    ),
    {State2, []} = status_coordinates(
        x_decoder_events,
        ?CUTOFF_STEP,
        ?PHENOM_PRESENT_MASK bor ?PHENOM_QUIET_MASK,
        [Last],
        State1
    ),
    {State3, []} = status_round(
        z_decoder_events,
        ?CUTOFF_STEP,
        ?PHENOM_QUIET_MASK,
        State2
    ),
    ?assertEqual(draining, maps:get(phase, State3)),
    {State4, []} = status_round(
        x_decoder_events,
        ?CUTOFF_STEP + 1,
        ?PHENOM_QUIET_MASK,
        State3
    ),
    {State5, []} = status_round(
        z_decoder_events,
        ?CUTOFF_STEP + 1,
        0,
        State4
    ),
    ?assertEqual(draining, maps:get(phase, State5)).

%% Both planes must complete the same quiet empty round before one readout query.
-spec matching_quiet_empty_rounds_emit_whole_device_query_test() -> ok.
matching_quiet_empty_rounds_emit_whole_device_query_test() ->
    {State0, _Cutoff} = new_experiment(),
    {State1, []} = status_round(
        x_decoder_events,
        ?CUTOFF_STEP,
        ?PHENOM_QUIET_MASK,
        State0
    ),
    {State2, []} = status_round(
        z_decoder_events,
        ?CUTOFF_STEP + 1,
        ?PHENOM_QUIET_MASK,
        State1
    ),
    {State3, Commands} = status_round(
        x_decoder_events,
        ?CUTOFF_STEP + 1,
        ?PHENOM_QUIET_MASK,
        State2
    ),
    ?assertEqual(querying, maps:get(phase, State3)),
    ?assertEqual(?CUTOFF_STEP + 1, maps:get(closeout_step, State3)),
    ?assertEqual([snapshot_query()], Commands).

%% Emit each correction before the status fence can release the readout request.
-spec correction_update_precedes_drain_query_test() -> ok.
correction_update_precedes_drain_query_test() ->
    {State0, _Cutoff} = new_experiment(),
    Correction = #phi_correction{
        step = ?CUTOFF_STEP,
        x = 0,
        y = 0,
        direction = ?PHI_NORTH_MASK
    },
    {State1, CorrectionCommands} = phi_memory_experiment:event(
        x_decoder_events,
        Correction,
        State0
    ),
    ?assertEqual([
        {control_router, data, {0, 5, 0, 5}, #pauli_update{pauli = z}}
    ], CorrectionCommands),
    {State2, XStatusCommands} = status_round(
        x_decoder_events,
        ?CUTOFF_STEP,
        ?PHENOM_QUIET_MASK,
        State1
    ),
    {State3, QueryCommands} = status_round(
        z_decoder_events,
        ?CUTOFF_STEP,
        ?PHENOM_QUIET_MASK,
        State2
    ),
    ?assertEqual(
        [
            {control_router, data, {0, 5, 0, 5},
                #pauli_update{pauli = z}},
            snapshot_query()
        ],
        CorrectionCommands ++ XStatusCommands ++ QueryCommands
    ),
    ?assertEqual(
        [{x, ?CUTOFF_STEP, 0, 0, ?PHI_NORTH_MASK}],
        maps:get(correction_log, State3)
    ).

%% Reject repeated corrections rather than applying the same Pauli twice.
-spec duplicate_correction_fails_before_status_fence_test() -> ok.
duplicate_correction_fails_before_status_fence_test() ->
    {State0, _Cutoff} = new_experiment(),
    Correction = #phi_correction{
        step = ?CUTOFF_STEP,
        x = 1,
        y = 2,
        direction = ?PHI_WEST_MASK
    },
    {State1, [_Update]} = phi_memory_experiment:event(
        z_decoder_events,
        Correction,
        State0
    ),
    {error, duplicate_correction, Failed} = phi_memory_experiment:event(
        z_decoder_events,
        Correction,
        State1
    ),
    ?assertEqual(failed, maps:get(phase, Failed)).

%% Out-of-domain coordinates fail the reducer before emitting a data command.
-spec out_of_range_correction_fails_reducer_test() -> ok.
out_of_range_correction_fails_reducer_test() ->
    {State, _Cutoff} = new_experiment(),
    {error, correction, Failed} = phi_memory_experiment:event(
        x_decoder_events,
        #phi_correction{
            step = ?CUTOFF_STEP,
            x = ?DISTANCE,
            y = 0,
            direction = ?PHI_NORTH_MASK
        },
        State
    ),
    ?assertEqual(failed, maps:get(phase, Failed)).

%% Ignore unrelated requests and sort complete matching replies into a canonical witness.
-spec out_of_order_whole_device_replies_build_canonical_witness_test() -> ok.
out_of_order_whole_device_replies_build_canonical_witness_test() ->
    Querying = querying_state(),
    {Querying, []} = phi_memory_experiment:event(
        data_measurements,
        reply(?REQUEST_ID + 1, 0, 0, 1),
        Querying
    ),
    Replies = [
        reply(?REQUEST_ID, X, Y, anticommutes_at(X, Y))
        || {X, Y} <- lists:reverse(snapshot_coordinates())
    ],
    {done, Witness, Done} = replies(Replies, Querying),
    ?assertEqual(done, maps:get(phase, Done)),
    ?assertEqual(?CUTOFF_STEP, maps:get(closeout_step, Witness)),
    ?assertEqual([], maps:get(corrections, Witness)),
    ?assertEqual(z, maps:get(measurement, Witness)),
    ?assertEqual(
        lists:sort([
            {{X, Y}, anticommutes_at(X, Y)}
            || {X, Y} <- snapshot_coordinates()
        ]),
        maps:get(data_anticommutations, Witness)
    ),
    ?assertEqual(
        #{y => ?LINE_Y, parity => 0},
        maps:get(row, Witness)
    ).

%% Reject repeated coordinates within one readout request.
-spec duplicate_reply_fails_test() -> ok.
duplicate_reply_fails_test() ->
    Querying = querying_state(),
    Reply = reply(?REQUEST_ID, 2, 5, 1),
    {State1, []} = phi_memory_experiment:event(
        data_measurements,
        Reply,
        Querying
    ),
    {error, duplicate_reply, Failed} = phi_memory_experiment:event(
        data_measurements,
        Reply,
        State1
    ),
    ?assertEqual(failed, maps:get(phase, Failed)).

%% The maximum u32 request ID remains valid without incrementing it.
-spec maximum_request_id_is_used_without_a_successor_test() -> ok.
maximum_request_id_is_used_without_a_successor_test() ->
    Max = 16#ffffffff,
    {State0, _Cutoff} = phi_memory_experiment:new(#{
        distance => ?DISTANCE,
        first_quiet_step => ?CUTOFF_STEP,
        line_y => ?LINE_Y,
        measurement => z,
        request_id => Max
    }),
    {State1, []} = status_round(
        x_decoder_events,
        ?CUTOFF_STEP,
        ?PHENOM_QUIET_MASK,
        State0
    ),
    {_Querying, [Query]} = status_round(
        z_decoder_events,
        ?CUTOFF_STEP,
        ?PHENOM_QUIET_MASK,
        State1
    ),
    ?assertEqual(
        {control_router, data, {0, 0, 2, 5}, #pauli_query{
            request_id = Max,
            measurement = z
        }},
        Query
    ).

%% A separate experiment retains its selected measurement basis through readout.
-spec complementary_basis_requires_a_fresh_experiment_test() -> ok.
complementary_basis_requires_a_fresh_experiment_test() ->
    {State0, _Cutoff} = phi_memory_experiment:new(#{
        distance => ?DISTANCE,
        first_quiet_step => ?CUTOFF_STEP,
        line_y => ?LINE_Y,
        measurement => x,
        request_id => ?REQUEST_ID
    }),
    {State1, []} = status_round(
        x_decoder_events,
        ?CUTOFF_STEP,
        ?PHENOM_QUIET_MASK,
        State0
    ),
    {Querying, [Query]} = status_round(
        z_decoder_events,
        ?CUTOFF_STEP,
        ?PHENOM_QUIET_MASK,
        State1
    ),
    ?assertEqual(
        {control_router, data, {0, 0, 2, 5}, #pauli_query{
            request_id = ?REQUEST_ID,
            measurement = x
        }},
        Query
    ),
    Replies = [
        reply(?REQUEST_ID, X, Y, (X + Y) band 1)
        || {X, Y} <- snapshot_coordinates()
    ],
    {done, Witness, _Done} = replies(Replies, Querying),
    ?assertEqual(x, maps:get(measurement, Witness)).

%% Initialize the common distance-three closeout fixture.
-spec new_experiment() -> {phi_memory_experiment:state(), [phi_memory_experiment:command()]}.
new_experiment() ->
    phi_memory_experiment:new(#{
        distance => ?DISTANCE,
        first_quiet_step => ?CUTOFF_STEP,
        line_y => ?LINE_Y,
        measurement => z,
        request_id => ?REQUEST_ID
    }).

%% Drive both complete quiet status rounds and assert the resulting readout query.
-spec querying_state() -> phi_memory_experiment:state().
querying_state() ->
    {State0, _Cutoff} = new_experiment(),
    {State1, []} = status_round(
        x_decoder_events,
        ?CUTOFF_STEP,
        ?PHENOM_QUIET_MASK,
        State0
    ),
    {State2, [Query]} = status_round(
        z_decoder_events,
        ?CUTOFF_STEP,
        ?PHENOM_QUIET_MASK,
        State1
    ),
    ?assertEqual(snapshot_query(), Query),
    State2.

%% Supply every decoder coordinate for one status round.
-spec status_round(phi_memory_experiment:stream(), hls_nums:u32(), hls_nums:u32(), phi_memory_experiment:state()) -> {phi_memory_experiment:state(), [phi_memory_experiment:command()]}.
status_round(Stream, Step, Flags, State) ->
    status_coordinates(Stream, Step, Flags, coordinates(), State).

%% Fold selected status events in order and concatenate their emitted commands.
-spec status_coordinates(phi_memory_experiment:stream(), hls_nums:u32(), hls_nums:u32(), [{hls_nums:u16(), hls_nums:u16()}], phi_memory_experiment:state()) -> {phi_memory_experiment:state(), [phi_memory_experiment:command()]}.
status_coordinates(Stream, Step, Flags, Coordinates, State) ->
    lists:foldl(
        fun({X, Y}, {Current, Commands}) ->
            {Next, NewCommands} = phi_memory_experiment:event(
                Stream,
                #phi_status{step = Step, x = X, y = Y, flags = Flags},
                Current
            ),
            {Next, Commands ++ NewCommands}
        end,
        {State, []},
        Coordinates
    ).

%% Enumerate the square decoder plane in stable coordinate order.
-spec coordinates() -> [{0..2, 0..2}].
coordinates() ->
    [
        {X, Y}
        || X <- lists:seq(0, ?DISTANCE - 1),
           Y <- lists:seq(0, ?DISTANCE - 1)
    ].

%% Enumerate the physical data grid, which has twice the decoder height.
-spec snapshot_coordinates() -> [{0..2, 0..5}].
snapshot_coordinates() ->
    [
        {X, Y}
        || X <- lists:seq(0, ?DISTANCE - 1),
           Y <- lists:seq(0, 2 * ?DISTANCE - 1)
    ].

%% Construct the fixed whole-data-grid readout query.
-spec snapshot_query() -> phi_memory_experiment:command().
snapshot_query() ->
    {control_router, data, {0, 0, ?DISTANCE - 1, 2 * ?DISTANCE - 1},
        #pauli_query{request_id = ?REQUEST_ID, measurement = z}}.

%% Construct a readout event for one physical coordinate.
-spec reply(hls_nums:u32(), hls_nums:u16(), hls_nums:u16(), 0 | 1) -> #pauli_reply{}.
reply(RequestId, X, Y, Anticommutes) ->
    #pauli_reply{
        request_id = RequestId,
        x = X,
        y = Y,
        anticommutes = Anticommutes
    }.

%% Fold a finite readout stream, requiring completion exactly at its end.
-spec replies([#pauli_reply{}], phi_memory_experiment:state()) -> {phi_memory_experiment:state(), [phi_memory_experiment:command()]} | {done, phi_memory_experiment:witness(), phi_memory_experiment:state()}.
replies(Replies, State) ->
    replies(Replies, State, []).

%% Accumulate commands and reject early completion or any reducer failure.
-spec replies([#pauli_reply{}], phi_memory_experiment:state(), [phi_memory_experiment:command()]) -> {phi_memory_experiment:state(), [phi_memory_experiment:command()]} | {done, phi_memory_experiment:witness(), phi_memory_experiment:state()}.
replies([], State, Commands) ->
    {State, Commands};
replies([Reply | Rest], State, Commands) ->
    case phi_memory_experiment:event(data_measurements, Reply, State) of
        {Next, NewCommands} ->
            replies(Rest, Next, Commands ++ NewCommands);
        {done, _Witness, _Done} = Done when Rest =:= [] ->
            Done;
        {done, _Witness, _Done} = Done ->
            error({replies_after_done, Rest, Done});
        {error, _Reason, _Failed} = Error ->
            error({unexpected_reply_error, Reply, Error})
    end.

%% Supply four fixed errors with even parity on the selected logical row.
-spec anticommutes_at(non_neg_integer(), non_neg_integer()) -> 0 | 1.
anticommutes_at(0, 0) -> 1;
anticommutes_at(0, 1) -> 1;
anticommutes_at(0, ?LINE_Y) -> 1;
anticommutes_at(2, ?LINE_Y) -> 1;
anticommutes_at(_X, _Y) -> 0.
