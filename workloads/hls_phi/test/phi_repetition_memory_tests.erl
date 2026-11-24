-module(phi_repetition_memory_tests).

-include_lib("eunit/include/eunit.hrl").
-include("phi_protocol.hrl").

-define(REQUEST, 16#52455031).
-define(STEP, 18).

%% Witness that a remote correction is admitted before the shared measurement fence.
-spec cross_partition_closeout_orders_updates_before_queries_test() -> ok.
cross_partition_closeout_orders_updates_before_queries_test() ->
    {A0, ACutoff} = new(a, [0, 1, 2], {0, 0, 2, 0}),
    {B0, BCutoff} = new(b, [3, 4, 5], {3, 0, 5, 0}),
    ?assertEqual(
        {control_router, noise, {0, 0, 2, 0}, #noise_cutoff{first_quiet_step = 16}},
        ACutoff
    ),
    ?assertEqual(
        {control_router, noise, {3, 0, 5, 0}, #noise_cutoff{first_quiet_step = 16}},
        BCutoff
    ),

    Correction = #phi_correction{step = 16, x = 2, y = 0, direction = ?PHI_EAST_MASK},
    {ok, A1, [{peer, CorrectionMessage}, {observation, _}]} =
        phi_repetition_memory:event(decoder_events, Correction, A0),
    {ok, B1, [
        {command, {control_router, data, {3, 0, 3, 0}, #pauli_update{pauli = z}}},
        {peer, Ack},
        {observation, _}
    ]} = phi_repetition_memory:peer(CorrectionMessage, B0),
    {ok, A2, []} = phi_repetition_memory:peer(Ack, A1),

    {A3, [{peer, AQuiet}]} = quiet_round(A2),
    {B2, [{peer, BQuiet}]} = quiet_round(B1),
    {ok, A4, [{peer, AReady}]} = phi_repetition_memory:peer(BQuiet, A3),
    {ok, B3, [{peer, BReady}]} = phi_repetition_memory:peer(AQuiet, B2),
    {ok, B4, []} = phi_repetition_memory:peer(AReady, B3),
    {ok, A5, [{peer, QueryMessage}, {command, AQuery}]} =
        phi_repetition_memory:peer(BReady, A4),
    {ok, B5, [{command, BQuery}]} = phi_repetition_memory:peer(QueryMessage, B4),
    ?assertMatch({control_router, data, {0, 0, 2, 0}, #pauli_query{}}, AQuery),
    ?assertMatch({control_router, data, {3, 0, 5, 0}, #pauli_query{}}, BQuery),
    {A6, B6, ReplyMessages} = local_replies(A5, B5),
    {done, AWitness, _A8, [{peer, Done}]} =
        lists:foldl(fun(Message, {ok, State, []}) ->
            strip_observations(phi_repetition_memory:peer(Message, State))
        end, {ok, A6, []}, ReplyMessages),
    {done, BWitness, _B7, []} = phi_repetition_memory:peer(Done, B6),
    ?assertEqual(1, maps:get(correction_count, AWitness)),
    ?assertEqual(1, maps:get(crossing_corrections, AWitness)),
    ?assertEqual(1, maps:get(logical_x_parity, AWitness)),
    ?assertEqual(1, maps:get(logical_x_parity, BWitness)).

%% Preserve every fixed-layout coordinator packet across encoding.
-spec peer_codec_round_trips_closed_vocabulary_test() -> ok.
peer_codec_round_trips_closed_vocabulary_test() ->
    Messages = [
        {hello, a},
        {hello, b},
        start,
        start_ack,
        {correction, 7, 16, 2, ?PHI_EAST_MASK, 3, true},
        {ack, 7},
        {quiet, 18},
        {ready, 18},
        {query, ?REQUEST, 18},
        {reply, ?REQUEST, 4, 1},
        {done, 18, 1, 3}
    ],
    lists:foreach(fun(Message) ->
        ?assertEqual(Message, phi_repetition_memory:decode_peer(
            phi_repetition_memory:encode_peer(Message)))
    end, Messages),
    ?assertError({peer_packet, <<255>>}, phi_repetition_memory:decode_peer(<<255>>)).

%% Reject a correction replay before the Pauli update can cancel itself.
-spec duplicate_correction_fails_before_fence_test() -> ok.
duplicate_correction_fails_before_fence_test() ->
    {A0, _} = new(a, [0, 1, 2], {0, 0, 2, 0}),
    Correction = #phi_correction{step = 16, x = 0, y = 0, direction = ?PHI_WEST_MASK},
    {ok, A1, _} = phi_repetition_memory:event(decoder_events, Correction, A0),
    ?assertMatch(
        {error, duplicate_correction, _},
        phi_repetition_memory:event(decoder_events, Correction, A1)
    ).

%% Construct one role with the physical 3+3 experiment contract.
-spec new(a | b, [0..5], {0..5, 0, 0..5, 0}) -> {map(), tuple()}.
new(Role, Coordinates, Rectangle) ->
    phi_repetition_memory:new(#{
        role => Role,
        size => 6,
        coordinates => Coordinates,
        rectangle => Rectangle,
        first_quiet_step => 16,
        request_id => ?REQUEST
    }).

%% Feed a complete quiet/empty local round and retain only peer effects.
-spec quiet_round(map()) -> {map(), [tuple()]}.
quiet_round(State = #{coordinates := Coordinates}) ->
    lists:foldl(fun(X, {Current, Effects}) ->
        {ok, Next, NewEffects} = phi_repetition_memory:event(
            decoder_events,
            #phi_status{step = ?STEP, x = X, y = 0, flags = ?PHENOM_QUIET_MASK},
            Current
        ),
        {Next, Effects ++ NewEffects}
    end, {State, []}, Coordinates).

%% Deliver all local replies and return role-B peer reply packets.
-spec local_replies(map(), map()) -> {map(), map(), [tuple()]}.
local_replies(A0, B0) ->
    {A1, _AObservations} = role_replies([0, 1, 2], A0),
    {B1, Effects} = role_replies([3, 4, 5], B0),
    Messages = [Message || {peer, Message} <- Effects],
    {A1, B1, Messages}.

%% Use odd total parity while preserving deterministic reply order.
-spec role_replies([0..5], map()) -> {map(), [tuple()]}.
role_replies(Coordinates, State) ->
    lists:foldl(fun(X, {Current, Effects}) ->
        Bit = case X of 5 -> 1; _ -> 0 end,
        Transition = phi_repetition_memory:event(
            data_measurements,
            #pauli_reply{request_id = ?REQUEST, x = X, y = 0, anticommutes = Bit},
            Current
        ),
        case Transition of
            {ok, Next, NewEffects} -> {Next, Effects ++ NewEffects};
            {done, _Witness, Next, NewEffects} -> {Next, Effects ++ NewEffects}
        end
    end, {State, []}, Coordinates).

%% Discard human-readable observations when folding peer replies.
-spec strip_observations(phi_repetition_memory:transition()) ->
    phi_repetition_memory:transition().
strip_observations({ok, State, Effects}) ->
    {ok, State, [Effect || Effect <- Effects, element(1, Effect) =/= observation]};
strip_observations({done, Witness, State, Effects}) ->
    {done, Witness, State,
     [Effect || Effect <- Effects, element(1, Effect) =/= observation]};
strip_observations(Error) -> Error.
