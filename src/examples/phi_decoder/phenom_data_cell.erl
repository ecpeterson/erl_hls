%%%% phenom_data_cell.erl
%%%%
%%%% One data-qubit noise source for a periodic phenomenological-noise mesh.

-module(phenom_data_cell).
-moduledoc """
A source-aware data-qubit cell for a small phenomenological-noise experiment.

## Protocol

The cell begins in `configuring`. A one-shot configuration supplies a nonzero
PRNG seed, a `u32` Bernoulli threshold, and the cell's lattice coordinate.
Neighbor queries which arrive before that configuration are retained in the
bounded mailbox.

In `collecting`, the cell accepts one query for its current step from each of
the four logical directions. The source masks identify edges rather than
processes, so a small periodic CPU topology may connect more than one edge to
the same PID. Duplicate, invalid, and stale queries fail the cell. A query for
the immediately following step is postponed.

The fourth distinct query normally advances `hls_prng:xorshift32/1` exactly
once. The round reports an error when the next random word is less than the
configured threshold. Each present binary event is interpreted as Pauli Y and
multiplied into the cell's cumulative Pauli frame. Endpoint-local
`pauli_update` messages multiply decoder corrections into that same frame.
Entering `reporting` casts the event to all four adjacent syndrome cells, with
each message labelled by the incoming edge as seen by its recipient.

A `noise_cutoff` names the first quiet step. It is consumed immediately when
received ahead of that step; at and after the boundary the actor injects zero
noise and stops advancing its PRNG. Every data reply carries that persistent
quiet state through the downstream syndrome and phi status, certifying the
whole noise neighborhood.

Once the cutoff has applied, a controller may query whether the stable
cumulative Pauli anticommutes with a requested measurement. A query has no
round number and is accepted from either protocol phase. The short `replying`
phase emits the reply immediately, then preserves whether the data protocol
was collecting the current round or reporting the preceding one. Further
queries repeat that phase boundary and therefore preserve reply order.

This cell still models one binary physical-error event per round. Applying
decoder corrections is endpoint-local; the topology controller remains
responsible for ordering all correction updates before admitting a final
logical query.
""".

-include("phi_protocol.hrl").

-export([
    start_link/0,
    start_link/1,
    connect/2,
    stop/1,
    configure/3,
    configure/5,
    offer_query/3,
    noise_cutoff/2,
    pauli_query/3,
    pauli_update/2,
    runtime_info/1
]).
-export([init/1, handle_enter/3, handle_cast/3]).

