%%%% phi_halo_cell.erl
%%%%
%%%% One cell from a two-layer, three-dimensional phi-decoder relaxation mesh.

-module(phi_halo_cell).
-moduledoc """
An autonomous cell for a small phi-decoder protocol experiment.

## Protocol

The cell has two control phases with direct protocol meanings:

  * On entering `gathering`, it casts its current two-layer phi value to each
    of four neighbors. Four phi messages complete one diffusion round. An
    intermediate round explicitly repeats `gathering`, which sends the updated
    value and releases messages for the next diffusion epoch. The final round
    moves the cell to `flipping`.
  * On entering `flipping`, it casts one anyon update to each neighbor. Four
    anyon messages complete the step and move the cell back to `gathering`.

Phi messages carry a wrapping diffusion epoch in their first `u32` word. The
cell derives that epoch from its decoder step and diffusion round, so repeated
diffusion does not widen the 96-bit phi frame. Messages for the next diffusion
epoch or phase may arrive early. They are postponed until the phase changes or
is explicitly repeated, then retried in their original arrival order. Partial
sums and receive counts are ordinary data changes and do not themselves retry
a postponed message.

The generated module exposes four separately backpressured output ports named
`north`, `east`, `west`, and `south`. The CPU scheduler maps those names to the
four PIDs passed to `start_link/1`; no broadcast recipient is hidden in the
cell. To build a cyclic CPU mesh, start every cell with `start_link/0` and then
wire each one with `connect/2`; its initial gathering entry runs on connection.

The count-based joins rely on the topology delivering exactly one message per
incoming edge in each phase. A topology which can duplicate an edge must
deduplicate it or the cell must use a fixed source mask.

## Deliberate simplifications

This slice performs two diffusion rounds per anyon step. Two is the smallest
round count which exercises same-phase re-entry and next-epoch postponement;
it is a compile-time protocol fixture rather than a convergence policy. The
stochastic coin takes its no-move branch, so every flipping entry sends
`present = false`; input noise is also absent. Incoming anyon updates are still
combined by parity so the phase protocol does not erase a move supplied by a
test or a future neighbor.

A fuller decoder needs a configurable diffusion stopping rule, move selection
based on a post-diffusion neighbor comparison, measurement input, and
correction output. Those additions should preserve the two genuine barrier
phases; a parity-only wakeup phase would not have direct protocol meaning.

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
-define(DIFFUSION_ROUNDS, 2).
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
%% TODO: Replace the fixed diffusion count with the decoder's stopping rule and
%% add the post-diffusion phi0 barrier before enabling a nontrivial coin and
%% correction output.
%% TODO: Revisit neighbor configuration so FPGA topology can be fixed at
%% compile time while CPU models retain ergonomic runtime wiring.
%% TODO: Separate logical field types from word-aligned wire codecs so
%% #anyon_move.present can be boolean in lowerable callbacks.

-record(phi, {
    epoch = xls_type:zero() :: xls_nums:u32(),
    values = xls_type:zero() ::
        xls_lists:list(xls_nums:u32(), ?LAYER_COUNT)
}).

-record(anyon_move, {
    step = xls_type:zero() :: xls_nums:u32(),
    present = xls_type:zero() :: xls_nums:u32()
}).

-record(cell, {
    step = xls_type:zero() :: xls_nums:u32(),
    diffusion_round = xls_type:zero() :: xls_nums:u32(),
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
-type conclusion() ::
    {phase(), #cell{}, directive()} |
    {repeat_phase, #cell{}, consume}.
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
            Options = [
                {mailbox_capacity, ?MAILBOX_CAPACITY},
                {outputs, Neighbors}
            ],
            xls_statem:start_link(?MODULE, [], Options);
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

-doc "Offers one neighbor phi value for diffusion `Epoch` to a cell.".
-spec offer_phi(pid(), xls_nums:u32(), [xls_nums:u32()]) -> ok.
offer_phi(PID, Epoch, Values) ->
    xls_statem:cast(PID, #phi{epoch = Epoch, values = Values}).

-doc "Offers one neighbor anyon update to a cell.".
-spec offer_anyon(pid(), xls_nums:u32(), boolean()) -> ok.
offer_anyon(PID, Step, Present) when is_boolean(Present) ->
    PresentWord = case Present of
        false -> 0;
        true -> 1
    end,
    xls_statem:cast(PID, #anyon_move{step = Step, present = PresentWord}).

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
    Epoch = ((Cell#cell.step * ?DIFFUSION_ROUNDS) +
        Cell#cell.diffusion_round) band ?U32_MASK,
    Message = #phi{epoch = Epoch, values = Cell#cell.phi},
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
    #phi{epoch = Epoch, values = Values},
    gathering,
    Cell = #cell{step = Step, diffusion_round = Round}
) when Epoch =:= ((Step * ?DIFFUSION_ROUNDS + Round) band ?U32_MASK) ->
    Value0 = xls_lists:nth(1, Values),
    Value1 = xls_lists:nth(2, Values),
    Sum0 = (xls_lists:nth(1, Cell#cell.phi_sum) + Value0)
        band ?U32_MASK,
    Sum1 = (xls_lists:nth(2, Cell#cell.phi_sum) + Value1)
        band ?U32_MASK,
    SumFirst = xls_lists:set(1, Cell#cell.phi_sum, Sum0),
    NewSum = xls_lists:set(2, SumFirst, Sum1),
    ReceivedNext = Cell#cell.phi_received + 1,
    case ReceivedNext =:= ?NEIGHBOR_COUNT of
        false ->
            Accumulated = Cell#cell{
                phi_sum = NewSum,
                phi_received = ReceivedNext
            },
            {gathering, Accumulated, consume};
        true ->
            P0 = xls_lists:nth(1, Cell#cell.phi),
            P1 = xls_lists:nth(2, Cell#cell.phi),
            Charge = Cell#cell.anyon bsl 16,
            New0 = (Charge + (P0 bsr 2) +
                (((P1 bsl 1) + Sum0) bsr 3)) band ?U32_MASK,
            New1 = (((P1 * 3) bsr 2) + ((P0 + Sum1) div 20))
                band ?U32_MASK,
            PhiFirst = xls_lists:set(1, Cell#cell.phi, New0),
            NewPhi = xls_lists:set(2, PhiFirst, New1),
            Updated = Cell#cell{
                diffusion_round = Round + 1,
                phi = NewPhi,
                phi_sum = xls_lists:new(
                    xls_nums:u32(),
                    ?LAYER_COUNT
                ),
                phi_received = 0
            },
            case Round + 1 =:= ?DIFFUSION_ROUNDS of
                false -> {repeat_phase, Updated, consume};
                true -> {flipping, Updated, consume}
            end
    end;
handle_cast(
    #phi{epoch = Epoch},
    gathering,
    Cell = #cell{step = Step, diffusion_round = Round}
) when Epoch =:= ((Step * ?DIFFUSION_ROUNDS + Round + 1)
        band ?U32_MASK) ->
    {gathering, Cell, postpone};
handle_cast(#phi{}, gathering, Cell) ->
    {gathering, Cell, fail};
handle_cast(
    #anyon_move{step = Step},
    gathering,
    Cell = #cell{step = Step}
) ->
    {gathering, Cell, postpone};
handle_cast(#anyon_move{}, gathering, Cell) ->
    {gathering, Cell, fail};
handle_cast(
    #phi{epoch = Epoch},
    flipping,
    Cell = #cell{step = Step, diffusion_round = Round}
) when Epoch =:= ((Step * ?DIFFUSION_ROUNDS + Round) band ?U32_MASK) ->
    {flipping, Cell, postpone};
handle_cast(#phi{}, flipping, Cell) ->
    {flipping, Cell, fail};
handle_cast(
    #anyon_move{step = Step, present = PresentWord},
    flipping,
    Cell = #cell{step = Step}
) when PresentWord < 2 ->
    ReceivedNext = Cell#cell.moves_received + 1,
    NextAnyon = Cell#cell.anyon bxor PresentWord,
    case ReceivedNext =:= ?NEIGHBOR_COUNT of
        false ->
            Accumulated = Cell#cell{
                moves_received = ReceivedNext,
                anyon = NextAnyon
            },
            {flipping, Accumulated, consume};
        true ->
            Advanced = Cell#cell{
                step = (Cell#cell.step + 1) band ?U32_MASK,
                diffusion_round = 0,
                moves_received = 0,
                anyon = NextAnyon
            },
            {gathering, Advanced, consume}
    end;
handle_cast(#anyon_move{}, flipping, Cell) ->
    {flipping, Cell, fail}.

valid_neighbors(Neighbors) ->
    is_map(Neighbors) andalso
        lists:sort(maps:keys(Neighbors)) =:=
            lists:sort([north, east, west, south]) andalso
        lists:all(fun is_pid/1, maps:values(Neighbors)).
