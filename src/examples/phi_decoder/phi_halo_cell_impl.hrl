%% Shared callbacks for the grid and line wrappers; geometry is compile-time.
-include("phi_protocol.hrl").
-include("phi_neighborhood.hrl").

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
-export([
    configuring/3,
    measuring/3,
    gathering/3,
    comparing/3,
    flipping/3,
    init/1,
    reduce/3
]).

-define(MAILBOX_CAPACITY, (?NEIGHBOR_COUNT + 1)).
%% The paper prescribes c = 10 log^2(L) field updates per anyon update. For
%% original distance-three demonstration this gave c = 12. The line keeps
%% that workload parameter; its adequacy as a decoder needs separate study.
-define(DIFFUSION_ROUNDS, 12).
-define(U32_MASK, 16#ffffffff).
-define(NO_DIRECTION, 0).

-behavior(hls_statem).
-hls_data(cell).
-hls_phases([configuring, measuring, gathering, comparing, flipping]).
-ifdef(PHI_REPETITION).
-hls_outputs([east, west, syndrome, correction, status]).
-else.
-hls_outputs([north, east, west, south, syndrome, correction, status]).
-endif.
-ifdef(PHI_REPETITION).
-hls_mailbox_capacity(3).
-else.
-hls_mailbox_capacity(5).
-endif.
-compile({parse_transform, hls_pack}).

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
    diffusion_epoch = hls_type:zero() :: hls_nums:u32(),
    phi = hls_type:zero() :: phi_field:field(),
    best_direction = hls_type:zero() :: hls_nums:u32(),
    anyon = hls_type:zero() :: hls_nums:u32(),
    random_state = hls_type:zero() :: hls_nums:u32(),
    x = hls_type:zero() :: hls_nums:u16(),
    y = hls_type:zero() :: hls_nums:u16(),
    noise_quiet = hls_type:zero() :: hls_nums:u32(),
    status_valid = hls_type:zero() :: hls_nums:u32()
}).

%% Private actor state shared by the three barrier reductions. `value0` and
%% `value1` hold widened layer sums during diffusion, maximum and winner mask
%% during comparison, and incoming parity in `value0` during movement.
-record(phi_fold, {
    value0 = hls_type:zero() :: hls_nums:s64(),
    value1 = hls_type:zero() :: hls_nums:s64()
}).

%% Named protocol barriers; state entry emits each barrier's actions.
-type phase() :: configuring | measuring | gathering | comparing | flipping.
-ifdef(PHI_REPETITION).
%% Required connections for the two-neighbor protocol.
-type neighbors() :: #{
    east := pid(), west := pid(),
    syndrome := pid(),
    correction := pid(),
    status := pid()
}.
-else.
%% Required connections for the four-neighbor protocol.
-type neighbors() :: #{
    north := pid(), east := pid(), west := pid(), south := pid(),
    syndrome := pid(),
    correction := pid(),
    status := pid()
}.
-endif.
%% Direction names are the actor's physically present ports.
-type direction() :: ?NEIGHBOR_TYPE.

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

