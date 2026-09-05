%%%% phi_halo_cell.erl
%%%%
%%%% One cell from a two-layer, three-dimensional phi-decoder relaxation mesh.

-module(phi_halo_cell).
-moduledoc """
An autonomous cell for a small phi-decoder protocol experiment.

## Protocol

The cell begins quiescent in `configuring`. A single nonzero seed selects its
coin stream and advances it to the four control phases with direct protocol
meanings:

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

The generated module exposes seven separately backpressured output ports:
`north`, `east`, `west`, and `south` for the decoder mesh, `syndrome` for its
measurement source, and provisional `correction` and `status` event streams. A
physical correction belongs to the data-qubit edge between this syndrome
location and the selected neighboring syndrome location. The compact event
identifies that edge by syndrome coordinate and direction; it is not a claim
that a phi cell has only one neighboring data qubit. Status is emitted after
all four incoming moves complete the step and reports both the resulting local
anyon occupancy and the quiet certificate propagated from that step's
syndrome neighborhood. For one cell, its optional correction precedes its
status on the source-ordered egress. Complete same-step quiet and empty status
sets from both decoder planes can therefore fence all earlier correction
events. The CPU scheduler maps output names to the PIDs passed to
`start_link/1`; no recipient is hidden in the cell. To build a cyclic CPU
topology, start every cell with `start_link/0` and then call `connect/2`; its
initial measurement request runs once both connection and configuration are
complete.

The diffusion and anyon joins rely on the topology delivering exactly one
message per incoming edge in each phase. The comparison join is source-aware:
it rejects an invalid or duplicate direction instead of allowing it to satisfy
the four-way barrier. The five-slot mailbox holds one complete early barrier
plus the message which lets the current barrier advance. Direct-neighbor
causality prevents a sender from reaching a second future barrier before this
cell has emitted the message needed to release the first.

## Deliberate simplifications

This distance-three slice performs twelve diffusion rounds per anyon step. The
paper prescribes `c = 10 log^2(L)` field updates; twelve is the nearest whole
number at `L = 3`. The coin is the most-significant bit of a deterministic
`xorshift32` sequence.
Each cell receives a nonzero seed before it begins, so a topology can give
statically instantiated cells distinct reproducible streams. The paired
syndrome input supplies nontrivial noise; its data and measurement generators
are separate actors.

An outgoing move toggles the local anyon before incoming moves are combined by
parity. Consequently, simultaneous arrivals and departures produce the same
occupancy regardless of message order. Like the reference phi implementation,
this fixture emits a correction only when a move occurs. Its statically placed
`cast_if` action retains source order while a runtime predicate suppresses the
unused effect, so correction traffic scales with applied moves rather than
physical qubits and steps.

A fuller decoder needs a configurable diffusion stopping rule and richer
noise/measurement configuration. Those additions should preserve the four
genuine barrier phases; a parity-only wakeup phase would not have direct
protocol meaning.

## Field arithmetic

For the distance-three torus, reflection symmetry about the syndrome plane
makes the `z = 1` and `z = -1` values equal, so the complete field needs only
two stored layers. Values use the example-local signed Q15.16 `phi_field` type.
Each recurrence widens its complete rational numerator to 64 bits, rounds once
to the nearest stored value with ties away from zero, then saturates to the
32-bit field. For the paper's `eta = 1/2`, the center plane retains `1/2` of
its old value and receives `1/12` of each of its six spatial neighbors. The
charge-free bulk layer receives the same coefficient from each neighbor; one
of its two z-neighbors is the center plane and the other is its reflected bulk
counterpart.
""".

-include("phi_protocol.hrl").

-export([
    start_link/0,
    start_link/1,
    configure/2,
    connect/2,
    stop/1,
    offer_phi/3,
    offer_phi0/4,
    offer_anyon/3,
    offer_measurement/3,
    offer_measurement/5,
    runtime_info/1
]).
-export([init/1, handle_enter/3, handle_cast/3]).

