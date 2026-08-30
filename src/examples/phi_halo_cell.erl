%%%% phi_halo_cell.erl
%%%%
%%%% One cell from a two-layer, three-dimensional phi-decoder relaxation mesh.

-module(phi_halo_cell).
-moduledoc """
An autonomous cell for a small phi-decoder protocol experiment.

## Protocol

The cell has four control phases with direct protocol meanings:

  * On entering `measuring`, it asks its paired phenomenological syndrome cell
    for the detection event at the current step. The reply is XORed into the
    local anyon before diffusion begins. Halo traffic from a faster neighbor is
    postponed at this boundary, so an absent reply is never interpreted as a
    zero measurement.

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
    and move the cell back to `measuring`.

Phi messages carry a wrapping diffusion epoch in their first `u32` word. The
cell derives that epoch from its decoder step and diffusion round, so repeated
diffusion does not widen the 96-bit phi frame. Messages for the next diffusion
epoch or phase may arrive early. They are postponed until the phase changes or
is explicitly repeated, then retried in their original arrival order. Partial
sums, receive masks, and receive counts are ordinary data changes and do not
themselves retry a postponed message.

The generated module exposes five separately backpressured output ports:
`north`, `east`, `west`, and `south` for the decoder mesh, plus `syndrome` for
its measurement source. The CPU scheduler maps those names to the PIDs passed
to `start_link/1`; no recipient is hidden in the cell. To build a cyclic CPU
topology, start every cell with `start_link/0` and then call `connect/2`; its
initial measurement request runs on connection.

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
configuration mechanism. The paired syndrome input supplies nontrivial noise;
its data and measurement generators are separate actors.

An outgoing move toggles the local anyon before incoming moves are combined by
parity. Consequently, simultaneous arrivals and departures produce the same
occupancy regardless of message order. This module does not emit the physical
correction associated with the selected edge.

A fuller decoder needs a configurable diffusion stopping rule, independent
per-cell coin streams, richer noise/measurement configuration, and correction
output. Those additions should preserve the four genuine barrier phases; a
parity-only wakeup phase would not have direct protocol meaning.

## Field arithmetic

The two stored layers are a deliberately small z-depth probe. Layer zero is the
syndrome plane and layer one uses the charge-free bulk coefficient. Values use
unsigned Q16.16 in the intended deployment. Integer operations implement this
two-layer specialization of the relaxation coefficients; explicit `u32` masks
keep the CPU model aligned with fixed-width generated arithmetic.
""".

-include("phi_protocol.hrl").

