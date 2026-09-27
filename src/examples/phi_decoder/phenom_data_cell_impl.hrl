%% Shared callbacks for the grid and line wrappers; geometry is compile-time.
-include("phi_protocol.hrl").
-include("phi_neighborhood.hrl").

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
-export([
    configuring/3,
    collecting/3,
    reporting/3,
    replying/3,
    init/1
]).

-define(MAILBOX_CAPACITY, (?NEIGHBOR_COUNT + 1)).
-define(U16_MASK, 16#ffff).
-define(U32_MASK, 16#ffffffff).
-define(REPLY_FROM_COLLECTING, 1).
-define(REPLY_FROM_REPORTING, 2).

-behavior(hls_statem).
-hls_data(data_cell).
-hls_phases([configuring, collecting, reporting, replying]).
-ifdef(PHI_REPETITION).
-hls_outputs([east, west, measurement]).
-else.
-hls_outputs([north, east, west, south, measurement]).
-endif.
-ifdef(PHI_REPETITION).
-hls_mailbox_capacity(3).
-else.
-hls_mailbox_capacity(5).
-endif.
-compile({parse_transform, hls_pack}).

%% TODO: Add the other Pauli channel(s) once the surrounding experiment
%% distinguishes their syndrome neighborhoods.
%% TODO: Fence logical snapshots with noise disable plus a decoder/transport
%% drain witness; zero live anyons alone does not close an epoch.
%% TODO: Validate external Pauli codes before narrowing their logical type to u2.
%% Padded codecs permit narrow values, but truncating first would erase invalid
%% u32 encodings that the update/query guards must still reject.

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
    noise_disabled = hls_type:zero() :: hls_bool:bool(),
    cutoff_armed = hls_type:zero() :: hls_bool:bool(),
    cutoff_step = hls_type:zero() :: hls_nums:u32()
}).

%% Named protocol barriers; state entry emits each barrier's actions.
-type phase() :: configuring | collecting | reporting | replying.
-ifdef(PHI_REPETITION).
%% Required connections for the two-neighbor protocol.
-type neighbors() :: #{
    east := pid(), west := pid(),
    measurement := pid()
}.
-else.
%% Required connections for the four-neighbor protocol.
-type neighbors() :: #{
    north := pid(), east := pid(), west := pid(), south := pid(),
    measurement := pid()
}.
-endif.
%% Direction names are the actor's physically present ports.
-type direction() :: ?NEIGHBOR_TYPE.

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

-doc "Stops the CPU actor and releases its scheduler.".
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