-define(LAYER_COUNT, 2).
-define(MAILBOX_CAPACITY, 5).
-define(NEIGHBOR_COUNT, 4).
%% The paper prescribes c = 10 log^2(L) field updates per anyon update. For
%% this distance-three demonstration, rounding the real-valued prescription
%% to the nearest whole update gives c = 12.
-define(DIFFUSION_ROUNDS, 12).
-define(U32_MASK, 16#ffffffff).
-define(NO_DIRECTION, 0).

-behavior(hls_statem).
-hls_data(cell).
-hls_phases([configuring, measuring, gathering, comparing, flipping]).
-hls_outputs([north, east, west, south, syndrome, correction, status]).
-hls_mailbox_capacity(?MAILBOX_CAPACITY).
-compile({parse_transform, hls_pack}).

%% TODO: Replace the two-element hls_lists values with hls_vec once vector
%% arithmetic is part of the lowerable library.
%% TODO: Replace the fixed diffusion count with the decoder's stopping rule.
%% TODO: Choose the deployment boundary for applied corrections: either route
%% each move to its neighboring data-qubit actor in PL, or translate the
%% coordinate/direction event in an explicit PL-PS gateway.
%% TODO: Revisit neighbor configuration so FPGA topology can be fixed at
%% compile time while CPU models retain ergonomic runtime wiring.
%% TODO: Separate logical field types from word-aligned wire codecs so
%% #anyon_move.present can be boolean in lowerable callbacks.

-record(cell, {
    step = hls_type:zero() :: hls_nums:u32(),
    diffusion_round = hls_type:zero() :: hls_nums:u32(),
    phi = hls_type:zero() ::
        hls_lists:list(phi_field:field(), ?LAYER_COUNT),
    phi_sum = hls_type:zero() ::
        hls_lists:list(hls_nums:s64(), ?LAYER_COUNT),
    phi_received = hls_type:zero() :: hls_nums:u8(),
    seen_sources = hls_type:zero() :: hls_nums:u32(),
    best_phi0 = hls_type:zero() :: phi_field:field(),
    best_direction = hls_type:zero() :: hls_nums:u32(),
    moves_received = hls_type:zero() :: hls_nums:u8(),
    anyon = hls_type:zero() :: hls_nums:u32(),
    random_state = hls_type:zero() :: hls_nums:u32(),
    x = hls_type:zero() :: hls_nums:u16(),
    y = hls_type:zero() :: hls_nums:u16(),
    noise_quiet = hls_type:zero() :: hls_nums:u32(),
    status_valid = hls_type:zero() :: hls_nums:u32()
}).

-type phase() :: configuring | measuring | gathering | comparing | flipping.
-type directive() :: consume | postpone | fail.
-type conclusion() ::
    {phase(), #cell{}, directive()} |
    {repeat_phase, #cell{}, consume}.
-type neighbors() :: #{
    north := pid(),
    east := pid(),
    west := pid(),
    south := pid(),
    syndrome := pid(),
    correction := pid(),
    status := pid()
}.
-type direction() :: north | east | west | south.

%%%
%%% CPU interface
%%%

-doc "Starts a cell whose outputs will be connected later.".
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

-doc "Connects a deferred cell to its mesh, syndrome, and correction outputs.".
-spec connect(pid(), neighbors()) -> ok | {error, already_connected}.
connect(PID, Neighbors) ->
    case valid_neighbors(Neighbors) of
        true -> hls_statem:connect(PID, Neighbors);
        false -> error(badarg)
    end.

-spec stop(pid()) -> ok.
stop(PID) ->
    hls_statem:stop(PID).

-doc "Configures the cell's nonzero coin-stream seed.".
-spec configure(pid(), hls_nums:u32()) -> ok.
configure(PID, Seed) when Seed > 0, Seed =< ?U32_MASK ->
    hls_statem:cast(PID, #phi_config{seed = Seed});
configure(_PID, _Seed) ->
    error(badarg).

-doc "Offers one neighbor phi value for diffusion `Epoch` to a cell.".
-spec offer_phi(pid(), hls_nums:u32(), [phi_field:field()]) -> ok.
offer_phi(PID, Epoch, Values) ->
    hls_statem:cast(PID, #phi{epoch = Epoch, values = Values}).

-doc "Offers one final phi0 value from `Source` as seen by the cell.".
-spec offer_phi0(pid(), hls_nums:u32(), direction(), phi_field:field()) -> ok.
offer_phi0(PID, Step, Source, Value) ->
    SourceMask = source_mask(Source),
    hls_statem:cast(PID, #phi0{
        step = Step,
        source = SourceMask,
        value = Value
    }).

-doc "Offers one neighbor anyon update to a cell.".
-spec offer_anyon(pid(), hls_nums:u32(), boolean()) -> ok.
offer_anyon(PID, Step, Present) ->
    PresentWord = case Present of
        false -> 0;
        true -> 1
    end,
    hls_statem:cast(PID, #anyon_move{step = Step, present = PresentWord}).

-doc "Offers the detection event for one decoder step.".
-spec offer_measurement(pid(), hls_nums:u32(), boolean()) -> ok.
offer_measurement(PID, Step, Present) ->
    offer_measurement(PID, Step, Present, 0, 0).

-doc "Offers a detection event and its paired lattice coordinate.".
-spec offer_measurement(
    pid(),
    hls_nums:u32(),
    boolean(),
    hls_nums:u16(),
    hls_nums:u16()
) -> ok.
offer_measurement(PID, Step, Present, X, Y)
        when X >= 0, X =< 16#ffff,
             Y >= 0, Y =< 16#ffff ->
    PresentWord = case Present of
        false -> 0;
        true -> 1
    end,
    hls_statem:cast(PID, #phenom_anyon{
        step = Step,
        flags = PresentWord,
        x = X,
        y = Y
    }).

-doc "Returns diagnostic data from the bounded CPU scheduler.".
-spec runtime_info(pid()) -> map().
runtime_info(PID) ->
    hls_statem:info(PID).

%%%
%%% hls_statem callbacks
%%%

-spec init(any()) -> {ok, phase(), #cell{}}.
init([]) ->
    {ok, configuring, #cell{}}.

-spec handle_enter(phase(), phase(), #cell{}) ->
    hls_statem:enter_result().
handle_enter(_OldPhase, configuring, Cell) ->
    {Cell, []};
handle_enter(_OldPhase, measuring, Cell) ->
    CompletedStep = (Cell#cell.step - 1) band ?U32_MASK,
    Status = #phi_status{
        step = CompletedStep,
        x = Cell#cell.x,
        y = Cell#cell.y,
        flags = Cell#cell.anyon bor (Cell#cell.noise_quiet bsl 1)
    },
    Request = #phenom_request{step = Cell#cell.step},
    {Cell, [
        {cast_if, Cell#cell.status_valid =:= 1, status, Status},
        {cast, syndrome, Request}
    ]};
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
    Phi0 = hls_lists:nth(1, Cell#cell.phi),
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
    NextRandom = hls_prng:xorshift32(Cell#cell.random_state),
    Heads = (NextRandom bsr 31) =:= 1,
    Move = Cell#cell.anyon =:= 1 andalso
        Cell#cell.best_direction =/= ?NO_DIRECTION andalso
        Heads,
    Absent = hls_type:as(hls_nums:u32(), 0),
    Present = case Move of
        false -> Absent;
        true -> hls_type:as(hls_nums:u32(), 1)
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
    CorrectionDirection = case Move of
        false -> Absent;
        true -> Cell#cell.best_direction
    end,
    Correction = #phi_correction{
        step = Cell#cell.step,
        x = Cell#cell.x,
        y = Cell#cell.y,
        direction = CorrectionDirection
    },
    Updated = Cell#cell{
        anyon = Cell#cell.anyon bxor Present,
        random_state = NextRandom
    },
    {Updated, [
        {cast, north, Message#anyon_move{present = NorthPresent}},
        {cast, east, Message#anyon_move{present = EastPresent}},
        {cast, west, Message#anyon_move{present = WestPresent}},
        {cast, south, Message#anyon_move{present = SouthPresent}},
        {cast_if, Move, correction, Correction}
    ]}.

-spec handle_cast(
    #phi_config{} | #phi{} | #phi0{} | #anyon_move{} | #phenom_anyon{},
    phase(),
    #cell{}
) ->
    conclusion().
handle_cast(
    #phi_config{seed = Seed},
    configuring,
    Cell
) when Seed > 0, Seed =< ?U32_MASK ->
    {measuring, Cell#cell{random_state = Seed}, consume};
handle_cast(#phi_config{}, configuring, Cell) ->
    {configuring, Cell, fail};
handle_cast(#phi{epoch = 0}, configuring, Cell) ->
    {configuring, Cell, postpone};
handle_cast(#phi{}, configuring, Cell) ->
    {configuring, Cell, fail};
handle_cast(#phenom_anyon{step = 0}, configuring, Cell) ->
    {configuring, Cell, postpone};
handle_cast(#phenom_anyon{}, configuring, Cell) ->
    {configuring, Cell, fail};
handle_cast(#phi0{}, configuring, Cell) ->
    {configuring, Cell, fail};
handle_cast(#anyon_move{}, configuring, Cell) ->
    {configuring, Cell, fail};
handle_cast(#phi_config{}, measuring, Cell) ->
    {measuring, Cell, fail};
handle_cast(
    #phenom_anyon{step = Step, flags = Flags, x = X, y = Y},
    measuring,
    Cell = #cell{step = Step}
) when Flags < 4,
       X >= 0, X =< 16#ffff,
       Y >= 0, Y =< 16#ffff ->
    Present = Flags band ?PHENOM_PRESENT_MASK,
    Quiet = (Flags band ?PHENOM_QUIET_MASK) bsr 1,
    Updated = Cell#cell{
        anyon = Cell#cell.anyon bxor Present,
        x = X,
        y = Y,
        noise_quiet = Quiet
    },
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
    Value0 = hls_lists:nth(1, Values),
    Value1 = hls_lists:nth(2, Values),
    Sum0 = phi_field:accumulate(
        hls_lists:nth(1, Cell#cell.phi_sum), Value0
    ),
    Sum1 = phi_field:accumulate(
        hls_lists:nth(2, Cell#cell.phi_sum), Value1
    ),
    SumFirst = hls_lists:set(1, Cell#cell.phi_sum, Sum0),
    NewSum = hls_lists:set(2, SumFirst, Sum1),
    ReceivedNext = Cell#cell.phi_received + 1,
    case ReceivedNext =:= ?NEIGHBOR_COUNT of
        false ->
            Accumulated = Cell#cell{
                phi_sum = NewSum,
                phi_received = ReceivedNext
            },
            {gathering, Accumulated, consume};
        true ->
            P0 = hls_lists:nth(1, Cell#cell.phi),
            P1 = hls_lists:nth(2, Cell#cell.phi),
            New0 = phi_field:relax_center(
                Cell#cell.anyon, P0, P1, Sum0
            ),
            New1 = phi_field:relax_bulk(P0, P1, Sum1),
            PhiFirst = hls_lists:set(1, Cell#cell.phi, New0),
            NewPhi = hls_lists:set(2, PhiFirst, New1),
            Updated = Cell#cell{
                diffusion_round = Round + 1,
                phi = NewPhi,
                phi_sum = hls_lists:new(
                    hls_nums:s64(),
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
handle_cast(#phi_config{}, gathering, Cell) ->
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
    NewBest = case Seen =:= 0 orelse Value > Best of
        true -> Value;
        false -> Best
    end,
    NewBestDirection = if
        Seen =:= 0 -> Source;
        Value > Best -> Source;
        Value =:= Best -> hls_type:as(hls_nums:u32(), ?NO_DIRECTION);
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
handle_cast(#phi_config{}, comparing, Cell) ->
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
                anyon = NextAnyon,
                status_valid = 1
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
    {flipping, Cell, fail};
handle_cast(#phi_config{}, flipping, Cell) ->
    {flipping, Cell, fail}.

source_mask(north) -> ?PHI_NORTH_MASK;
source_mask(east) -> ?PHI_EAST_MASK;
source_mask(west) -> ?PHI_WEST_MASK;
source_mask(south) -> ?PHI_SOUTH_MASK;
source_mask(_Direction) -> error(badarg).

valid_neighbors(Neighbors) ->
    is_map(Neighbors) andalso
        lists:sort(maps:keys(Neighbors)) =:=
            lists:sort([
                north, east, west, south, syndrome, correction, status
            ]) andalso
        lists:all(fun is_pid/1, maps:values(Neighbors)).
