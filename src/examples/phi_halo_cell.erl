%%%% phi_halo_cell.erl
%%%%
%%%% One cell of a two-layer, three-dimensional phi-decoder relaxation mesh.
%%%% The callback surface is deliberately a fixed XLS product rather than an
%%%% OTP callback-result union.

-module(phi_halo_cell).
-moduledoc """
An autonomous reference cell for the phi-decoder field update
(arXiv:1406.2338, equation 4).

Each cell receives four identical halo messages for its current epoch. The
four in-plane neighbors are symmetric, so their two-layer values are summed as
they arrive instead of being stored in directional slots. The fourth message
immediately performs the Jacobi update, advances the epoch, and emits one halo
for static fanout to the four neighbors. There is no coordinating `diffuse`
request.

The outer states `gather_even` and `gather_odd` alternate only when a four-way
join completes. They are the retry boundary for one-epoch-lookahead messages;
changes to the epoch, partial sum, and receive count are inner data changes and
do not by themselves retry postponed input.

The count-based join assumes the topology admits exactly one halo from each
incoming edge per epoch. If transport retries can duplicate an edge, the
topology must deduplicate or this state must regain a fixed source mask.

The two layers form the smallest periodic z dimension: each sees the other
twice. Field values are unsigned Q16.16 in the intended deployment. The CPU
probe uses ordinary Erlang arithmetic while generated DSLX applies its operand
widths; explicit masks retain the state fields as `u32` values.
""".

-export([
    start_link/0,
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

-behaviour(xls_statem).
-xls_state(state).
-xls_states([gather_even, gather_odd]).
-xls_mailbox_capacity(?MAILBOX_CAPACITY).
-xls_tags([halo]).
-compile({parse_transform, xls_pack}).

%%%% A static fabric fanout will replicate each emitted halo to four edges. It
%%%% must retain a fixed completion mask until all destinations accept it.
%%%% This single-cell compile probe exposes one stream until that topology is
%%%% introduced; epoch advance therefore commits when that stream accepts.
%%%% LOCAL_CHARGE is a hand-checkable fixture until the syndrome source is
%%%% connected to this cell's state on fabric.
%%%% TODO: replace the two-element xls_lists values with an xls_vec type once
%%%% vector arithmetic is part of the lowerable library.

-record(halo, {
    epoch = xls_type:zero() :: xls_nums:u32(),
    values = xls_type:zero() ::
        xls_lists:list(xls_nums:u32(), ?LAYER_COUNT)
}).

-record(state, {
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
-type machine() :: {phase(), #state{}}.
-type conclusion() :: {output(), machine(), directive()}.

%%%
%%% CPU interface
%%%

-spec start_link() -> {ok, pid()}.
start_link() ->
    xls_statem:start_link(
        ?MODULE,
        [],
        [{mailbox_capacity, ?MAILBOX_CAPACITY}]
    ).

-spec stop(pid()) -> ok.
stop(PID) ->
    xls_statem:stop(PID).

-doc "Offers one neighbor halo to the autonomous cell.".
-spec offer(pid(), xls_nums:u32(), [xls_nums:u32()]) -> ok.
offer(PID, Epoch, Values) ->
    xls_statem:send(PID, #halo{epoch = Epoch, values = Values}).

-doc "Receives one initial or newly diffused halo emitted by the cell.".
-spec receive_halo(pid(), timeout()) ->
    {ok, xls_nums:u32(), [xls_nums:u32()]} | timeout.
receive_halo(PID, Timeout) ->
    receive
        {xls_statem, PID, #halo{epoch = Epoch, values = Values}} ->
            {ok, Epoch, Values}
    after Timeout ->
        timeout
    end.

-doc "Returns diagnostic state from the bounded CPU scheduler.".
-spec runtime_info(pid()) -> map().
runtime_info(PID) ->
    xls_statem:info(PID).

%%%
%%% Uniform lowerable state-machine callbacks
%%%

-spec init(any()) -> {output(), machine()}.
init([]) ->
    InitialHalo = #halo{},
    InitialData = #state{charge = ?LOCAL_CHARGE},
    {{true, InitialHalo}, {gather_even, InitialData}}.

-spec transition(#halo{}, machine()) -> conclusion().
transition(
    #halo{epoch = EventEpoch, values = Values},
    {Phase, State}
) ->
    CurrentEpoch = State#state.epoch,
    NextEpoch = (CurrentEpoch + 1) band ?U32_MASK,
    Current = EventEpoch =:= CurrentEpoch,
    Next = EventEpoch =:= NextEpoch,
    Valid = Current orelse Next,

    Value0 = xls_lists:nth(1, Values),
    Value1 = xls_lists:nth(2, Values),
    Sum0 = (xls_lists:nth(1, State#state.halo_sum) + Value0)
        band ?U32_MASK,
    Sum1 = (xls_lists:nth(2, State#state.halo_sum) + Value1)
        band ?U32_MASK,
    SumFirst = xls_lists:set(1, State#state.halo_sum, Sum0),
    NewSum = xls_lists:set(2, SumFirst, Sum1),
    Received = State#state.received,
    ReceivedNext = Received + 1,
    Ready = ReceivedNext =:= ?NEIGHBOR_COUNT,

    P0 = xls_lists:nth(1, State#state.phi),
    P1 = xls_lists:nth(2, State#state.phi),
    Numerator0 = ((P0 bsl 3) + (P0 bsl 1) + (P1 bsl 1) + Sum0)
        band ?U32_MASK,
    Numerator1 = ((P1 bsl 3) + (P1 bsl 1) + (P0 bsl 1) + Sum1)
        band ?U32_MASK,
    New0 = (State#state.charge + (Numerator0 bsr 4)) band ?U32_MASK,
    New1 = Numerator1 bsr 4,
    PhiFirst = xls_lists:set(1, State#state.phi, New0),
    NewPhi = xls_lists:set(2, PhiFirst, New1),

    Accumulated = State#state{
        halo_sum = NewSum,
        received = ReceivedNext
    },
    Advanced = State#state{
        epoch = NextEpoch,
        phi = NewPhi,
        halo_sum = xls_lists:new(xls_nums:u32(), ?LAYER_COUNT),
        received = 0
    },
    CurrentData = xls_type:select(Ready, Advanced, Accumulated),
    NextData = xls_type:select(Current, CurrentData, State),

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

    {{Emit, Output}, {NextPhase, NextData}, Directive}.