-export([
    start_link/0,
    start_link/1,
    connect/2,
    stop/1,
    offer_phi/3,
    offer_phi0/4,
    offer_anyon/3,
    offer_measurement/3,
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

-behavior(xls_statem).
-xls_data(cell).
-xls_phases([measuring, gathering, comparing, flipping]).
-xls_outputs([north, east, west, south, syndrome]).
-xls_mailbox_capacity(?MAILBOX_CAPACITY).
-xls_tags(?PHI_PROTOCOL_TAGS).
-compile({parse_transform, xls_pack}).

%% TODO: Replace the two-element xls_lists values with xls_vec once vector
%% arithmetic is part of the lowerable library.
%% TODO: Replace the fixed diffusion count with the decoder's stopping rule and
%% expose the physical-correction boundary.
%% TODO: Revisit neighbor configuration so FPGA topology can be fixed at
%% compile time while CPU models retain ergonomic runtime wiring.
%% TODO: Give statically instantiated cells distinct nonzero PRNG seeds. The
%% fixed seed above is a reproducible single-cell fixture, not an independent
%% random source for every cell in a mesh.
%% TODO: Separate logical field types from word-aligned wire codecs so
%% #anyon_move.present can be boolean in lowerable callbacks.

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

-type phase() :: measuring | gathering | comparing | flipping.
-type directive() :: consume | postpone | fail.
-type conclusion() ::
    {phase(), #cell{}, directive()} |
    {repeat_phase, #cell{}, consume}.
-type neighbors() :: #{
    north := pid(),
    east := pid(),
    west := pid(),
    south := pid(),
    syndrome := pid()
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

-doc "Connects a deferred cell to four neighbors and its syndrome source.".
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

-doc "Offers the detection event for one decoder step.".
-spec offer_measurement(pid(), xls_nums:u32(), boolean()) -> ok.
offer_measurement(PID, Step, Present) when is_boolean(Present) ->
    PresentWord = case Present of
        false -> 0;
        true -> 1
    end,
    xls_statem:cast(PID, #phenom_anyon{
        step = Step,
        present = PresentWord
    }).

-doc "Returns diagnostic data from the bounded CPU scheduler.".
-spec runtime_info(pid()) -> map().
runtime_info(PID) ->
    xls_statem:info(PID).

%%%
%%% xls_statem callbacks
%%%

-spec init(any()) -> {ok, phase(), #cell{}}.
init([]) ->
    {ok, measuring, #cell{random_state = ?PRNG_SEED}}.

-spec handle_enter(phase(), phase(), #cell{}) ->
    xls_statem:enter_result().
handle_enter(_OldPhase, measuring, Cell) ->
    Request = #phenom_request{step = Cell#cell.step},
    {Cell, [{cast, syndrome, Request}]};
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
    Message = #phi0{
        step = Cell#cell.step,
        value = Phi0
    },
    {Cell, [
        {cast, north, Message#phi0{source = ?PHI_SOUTH_MASK}},
        {cast, east, Message#phi0{source = ?PHI_WEST_MASK}},
        {cast, west, Message#phi0{source = ?PHI_EAST_MASK}},
        {cast, south, Message#phi0{source = ?PHI_NORTH_MASK}}
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
    {NorthPresent, EastPresent, WestPresent, SouthPresent} =
        case Cell#cell.best_direction of
            ?PHI_NORTH_MASK -> {Present, Absent, Absent, Absent};
            ?PHI_EAST_MASK -> {Absent, Present, Absent, Absent};
            ?PHI_WEST_MASK -> {Absent, Absent, Present, Absent};
            ?PHI_SOUTH_MASK -> {Absent, Absent, Absent, Present};
            _ -> {Absent, Absent, Absent, Absent}
        end,
    Message = #anyon_move{step = Cell#cell.step},
    Updated = Cell#cell{
        anyon = Cell#cell.anyon bxor Present,
        random_state = NextRandom
    },
    {Updated, [
        {cast, north, Message#anyon_move{present = NorthPresent}},
        {cast, east, Message#anyon_move{present = EastPresent}},
        {cast, west, Message#anyon_move{present = WestPresent}},
        {cast, south, Message#anyon_move{present = SouthPresent}}
    ]}.

-spec handle_cast(
    #phi{} | #phi0{} | #anyon_move{} | #phenom_anyon{},
    phase(),
    #cell{}
) ->
    conclusion().
handle_cast(
    #phenom_anyon{step = Step, present = Present},
    measuring,
    Cell = #cell{step = Step}
) when Present < 2 ->
    Updated = Cell#cell{anyon = Cell#cell.anyon bxor Present},
    {gathering, Updated, consume};
handle_cast(#phenom_anyon{}, measuring, Cell) ->
    {measuring, Cell, fail};
handle_cast(
    #phi{epoch = Epoch},
    measuring,
    Cell = #cell{step = Step}
) when Epoch =:= ((Step * ?DIFFUSION_ROUNDS) band ?U32_MASK) ->
    {measuring, Cell, postpone};
handle_cast(#phi{}, measuring, Cell) ->
    {measuring, Cell, fail};
handle_cast(#phi0{}, measuring, Cell) ->
    {measuring, Cell, fail};
handle_cast(#anyon_move{}, measuring, Cell) ->
    {measuring, Cell, fail};
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
    #phenom_anyon{step = EventStep},
    gathering,
    Cell = #cell{step = Step}
) when EventStep =:= ((Step + 1) band ?U32_MASK) ->
    {gathering, Cell, postpone};
handle_cast(#phenom_anyon{}, gathering, Cell) ->
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
) when (Source =:= ?PHI_NORTH_MASK orelse
        Source =:= ?PHI_EAST_MASK orelse
        Source =:= ?PHI_WEST_MASK orelse
        Source =:= ?PHI_SOUTH_MASK),
       Seen band Source =:= 0 ->
    NewSeen = Seen bor Source,
    NewBest = case Value > Best of
        true -> Value;
        false -> Best
    end,
    NewBestDirection = if
        Value > Best -> Source;
        Value =:= Best -> xls_type:as(xls_nums:u32(), ?NO_DIRECTION);
        true -> BestDirection
    end,
    Compared = Cell#cell{
        seen_sources = NewSeen,
        best_phi0 = NewBest,
        best_direction = NewBestDirection
    },
    case NewSeen =:= ?PHI_ALL_DIRECTIONS of
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
    #phenom_anyon{step = EventStep},
    comparing,
    Cell = #cell{step = Step}
) when EventStep =:= ((Step + 1) band ?U32_MASK) ->
    {comparing, Cell, postpone};
handle_cast(#phenom_anyon{}, comparing, Cell) ->
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
            {measuring, Advanced, consume}
    end;
handle_cast(#anyon_move{}, flipping, Cell) ->
    {flipping, Cell, fail};
handle_cast(
    #phenom_anyon{step = EventStep},
    flipping,
    Cell = #cell{step = Step}
) when EventStep =:= ((Step + 1) band ?U32_MASK) ->
    {flipping, Cell, postpone};
handle_cast(#phenom_anyon{}, flipping, Cell) ->
    {flipping, Cell, fail}.

source_mask(north) -> ?PHI_NORTH_MASK;
source_mask(east) -> ?PHI_EAST_MASK;
source_mask(west) -> ?PHI_WEST_MASK;
source_mask(south) -> ?PHI_SOUTH_MASK;
source_mask(_Direction) -> error(badarg).

valid_neighbors(Neighbors) ->
    is_map(Neighbors) andalso
        lists:sort(maps:keys(Neighbors)) =:=
            lists:sort([north, east, west, south, syndrome]) andalso
        lists:all(fun is_pid/1, maps:values(Neighbors)).