-define(MAILBOX_CAPACITY, 5).
-define(U16_MASK, 16#ffff).
-define(U32_MASK, 16#ffffffff).
-define(REPLY_FROM_COLLECTING, 1).
-define(REPLY_FROM_REPORTING, 2).

-behavior(hls_statem).
-hls_data(data_cell).
-hls_phases([configuring, collecting, reporting, replying]).
-hls_outputs([north, east, west, south, measurement]).
-hls_mailbox_capacity(?MAILBOX_CAPACITY).
-compile({parse_transform, hls_pack}).

%% TODO: Add the other Pauli channel(s) once the surrounding experiment
%% distinguishes their syndrome neighborhoods.
%% TODO: Fence logical snapshots with noise disable plus a decoder/transport
%% drain witness; zero live anyons alone does not close an epoch.
%% TODO: Pack hls_pauli as a genuine u2 once hls_pack supports non-byte-aligned
%% record fields; until then an external update/query must reject invalid u32
%% encodings at this untrusted boundary.

-record(data_cell, {
    step = hls_type:zero() :: hls_nums:u32(),
    seen_sources = hls_type:zero() :: hls_nums:u32(),
    threshold = hls_type:zero() :: hls_nums:u32(),
    event = hls_type:zero() :: hls_nums:u32(),
    random_state = hls_type:zero() :: hls_nums:u32(),
    x = hls_type:zero() :: hls_nums:u16(),
    y = hls_type:zero() :: hls_nums:u16(),
    accumulated_pauli = hls_type:zero() :: hls_pauli:pauli(),
    reply_request_id = hls_type:zero() :: hls_nums:u32(),
    reply_anticommutes = hls_type:zero() :: hls_nums:u32(),
    reply_resume = hls_type:zero() :: hls_nums:u32(),
    noise_disabled = hls_type:zero() :: hls_nums:u32(),
    cutoff_armed = hls_type:zero() :: hls_nums:u32(),
    cutoff_step = hls_type:zero() :: hls_nums:u32()
}).

-type phase() :: configuring | collecting | reporting | replying.
-type directive() :: consume | postpone | fail.
-type conclusion() ::
    {phase(), #data_cell{}, directive()} |
    {repeat_phase, #data_cell{}, consume}.
-type neighbors() :: #{
    north := pid(),
    east := pid(),
    west := pid(),
    south := pid(),
    measurement := pid()
}.
-type direction() :: north | east | west | south.

%%%
%%% CPU interface
%%%

-doc "Starts a data cell whose outputs will be connected later.".
-spec start_link() -> {ok, pid()}.
start_link() ->
    hls_statem:start_link(
        ?MODULE,
        [],
        [{mailbox_capacity, ?MAILBOX_CAPACITY}]
    ).

-doc "Starts and immediately connects one process per named output.".
-spec start_link(neighbors()) -> {ok, pid()}.
start_link(Neighbors) ->
    case valid_neighbors(Neighbors) of
        true ->
            Options = [
                {mailbox_capacity, ?MAILBOX_CAPACITY},
                {outputs, Neighbors}
            ],
            hls_statem:start_link(?MODULE, [], Options);
        false ->
            error(badarg)
    end.

-doc "Connects a deferred cell to its adjacent syndromes and measurement sink.".
-spec connect(pid(), neighbors()) -> ok | {error, already_connected}.
connect(PID, Neighbors) ->
    case valid_neighbors(Neighbors) of
        true -> hls_statem:connect(PID, Neighbors);
        false -> error(badarg)
    end.

-spec stop(pid()) -> ok.
stop(PID) ->
    hls_statem:stop(PID).

-doc "Configures the nonzero PRNG seed and Bernoulli threshold.".
-spec configure(pid(), hls_nums:u32(), hls_nums:u32()) -> ok.
configure(PID, Seed, Threshold) ->
    configure(PID, Seed, Threshold, 0, 0).

-doc "Configures the PRNG, threshold, and lattice coordinate.".
-spec configure(
    pid(),
    hls_nums:u32(),
    hls_nums:u32(),
    hls_nums:u16(),
    hls_nums:u16()
) -> ok.
configure(PID, Seed, Threshold, X, Y)
        when Seed > 0, Seed =< ?U32_MASK,
             Threshold >= 0, Threshold =< ?U32_MASK,
             X >= 0, X =< ?U16_MASK,
             Y >= 0, Y =< ?U16_MASK ->
    hls_statem:cast(PID, #phenom_config{
        seed = Seed,
        threshold = Threshold,
        x = X,
        y = Y
    });
configure(_PID, _Seed, _Threshold, _X, _Y) ->
    error(badarg).

-doc "Offers a step query from one logical direction.".
-spec offer_query(pid(), hls_nums:u32(), direction()) -> ok.
offer_query(PID, Step, Source)
        when Step >= 0, Step =< ?U32_MASK ->
    hls_statem:cast(PID, #phenom_query{
        step = Step,
        source = source_mask(Source)
    });
offer_query(_PID, _Step, _Source) ->
    error(badarg).

-doc "Arms the first round which must inject no new physical noise.".
-spec noise_cutoff(pid(), hls_nums:u32()) -> ok.
noise_cutoff(PID, FirstQuietStep)
        when FirstQuietStep >= 0, FirstQuietStep =< ?U32_MASK ->
    hls_statem:cast(PID, #noise_cutoff{
        first_quiet_step = FirstQuietStep
    });
noise_cutoff(_PID, _FirstQuietStep) ->
    error(badarg).

-doc "Queries the stable cumulative physical-and-correction Pauli frame.".
-spec pauli_query(
    pid(),
    hls_nums:u32(),
    hls_pauli:pauli()
) -> ok.
pauli_query(PID, RequestId, Measurement)
        when RequestId >= 0, RequestId =< ?U32_MASK ->
    hls_statem:cast(PID, #pauli_query{
        request_id = RequestId,
        measurement = Measurement
    });
pauli_query(_PID, _RequestId, _Measurement) ->
    error(badarg).