-doc "Returns the unconfigured actor state; no protocol traffic is emitted.".
-spec init(any()) -> {ok, phase(), #data_cell{}}.
init([]) ->
    {ok, configuring, #data_cell{}}.

-doc "Accepts one valid configuration before beginning the request-paced protocol.".
-spec configuring(enter, phase(), #data_cell{}) ->
    hls_statem:enter_result(#data_cell{});
    (cast,
        #phenom_config{} | #phenom_query{} | #pauli_query{} |
            #noise_cutoff{} | #pauli_update{},
        #data_cell{}) -> hls_statem:cast_result(phase(), #data_cell{}).
configuring(enter, _OldPhase, Cell) ->
    {Cell, []};
configuring(
    cast,
    #phenom_config{seed = Seed, threshold = Threshold, x = X, y = Y},
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
configuring(cast, #phenom_config{}, Cell) ->
    {configuring, Cell, fail};
configuring(
    cast,
    #phenom_query{step = 0},
    Cell
) ->
    {configuring, Cell, postpone};
configuring(cast, #phenom_query{}, Cell) ->
    {configuring, Cell, fail};
configuring(cast, #pauli_query{}, Cell) ->
    {configuring, Cell, fail};
configuring(cast, #noise_cutoff{}, Cell) ->
    {configuring, Cell, fail};
configuring(cast, #pauli_update{}, Cell) ->
    {configuring, Cell, fail}.

-doc "Collects neighbor queries, applies corrections and serves stable Pauli queries.".
-spec collecting(enter, phase(), #data_cell{}) ->
    hls_statem:enter_result(#data_cell{});
    (cast,
        #phenom_config{} | #phenom_query{} | #pauli_query{} |
            #noise_cutoff{} | #pauli_update{},
        #data_cell{}) -> hls_statem:cast_result(phase(), #data_cell{}).
collecting(enter, _OldPhase, Cell) ->
    {Cell, []};
collecting(
    cast,
    #noise_cutoff{
        first_quiet_step = FirstQuietStep
    },
    Cell = #data_cell{
        step = Step,
        noise_disabled = false,
        cutoff_armed = false
    }
) when FirstQuietStep >= Step ->
    {collecting, Cell#data_cell{
        cutoff_armed = true,
        cutoff_step = FirstQuietStep
    }, consume};
collecting(cast, #noise_cutoff{}, Cell) ->
    {collecting, Cell, fail};
collecting(cast, #pauli_update{pauli = Pauli}, Cell) ->
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
collecting(
    cast,
    #phenom_query{step = Step, source = Source},
    Cell = #data_cell{step = Step, seen_sources = Seen}
) when ?SOURCE_VALID(Source),
       Seen band Source =:= 0 ->
    NewSeen = Seen bor Source,
    Collected = Cell#data_cell{seen_sources = NewSeen},
    {NextPhase, NextCell} = case NewSeen =:= ?NEIGHBOR_MASK of
        false -> {collecting, Collected};
        true ->
            CutoffApplies = Cell#data_cell.cutoff_armed andalso
                Step >= Cell#data_cell.cutoff_step,
            NoiseDisabled = Cell#data_cell.noise_disabled orelse
                CutoffApplies,
            {NextRandom, Event} = case NoiseDisabled of
                true -> {Cell#data_cell.random_state, 0};
                false ->
                    Sample = hls_prng:xorshift32(Cell#data_cell.random_state),
                    Hit = if
                        Sample < Cell#data_cell.threshold -> 1;
                        true -> 0
                    end,
                    {Sample, Hit}
            end,
            AccumulatedPauli = case Event of
                1 -> hls_pauli:multiply(
                    Cell#data_cell.accumulated_pauli,
                    hls_pauli:?DATA_ERROR()
                );
                _ -> Cell#data_cell.accumulated_pauli
            end,
            Completed = Collected#data_cell{
                event = Event,
                random_state = NextRandom,
                accumulated_pauli = AccumulatedPauli,
                noise_disabled = NoiseDisabled,
                cutoff_armed = Cell#data_cell.cutoff_armed andalso not CutoffApplies
            },
            {reporting, Completed}
    end,
    {NextPhase, NextCell, consume};
collecting(
    cast,
    #phenom_query{step = QueryStep},
    Cell = #data_cell{step = Step}
) when QueryStep =:= ((Step + 1) band ?U32_MASK) ->
    {collecting, Cell, postpone};
collecting(cast, #phenom_query{}, Cell) ->
    {collecting, Cell, fail};
collecting(
    cast,
    #pauli_query{
        request_id = RequestId,
        measurement = Measurement
    },
    Cell = #data_cell{noise_disabled = true}
) ->
    case hls_pauli:is_pauli(Measurement) of
        true ->
            Replying = prepare_reply(Cell, RequestId, Measurement),
            {replying, Replying#data_cell{
                reply_resume = ?REPLY_FROM_COLLECTING
            }, consume};
        false ->
            {collecting, Cell, fail}
    end;
collecting(cast, #pauli_query{}, Cell) ->
    {collecting, Cell, fail}.

-doc "Publishes the completed noise round and handles corrections, cutoffs and stable queries.".
-spec reporting(enter, phase(), #data_cell{}) ->
    hls_statem:enter_result(#data_cell{});
    (cast,
        #phenom_config{} | #phenom_query{} | #pauli_query{} |
            #noise_cutoff{} | #pauli_update{},
        #data_cell{}) -> hls_statem:cast_result(phase(), #data_cell{}).
reporting(enter, _OldPhase, Cell) ->
    QuietFlag = case Cell#data_cell.noise_disabled of
        true -> 2;
        false -> 0
    end,
    Message = #phenom_data{
        step = Cell#data_cell.step,
        flags = Cell#data_cell.event bor QuietFlag
    },
    {Cell, ?NEIGHBOR_ACTIONS(
        {cast, north, Message#phenom_data{source = ?PHI_SOUTH_MASK}},
        {cast, east, Message#phenom_data{source = ?PHI_WEST_MASK}},
        {cast, west, Message#phenom_data{source = ?PHI_EAST_MASK}},
        {cast, south, Message#phenom_data{source = ?PHI_NORTH_MASK}})};
reporting(
    cast,
    #noise_cutoff{
        first_quiet_step = FirstQuietStep
    },
    Cell = #data_cell{
        step = Step,
        noise_disabled = false,
        cutoff_armed = false
    }
) when FirstQuietStep > Step ->
    {reporting, Cell#data_cell{
        cutoff_armed = true,
        cutoff_step = FirstQuietStep
    }, consume};
reporting(cast, #noise_cutoff{}, Cell) ->
    {reporting, Cell, fail};
reporting(cast, #pauli_update{pauli = Pauli}, Cell) ->
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
reporting(
    cast,
    #phenom_query{step = QueryStep, source = Source},
    Cell = #data_cell{step = Step}
) when QueryStep =:= ((Step + 1) band ?U32_MASK),
       ?SOURCE_VALID(Source) ->
    Collecting = Cell#data_cell{
        step = QueryStep,
        seen_sources = Source,
        event = 0
    },
    {collecting, Collecting, consume};
reporting(cast, #phenom_query{}, Cell) ->
    {reporting, Cell, fail};
reporting(
    cast,
    #pauli_query{
        request_id = RequestId,
        measurement = Measurement
    },
    Cell = #data_cell{noise_disabled = true}
) ->
    case hls_pauli:is_pauli(Measurement) of
        true ->
            Replying = prepare_reply(Cell, RequestId, Measurement),
            {replying, Replying#data_cell{
                reply_resume = ?REPLY_FROM_REPORTING
            }, consume};
        false ->
            {reporting, Cell, fail}
    end;
reporting(cast, #pauli_query{}, Cell) ->
    {reporting, Cell, fail}.

-doc "Emits a Pauli-query response, then resumes the saved noise-protocol phase.".
-spec replying(enter, phase(), #data_cell{}) ->
    hls_statem:enter_result(#data_cell{});
    (cast,
        #phenom_config{} | #phenom_query{} | #pauli_query{} |
            #noise_cutoff{} | #pauli_update{},
        #data_cell{}) -> hls_statem:cast_result(phase(), #data_cell{}).
replying(enter, _OldPhase, Cell) ->
    Reply = #pauli_reply{
        request_id = Cell#data_cell.reply_request_id,
        x = Cell#data_cell.x,
        y = Cell#data_cell.y,
        anticommutes = Cell#data_cell.reply_anticommutes
    },
    {Cell, [{cast, measurement, Reply}]};
replying(cast, #phenom_config{}, Cell) ->
    {replying, Cell, fail};
replying(
    cast,
    #phenom_query{step = Step, source = Source},
    Cell = #data_cell{
        step = Step,
        seen_sources = Seen,
        reply_resume = ?REPLY_FROM_COLLECTING
    }
) when ?SOURCE_VALID(Source),
       Seen band Source =:= 0 ->
    NewSeen = Seen bor Source,
    case NewSeen =:= ?NEIGHBOR_MASK of
        false ->
            {replying, Cell#data_cell{seen_sources = NewSeen}, consume};
        true ->
            {reporting, Cell#data_cell{
                seen_sources = NewSeen,
                event = 0
            }, consume}
    end;
replying(
    cast,
    #phenom_query{step = QueryStep},
    Cell = #data_cell{
        step = Step,
        reply_resume = ?REPLY_FROM_COLLECTING
    }
) when QueryStep =:= ((Step + 1) band ?U32_MASK) ->
    {replying, Cell, postpone};
replying(
    cast,
    #phenom_query{step = QueryStep, source = Source},
    Cell = #data_cell{
        step = Step,
        reply_resume = ?REPLY_FROM_REPORTING
    }
) when QueryStep =:= ((Step + 1) band ?U32_MASK),
       ?SOURCE_VALID(Source) ->
    Collecting = Cell#data_cell{
        step = QueryStep,
        seen_sources = Source,
        event = 0
    },
    {collecting, Collecting, consume};
replying(cast, #phenom_query{}, Cell) ->
    {replying, Cell, fail};
replying(cast, #noise_cutoff{}, Cell) ->
    {replying, Cell, fail};
replying(cast, #pauli_update{pauli = Pauli}, Cell) ->
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
replying(
    cast,
    #pauli_query{
        request_id = RequestId,
        measurement = Measurement
    },
    Cell = #data_cell{noise_disabled = true}
) ->
    case hls_pauli:is_pauli(Measurement) of
        true ->
            Replying = prepare_reply(Cell, RequestId, Measurement),
            {repeat_phase, Replying, consume};
        false ->
            {replying, Cell, fail}
    end;
replying(cast, #pauli_query{}, Cell) ->
    {replying, Cell, fail}.

%% Builds a nondestructive Pauli-query response in the cell state.
-spec prepare_reply(#data_cell{}, hls_nums:u32(), hls_pauli:pauli()) -> #data_cell{}.
prepare_reply(Cell, RequestId, Measurement) ->
    Anticommutes = hls_pauli:anticommutes(Cell#data_cell.accumulated_pauli, Measurement),
    Cell#data_cell{
        reply_request_id = RequestId,
        reply_anticommutes = case Anticommutes of
            false -> 0;
            true -> 1
        end
    }.

%% Reject names absent from this specialization before admitting a CPU message.
-spec source_mask(direction()) -> hls_nums:u32().
source_mask(Direction) ->
    Mask = case Direction of
        north -> ?PHI_NORTH_MASK;
        east -> ?PHI_EAST_MASK;
        west -> ?PHI_WEST_MASK;
        south -> ?PHI_SOUTH_MASK;
        _ -> error(badarg)
    end,
    case Mask band ?NEIGHBOR_MASK of
        Mask -> Mask;
        _ -> error(badarg)
    end.

%% Require exactly the specialization's named output PIDs.
-spec valid_neighbors(map()) -> boolean().
valid_neighbors(Neighbors) ->
    is_map(Neighbors) andalso
        lists:sort(maps:keys(Neighbors)) =:=
            lists:sort(?NEIGHBOR_PORTS ++ [measurement]) andalso
        lists:all(fun is_pid/1, maps:values(Neighbors)).