-doc "Stops the CPU actor and releases its scheduler.".
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
-spec offer_phi(pid(), hls_nums:u32(), phi_field:field()) -> ok.
offer_phi(PID, Epoch, Values) ->
    hls_statem:cast(PID, #phi{epoch = Epoch, values = Values}).

-doc "Offers one final phi0 value from `Source` as seen by the cell.".
-spec offer_phi0(pid(), hls_nums:u32(), direction(), phi_field:scalar()) -> ok.
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

-doc "Returns the unconfigured actor state; no protocol traffic is emitted.".
-spec init(any()) -> {ok, phase(), #cell{}}.
init([]) ->
    {ok, configuring, #cell{}}.

-doc "Accepts one valid configuration before beginning the request-paced protocol.".
-spec configuring(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast,
        #phi_config{} | #phi{} | #phi0{} | #anyon_move{} |
            #phenom_anyon{},
        #cell{}) -> hls_statem:cast_result(phase(), #cell{}).
configuring(enter, _OldPhase, Cell) ->
    {Cell, []};
configuring(
    cast,
    #phi_config{seed = Seed},
    Cell
) when Seed > 0, Seed =< ?U32_MASK ->
    {measuring, Cell#cell{random_state = Seed}, consume};
configuring(cast, #phi_config{}, Cell) ->
    {configuring, Cell, fail};
configuring(cast, #phi{epoch = 0}, Cell) ->
    {configuring, Cell, postpone};
configuring(cast, #phi{}, Cell) ->
    {configuring, Cell, fail};
configuring(cast, #phenom_anyon{step = 0}, Cell) ->
    {configuring, Cell, postpone};
configuring(cast, #phenom_anyon{}, Cell) ->
    {configuring, Cell, fail};
configuring(cast, #phi0{}, Cell) ->
    {configuring, Cell, fail};
configuring(cast, #anyon_move{}, Cell) ->
    {configuring, Cell, fail}.

-doc "Requests the current detection event and postpones early diffusion traffic.".
-spec measuring(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast,
        #phi_config{} | #phi{} | #phi0{} | #anyon_move{} |
            #phenom_anyon{},
        #cell{}) -> hls_statem:cast_result(phase(), #cell{}).
measuring(enter, _OldPhase, Cell) ->
    Reports = case Cell#cell.status_valid =:= 1 of
        true ->
            Status = #phi_status{
                step = (Cell#cell.step - 1) band ?U32_MASK,
                x = Cell#cell.x,
                y = Cell#cell.y,
                flags = Cell#cell.anyon bor (Cell#cell.noise_quiet bsl 1)
            },
            [{cast, status, Status}];
        false -> []
    end,
    {Cell, Reports ++ [{cast, syndrome, #phenom_request{step = Cell#cell.step}}]};
measuring(cast, #phi_config{}, Cell) ->
    {measuring, Cell, fail};
measuring(
    cast,
    #phenom_anyon{step = Step, flags = Flags, x = X, y = Y},
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
measuring(cast, #phenom_anyon{}, Cell) ->
    {measuring, Cell, fail};
measuring(
    cast,
    #phi{epoch = Epoch},
    Cell = #cell{step = Step}
) when Epoch =:= ((Step * ?DIFFUSION_ROUNDS) band ?U32_MASK) ->
    {measuring, Cell, postpone};
measuring(cast, #phi{}, Cell) ->
    {measuring, Cell, fail};
measuring(cast, #phi0{}, Cell) ->
    {measuring, Cell, fail};
measuring(cast, #anyon_move{}, Cell) ->
    {measuring, Cell, fail}.

-doc "Publishes this diffusion epoch and waits for every configured neighbor.".
-spec gathering(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast,
        #phi_config{} | #phi{} | #phi0{} | #anyon_move{} |
            #phenom_anyon{},
        #cell{}) -> hls_statem:cast_result(phase(), #cell{});
    (internal, hls_statem:reduction_complete(), #cell{}) ->
        hls_statem:internal_result(phase(), #cell{}).
gathering(enter, _OldPhase, Cell) ->
    Epoch = Cell#cell.diffusion_epoch,
    Message = #phi{epoch = Epoch, values = Cell#cell.phi},
    {Cell, [
        {open_reduction, diffusion, Cell#cell.diffusion_epoch,
            {count, ?NEIGHBOR_COUNT},
            {commutative_monoid, #phi_fold{value0 = 0, value1 = 0}}} | ?NEIGHBOR_ACTIONS(
        {cast, north, Message},
        {cast, east, Message},
        {cast, west, Message},
        {cast, south, Message})]};
gathering(
    cast,
    #phi{epoch = Epoch, values = [Phi0, Phi1]},
    Cell
) ->
    {gathering, Cell,
        {contribute, diffusion, Epoch, #phi_fold{
            value0 = phi_field:accumulate(0, Phi0),
            value1 = phi_field:accumulate(0, Phi1)
        }}};
gathering(
    internal,
    {reduction_complete, diffusion, Epoch,
        #phi_fold{value0 = Sum0, value1 = Sum1}},
    Cell = #cell{step = Step, diffusion_epoch = Epoch}
) ->
    NewPhi = phi_field:?FIELD_RELAX(Cell#cell.anyon, Cell#cell.phi, Sum0, Sum1),
    NextEpoch = (Epoch + 1) band ?U32_MASK,
    Updated = Cell#cell{
        diffusion_epoch = NextEpoch,
        phi = NewPhi
    },
    NextStepEpoch = ((Step + 1) * ?DIFFUSION_ROUNDS) band ?U32_MASK,
    {NextPhase, NextCell} = case NextEpoch =:= NextStepEpoch of
        false -> {repeat_phase, Updated};
        true -> {comparing, Updated#cell{best_direction = ?NO_DIRECTION}}
    end,
    {NextPhase, NextCell, consume};
gathering(
    cast,
    #phi0{step = Step},
    Cell = #cell{step = Step}
) ->
    {gathering, Cell, postpone};
gathering(cast, #phi0{}, Cell) ->
    {gathering, Cell, fail};
gathering(
    cast,
    #anyon_move{step = Step},
    Cell = #cell{step = Step}
) ->
    {gathering, Cell, postpone};
gathering(cast, #anyon_move{}, Cell) ->
    {gathering, Cell, fail};
gathering(
    cast,
    #phenom_anyon{step = EventStep},
    Cell = #cell{step = Step}
) when EventStep =:= ((Step + 1) band ?U32_MASK) ->
    {gathering, Cell, postpone};
gathering(cast, #phenom_anyon{}, Cell) ->
    {gathering, Cell, fail};
gathering(cast, #phi_config{}, Cell) ->
    {gathering, Cell, fail}.

-doc "Reduces neighbor field strengths to a movement direction while deferring later steps.".
-spec comparing(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast,
        #phi_config{} | #phi{} | #phi0{} | #anyon_move{} |
            #phenom_anyon{},
        #cell{}) -> hls_statem:cast_result(phase(), #cell{});
    (internal, hls_statem:reduction_complete(), #cell{}) ->
        hls_statem:internal_result(phase(), #cell{}).
comparing(enter, _OldPhase, Cell) ->
    [Phi0 | _] = Cell#cell.phi,
    Message = #phi0{
        step = Cell#cell.step,
        value = Phi0
    },
    {Cell, [
        {open_reduction, comparison, Cell#cell.step,
            {members, ?NEIGHBOR_MEMBERS},
            {commutative_monoid, #phi_fold{value0 = 0, value1 = 0}}} | ?NEIGHBOR_ACTIONS(
        {cast, north, Message#phi0{source = ?PHI_SOUTH_MASK}},
        {cast, east, Message#phi0{source = ?PHI_WEST_MASK}},
        {cast, west, Message#phi0{source = ?PHI_EAST_MASK}},
        {cast, south, Message#phi0{source = ?PHI_NORTH_MASK}})]};
comparing(
    cast,
    #phi0{step = Step, source = Source, value = Value},
    Cell
) ->
    {comparing, Cell,
        {contribute, comparison, Step, Source, #phi_fold{
            value0 = phi_field:accumulate(0, Value),
            value1 = hls_type:as(hls_nums:s64(), Source)
        }}};
comparing(
    internal,
    {reduction_complete, comparison, Step,
        #phi_fold{value1 = WinnerMask}},
    Cell = #cell{step = Step}
) ->
    NextRandom = hls_prng:xorshift32(Cell#cell.random_state),
    BestDirection = choose_direction(hls_type:as(hls_nums:u32(), WinnerMask), NextRandom),
    {flipping, Cell#cell{best_direction = BestDirection}, consume};
comparing(
    cast,
    #phi{epoch = Epoch},
    Cell = #cell{diffusion_epoch = Epoch}
) ->
    {comparing, Cell, postpone};
comparing(cast, #phi{}, Cell) ->
    {comparing, Cell, fail};
comparing(
    cast,
    #anyon_move{step = Step},
    Cell = #cell{step = Step}
) ->
    {comparing, Cell, postpone};
comparing(cast, #anyon_move{}, Cell) ->
    {comparing, Cell, fail};
comparing(
    cast,
    #phenom_anyon{step = EventStep},
    Cell = #cell{step = Step}
) when EventStep =:= ((Step + 1) band ?U32_MASK) ->
    {comparing, Cell, postpone};
comparing(cast, #phenom_anyon{}, Cell) ->
    {comparing, Cell, fail};
comparing(cast, #phi_config{}, Cell) ->
    {comparing, Cell, fail}.

-ifdef(PHI_REPETITION).
%% Equivalent to multiply-high ranking for the valid winner masks 0, 2, 4, 6.
%% Two tied edges split the low-31-bit draw at bit 30; no multiplication remains.
-spec choose_direction(hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
choose_direction(Mask, Random) ->
    case Mask of
        ?PHI_EAST_MASK -> ?PHI_EAST_MASK;
        ?PHI_WEST_MASK -> ?PHI_WEST_MASK;
        ?NEIGHBOR_MASK ->
            case Random band 16#40000000 of
                0 -> ?PHI_EAST_MASK;
                _ -> ?PHI_WEST_MASK
            end;
        _ -> ?NO_DIRECTION
    end.
-else.
%% Map the low 31 random bits to an ordinal among the winning edges. Multiply
%% high avoids division; the three-way case's bucket sizes differ by one draw.
-spec choose_direction(hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
choose_direction(Mask, Random) ->
    North = Mask band 1,
    East = (Mask bsr 1) band 1,
    West = (Mask bsr 2) band 1,
    South = (Mask bsr 3) band 1,
    Count = North + East + West + South,
    Draw = hls_type:as(hls_nums:u64(), Random band 16#7fffffff),
    Rank = hls_type:as(hls_nums:u32(),
        (Draw * hls_type:as(hls_nums:u64(), Count)) bsr 31),
    if
        Count =:= 0 -> ?NO_DIRECTION;
        Rank < North -> ?PHI_NORTH_MASK;
        Rank < North + East -> ?PHI_EAST_MASK;
        Rank < North + East + West -> ?PHI_WEST_MASK;
        true -> ?PHI_SOUTH_MASK
    end.

-endif.

-doc "Chooses a correction and publishes directional moves, then collects neighbor arrivals.".
-spec flipping(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast,
        #phi_config{} | #phi{} | #phi0{} | #anyon_move{} |
            #phenom_anyon{},
        #cell{}) -> hls_statem:cast_result(phase(), #cell{});
    (internal, hls_statem:reduction_complete(), #cell{}) ->
        hls_statem:internal_result(phase(), #cell{}).
flipping(enter, _OldPhase, Cell) ->
    NextRandom = hls_prng:xorshift32(Cell#cell.random_state),
    Absent = 0,
    {Present, Corrections} = if
        Cell#cell.anyon =:= 1,
        Cell#cell.best_direction =/= ?NO_DIRECTION,
        (NextRandom bsr 31) =:= 1 ->
            {1, [{cast, correction, #phi_correction{
                step = Cell#cell.step,
                x = Cell#cell.x,
                y = Cell#cell.y,
                direction = Cell#cell.best_direction
            }}]};
        true -> {Absent, []}
    end,
    {_NorthPresent, EastPresent, WestPresent, _SouthPresent} =
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
        {open_reduction, movement, Cell#cell.step,
            {count, ?NEIGHBOR_COUNT},
            {commutative_monoid, #phi_fold{value0 = 0, value1 = 0}}} | ?NEIGHBOR_ACTIONS(
        {cast, north, Message#anyon_move{present = _NorthPresent}},
        {cast, east, Message#anyon_move{present = EastPresent}},
        {cast, west, Message#anyon_move{present = WestPresent}},
        {cast, south, Message#anyon_move{present = _SouthPresent}}) ++ Corrections]};
flipping(
    cast,
    #phi{epoch = Epoch},
    Cell = #cell{diffusion_epoch = Epoch}
) ->
    {flipping, Cell, postpone};
flipping(cast, #phi{}, Cell) ->
    {flipping, Cell, fail};
flipping(
    cast,
    #anyon_move{step = Step, present = PresentWord},
    Cell
) ->
    {flipping, Cell,
        {contribute, movement, Step, #phi_fold{
            value0 = hls_type:as(
                hls_nums:s64(), PresentWord band ?PHENOM_PRESENT_MASK
            ),
            value1 = hls_type:as(
                hls_nums:s64(),
                case PresentWord < 2 of
                    true -> 0;
                    false -> 1
                end
            )
        }}};
flipping(
    internal,
    {reduction_complete, movement, Step,
        #phi_fold{value0 = IncomingParity, value1 = Invalid}},
    Cell = #cell{step = Step}
) ->
    case Invalid =:= 0 of
        false ->
            {flipping, Cell, fail};
        true ->
            NextStep = (Step + 1) band ?U32_MASK,
            Advanced = Cell#cell{
                step = NextStep,
                diffusion_epoch =
                    (NextStep * ?DIFFUSION_ROUNDS) band ?U32_MASK,
                anyon = Cell#cell.anyon bxor
                    hls_type:as(hls_nums:u32(), IncomingParity),
                status_valid = 1
            },
            {measuring, Advanced, consume}
    end;
flipping(
    cast,
    #phenom_anyon{step = EventStep},
    Cell = #cell{step = Step}
) when EventStep =:= ((Step + 1) band ?U32_MASK) ->
    {flipping, Cell, postpone};
flipping(cast, #phenom_anyon{}, Cell) ->
    {flipping, Cell, fail};
flipping(cast, #phi_config{}, Cell) ->
    {flipping, Cell, fail}.

-doc "Combines field sums, comparison maxima or movement parity for a barrier.".
-spec reduce(
    diffusion | comparison | movement,
    #phi_fold{},
    #phi_fold{}
) -> #phi_fold{}.
reduce(
    diffusion,
    #phi_fold{value0 = Left0, value1 = Left1},
    #phi_fold{value0 = Right0, value1 = Right1}
) ->
    #phi_fold{value0 = Left0 + Right0, value1 = Left1 + Right1};
reduce(
    comparison,
    #phi_fold{value0 = LeftValue, value1 = LeftMask},
    #phi_fold{value0 = RightValue, value1 = RightMask}
) ->
    Zero = hls_type:as(hls_nums:s64(), 0),
    {BestValue, WinnerMask} = if
        LeftMask =:= 0, RightMask =:= 0 -> {Zero, Zero};
        LeftMask =:= 0 -> {RightValue, RightMask};
        RightMask =:= 0 -> {LeftValue, LeftMask};
        LeftValue > RightValue -> {LeftValue, LeftMask};
        RightValue > LeftValue -> {RightValue, RightMask};
        true -> {LeftValue, LeftMask bor RightMask}
    end,
    #phi_fold{value0 = BestValue, value1 = WinnerMask};
reduce(
    movement,
    #phi_fold{value0 = LeftParity, value1 = LeftInvalid},
    #phi_fold{value0 = RightParity, value1 = RightInvalid}
) ->
    #phi_fold{
        value0 = LeftParity bxor RightParity,
        value1 = LeftInvalid bor RightInvalid
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
            lists:sort(?NEIGHBOR_PORTS ++ [syndrome, correction, status]) andalso
        lists:all(fun is_pid/1, maps:values(Neighbors)).
