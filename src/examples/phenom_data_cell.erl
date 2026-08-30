%%%% phenom_data_cell.erl
%%%%
%%%% One data-qubit noise source for a periodic phenomenological-noise mesh.

-module(phenom_data_cell).
-moduledoc """
A source-aware data-qubit cell for a small phenomenological-noise experiment.

## Protocol

The cell begins in `configuring`. A one-shot configuration supplies a nonzero
PRNG seed and a `u32` Bernoulli threshold. Queries which arrive before that
configuration are retained in the bounded mailbox.

In `collecting`, the cell accepts one query for its current step from each of
the four logical directions. The source masks identify edges rather than
processes, so a small periodic CPU topology may connect more than one edge to
the same PID. Duplicate, invalid, and stale queries fail the cell. A query for
the immediately following step is postponed.

The fourth distinct query advances `xls_prng:xorshift32/1` exactly once. The
round reports an error when the next random word is less than the configured
threshold. Entering `reporting` casts that result to all four adjacent
syndrome cells, with each message labelled by the incoming edge as seen by its
recipient. The first valid query for the next step returns the cell to
`collecting`; the phase change then releases the other postponed queries.

This cell models one independent binary error event per round. It does not yet
model multiple Pauli channels or accept decoder corrections. A future
correction path can use the same edge identities to make this data cell the
physical or Pauli-frame correction sink.
""".

-include("phi_protocol.hrl").

-export([
    start_link/0,
    start_link/1,
    connect/2,
    stop/1,
    configure/3,
    offer_query/3,
    runtime_info/1
]).
-export([init/1, handle_enter/3, handle_cast/3]).

-define(MAILBOX_CAPACITY, 5).
-define(U32_MASK, 16#ffffffff).

-behavior(xls_statem).
-xls_data(data_cell).
-xls_phases([configuring, collecting, reporting]).
-xls_outputs([north, east, west, south]).
-xls_mailbox_capacity(?MAILBOX_CAPACITY).
-xls_tags(?PHI_PROTOCOL_TAGS).
-compile({parse_transform, xls_pack}).

%% TODO: Add the other Pauli channel(s) once the surrounding experiment
%% distinguishes their syndrome neighborhoods.
%% TODO: Accept a selected-edge correction once the phi topology exposes a
%% correction boundary.

-record(data_cell, {
    step = xls_type:zero() :: xls_nums:u32(),
    seen_sources = xls_type:zero() :: xls_nums:u32(),
    threshold = xls_type:zero() :: xls_nums:u32(),
    event = xls_type:zero() :: xls_nums:u32(),
    random_state = xls_type:zero() :: xls_nums:u32()
}).

-type phase() :: configuring | collecting | reporting.
-type directive() :: consume | postpone | fail.
-type conclusion() :: {phase(), #data_cell{}, directive()}.
-type neighbors() :: #{
    north := pid(),
    east := pid(),
    west := pid(),
    south := pid()
}.
-type direction() :: north | east | west | south.

%%%
%%% CPU interface
%%%

-doc "Starts a data cell whose outputs will be connected later.".
-spec start_link() -> {ok, pid()}.
start_link() ->
    xls_statem:start_link(
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
            xls_statem:start_link(?MODULE, [], Options);
        false ->
            error(badarg)
    end.

-doc "Connects a deferred cell to its four adjacent syndrome cells.".
-spec connect(pid(), neighbors()) -> ok | {error, already_connected}.
connect(PID, Neighbors) ->
    case valid_neighbors(Neighbors) of
        true -> xls_statem:connect(PID, Neighbors);
        false -> error(badarg)
    end.

-spec stop(pid()) -> ok.
stop(PID) ->
    xls_statem:stop(PID).

-doc "Configures the nonzero PRNG seed and Bernoulli threshold.".
-spec configure(pid(), xls_nums:u32(), xls_nums:u32()) -> ok.
configure(PID, Seed, Threshold)
        when is_integer(Seed), Seed > 0, Seed =< ?U32_MASK,
             is_integer(Threshold), Threshold >= 0,
             Threshold =< ?U32_MASK ->
    xls_statem:cast(PID, #phenom_config{
        seed = Seed,
        threshold = Threshold
    });
configure(_PID, _Seed, _Threshold) ->
    error(badarg).

-doc "Offers a step query from one logical direction.".
-spec offer_query(pid(), xls_nums:u32(), direction()) -> ok.
offer_query(PID, Step, Source)
        when is_integer(Step), Step >= 0, Step =< ?U32_MASK ->
    xls_statem:cast(PID, #phenom_query{
        step = Step,
        source = source_mask(Source)
    });
offer_query(_PID, _Step, _Source) ->
    error(badarg).

-doc "Returns diagnostic data from the bounded CPU scheduler.".
-spec runtime_info(pid()) -> map().
runtime_info(PID) ->
    xls_statem:info(PID).

%%%
%%% xls_statem callbacks
%%%

-spec init(any()) -> {ok, phase(), #data_cell{}}.
init([]) ->
    {ok, configuring, #data_cell{}}.

-spec handle_enter(phase(), phase(), #data_cell{}) ->
    xls_statem:enter_result().
handle_enter(_OldPhase, configuring, Cell) ->
    {Cell, []};
handle_enter(_OldPhase, collecting, Cell) ->
    {Cell, []};
handle_enter(_OldPhase, reporting, Cell) ->
    Message = #phenom_data{
        step = Cell#data_cell.step,
        present = Cell#data_cell.event
    },
    {Cell, [
        {cast, north, Message#phenom_data{source = ?PHI_SOUTH_MASK}},
        {cast, east, Message#phenom_data{source = ?PHI_WEST_MASK}},
        {cast, west, Message#phenom_data{source = ?PHI_EAST_MASK}},
        {cast, south, Message#phenom_data{source = ?PHI_NORTH_MASK}}
    ]}.

-spec handle_cast(#phenom_config{} | #phenom_query{}, phase(), #data_cell{}) ->
    conclusion().
handle_cast(
    #phenom_config{seed = Seed, threshold = Threshold},
    configuring,
    Cell
) when Seed > 0 ->
    Configured = Cell#data_cell{
        threshold = Threshold,
        random_state = Seed
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
            NextRandom = xls_prng:xorshift32(Cell#data_cell.random_state),
            Event = case NextRandom < Cell#data_cell.threshold of
                false -> xls_type:as(xls_nums:u32(), 0);
                true -> xls_type:as(xls_nums:u32(), 1)
            end,
            Completed = Cell#data_cell{
                seen_sources = NewSeen,
                event = Event,
                random_state = NextRandom
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
    {reporting, Cell, fail}.

source_mask(north) -> ?PHI_NORTH_MASK;
source_mask(east) -> ?PHI_EAST_MASK;
source_mask(west) -> ?PHI_WEST_MASK;
source_mask(south) -> ?PHI_SOUTH_MASK;
source_mask(_Direction) -> error(badarg).

valid_neighbors(Neighbors) ->
    is_map(Neighbors) andalso
        lists:sort(maps:keys(Neighbors)) =:=
            lists:sort([north, east, west, south]) andalso
        lists:all(fun is_pid/1, maps:values(Neighbors)).
