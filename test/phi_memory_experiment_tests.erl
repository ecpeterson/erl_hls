-module(phi_memory_experiment_tests).

-include_lib("eunit/include/eunit.hrl").
-include("phi_protocol.hrl").

-define(DISTANCE, 3).
-define(CUTOFF_STEP, 7).
-define(LINE_Y, 4).
-define(REQUEST_ID, 16#cafe).

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

new_experiment_emits_one_whole_fabric_cutoff_test() ->
    {State, Commands} = new_experiment(),
    ?assertEqual(draining, maps:get(phase, State)),
    ?assertEqual([
        {control_router, noise, {0, 0, 2, 5}, #noise_cutoff{
            first_quiet_step = ?CUTOFF_STEP
        }}
    ], Commands).

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

matching_quiet_empty_rounds_emit_one_line_query_test() ->
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
    ?assertEqual([line_query()], Commands).

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
    {_State3, QueryCommands} = status_round(
        z_decoder_events,
        ?CUTOFF_STEP,
        ?PHENOM_QUIET_MASK,
        State2
    ),
    ?assertEqual(
        [
            {control_router, data, {0, 5, 0, 5},
                #pauli_update{pauli = z}},
            line_query()
        ],
        CorrectionCommands ++ XStatusCommands ++ QueryCommands
    ).

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

out_of_order_replies_xor_after_ignoring_wrong_request_test() ->
    Querying = querying_state(),
    {Querying, []} = phi_memory_experiment:event(
        data_measurements,
        reply(?REQUEST_ID + 1, 0, 1),
        Querying
    ),
    {State1, []} = phi_memory_experiment:event(
        data_measurements,
        reply(?REQUEST_ID, 2, 1),
        Querying
    ),
    {State2, []} = phi_memory_experiment:event(
        data_measurements,
        reply(?REQUEST_ID, 0, 0),
        State1
    ),
    {done, 0, Done} = phi_memory_experiment:event(
        data_measurements,
        reply(?REQUEST_ID, 1, 1),
        State2
    ),
    ?assertEqual(done, maps:get(phase, Done)).

duplicate_reply_fails_test() ->
    Querying = querying_state(),
    Reply = reply(?REQUEST_ID, 2, 1),
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

new_experiment() ->
    phi_memory_experiment:new(#{
        distance => ?DISTANCE,
        first_quiet_step => ?CUTOFF_STEP,
        line_y => ?LINE_Y,
        measurement => z,
        request_id => ?REQUEST_ID
    }).

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
    ?assertEqual(line_query(), Query),
    State2.

status_round(Stream, Step, Flags, State) ->
    status_coordinates(Stream, Step, Flags, coordinates(), State).

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

coordinates() ->
    [
        {X, Y}
        || X <- lists:seq(0, ?DISTANCE - 1),
           Y <- lists:seq(0, ?DISTANCE - 1)
    ].

line_query() ->
    {control_router, data, {0, ?LINE_Y, ?DISTANCE - 1, ?LINE_Y},
        #pauli_query{request_id = ?REQUEST_ID, measurement = z}}.

reply(RequestId, X, Anticommutes) ->
    #pauli_reply{
        request_id = RequestId,
        x = X,
        y = ?LINE_Y,
        anticommutes = Anticommutes
    }.
