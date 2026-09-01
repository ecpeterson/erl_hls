%%%% phi_memory_experiment
%%%%
%%%% Pure host-side closeout protocol for the phi memory-demo fixture.

-module(phi_memory_experiment).
-moduledoc """
Reduces phi/noise output events into the commands needed to finish one memory
experiment and measure one caller-selected horizontal data row. The caller is
responsible for choosing a row and Pauli which represent the intended
nontrivial logical operator; this plumbing reducer does not prove homology.
Its `distance` option must come from the active normalized topology. The pure
reducer cannot discover or verify that deployment fact on its own.

This module is deliberately a pure, example-local protocol reducer. `new/1`
returns the whole-fabric noise cutoff. Each later `event/3` returns zero or
more commands which a runner must submit, in order, to the one externally
addressed `control_router` service before supplying the next event. The runner
is the ordinary ERTS destination; the target and rectangle inside each command
are FPGA-local multicast selectors.

The runner must continuously drain every external output, including the two
announcement streams which this reducer otherwise ignores. Those diagnostic
branches share lossless fanout with the decoder and can backpressure it.

Sparse decoder corrections are immediately translated into point-addressed
data-qubit Pauli updates. A complete status round from both decoder planes is a
closeout fence only when every coordinate reports both `quiet = 1` and
`present = 0`. Correction and status share one ordered output per plane, so at
that point every earlier correction has crossed the output boundary. The
resulting line query follows all update commands on the one serialized ingress.

The fence is a safety condition, not a convergence guarantee. The current
fixed-round decoder can leave symmetric nonempty configurations stationary, so
a runner must impose an experiment timeout and report nonconvergence when no
quiet, empty status round arrives.

The reducer assumes one lossless, non-restarting local fabric activation. It
does not define retries, process generations, multi-FPGA multicast, or a PL-PS
wire envelope. Reset or gateway failure must abort and restart the experiment.
""".

-include("phi_protocol.hrl").

-export([new/1, event/3]).
-export_type([options/0, command/0, state/0, result/0]).

-define(U32_MASK, 16#ffffffff).

-type stream() ::
    x_announcements |
    z_announcements |
    x_decoder_events |
    z_decoder_events |
    data_measurements.
-type options() :: #{
    distance := pos_integer(),
    first_quiet_step := hls_nums:u32(),
    line_y := hls_nums:u16(),
    measurement := hls_pauli:pauli(),
    request_id := hls_nums:u32()
}.
-type rectangle() :: {
    non_neg_integer(),
    non_neg_integer(),
    non_neg_integer(),
    non_neg_integer()
}.
-type command() :: {
    control_router,
    data | noise,
    rectangle(),
    #noise_cutoff{} | #pauli_update{} | #pauli_query{}
}.
-type state() :: map().
-type result() ::
    {state(), [command()]} |
    {done, 0 | 1, state()} |
    {error, atom(), state()}.

-doc "Starts one closeout and returns its whole-fabric cutoff command.".
-spec new(options()) -> {state(), [command()]}.
new(#{
    distance := Distance,
    first_quiet_step := FirstQuietStep,
    line_y := LineY,
    measurement := Measurement,
    request_id := RequestId
}) when Distance > 0,
        FirstQuietStep >= 0, FirstQuietStep =< ?U32_MASK,
        LineY >= 0, LineY < 2 * Distance,
        RequestId >= 0, RequestId =< ?U32_MASK ->
    case hls_pauli:is_pauli(Measurement) of
        true ->
            State = #{
                distance => Distance,
                cutoff_step => FirstQuietStep,
                line_y => LineY,
                measurement => Measurement,
                request_id => RequestId,
                phase => draining,
                status_rounds => #{},
                closed_steps => #{},
                zero_steps => #{x => #{}, z => #{}},
                seen_corrections => #{},
                replies => #{}
            },
            Rectangle = {0, 0, Distance - 1, 2 * Distance - 1},
            {State, [{control_router, noise, Rectangle, #noise_cutoff{
                first_quiet_step = FirstQuietStep
            }}]};
        false ->
            error(badarg)
    end;
