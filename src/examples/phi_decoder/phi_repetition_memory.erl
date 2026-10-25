%%%% phi_repetition_memory
%%%%
%%%% Pure two-partition closeout protocol for the periodic repetition example.

-module(phi_repetition_memory).
-moduledoc """
Coordinates one logical-memory closeout across two partitions of a periodic
repetition-code line.

The reducer owns correction routing, the global quiet fence, measurement
ordering and logical parity. It has no socket or fabric dependency. Callers
execute returned effects in order: local commands before later peer messages.
Peer acknowledgements therefore certify that a cross-partition update has
entered the remote ordered command stream before either side can query data.

The protocol assumes one lossless, ordered peer channel and one lossless,
non-restarting local partition activation per role. It performs no retry;
replaying a Pauli update would cancel it. Completion is a physical or
simulation witness for the observed activation, not decoder threshold proof.
""".

-include("phi_protocol.hrl").

-export([
    new/1,
    event/3,
    peer/2,
    progress/1,
    peer_role/1,
    encode_peer/1,
    decode_peer/1
]).
-export_type([
    role/0,
    options/0,
    command/0,
    peer_message/0,
    effect/0,
    witness/0,
    state/0,
    transition/0
]).

 -doc "Identifies one half of the two-partition experiment.".
-type role() :: a | b.

%% One contiguous row segment owned by a role.
-type rectangle() :: {
    hls_nums:u16(),
    0,
    hls_nums:u16(),
    0
}.

-doc "Configures role ownership, line geometry, cutoff and measurement identity.".
-type options() :: #{
    role := role(),
    size := 2 .. ((1 bsl 16) - 1),
    coordinates := [hls_nums:u16()],
    rectangle := rectangle(),
    first_quiet_step := hls_nums:u32(),
    request_id := hls_nums:u32()
}.

-doc "Names one ordered command for the role-local repetition topology.".
-type command() :: {
    control_router,
    data | noise,
    rectangle(),
    #noise_cutoff{} | #pauli_update{} | #pauli_query{}
}.

-doc "Names one packet in the closed ordered peer protocol.".
-type peer_message() ::
    {hello, role()} |
    start |
    start_ack |
    {correction, hls_nums:u32(), hls_nums:u32(), hls_nums:u16(),
        hls_nums:u32(), hls_nums:u16(), boolean()} |
    {ack, hls_nums:u32()} |
    {quiet, hls_nums:u32()} |
    {ready, hls_nums:u32()} |
    {query, hls_nums:u32(), hls_nums:u32()} |
    {reply, hls_nums:u32(), hls_nums:u16(), 0 | 1} |
    {done, hls_nums:u32(), 0 | 1, non_neg_integer()}.

-doc "Requests one ordered local command, peer packet or display observation.".
-type effect() ::
    {command, command()} |
    {peer, peer_message()} |
    {observation, map()}.

-doc "Summarizes the closeout step, corrections and logical-X measurement.".
-type witness() :: #{
    role := role(),
    closeout_step := hls_nums:u32(),
    correction_count := non_neg_integer(),
    logical_x_parity := 0 | 1,
    crossing_corrections => non_neg_integer(),
    measurements => #{hls_nums:u16() := 0 | 1},
    local_measurements => #{hls_nums:u16() := 0 | 1}
}.

-doc "Holds one role's pure closeout state.".
-type state() :: map().

-doc "Returns the next state and effects, completion witness, or terminal protocol error.".
-type transition() ::
    {ok, state(), [effect()]} |
    {done, witness(), state(), [effect()]} |
    {error, atom(), state()}.

