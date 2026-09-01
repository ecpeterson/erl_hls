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
    ?assertEqual(querying_x, maps:get(phase, State3)),
    ?assertEqual(?CUTOFF_STEP + 1, maps:get(closeout_step, State3)),
    ?assertEqual([snapshot_query(x)], Commands).

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
            snapshot_query(x)
        ],
        CorrectionCommands ++ XStatusCommands ++ QueryCommands
    ),
    ?assertEqual(
        [{x, ?CUTOFF_STEP, 0, 0, ?PHI_NORTH_MASK}],
        maps:get(correction_log, State3)
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

out_of_order_whole_device_replies_build_canonical_witness_test() ->
    Querying = querying_state(),
    {Querying, []} = phi_memory_experiment:event(
        data_measurements,
        reply(?REQUEST_ID + 1, 0, 0, 1),
        Querying
    ),
    XReplies = [
        reply(?REQUEST_ID, X, Y, anti_x(pauli_at(X, Y)))
        || {X, Y} <- lists:reverse(snapshot_coordinates())
    ],
    {QueryingZ, [ZQuery]} = replies(XReplies, Querying),
    ?assertEqual(querying_z, maps:get(phase, QueryingZ)),
    ?assertEqual(snapshot_query(z), ZQuery),
    {QueryingZ, []} = phi_memory_experiment:event(
        data_measurements,
        reply(?REQUEST_ID + 7, 2, 5, 1),
        QueryingZ
    ),
    ZReplies = [
        reply(?REQUEST_ID + 1, X, Y, anti_z(pauli_at(X, Y)))
        || {X, Y} <- snapshot_coordinates()
    ],
    {done, Witness, Done} = replies(ZReplies, QueryingZ),
    ?assertEqual(done, maps:get(phase, Done)),
    ?assertEqual(?CUTOFF_STEP, maps:get(closeout_step, Witness)),
    ?assertEqual([], maps:get(corrections, Witness)),
    ?assertEqual(
        lists:sort([
            {{X, Y}, pauli_at(X, Y)}
            || {X, Y} <- snapshot_coordinates()
        ]),
        maps:get(data_paulis, Witness)
    ),
    ?assertEqual(
        #{y => ?LINE_Y, measurement => z, parity => 0},
        maps:get(row, Witness)
    ).

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

late_x_reply_fails_during_z_query_test() ->
    QueryingX = querying_state(),
    XReplies = [
        reply(?REQUEST_ID, X, Y, 0)
        || {X, Y} <- snapshot_coordinates()
    ],
    {QueryingZ, [_ZQuery]} = replies(XReplies, QueryingX),
    {error, late_reply, Failed} = phi_memory_experiment:event(
        data_measurements,
        reply(?REQUEST_ID, 0, 0, 0),
        QueryingZ
    ),
    ?assertEqual(failed, maps:get(phase, Failed)).

request_id_wraps_between_snapshot_queries_test() ->
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
    {QueryingX, [XQuery]} = status_round(
        z_decoder_events,
        ?CUTOFF_STEP,
        ?PHENOM_QUIET_MASK,
        State1
    ),
    ?assertEqual(
        {control_router, data, {0, 0, 2, 5}, #pauli_query{
            request_id = Max,
            measurement = x
        }},
        XQuery
    ),
    XReplies = [
        reply(Max, X, Y, 0)
        || {X, Y} <- snapshot_coordinates()
    ],
    {_QueryingZ, [ZQuery]} = replies(XReplies, QueryingX),
    ?assertEqual(
        {control_router, data, {0, 0, 2, 5}, #pauli_query{
            request_id = 0,
            measurement = z
        }},
        ZQuery
    ).

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
    ?assertEqual(snapshot_query(x), Query),
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

snapshot_coordinates() ->
    [
        {X, Y}
        || X <- lists:seq(0, ?DISTANCE - 1),
           Y <- lists:seq(0, 2 * ?DISTANCE - 1)
    ].

snapshot_query(x) ->
    {control_router, data, {0, 0, ?DISTANCE - 1, 2 * ?DISTANCE - 1},
        #pauli_query{request_id = ?REQUEST_ID, measurement = x}};
snapshot_query(z) ->
    {control_router, data, {0, 0, ?DISTANCE - 1, 2 * ?DISTANCE - 1},
        #pauli_query{request_id = ?REQUEST_ID + 1, measurement = z}}.

reply(RequestId, X, Y, Anticommutes) ->
    #pauli_reply{
        request_id = RequestId,
        x = X,
        y = Y,
        anticommutes = Anticommutes
    }.

replies(Replies, State) ->
    replies(Replies, State, []).

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

pauli_at(0, 0) -> i;
pauli_at(0, 1) -> x;
pauli_at(0, 2) -> z;
pauli_at(0, 3) -> y;
pauli_at(0, ?LINE_Y) -> x;
pauli_at(1, ?LINE_Y) -> z;
pauli_at(2, ?LINE_Y) -> y;
pauli_at(_X, _Y) -> i.

anti_x(i) -> 0;
anti_x(x) -> 0;
anti_x(y) -> 1;
anti_x(z) -> 1.

anti_z(i) -> 0;
anti_z(x) -> 1;
anti_z(y) -> 1;
anti_z(z) -> 0.
