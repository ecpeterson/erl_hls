%%%% phi_halo_cell.erl
%%%%
%%%% One cell from a two-layer, three-dimensional phi-decoder relaxation mesh.

-module(phi_halo_cell).
-moduledoc """
An autonomous cell for a small phi-decoder protocol experiment.

## Protocol

The cell has three control phases with direct protocol meanings:

  * On entering `gathering`, it casts its current two-layer phi value to each
    of four neighbors. Four phi messages complete one diffusion round. An
    intermediate round explicitly repeats `gathering`, which sends the updated
    value and releases messages for the next diffusion epoch. The final round
    moves the cell to `comparing`.
  * On entering `comparing`, it casts its final layer-zero value to each
    neighbor. Each message identifies the incoming edge as seen by its
    recipient. Four distinct sources complete the comparison and record both
    the largest neighboring value and its direction when that maximum is
    unique. A tie has no candidate direction. The cell then moves to
    `flipping`.
  * On entering `flipping`, it advances a small pseudorandom generator and
    moves a local anyon toward the unique comparison winner on heads. Exactly
    one neighbor receives a present anyon update for a move; the other three
    receive an absent update. Four incoming anyon messages complete the step
    and move the cell back to `gathering`.

Phi messages carry a wrapping diffusion epoch in their first `u32` word. The
cell derives that epoch from its decoder step and diffusion round, so repeated
diffusion does not widen the 96-bit phi frame. Messages for the next diffusion
epoch or phase may arrive early. They are postponed until the phase changes or
is explicitly repeated, then retried in their original arrival order. Partial
sums, receive masks, and receive counts are ordinary data changes and do not
themselves retry a postponed message.

The generated module exposes four separately backpressured output ports named
`north`, `east`, `west`, and `south`. The CPU scheduler maps those names to the
four PIDs passed to `start_link/1`; no broadcast recipient is hidden in the
cell. To build a cyclic CPU mesh, start every cell with `start_link/0` and then
wire each one with `connect/2`; its initial gathering entry runs on connection.

The diffusion and anyon joins rely on the topology delivering exactly one
message per incoming edge in each phase. The comparison join is source-aware:
it rejects an invalid or duplicate direction instead of allowing it to satisfy
the four-way barrier. The five-slot mailbox holds one complete early barrier
plus the message which lets the current barrier advance. Direct-neighbor
causality prevents a sender from reaching a second future barrier before this
cell has emitted the message needed to release the first.

## Deliberate simplifications

This slice performs two diffusion rounds per anyon step. Two is the smallest
round count which exercises same-phase re-entry and next-epoch postponement;
it is a compile-time protocol fixture rather than a convergence policy. The
coin is the most-significant bit of a deterministic `xorshift32` sequence. Its
fixed seed makes CPU and RTL runs reproducible, but also correlates the coins
of cells which begin together. A mesh intended to model independent coins must
supply distinct nonzero seeds through a future static per-instance
configuration mechanism. Input noise is still absent.

An outgoing move toggles the local anyon before incoming moves are combined by
parity. Consequently, simultaneous arrivals and departures produce the same
occupancy regardless of message order. This module does not emit the physical
correction associated with the selected edge.

A fuller decoder needs a configurable diffusion stopping rule, independent
per-cell coin streams, measurement input, and correction output. Those
additions should preserve the three genuine barrier phases; a parity-only
wakeup phase would not have direct protocol meaning.

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
    offer_phi0/4,
    offer_anyon/3,
    runtime_info/1
]).
-export([init/1, handle_enter/3, handle_cast/3]).

-define(LAYER_COUNT, 2).
-define(MAILBOX_CAPACITY, 5).
-define(NEIGHBOR_COUNT, 4).
-define(DIFFUSION_ROUNDS, 2).
-define(PRNG_SEED, 16#6d2b79f5).
-define(U32_MASK, 16#ffffffff).
-define(NO_DIRECTION, 0).
-define(NORTH_MASK, 1).
-define(EAST_MASK, 2).
-define(WEST_MASK, 4).
-define(SOUTH_MASK, 8).
-define(ALL_DIRECTIONS, 15).

-behavior(xls_statem).
-xls_data(cell).
-xls_phases([gathering, comparing, flipping]).
-xls_outputs([north, east, west, south]).
-xls_mailbox_capacity(?MAILBOX_CAPACITY).
-xls_tags([phi, anyon_move, phi0]).
-compile({parse_transform, xls_pack}).

%% TODO: Replace the two-element xls_lists values with xls_vec once vector
%% arithmetic is part of the lowerable library.
%% TODO: Replace the fixed diffusion count with the decoder's stopping rule and
%% expose the measurement and physical-correction boundaries.
%% TODO: Revisit neighbor configuration so FPGA topology can be fixed at
%% compile time while CPU models retain ergonomic runtime wiring.
%% TODO: Give statically instantiated cells distinct nonzero PRNG seeds. The
%% fixed seed above is a reproducible single-cell fixture, not an independent
%% random source for every cell in a mesh.
%% TODO: Separate logical field types from word-aligned wire codecs so
%% #anyon_move.present can be boolean in lowerable callbacks.

-record(phi, {
    epoch = xls_type:zero() :: xls_nums:u32(),
    values = xls_type:zero() ::
        xls_lists:list(xls_nums:u32(), ?LAYER_COUNT)
}).

-record(phi0, {
    step = xls_type:zero() :: xls_nums:u32(),
    source = xls_type:zero() :: xls_nums:u32(),
    value = xls_type:zero() :: xls_nums:u32()
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
    seen_sources = xls_type:zero() :: xls_nums:u32(),
    best_phi0 = xls_type:zero() :: xls_nums:u32(),
    best_direction = xls_type:zero() :: xls_nums:u32(),
    moves_received = xls_type:zero() :: xls_nums:u8(),
    anyon = xls_type:zero() :: xls_nums:u32(),
    random_state = xls_type:zero() :: xls_nums:u32()
}).

-type phase() :: gathering | comparing | flipping.
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
-type direction() :: north | east | west | south.

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

-doc "Offers one final phi0 value from `Source` as seen by the cell.".
-spec offer_phi0(pid(), xls_nums:u32(), direction(), xls_nums:u32()) -> ok.
offer_phi0(PID, Step, Source, Value) ->
    SourceMask = source_mask(Source),
    xls_statem:cast(PID, #phi0{
        step = Step,
        source = SourceMask,
        value = Value
    }).

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
    {ok, gathering, #cell{random_state = ?PRNG_SEED}}.

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
handle_enter(_OldPhase, comparing, Cell) ->
    Phi0 = xls_lists:nth(1, Cell#cell.phi),
    North = #phi0{
        step = Cell#cell.step,
        source = ?SOUTH_MASK,
        value = Phi0
    },
    East = #phi0{
        step = Cell#cell.step,
        source = ?WEST_MASK,
        value = Phi0
    },
    West = #phi0{
        step = Cell#cell.step,
        source = ?EAST_MASK,
        value = Phi0
    },
    South = #phi0{
        step = Cell#cell.step,
        source = ?NORTH_MASK,
        value = Phi0
    },
    {Cell, [
        {cast, north, North},
        {cast, east, East},
        {cast, west, West},
        {cast, south, South}
    ]};
handle_enter(_OldPhase, flipping, Cell) ->
    NextRandom = xls_prng:xorshift32(Cell#cell.random_state),
    Heads = (NextRandom bsr 31) =:= 1,
    Move = Cell#cell.anyon =:= 1 andalso
        Cell#cell.best_direction =/= ?NO_DIRECTION andalso
        Heads,
    Absent = xls_type:as(xls_nums:u32(), 0),
    Present = case Move of
        false -> Absent;
        true -> xls_type:as(xls_nums:u32(), 1)
    end,
    NorthPresent = case Cell#cell.best_direction =:= ?NORTH_MASK of
        false -> Absent;
        true -> Present
    end,
    EastPresent = case Cell#cell.best_direction =:= ?EAST_MASK of
        false -> Absent;
        true -> Present
    end,
    WestPresent = case Cell#cell.best_direction =:= ?WEST_MASK of
        false -> Absent;
        true -> Present
    end,
    SouthPresent = case Cell#cell.best_direction =:= ?SOUTH_MASK of
        false -> Absent;
        true -> Present
    end,
    North = #anyon_move{
        step = Cell#cell.step,
        present = NorthPresent
    },
    East = #anyon_move{
        step = Cell#cell.step,
        present = EastPresent
    },
    West = #anyon_move{
        step = Cell#cell.step,
        present = WestPresent
    },
    South = #anyon_move{
        step = Cell#cell.step,
        present = SouthPresent
    },
    Updated = Cell#cell{
        anyon = Cell#cell.anyon bxor Present,
        random_state = NextRandom
    },
    {Updated, [
        {cast, north, North},
        {cast, east, East},
        {cast, west, West},
        {cast, south, South}
    ]}.

-spec handle_cast(#phi{} | #phi0{} | #anyon_move{}, phase(), #cell{}) ->
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
                true -> {comparing, Updated#cell{
                    seen_sources = 0,
                    best_phi0 = 0,
                    best_direction = ?NO_DIRECTION
                }, consume}
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
    #phi0{step = Step},
    gathering,
    Cell = #cell{step = Step}
) ->
    {gathering, Cell, postpone};
handle_cast(#phi0{}, gathering, Cell) ->
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
    #phi0{step = Step, source = Source, value = Value},
    comparing,
    Cell = #cell{
        step = Step,
        seen_sources = Seen,
        best_phi0 = Best,
        best_direction = BestDirection
    }
) when (Source =:= ?NORTH_MASK orelse
        Source =:= ?EAST_MASK orelse
        Source =:= ?WEST_MASK orelse
        Source =:= ?SOUTH_MASK),
       Seen band Source =:= 0 ->
    NewSeen = Seen bor Source,
    NewBest = case Value > Best of
        true -> Value;
        false -> Best
    end,
    NewBestDirection = case Value > Best of
        true -> Source;
        false ->
            case Value =:= Best of
                true -> xls_type:as(xls_nums:u32(), ?NO_DIRECTION);
                false -> BestDirection
            end
    end,
    Compared = Cell#cell{
        seen_sources = NewSeen,
        best_phi0 = NewBest,
        best_direction = NewBestDirection
    },
    case NewSeen =:= ?ALL_DIRECTIONS of
        false -> {comparing, Compared, consume};
        true -> {flipping, Compared, consume}
    end;
handle_cast(#phi0{}, comparing, Cell) ->
    {comparing, Cell, fail};
handle_cast(
    #phi{epoch = Epoch},
    comparing,
    Cell = #cell{step = Step, diffusion_round = Round}
) when Epoch =:= ((Step * ?DIFFUSION_ROUNDS + Round) band ?U32_MASK) ->
    {comparing, Cell, postpone};
handle_cast(#phi{}, comparing, Cell) ->
    {comparing, Cell, fail};
handle_cast(
    #anyon_move{step = Step},
    comparing,
    Cell = #cell{step = Step}
) ->
    {comparing, Cell, postpone};
handle_cast(#anyon_move{}, comparing, Cell) ->
    {comparing, Cell, fail};
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

source_mask(north) -> ?NORTH_MASK;
source_mask(east) -> ?EAST_MASK;
source_mask(west) -> ?WEST_MASK;
source_mask(south) -> ?SOUTH_MASK;
source_mask(_Direction) -> error(badarg).

valid_neighbors(Neighbors) ->
    is_map(Neighbors) andalso
        lists:sort(maps:keys(Neighbors)) =:=
            lists:sort([north, east, west, south]) andalso
        lists:all(fun is_pid/1, maps:values(Neighbors)).