-doc "Multiplies one endpoint-local decoder correction into the Pauli frame.".
-spec pauli_update(pid(), hls_pauli:pauli()) -> ok.
pauli_update(PID, Pauli) ->
    hls_statem:cast(PID, #pauli_update{pauli = Pauli}).

-doc "Returns diagnostic data from the bounded CPU scheduler.".
-spec runtime_info(pid()) -> map().
runtime_info(PID) ->
    hls_statem:info(PID).

%%%
%%% hls_statem callbacks
%%%

-spec init(any()) -> {ok, phase(), #data_cell{}}.
init([]) ->
    {ok, configuring, #data_cell{}}.

-spec handle_enter(phase(), phase(), #data_cell{}) ->
    hls_statem:enter_result().
handle_enter(_OldPhase, configuring, Cell) ->
    {Cell, []};
handle_enter(_OldPhase, collecting, Cell) ->
    {Cell, []};
handle_enter(_OldPhase, reporting, Cell) ->
    Message = #phenom_data{
        step = Cell#data_cell.step,
        flags = Cell#data_cell.event bor
            (Cell#data_cell.noise_disabled bsl 1)
    },
    {Cell, [
        {cast, north, Message#phenom_data{source = ?PHI_SOUTH_MASK}},
        {cast, east, Message#phenom_data{source = ?PHI_WEST_MASK}},
        {cast, west, Message#phenom_data{source = ?PHI_EAST_MASK}},
        {cast, south, Message#phenom_data{source = ?PHI_NORTH_MASK}}
    ]};
handle_enter(_OldPhase, replying, Cell) ->
    Reply = #pauli_reply{
        request_id = Cell#data_cell.reply_request_id,
        x = Cell#data_cell.x,
        y = Cell#data_cell.y,
        anticommutes = Cell#data_cell.reply_anticommutes
    },
    {Cell, [{cast, measurement, Reply}]}.

-spec handle_cast(
    #phenom_config{} | #phenom_query{} | #pauli_query{} |
        #noise_cutoff{} | #pauli_update{},
    phase(),
    #data_cell{}
) ->
    conclusion().
handle_cast(
    #phenom_config{seed = Seed, threshold = Threshold, x = X, y = Y},
    configuring,
    Cell
) when Seed > 0 ->
    Configured = Cell#data_cell{
        threshold = Threshold,
        random_state = Seed,
        x = X,
        y = Y,
        accumulated_pauli = hls_pauli:i()
    },
    {collecting, Configured, consume};
handle_cast(#phenom_config{}, configuring, Cell) ->
    {configuring, Cell, fail};
handle_cast(
    #phenom_query{step = 0},
    configuring,
    Cell
) ->
    {configuring, Cell, postpone};
handle_cast(#phenom_query{}, configuring, Cell) ->
    {configuring, Cell, fail};
handle_cast(#pauli_query{}, configuring, Cell) ->
    {configuring, Cell, fail};
handle_cast(#noise_cutoff{}, configuring, Cell) ->
    {configuring, Cell, fail};
handle_cast(#pauli_update{}, configuring, Cell) ->
    {configuring, Cell, fail};

handle_cast(
    #noise_cutoff{
        first_quiet_step = FirstQuietStep
    },
    collecting,
    Cell = #data_cell{
        step = Step,
        noise_disabled = 0,
        cutoff_armed = 0
    }
) when FirstQuietStep >= Step ->
    {collecting, Cell#data_cell{
        cutoff_armed = 1,
        cutoff_step = FirstQuietStep
    }, consume};
handle_cast(#noise_cutoff{}, collecting, Cell) ->
    {collecting, Cell, fail};
handle_cast(#pauli_update{pauli = Pauli}, collecting, Cell) ->
    case hls_pauli:is_pauli(Pauli) of
        true ->
            {collecting, Cell#data_cell{
                accumulated_pauli = hls_pauli:multiply(
                    Cell#data_cell.accumulated_pauli,
                    Pauli
                )
            }, consume};
        false ->
            {collecting, Cell, fail}
    end;
handle_cast(
    #phenom_query{step = Step, source = Source},
    collecting,
    Cell = #data_cell{step = Step, seen_sources = Seen}
) when (Source =:= ?PHI_NORTH_MASK orelse
        Source =:= ?PHI_EAST_MASK orelse
        Source =:= ?PHI_WEST_MASK orelse
        Source =:= ?PHI_SOUTH_MASK),
       Seen band Source =:= 0 ->
    NewSeen = Seen bor Source,
    case NewSeen =:= ?PHI_ALL_DIRECTIONS of
        false ->
            {collecting, Cell#data_cell{
                seen_sources = NewSeen
            }, consume};
        true ->
            CutoffApplies = Cell#data_cell.cutoff_armed =:= 1 andalso
                Step >= Cell#data_cell.cutoff_step,
            NoiseDisabled = Cell#data_cell.noise_disabled =:= 1 orelse
                CutoffApplies,
            NoiseDisabledWord = case NoiseDisabled of
                false -> hls_type:as(hls_nums:u32(), 0);
                true -> hls_type:as(hls_nums:u32(), 1)
            end,
            NextRandom = case NoiseDisabled of
                true -> Cell#data_cell.random_state;
                false -> hls_prng:xorshift32(
                    Cell#data_cell.random_state
                )
            end,
            Event = case NoiseDisabled of
                true -> hls_type:as(hls_nums:u32(), 0);
                false -> case NextRandom < Cell#data_cell.threshold of
                    false -> hls_type:as(hls_nums:u32(), 0);
                    true -> hls_type:as(hls_nums:u32(), 1)
                end
            end,
            AccumulatedPauli = case Event of
                1 -> hls_pauli:multiply(
                    Cell#data_cell.accumulated_pauli,
                    hls_pauli:y()
                );
                _ -> Cell#data_cell.accumulated_pauli
            end,
            Completed = Cell#data_cell{
                seen_sources = NewSeen,
                event = Event,
                random_state = NextRandom,
                accumulated_pauli = AccumulatedPauli,
                noise_disabled = NoiseDisabledWord,
                cutoff_armed = case CutoffApplies of
                    false -> Cell#data_cell.cutoff_armed;
                    true -> hls_type:as(hls_nums:u32(), 0)
                end
            },
            {reporting, Completed, consume}
    end;
handle_cast(
    #phenom_query{step = QueryStep},
    collecting,
    Cell = #data_cell{step = Step}
) when QueryStep =:= ((Step + 1) band ?U32_MASK) ->
    {collecting, Cell, postpone};
handle_cast(#phenom_query{}, collecting, Cell) ->
    {collecting, Cell, fail};
handle_cast(
    #pauli_query{
        request_id = RequestId,
        measurement = Measurement
    },
    collecting,
    Cell = #data_cell{noise_disabled = 1}
) ->
    case hls_pauli:is_pauli(Measurement) of
        true ->
            Replying = Cell#data_cell{
                reply_request_id = RequestId,
                reply_anticommutes = case hls_pauli:anticommutes(
                    Cell#data_cell.accumulated_pauli,
                    Measurement
                ) of
                    false -> hls_type:as(hls_nums:u32(), 0);
                    true -> hls_type:as(hls_nums:u32(), 1)
                end,
                reply_resume = ?REPLY_FROM_COLLECTING
            },
            {replying, Replying, consume};
        false ->
            {collecting, Cell, fail}
    end;
handle_cast(#pauli_query{}, collecting, Cell) ->
    {collecting, Cell, fail};

handle_cast(
    #noise_cutoff{
        first_quiet_step = FirstQuietStep
    },
    reporting,
    Cell = #data_cell{
        step = Step,
        noise_disabled = 0,
        cutoff_armed = 0
    }
) when FirstQuietStep > Step ->
    {reporting, Cell#data_cell{
        cutoff_armed = 1,
        cutoff_step = FirstQuietStep
    }, consume};
handle_cast(#noise_cutoff{}, reporting, Cell) ->
    {reporting, Cell, fail};
handle_cast(#pauli_update{pauli = Pauli}, reporting, Cell) ->
    case hls_pauli:is_pauli(Pauli) of
        true ->
            {reporting, Cell#data_cell{
                accumulated_pauli = hls_pauli:multiply(
                    Cell#data_cell.accumulated_pauli,
                    Pauli
                )
            }, consume};
        false ->
            {reporting, Cell, fail}
    end;
handle_cast(
    #phenom_query{step = QueryStep, source = Source},
    reporting,
    Cell = #data_cell{step = Step}
) when QueryStep =:= ((Step + 1) band ?U32_MASK),
       (Source =:= ?PHI_NORTH_MASK orelse
        Source =:= ?PHI_EAST_MASK orelse
        Source =:= ?PHI_WEST_MASK orelse
        Source =:= ?PHI_SOUTH_MASK) ->
    Collecting = Cell#data_cell{
        step = QueryStep,
        seen_sources = Source,
        event = 0
    },
    {collecting, Collecting, consume};
handle_cast(#phenom_query{}, reporting, Cell) ->
    {reporting, Cell, fail};
handle_cast(
    #pauli_query{
        request_id = RequestId,
        measurement = Measurement
    },
    reporting,
    Cell = #data_cell{noise_disabled = 1}
) ->
    case hls_pauli:is_pauli(Measurement) of
        true ->
            Replying = Cell#data_cell{
                reply_request_id = RequestId,
                reply_anticommutes = case hls_pauli:anticommutes(
                    Cell#data_cell.accumulated_pauli,
                    Measurement
                ) of
                    false -> hls_type:as(hls_nums:u32(), 0);
                    true -> hls_type:as(hls_nums:u32(), 1)
                end,
                reply_resume = ?REPLY_FROM_REPORTING
            },
            {replying, Replying, consume};
        false ->
            {reporting, Cell, fail}
    end;
handle_cast(#pauli_query{}, reporting, Cell) ->
    {reporting, Cell, fail};

handle_cast(#phenom_config{}, replying, Cell) ->
    {replying, Cell, fail};
handle_cast(
    #phenom_query{step = Step, source = Source},
    replying,
    Cell = #data_cell{
        step = Step,
        seen_sources = Seen,
        reply_resume = ?REPLY_FROM_COLLECTING
    }
) when (Source =:= ?PHI_NORTH_MASK orelse
        Source =:= ?PHI_EAST_MASK orelse
        Source =:= ?PHI_WEST_MASK orelse
        Source =:= ?PHI_SOUTH_MASK),
       Seen band Source =:= 0 ->
    NewSeen = Seen bor Source,
    case NewSeen =:= ?PHI_ALL_DIRECTIONS of
        false ->
            {replying, Cell#data_cell{seen_sources = NewSeen}, consume};
        true ->
            {reporting, Cell#data_cell{
                seen_sources = NewSeen,
                event = hls_type:as(hls_nums:u32(), 0)
            }, consume}
    end;
handle_cast(
    #phenom_query{step = QueryStep},
    replying,
    Cell = #data_cell{
        step = Step,
        reply_resume = ?REPLY_FROM_COLLECTING
    }
) when QueryStep =:= ((Step + 1) band ?U32_MASK) ->
    {replying, Cell, postpone};
handle_cast(
    #phenom_query{step = QueryStep, source = Source},
    replying,
    Cell = #data_cell{
        step = Step,
        reply_resume = ?REPLY_FROM_REPORTING
    }
) when QueryStep =:= ((Step + 1) band ?U32_MASK),
       (Source =:= ?PHI_NORTH_MASK orelse
        Source =:= ?PHI_EAST_MASK orelse
        Source =:= ?PHI_WEST_MASK orelse
        Source =:= ?PHI_SOUTH_MASK) ->
    Collecting = Cell#data_cell{
        step = QueryStep,
        seen_sources = Source,
        event = 0
    },
    {collecting, Collecting, consume};
handle_cast(#phenom_query{}, replying, Cell) ->
    {replying, Cell, fail};
handle_cast(#noise_cutoff{}, replying, Cell) ->
    {replying, Cell, fail};
handle_cast(#pauli_update{pauli = Pauli}, replying, Cell) ->
    case hls_pauli:is_pauli(Pauli) of
        true ->
            {replying, Cell#data_cell{
                accumulated_pauli = hls_pauli:multiply(
                    Cell#data_cell.accumulated_pauli,
                    Pauli
                )
            }, consume};
        false ->
            {replying, Cell, fail}
    end;
handle_cast(
    #pauli_query{
        request_id = RequestId,
        measurement = Measurement
    },
    replying,
    Cell = #data_cell{noise_disabled = 1}
) ->
    case hls_pauli:is_pauli(Measurement) of
        true ->
            Replying = Cell#data_cell{
                reply_request_id = RequestId,
                reply_anticommutes = case hls_pauli:anticommutes(
                    Cell#data_cell.accumulated_pauli,
                    Measurement
                ) of
                    false -> hls_type:as(hls_nums:u32(), 0);
                    true -> hls_type:as(hls_nums:u32(), 1)
                end
            },
            {repeat_phase, Replying, consume};
        false ->
            {replying, Cell, fail}
    end;
handle_cast(#pauli_query{}, replying, Cell) ->
    {replying, Cell, fail}.

source_mask(north) -> ?PHI_NORTH_MASK;
source_mask(east) -> ?PHI_EAST_MASK;
source_mask(west) -> ?PHI_WEST_MASK;
source_mask(south) -> ?PHI_SOUTH_MASK;
source_mask(_Direction) -> error(badarg).

valid_neighbors(Neighbors) ->
    is_map(Neighbors) andalso
        lists:sort(maps:keys(Neighbors)) =:=
            lists:sort([north, east, west, south, measurement]) andalso
        lists:all(fun is_pid/1, maps:values(Neighbors)).
