%%%% phi_halo_cell.erl
%%%%
%%%% One cell from a two-layer, three-dimensional phi-decoder relaxation mesh.

-module(phi_halo_cell).
-moduledoc """
An autonomous cell for a small phi-decoder protocol experiment.

## Protocol

The cell has two control phases with direct protocol meanings:

  * On entering `gathering`, it casts its current two-layer phi value to each
    of four neighbors. Four phi messages complete one field update and move
    the cell to `flipping`.
  * On entering `flipping`, it casts one anyon update to each neighbor. Four
    anyon messages complete the step and move the cell back to `gathering`.

Messages for the next phase may arrive early. They are postponed until the
phase atom changes, then retried in their original arrival order. Partial sums,
receive counts, and the step number are data changes and do not themselves
retry a postponed message.

The generated module exposes four separately backpressured output ports named
`north`, `east`, `west`, and `south`. The CPU scheduler maps those names to the
four PIDs passed to `start_link/1`; no broadcast recipient is hidden in the
cell. To build a cyclic CPU mesh, start every cell with `start_link/0` and then
wire each one with `connect/2`; its initial gathering entry runs on connection.

The count-based joins rely on the topology delivering exactly one message per
incoming edge in each phase. A topology which can duplicate an edge must
deduplicate it or the cell must regain a fixed source mask.

## Deliberate simplifications

This slice performs one phi exchange per anyon step. The stochastic coin takes
its no-move branch, so every flipping entry sends `present = 0`; input noise is
also absent. Incoming anyon updates are still combined by parity so the phase
protocol does not erase a move supplied by a test or a future neighbor.

A fuller decoder needs repeated diffusion rounds, the post-diffusion neighbor
comparison used to choose a move, measurement input, and correction output.
Those additions should preserve the two genuine barrier phases instead of
reintroducing a parity phase whose only purpose is to wake postponed input.

## Field arithmetic

The two stored layers are a deliberately small z-depth probe. Layer zero is the
syndrome plane and layer one uses the charge-free bulk coefficient. Values use
unsigned Q16.16 in the intended deployment. Integer operations implement this
two-layer specialization of the relaxation coefficients; explicit `u32` masks
keep the CPU model aligned with fixed-width generated arithmetic.
""".

-export([
    start_link/0,
    start_link/1,
    connect/2,
    stop/1,
    offer_phi/3,
    offer_anyon/3,
    runtime_info/1
]).
-export([init/1, handle_enter/3, handle_cast/3]).