new(_Options) ->
    error(badarg).

-doc "Consumes one decoded output record and returns ordered ingress work.".
-spec event(stream(), tuple(), state()) -> result().
event(x_announcements, #phenom_anyon{}, State) ->
    {State, []};
event(z_announcements, #phenom_anyon{}, State) ->
    {State, []};
event(x_decoder_events, Event, State) ->
    decoder_event(x, Event, State);
event(z_decoder_events, Event, State) ->
    decoder_event(z, Event, State);
event(data_measurements, Reply = #pauli_reply{}, State) ->
    measurement_reply(Reply, State);
event(_Stream, _Event, State) ->
    {error, event, State}.

decoder_event(_Plane, _Event, State = #{phase := Phase})
        when Phase =:= done; Phase =:= failed ->
    {State, []};
decoder_event(Plane, Correction = #phi_correction{},
        State = #{phase := draining}) ->
    correction(Plane, Correction, State);
decoder_event(Plane, Status = #phi_status{},
        State = #{phase := draining}) ->
    status(Plane, Status, State);
decoder_event(_Plane, #phi_correction{}, State = #{phase := querying}) ->
    {error, late_correction, State#{phase := failed}};
decoder_event(_Plane, #phi_status{}, State = #{phase := querying}) ->
    {State, []};
decoder_event(_Plane, _Event, State) ->
    {error, decoder_event, State}.

correction(
    Plane,
    Correction = #phi_correction{
        step = Step,
        x = X,
        y = Y,
        direction = Direction
    },
    State = #{
        distance := Distance,
        closed_steps := Closed,
        seen_corrections := Seen
    }
) when X >= 0, X < Distance, Y >= 0, Y < Distance,
        (Direction =:= ?PHI_NORTH_MASK orelse
         Direction =:= ?PHI_EAST_MASK orelse
         Direction =:= ?PHI_WEST_MASK orelse
         Direction =:= ?PHI_SOUTH_MASK) ->
    Key = {Plane, Step, X, Y},
    case step_closed(Plane, Step, Closed) of
        true ->
            {error, late_correction, State#{phase := failed}};
        false ->
            case maps:is_key(Key, Seen) of
                true ->
                    {error, duplicate_correction, State#{phase := failed}};
                false ->
                    {{DataX, DataY}, Pauli} =
                        phi_noise_topology:correction_update(
                            Plane, Correction, Distance
                        ),
                    Command = {control_router, data,
                        {DataX, DataY, DataX, DataY},
                        #pauli_update{pauli = Pauli}},
                    {State#{seen_corrections := Seen#{Key => true}},
                        [Command]}
            end
    end;
correction(_Plane, #phi_correction{}, State) ->
    {error, correction, State#{phase := failed}}.

status(
    Plane,
    #phi_status{
        step = Step,
        x = X,
        y = Y,
        flags = Flags
    },
    State = #{
        distance := Distance,
        status_rounds := Rounds,
        closed_steps := Closed
    }
) when X >= 0, X < Distance, Y >= 0, Y < Distance,
        Flags < 4 ->
    Present = Flags band ?PHENOM_PRESENT_MASK,
    Quiet = (Flags band ?PHENOM_QUIET_MASK) bsr 1,
    Key = {Plane, Step},
    Coordinate = {X, Y},
    case step_closed(Plane, Step, Closed) of
        true ->
            {error, late_status, State#{phase := failed}};
        false ->
            Round = maps:get(Key, Rounds, #{}),
            case maps:is_key(Coordinate, Round) of
                true ->
                    {error, duplicate_status, State#{phase := failed}};
                false ->
                    UpdatedRound = Round#{Coordinate => {Present, Quiet}},
                    UpdatedRounds = Rounds#{Key => UpdatedRound},
                    Updated = State#{status_rounds := UpdatedRounds},
                    case map_size(UpdatedRound) =:= Distance * Distance of
                        false ->
                            {Updated, []};
                        true ->
                            complete_status_round(
                                Plane, Step, UpdatedRound, Updated
                            )
                    end
            end
    end;
status(_Plane, #phi_status{}, State) ->
    {error, status, State#{phase := failed}}.

complete_status_round(
    Plane,
    Step,
    Round,
    State = #{
        cutoff_step := CutoffStep,
        status_rounds := Rounds,
        closed_steps := Closed,
        zero_steps := ZeroSteps,
        seen_corrections := Seen
    }
) ->
    QuietAndEmpty = lists:all(
        fun({0, 1}) -> true; (_) -> false end,
        maps:values(Round)
    ),
    RemainingRounds = maps:remove({Plane, Step}, Rounds),
    RemainingCorrections = maps:filter(
        fun({SeenPlane, SeenStep, _X, _Y}, _Value) ->
            SeenPlane =/= Plane orelse SeenStep > Step
        end,
        Seen
    ),
    PlaneZeroSteps = maps:get(Plane, ZeroSteps),
    UpdatedPlaneZeroSteps = case QuietAndEmpty andalso Step >= CutoffStep of
        true -> PlaneZeroSteps#{Step => true};
        false -> PlaneZeroSteps
    end,
    UpdatedZeroSteps = ZeroSteps#{Plane := UpdatedPlaneZeroSteps},
    ClosedState = State#{
        status_rounds := RemainingRounds,
        closed_steps := Closed#{Plane => Step},
        zero_steps := UpdatedZeroSteps,
        seen_corrections := RemainingCorrections
    },
    maybe_query(prune_zero_steps(ClosedState)).

maybe_query(State = #{
    zero_steps := #{x := XSteps, z := ZSteps},
    distance := Distance,
    line_y := LineY,
    measurement := Measurement,
    request_id := RequestId
}) ->
    Common = lists:sort([
        Step || Step <- maps:keys(XSteps), maps:is_key(Step, ZSteps)
    ]),
    case Common of
        [] ->
            {State, []};
        [_Step | _] ->
            Query = #pauli_query{
                request_id = RequestId,
                measurement = Measurement
            },
            Command = {control_router, data,
                {0, LineY, Distance - 1, LineY}, Query},
            {State#{phase := querying}, [Command]}
    end.

prune_zero_steps(State = #{
    closed_steps := #{x := XClosed, z := ZClosed},
    zero_steps := ZeroSteps
}) ->
    Floor = min(XClosed, ZClosed),
    State#{zero_steps := maps:map(
        fun(_Plane, Steps) ->
            maps:filter(fun(Step, _Value) -> Step >= Floor end, Steps)
        end,
        ZeroSteps
    )};
prune_zero_steps(State) ->
    State.

measurement_reply(_Reply, State = #{phase := Phase})
        when Phase =:= draining; Phase =:= done; Phase =:= failed ->
    {State, []};
measurement_reply(
    #pauli_reply{
        request_id = RequestId,
        x = X,
        y = Y,
        anticommutes = Anticommutes
    },
    State = #{
        phase := querying,
        request_id := ExpectedRequestId,
        distance := Distance,
        line_y := Y,
        replies := Replies
    }
) when RequestId =:= ExpectedRequestId,
        X >= 0, X < Distance,
        Anticommutes < 2 ->
    case maps:is_key(X, Replies) of
        true ->
            {error, duplicate_reply, State#{phase := failed}};
        false ->
            UpdatedReplies = Replies#{X => Anticommutes},
            Updated = State#{replies := UpdatedReplies},
            case map_size(UpdatedReplies) =:= Distance of
                false ->
                    {Updated, []};
                true ->
                    Parity = lists:foldl(
                        fun(Value, Acc) -> Value bxor Acc end,
                        0,
                        maps:values(UpdatedReplies)
                    ),
                    Done = Updated#{phase := done},
                    {done, Parity, Done}
            end
    end;
measurement_reply(#pauli_reply{request_id = RequestId},
        State = #{phase := querying, request_id := Expected})
        when RequestId =/= Expected ->
    {State, []};
measurement_reply(#pauli_reply{}, State) ->
    {error, reply, State#{phase := failed}}.

step_closed(Plane, Step, Closed) ->
    case maps:find(Plane, Closed) of
        {ok, ClosedStep} -> Step =< ClosedStep;
        error -> false
    end.
