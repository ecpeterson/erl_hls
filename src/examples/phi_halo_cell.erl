%%%% phi_halo_cell.erl
%%%%
%%%% One cell core from a two-layer, three-dimensional phi-decoder relaxation
%%%% mesh. The callback uses a fixed product which has one XLS type.

-module(phi_halo_cell).
-moduledoc """
An autonomous cell core for the phi-decoder field update
(arXiv:1406.2338, equation 4).

## Field update

The cell consumes four halo messages for its current epoch. Its four in-plane
neighbors are symmetric, so their two-layer values are accumulated as they
arrive instead of being stored in directional slots. The fourth message
performs the Jacobi update, advances the epoch, and emits the next halo. There
is no coordinating `diffuse` request.

The two layers form the smallest periodic z dimension: each layer sees the
other twice. Field values are unsigned Q16.16 in the intended deployment. The
CPU probe uses ordinary Erlang arithmetic while generated DSLX applies the
operand widths; explicit masks retain the data fields as `u32` values.

## Scheduling

The control phases `gather_even` and `gather_odd` alternate when a four-way
join completes. They form the retry boundary for one-epoch-lookahead halos.
Changes to the epoch, partial sum, and receive count are data changes and do
not by themselves retry a postponed halo.

## Output port

The callback produces one halo on the cell's output port. In the CPU runtime,
`start_link/1` names the process which receives that output. The generated
module exposes it as one outbound stream. An enclosing mesh topology must fan
the stream out to the four neighboring inputs and keep the output pending until
all four edges have accepted it; that topology is not part of this cell-core
module.

## Input assumption

The count-based join assumes the topology admits exactly one halo from each
incoming edge per epoch. If a transport can duplicate an edge, the topology
must deduplicate it or this data record must regain a fixed source mask.
""".

-export([
    start_link/0,
    start_link/1,
    stop/1,
    offer/3,
    receive_halo/2,
    runtime_info/1
]).
-export([init/1, transition/2]).

