%%%% phi_memory_experiment
%%%%
%%%% Pure host-side closeout protocol for the phi memory-demo fixture.

-module(phi_memory_experiment).
-moduledoc """
Reduces phi/noise output events into the commands needed to finish one memory
experiment and measure every data qubit in one caller-selected Pauli basis.
The snapshot also evaluates one caller-selected horizontal row. The caller is
responsible for choosing a row and basis which represent the intended
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
resulting whole-device query follows all update commands on the one serialized
ingress. One experiment measures either X or Z. Measuring the complementary
basis requires a reset and a separate run; sequential X and Z queries would
incorrectly treat destructive physical measurements as Pauli-frame tomography.

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
-export_type([stream/0, options/0, command/0, witness/0, state/0, result/0]).

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
    measurement := x | z,
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
-type witness() :: #{
    closeout_step := hls_nums:u32(),
    corrections := [{
        x | z,
        hls_nums:u32(),
        hls_nums:u16(),
        hls_nums:u16(),
        hls_nums:u32()
    }],
    measurement := x | z,
    data_anticommutations := [
        {{hls_nums:u16(), hls_nums:u16()}, 0 | 1}
    ],
    row := #{
        y := hls_nums:u16(),
        parity := 0 | 1
    }
}.
-type state() :: map().
-type result() ::
    {state(), [command()]} |
    {done, witness(), state()} |
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
        (Measurement =:= x orelse Measurement =:= z),
        RequestId >= 0, RequestId =< ?U32_MASK ->
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
        correction_log => [],
        replies => #{}
    },
    Rectangle = {0, 0, Distance - 1, 2 * Distance - 1},
    {State, [{control_router, noise, Rectangle, #noise_cutoff{
        first_quiet_step = FirstQuietStep
    }}]};
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
decoder_event(_Plane, #phi_correction{}, State = #{phase := Phase})
        when Phase =:= querying ->
    {error, late_correction, State#{phase := failed}};
decoder_event(_Plane, #phi_status{}, State = #{phase := Phase})
        when Phase =:= querying ->
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
        seen_corrections := Seen,
        correction_log := CorrectionLog
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
                    Logged = {Plane, Step, X, Y, Direction},
                    {State#{
                        seen_corrections := Seen#{Key => true},
                        correction_log := [Logged | CorrectionLog]
                    },
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
    measurement := Measurement,
    request_id := RequestId
}) ->
    Common = lists:sort([
        Step || Step <- maps:keys(XSteps), maps:is_key(Step, ZSteps)
    ]),
    case Common of
        [] ->
            {State, []};
        [Step | _] ->
            Query = #pauli_query{
                request_id = RequestId,
                measurement = Measurement
            },
            Command = {control_router, data,
                {0, 0, Distance - 1, 2 * Distance - 1}, Query},
            {State#{phase := querying, closeout_step => Step}, [Command]}
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
        replies := Replies
    }
) when X >= 0, X < Distance, Y >= 0, Y < 2 * Distance,
        Anticommutes < 2 ->
    case RequestId =:= ExpectedRequestId of
        false ->
            {State, []};
        true ->
            collect_reply(
                {X, Y},
                Anticommutes,
                State,
                Replies,
                Distance
            )
    end;
measurement_reply(#pauli_reply{}, State = #{phase := querying}) ->
    {error, reply, State#{phase := failed}}.

collect_reply(Coordinate, Anticommutes, State, Replies, Distance) ->
    case maps:is_key(Coordinate, Replies) of
        true ->
            {error, duplicate_reply, State#{phase := failed}};
        false ->
            UpdatedReplies = Replies#{Coordinate => Anticommutes},
            Updated = State#{replies := UpdatedReplies},
            case map_size(UpdatedReplies) =:= 2 * Distance * Distance of
                false ->
                    {Updated, []};
                true ->
                    Witness = witness(Updated),
                    Done = Updated#{phase := done},
                    {done, Witness, Done}
            end
    end.

witness(#{
    closeout_step := CloseoutStep,
    correction_log := Corrections,
    replies := Replies,
    line_y := LineY,
    measurement := Measurement
}) ->
    DataAnticommutations = lists:sort(maps:to_list(Replies)),
    RowParity = lists:foldl(
        fun
            ({{_X, Y}, Anticommutes}, Parity) when Y =:= LineY ->
                Anticommutes bxor Parity;
            (_Other, Parity) ->
                Parity
        end,
        0,
        DataAnticommutations
    ),
    #{
        closeout_step => CloseoutStep,
        corrections => lists:sort(Corrections),
        measurement => Measurement,
        data_anticommutations => DataAnticommutations,
        row => #{
            y => LineY,
            parity => RowParity
        }
    }.

step_closed(Plane, Step, Closed) ->
    case maps:find(Plane, Closed) of
        {ok, ClosedStep} -> Step =< ClosedStep;
        error -> false
    end.