-define(LAYER_COUNT, 2).
-define(MAILBOX_CAPACITY, 5).
-define(NEIGHBOR_COUNT, 4).
-define(U32_MASK, 16#ffffffff).

-behavior(xls_statem).
-xls_data(cell).
-xls_phases([gathering, flipping]).
-xls_outputs([north, east, west, south]).
-xls_mailbox_capacity(?MAILBOX_CAPACITY).
-xls_tags([phi, anyon_move]).
-compile({parse_transform, xls_pack}).

%% TODO: Replace the two-element xls_lists values with xls_vec once vector
%% arithmetic is part of the lowerable library.
%% TODO: Add the repeated diffusion and post-diffusion phi0 barriers before
%% enabling a nontrivial coin and correction output.

-record(phi, {
    step = xls_type:zero() :: xls_nums:u32(),
    values = xls_type:zero() ::
        xls_lists:list(xls_nums:u32(), ?LAYER_COUNT)
}).

-record(anyon_move, {
    step = xls_type:zero() :: xls_nums:u32(),
    present = xls_type:zero() :: xls_nums:u32()
}).

-record(cell, {
    step = xls_type:zero() :: xls_nums:u32(),
    phi = xls_type:zero() ::
        xls_lists:list(xls_nums:u32(), ?LAYER_COUNT),
    phi_sum = xls_type:zero() ::
        xls_lists:list(xls_nums:u32(), ?LAYER_COUNT),
    phi_received = xls_type:zero() :: xls_nums:u8(),
    moves_received = xls_type:zero() :: xls_nums:u8(),
    anyon = xls_type:zero() :: xls_nums:u32()
}).

-type phase() :: gathering | flipping.
-type directive() :: consume | postpone | fail.
-type conclusion() :: {phase(), #cell{}, directive()}.
-type neighbors() :: #{
    north := pid(),
    east := pid(),
    west := pid(),
    south := pid()
}.

%%%
%%% CPU interface
%%%

-doc "Starts a cell whose outputs will be connected later.".
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
            xls_statem:start_link(
                ?MODULE,
                [],
                [
                    {mailbox_capacity, ?MAILBOX_CAPACITY},
                    {outputs, Neighbors}
                ]
            );
        false ->
            error(badarg)
    end.

-doc "Connects a deferred cell to its four named neighbors.".
-spec connect(pid(), neighbors()) -> ok | {error, already_connected}.
connect(PID, Neighbors) ->
    case valid_neighbors(Neighbors) of
        true -> xls_statem:connect(PID, Neighbors);
        false -> error(badarg)
    end.

-spec stop(pid()) -> ok.
stop(PID) ->
    xls_statem:stop(PID).

-doc "Offers one neighbor phi value to a cell.".
-spec offer_phi(pid(), xls_nums:u32(), [xls_nums:u32()]) -> ok.
offer_phi(PID, Step, Values) ->
    xls_statem:cast(PID, #phi{step = Step, values = Values}).

-doc "Offers one neighbor anyon update to a cell.".
-spec offer_anyon(pid(), xls_nums:u32(), 0 | 1) -> ok.
offer_anyon(PID, Step, Present) ->
    xls_statem:cast(PID, #anyon_move{step = Step, present = Present}).

-doc "Returns diagnostic data from the bounded CPU scheduler.".
-spec runtime_info(pid()) -> map().
runtime_info(PID) ->
    xls_statem:info(PID).

%%%
%%% xls_statem callbacks
%%%

-spec init(any()) -> {ok, phase(), #cell{}}.
init([]) ->
    {ok, gathering, #cell{}}.

-spec handle_enter(phase(), phase(), #cell{}) ->
    xls_statem:enter_result().
handle_enter(_OldPhase, gathering, Cell) ->
    Message = #phi{step = Cell#cell.step, values = Cell#cell.phi},
    {Cell, [
        {cast, north, Message},
        {cast, east, Message},
        {cast, west, Message},
        {cast, south, Message}
    ]};
handle_enter(_OldPhase, flipping, Cell) ->
    %% The dummy coin keeps the local anyon and reports no outgoing move.
    Message = #anyon_move{step = Cell#cell.step, present = 0},
    {Cell, [
        {cast, north, Message},
        {cast, east, Message},
        {cast, west, Message},
        {cast, south, Message}
    ]}.

-spec handle_cast(#phi{} | #anyon_move{}, phase(), #cell{}) ->
    conclusion().
handle_cast(
    #phi{step = EventStep, values = Values},
    gathering,
    Cell
) ->
    Current = EventStep =:= Cell#cell.step,
    Value0 = xls_lists:nth(1, Values),
    Value1 = xls_lists:nth(2, Values),
    Sum0 = (xls_lists:nth(1, Cell#cell.phi_sum) + Value0)
        band ?U32_MASK,
    Sum1 = (xls_lists:nth(2, Cell#cell.phi_sum) + Value1)
        band ?U32_MASK,
    SumFirst = xls_lists:set(1, Cell#cell.phi_sum, Sum0),
    NewSum = xls_lists:set(2, SumFirst, Sum1),
    ReceivedNext = Cell#cell.phi_received + 1,
    Ready = ReceivedNext =:= ?NEIGHBOR_COUNT,

    P0 = xls_lists:nth(1, Cell#cell.phi),
    P1 = xls_lists:nth(2, Cell#cell.phi),
    Charge = Cell#cell.anyon bsl 16,
    New0 = (Charge + (P0 bsr 2) +
        (((P1 bsl 1) + Sum0) bsr 3)) band ?U32_MASK,
    New1 = (((P1 * 3) bsr 2) + ((P0 + Sum1) div 20))
        band ?U32_MASK,
    PhiFirst = xls_lists:set(1, Cell#cell.phi, New0),
    NewPhi = xls_lists:set(2, PhiFirst, New1),

    Accumulated = Cell#cell{
        phi_sum = NewSum,
        phi_received = ReceivedNext
    },
    Updated = Cell#cell{
        phi = NewPhi,
        phi_sum = xls_lists:new(xls_nums:u32(), ?LAYER_COUNT),
        phi_received = 0
    },
    case Current of
        false ->
            {gathering, Cell, fail};
        true ->
            case Ready of
                false -> {gathering, Accumulated, consume};
                true -> {flipping, Updated, consume}
            end
    end;
handle_cast(
    #anyon_move{step = EventStep},
    gathering,
    Cell
) ->
    case EventStep =:= Cell#cell.step of
        true -> {gathering, Cell, postpone};
        false -> {gathering, Cell, fail}
    end;
handle_cast(
    #phi{step = EventStep},
    flipping,
    Cell
) ->
    NextStep = (Cell#cell.step + 1) band ?U32_MASK,
    case EventStep =:= NextStep of
        true -> {flipping, Cell, postpone};
        false -> {flipping, Cell, fail}
    end;
handle_cast(
    #anyon_move{step = EventStep, present = Present},
    flipping,
    Cell
) ->
    Current = EventStep =:= Cell#cell.step,
    ValidPresent = Present < 2,
    ReceivedNext = Cell#cell.moves_received + 1,
    Ready = ReceivedNext =:= ?NEIGHBOR_COUNT,
    NextAnyon = (Cell#cell.anyon + Present) band 1,
    Accumulated = Cell#cell{
        moves_received = ReceivedNext,
        anyon = NextAnyon
    },
    Advanced = Cell#cell{
        step = (Cell#cell.step + 1) band ?U32_MASK,
        moves_received = 0,
        anyon = NextAnyon
    },
    case Current andalso ValidPresent of
        false ->
            {flipping, Cell, fail};
        true ->
            case Ready of
                false -> {flipping, Accumulated, consume};
                true -> {gathering, Advanced, consume}
            end
    end.

valid_neighbors(Neighbors) ->
    is_map(Neighbors) andalso
        lists:sort(maps:keys(Neighbors)) =:=
            lists:sort([north, east, west, south]) andalso
        lists:all(fun is_pid/1, maps:values(Neighbors)).