-define(LAYER_COUNT, 2).
-define(MAILBOX_CAPACITY, 5).
-define(NEIGHBOR_COUNT, 4).
-define(LOCAL_CHARGE, 5).
-define(U32_MASK, 16#ffffffff).

-behavior(xls_statem).
-xls_data(cell).
-xls_phases([gather_even, gather_odd]).
-xls_mailbox_capacity(?MAILBOX_CAPACITY).
-xls_tags([halo]).
-compile({parse_transform, xls_pack}).

%% LOCAL_CHARGE is a hand-checkable fixture until a syndrome source supplies
%% this cell's charge in the generated topology.
%% TODO: lower a static fanout which retains a completion mask until all four
%% neighboring inputs accept the emitted halo.
%% TODO: replace the two-element xls_lists values with xls_vec once vector
%% arithmetic is part of the lowerable library.
%% TODO: teach the lowering to type same-shaped if/case branches so this
%% callback can use idiomatic Erlang control flow instead of xls_type:select.

-record(halo, {
    epoch = xls_type:zero() :: xls_nums:u32(),
    values = xls_type:zero() ::
        xls_lists:list(xls_nums:u32(), ?LAYER_COUNT)
}).

-record(cell, {
    epoch = xls_type:zero() :: xls_nums:u32(),
    phi = xls_type:zero() ::
        xls_lists:list(xls_nums:u32(), ?LAYER_COUNT),
    halo_sum = xls_type:zero() ::
        xls_lists:list(xls_nums:u32(), ?LAYER_COUNT),
    received = xls_type:zero() :: xls_nums:u8(),
    charge = xls_type:zero() :: xls_nums:u32()
}).

-type phase() :: gather_even | gather_odd.
-type directive() :: consume | postpone | fail.
-type output() :: {boolean(), #halo{}}.
-type machine() :: {phase(), #cell{}}.
-type conclusion() :: {output(), machine(), directive()}.

%%%
%%% CPU interface
%%%

-doc "Starts a standalone probe whose outputs are delivered to the caller.".
-spec start_link() -> {ok, pid()}.
start_link() ->
    start_link(self()).

-doc "Starts a cell core whose halos are delivered to `OutputPID`.".
-spec start_link(pid()) -> {ok, pid()}.
start_link(OutputPID) ->
    xls_statem:start_link(
        ?MODULE,
        [],
        [
            {mailbox_capacity, ?MAILBOX_CAPACITY},
            {output, OutputPID}
        ]
    ).

-spec stop(pid()) -> ok.
stop(PID) ->
    xls_statem:stop(PID).

-doc "Offers one neighbor halo to the autonomous cell.".
-spec offer(pid(), xls_nums:u32(), [xls_nums:u32()]) -> ok.
offer(PID, Epoch, Values) ->
    xls_statem:cast(PID, #halo{epoch = Epoch, values = Values}).

-doc """
Receives one initial or newly diffused halo emitted by the cell. The calling
process must be the output recipient supplied to `start_link/1`; `PID`
identifies the source cell in that process's mailbox.
""".
-spec receive_halo(pid(), timeout()) ->
    {ok, xls_nums:u32(), [xls_nums:u32()]} | timeout.
receive_halo(PID, Timeout) ->
    receive
        {xls_statem, PID, #halo{epoch = Epoch, values = Values}} ->
            {ok, Epoch, Values}
    after Timeout ->
        timeout
    end.

-doc "Returns diagnostic data from the bounded CPU scheduler.".
-spec runtime_info(pid()) -> map().
runtime_info(PID) ->
    xls_statem:info(PID).

%%%
%%% xls_statem callbacks
%%%

-spec init(any()) -> {output(), machine()}.
init([]) ->
    InitialHalo = #halo{},
    InitialCell = #cell{charge = ?LOCAL_CHARGE},
    {{true, InitialHalo}, {gather_even, InitialCell}}.

-spec transition(#halo{}, machine()) -> conclusion().
transition(
    #halo{epoch = EventEpoch, values = Values},
    {Phase, Cell}
) ->
    CurrentEpoch = Cell#cell.epoch,
    NextEpoch = (CurrentEpoch + 1) band ?U32_MASK,
    Current = EventEpoch =:= CurrentEpoch,
    Next = EventEpoch =:= NextEpoch,
    Valid = Current orelse Next,

    Value0 = xls_lists:nth(1, Values),
    Value1 = xls_lists:nth(2, Values),
    Sum0 = (xls_lists:nth(1, Cell#cell.halo_sum) + Value0)
        band ?U32_MASK,
    Sum1 = (xls_lists:nth(2, Cell#cell.halo_sum) + Value1)
        band ?U32_MASK,
    SumFirst = xls_lists:set(1, Cell#cell.halo_sum, Sum0),
    NewSum = xls_lists:set(2, SumFirst, Sum1),
    ReceivedNext = Cell#cell.received + 1,
    Ready = ReceivedNext =:= ?NEIGHBOR_COUNT,

    P0 = xls_lists:nth(1, Cell#cell.phi),
    P1 = xls_lists:nth(2, Cell#cell.phi),
    Numerator0 = ((P0 bsl 3) + (P0 bsl 1) + (P1 bsl 1) + Sum0)
        band ?U32_MASK,
    Numerator1 = ((P1 bsl 3) + (P1 bsl 1) + (P0 bsl 1) + Sum1)
        band ?U32_MASK,
    New0 = (Cell#cell.charge + (Numerator0 bsr 4)) band ?U32_MASK,
    New1 = Numerator1 bsr 4,
    PhiFirst = xls_lists:set(1, Cell#cell.phi, New0),
    NewPhi = xls_lists:set(2, PhiFirst, New1),

    Accumulated = Cell#cell{
        halo_sum = NewSum,
        received = ReceivedNext
    },
    Advanced = Cell#cell{
        epoch = NextEpoch,
        phi = NewPhi,
        halo_sum = xls_lists:new(xls_nums:u32(), ?LAYER_COUNT),
        received = 0
    },
    CurrentCell = xls_type:select(Ready, Advanced, Accumulated),
    NextCell = xls_type:select(Current, CurrentCell, Cell),

    Emit = Current andalso Ready,
    CandidateOutput = #halo{epoch = NextEpoch, values = NewPhi},
    Output = xls_type:select(Emit, CandidateOutput, #halo{}),
    OtherPhase = xls_type:select(
        Phase =:= gather_even,
        gather_odd,
        gather_even
    ),
    NextPhase = xls_type:select(Emit, OtherPhase, Phase),
    CandidateDirective = xls_type:select(Next, postpone, consume),
    Directive = xls_type:select(Valid, CandidateDirective, fail),

    {{Emit, Output}, {NextPhase, NextCell}, Directive}.