-doc "Starts one partition closeout and returns its role-local cutoff command.".
-spec new(options()) -> {state(), command()}.
new(#{
    role := Role,
    size := Size,
    coordinates := Coordinates,
    rectangle := Rectangle = {First, 0, Last, 0},
    first_quiet_step := FirstQuietStep,
    request_id := RequestId
}) when (Role =:= a orelse Role =:= b),
        Size >= 2, Size =< 16#ffff,
        FirstQuietStep >= 0, FirstQuietStep =< 16#ffffffff,
        RequestId >= 0, RequestId =< 16#ffffffff,
        First >= 0, Last < Size, First =< Last ->
    Coordinates = lists:seq(First, Last),
    true = Coordinates =/= [],
    State = #{
        role => Role,
        size => Size,
        coordinates => Coordinates,
        rectangle => Rectangle,
        first_quiet_step => FirstQuietStep,
        request_id => RequestId,
        rounds => #{},
        local_quiet => #{},
        peer_quiet => #{},
        pending => #{},
        next_sequence => 1,
        ready_step => none,
        peer_ready_step => none,
        query_step => none,
        corrections => [],
        seen_corrections => #{},
        local_replies => #{},
        peer_replies => #{},
        events => 0
    },
    Cutoff = {control_router, noise, Rectangle, #noise_cutoff{
        first_quiet_step = FirstQuietStep
    }},
    {State, Cutoff};
new(_Options) ->
    error(badarg).

-doc "Consumes one local decoded partition event and returns ordered effects.".
-spec event(atom(), tuple(), state()) -> transition().
event(decoder_events, Correction = #phi_correction{}, State) ->
    correction(Correction, State);
event(decoder_events, Status = #phi_status{}, State) ->
    status(Status, State);
event(data_measurements, Reply = #pauli_reply{}, State) ->
    measurement(Reply, State);
event(_Stream, _Event, State = #{events := Events}) ->
    {ok, State#{events := Events + 1}, []}.

-doc "Consumes one decoded ordered peer message and returns ordered effects.".
-spec peer(peer_message(), state()) -> transition().
peer({correction, Sequence, Step, X, Direction, DataX, Apply},
        State = #{role := Role, size := Size, coordinates := Coordinates,
                  corrections := Corrections}) ->
    Correction = #phi_correction{step = Step, x = X, y = 0, direction = Direction},
    {{DataX, 0}, z} = phi_repetition_topology:correction_update(Correction, Size),
    true = (Apply =:= true) =:= lists:member(DataX, Coordinates),
    Entry = correction_observation(peer_role(Role), Correction, DataX, Apply),
    Updated = State#{corrections := [Entry | Corrections]},
    case Apply of
        true ->
            none = maps:get(ready_step, State),
            {ok, Updated, [
                {command, update_command(DataX)},
                {peer, {ack, Sequence}},
                {observation, Entry}
            ]};
        false ->
            {ok, Updated, [{observation, Entry}]}
    end;
peer({ack, Sequence}, State = #{pending := Pending}) ->
    case maps:is_key(Sequence, Pending) of
        true -> maybe_ready(State#{pending := maps:remove(Sequence, Pending)}, []);
        false -> {error, acknowledgement, State}
    end;
peer({quiet, Step}, State = #{peer_quiet := Quiet}) ->
    maybe_ready(State#{peer_quiet := Quiet#{Step => true}}, []);
peer({ready, Step}, State) ->
    maybe_query(State#{peer_ready_step := Step}, []);
peer({query, Request, Step},
        State = #{role := b, request_id := Request, ready_step := Step,
                  peer_ready_step := Step, query_step := none,
                  rectangle := Rectangle}) ->
    {ok, State#{query_step := Step}, [{command, query_command(Rectangle, Request)}]};
peer({reply, Request, X, Bit},
        State = #{role := a, request_id := Request, coordinates := Coordinates,
                  peer_replies := Replies}) when Bit =:= 0; Bit =:= 1 ->
    false = lists:member(X, Coordinates),
    case maps:is_key(X, Replies) of
        true -> {error, duplicate_reply, State};
        false ->
            Observation = measurement_observation(b, X, Bit),
            maybe_finish(State#{peer_replies := Replies#{X => Bit}},
                         [{observation, Observation}])
    end;
peer({done, Step, Parity, Count}, State = #{role := b}) ->
    Witness = #{
        role => b,
        closeout_step => Step,
        correction_count => Count,
        logical_x_parity => Parity,
        local_measurements => maps:get(local_replies, State)
    },
    {done, Witness, State, []};
peer(_Message, State) ->
    {error, peer_message, State}.

-doc "Returns bounded public progress for timeout diagnostics.".
-spec progress(state()) -> map().
progress(State) ->
    #{
        role => maps:get(role, State),
        events => maps:get(events, State),
        pending_updates => map_size(maps:get(pending, State)),
        ready_step => maps:get(ready_step, State),
        peer_ready_step => maps:get(peer_ready_step, State),
        query_step => maps:get(query_step, State),
        correction_count => length(maps:get(corrections, State)),
        local_replies => maps:get(local_replies, State),
        peer_replies => maps:get(peer_replies, State)
    }.

-doc "Returns the only peer role in the two-partition protocol.".
-spec peer_role(role()) -> role().
peer_role(a) -> b;
peer_role(b) -> a.

-doc "Encodes one message from the closed peer protocol vocabulary.".
-spec encode_peer(peer_message()) -> binary().
encode_peer({hello, a}) -> <<1, 0>>;
encode_peer({hello, b}) -> <<1, 1>>;
encode_peer(start) -> <<2>>;
encode_peer(start_ack) -> <<3>>;
encode_peer({correction, Sequence, Step, X, Direction, DataX, Apply}) ->
    <<4, Sequence:32/little, Step:32/little, X:16/little,
      Direction:8, DataX:16/little, (boolean_bit(Apply)):8>>;
encode_peer({ack, Sequence}) -> <<5, Sequence:32/little>>;
encode_peer({quiet, Step}) -> <<6, Step:32/little>>;
encode_peer({ready, Step}) -> <<7, Step:32/little>>;
encode_peer({query, Request, Step}) -> <<8, Request:32/little, Step:32/little>>;
encode_peer({reply, Request, X, Bit}) ->
    <<9, Request:32/little, X:16/little, Bit:8>>;
encode_peer({done, Step, Parity, Count}) ->
    <<10, Step:32/little, Parity:8, Count:32/little>>.

-doc "Decodes one exact-length peer packet without deserializing terms.".
-spec decode_peer(binary()) -> peer_message().
decode_peer(<<1, 0>>) -> {hello, a};
decode_peer(<<1, 1>>) -> {hello, b};
decode_peer(<<2>>) -> start;
decode_peer(<<3>>) -> start_ack;
decode_peer(<<4, Sequence:32/little, Step:32/little, X:16/little,
              Direction:8, DataX:16/little, Apply:8>>) when Apply =< 1 ->
    {correction, Sequence, Step, X, Direction, DataX, Apply =:= 1};
decode_peer(<<5, Sequence:32/little>>) -> {ack, Sequence};
decode_peer(<<6, Step:32/little>>) -> {quiet, Step};
decode_peer(<<7, Step:32/little>>) -> {ready, Step};
decode_peer(<<8, Request:32/little, Step:32/little>>) -> {query, Request, Step};
decode_peer(<<9, Request:32/little, X:16/little, Bit:8>>) when Bit =< 1 ->
    {reply, Request, X, Bit};
decode_peer(<<10, Step:32/little, Parity:8, Count:32/little>>) when Parity =< 1 ->
    {done, Step, Parity, Count};
decode_peer(Packet) -> error({peer_packet, Packet}).

%% Route one correction exactly once, retaining remote work until acknowledged.
-spec correction(#phi_correction{}, state()) -> transition().
correction(Correction = #phi_correction{step = Step, x = X, y = 0},
        State = #{role := Role, size := Size, coordinates := Coordinates,
                  ready_step := none, next_sequence := Sequence,
                  seen_corrections := Seen, corrections := Corrections,
                  pending := Pending, events := Events}) ->
    Key = {Step, X},
    case maps:is_key(Key, Seen) of
        true -> {error, duplicate_correction, State};
        false ->
            {{DataX, 0}, z} = phi_repetition_topology:correction_update(Correction, Size),
            Local = lists:member(DataX, Coordinates),
            Entry = correction_observation(Role, Correction, DataX, not Local),
            CommandEffects = case Local of
                true -> [{command, update_command(DataX)}];
                false -> []
            end,
            PeerEffect = {peer, {correction, Sequence, Step, X,
                Correction#phi_correction.direction, DataX, not Local}},
            UpdatedPending = case Local of
                true -> Pending;
                false -> Pending#{Sequence => {Step, X, DataX}}
            end,
            Updated = State#{
                next_sequence := Sequence + 1,
                pending := UpdatedPending,
                seen_corrections := Seen#{Key => true},
                corrections := [Entry | Corrections],
                events := Events + 1
            },
            {ok, Updated, CommandEffects ++ [PeerEffect, {observation, Entry}]}
    end;
correction(#phi_correction{}, State) ->
    {error, correction, State}.

%% Close one local status round and announce each new quiet/empty fence.
-spec status(#phi_status{}, state()) -> transition().
status(#phi_status{step = Step, x = X, y = 0, flags = Flags},
        State = #{coordinates := Coordinates, rounds := Rounds,
                  local_quiet := Quiet, first_quiet_step := FirstQuietStep,
                  events := Events}) when Flags >= 0, Flags < 4 ->
    case lists:member(X, Coordinates) of
        false -> {error, status_coordinate, State};
        true ->
            Round = maps:get(Step, Rounds, #{}),
            case maps:is_key(X, Round) of
                true -> {error, duplicate_status, State};
                false ->
                    UpdatedRound = Round#{X => Flags},
                    Nearby = trim_status_rounds(Rounds#{Step => UpdatedRound}, Step),
                    Updated = State#{rounds := Nearby, events := Events + 1},
                    Complete = lists:all(
                        fun(Coordinate) -> maps:is_key(Coordinate, UpdatedRound) end,
                        Coordinates
                    ),
                    QuietAndEmpty = Complete andalso Step >= FirstQuietStep andalso
                        lists:all(fun(Flag) -> Flag =:= ?PHENOM_QUIET_MASK end,
                                  maps:values(UpdatedRound)),
                    case QuietAndEmpty andalso not maps:is_key(Step, Quiet) of
                        true -> maybe_ready(
                            Updated#{local_quiet := Quiet#{Step => true}},
                            [{peer, {quiet, Step}}]
                        );
                        false -> {ok, Updated, []}
                    end
            end
    end;
status(#phi_status{}, State) ->
    {error, status, State}.

%% Collect one local logical-X reply or forward it to the lead role.
-spec measurement(#pauli_reply{}, state()) -> transition().
measurement(#pauli_reply{request_id = Request, x = X, y = 0,
                         anticommutes = Bit},
        State = #{request_id := Request, coordinates := Coordinates,
                  local_replies := Replies, role := Role, events := Events})
        when Bit =:= 0; Bit =:= 1 ->
    case {lists:member(X, Coordinates), maps:is_key(X, Replies)} of
        {false, _} -> {error, reply_coordinate, State};
        {true, true} -> {error, duplicate_reply, State};
        {true, false} ->
            Observation = measurement_observation(Role, X, Bit),
            Updated = State#{local_replies := Replies#{X => Bit}, events := Events + 1},
            case Role of
                a -> maybe_finish(Updated, [{observation, Observation}]);
                b -> {ok, Updated, [
                    {peer, {reply, Request, X, Bit}},
                    {observation, Observation}
                ]}
            end
    end;
measurement(#pauli_reply{}, State) ->
    {ok, State, []}.

%% Announce the earliest common quiet step after remote updates are admitted.
-spec maybe_ready(state(), [effect()]) -> transition().
maybe_ready(State = #{ready_step := none, pending := Pending,
        local_quiet := Local, peer_quiet := Peer}, Effects)
        when map_size(Pending) =:= 0 ->
    Common = lists:sort([Step || Step <- maps:keys(Local), maps:is_key(Step, Peer)]),
    case Common of
        [] -> {ok, State, Effects};
        [Step | _] ->
            maybe_query(State#{ready_step := Step}, Effects ++ [{peer, {ready, Step}}])
    end;
maybe_ready(State, Effects) -> {ok, State, Effects}.

%% Let the lead issue both ordered queries after the shared fence.
-spec maybe_query(state(), [effect()]) -> transition().
maybe_query(State = #{role := a, ready_step := Step,
        peer_ready_step := Step, query_step := none, request_id := Request,
        rectangle := Rectangle}, Effects) when is_integer(Step) ->
    {ok, State#{query_step := Step}, Effects ++ [
        {peer, {query, Request, Step}},
        {command, query_command(Rectangle, Request)}
    ]};
maybe_query(State, Effects) -> {ok, State, Effects}.

%% Complete the lead after one reply from every data coordinate.
-spec maybe_finish(state(), [effect()]) -> transition().
maybe_finish(State = #{role := a, size := Size, local_replies := Local,
        peer_replies := Peer, query_step := Step, corrections := Corrections}, Effects)
        when map_size(Local) + map_size(Peer) =:= Size, is_integer(Step) ->
    Measurements = maps:merge(Local, Peer),
    true = lists:sort(maps:keys(Measurements)) =:= lists:seq(0, Size - 1),
    Parity = logical_parity(Measurements),
    Count = length(Corrections),
    Crossing = length([ok || #{crosses_partition := true} <- Corrections]),
    Witness = #{
        role => a,
        closeout_step => Step,
        correction_count => Count,
        crossing_corrections => Crossing,
        logical_x_parity => Parity,
        measurements => Measurements
    },
    {done, Witness, State, Effects ++ [{peer, {done, Step, Parity, Count}}]};
maybe_finish(State, Effects) -> {ok, State, Effects}.

%% Apply one decoder-requested Z to an addressed data actor.
-spec update_command(hls_nums:u16()) -> command().
update_command(X) ->
    {control_router, data, {X, 0, X, 0}, #pauli_update{pauli = z}}.

%% Query this role's data rectangle in the logical-X basis.
-spec query_command(rectangle(), hls_nums:u32()) -> command().
query_command(Rectangle, Request) ->
    {control_router, data, Rectangle, #pauli_query{
        request_id = Request,
        measurement = x
    }}.

%% Describe one correction without exposing record syntax to the coordinator.
-spec correction_observation(role(), #phi_correction{}, hls_nums:u16(), boolean()) -> map().
correction_observation(Role, #phi_correction{step = Step, x = X,
        direction = Direction}, DataX, Crosses) ->
    #{
        role => Role,
        event => correction,
        step => Step,
        check => {X, 0},
        direction => direction_name(Direction),
        data => {DataX, 0},
        update => z,
        crosses_partition => Crosses
    }.

%% Describe one nondestructive data-frame measurement.
-spec measurement_observation(role(), hls_nums:u16(), 0 | 1) -> map().
measurement_observation(Role, X, Bit) ->
    #{role => Role, event => measurement, data => {X, 0},
      basis => x, anticommutes => Bit}.

%% Name the only directions admitted by the repetition topology.
-spec direction_name(hls_nums:u32()) -> east | west.
direction_name(?PHI_EAST_MASK) -> east;
direction_name(?PHI_WEST_MASK) -> west.

%% XOR the complete periodic line to evaluate its logical X.
-spec logical_parity(#{hls_nums:u16() := 0 | 1}) -> 0 | 1.
logical_parity(Measurements) ->
    lists:foldl(fun(Bit, Parity) -> Bit bxor Parity end, 0,
                maps:values(Measurements)).

%% Keep timeout state bounded while retaining plausible common fences.
-spec trim_status_rounds(map(), hls_nums:u32()) -> map().
trim_status_rounds(Rounds, Latest) ->
    maps:filter(fun(Step, _Round) -> Step + 8 >= Latest end, Rounds).

%% Encode a protocol boolean without serializing an Erlang term.
-spec boolean_bit(boolean()) -> 0 | 1.
boolean_bit(false) -> 0;
boolean_bit(true) -> 1.
