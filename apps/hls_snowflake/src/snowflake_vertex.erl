-module(snowflake_vertex).
-moduledoc """
One Snowflake surface vertex communicating through ordinary actor messages.

The coordinator supplies geometry and phase epochs. Neighbor snapshots are
immutable until the phase commits; merge priority is independent of arrival
order. Both endpoints retain identical incident-edge replicas. A separate
below port shifts the time window even at boundary vertices without time edges.
""".
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-export([
    init/1,
    geometry/3,
    configuring/3,
    configured/3,
    ready/3,
    shifting/3,
    snapshotting/3,
    transferring/3,
    snapshot/1,
    reduce/3
]).
-hls_data(cell).
-hls_phases([
    geometry,
    configuring,
    configured,
    ready,
    shifting,
    snapshotting,
    transferring
]).
-hls_outputs([west, east, down, up, north, south, below, status, correction]).
-hls_mailbox_capacity(24).
-hls_continuations([local_drop, complete, advance]).
-include("snowflake_actor_protocol.hrl").

%% Live vertex state and per-phase metadata; collected snapshots remain private until complete.
-record(cell, {
    node = hls_type:zero() :: #node{},
    growth = hls_type:zero() :: hls_nums:uN(12),
    correction = hls_type:zero() :: hls_nums:uN(6),
    epoch = hls_type:zero() :: hls_nums:u32(),
    kind = hls_type:zero() :: hls_nums:u8(),
    mask = hls_type:zero() :: hls_nums:u32(),
    seen = hls_type:zero() :: hls_nums:u8(),
    outgoing = hls_type:zero() :: hls_nums:u8(),
    source = hls_type:zero() :: hls_nums:u8(),
    id = hls_type:zero() :: hls_nums:s32(),
    neighbors = hls_type:zero() :: hls_nums:u8(),
    syndrome_bit = hls_type:zero() :: hls_nums:u8(),
    retire_mask = hls_type:zero() :: hls_nums:u8(),
    height = hls_type:zero() :: hls_nums:u8(),
    top = hls_type:zero() :: hls_bool:bool(),
    bottom = hls_type:zero() :: hls_bool:bool(),
    boundary = hls_type:zero() :: hls_bool:bool(),
    below = hls_type:zero() :: hls_bool:bool(),
    boundary_limit = hls_type:zero() :: hls_nums:s32(),
    boundary_shift = hls_type:zero() :: hls_nums:s32(),
    bulk_shift = hls_type:zero() :: hls_nums:s32(),
    drop_count = hls_type:zero() :: hls_nums:u32(),
    warmup = hls_type:zero() :: hls_nums:u8(),
    retire_valid = hls_type:zero() :: hls_bool:bool(),
    retire_sheet = hls_type:zero() :: hls_nums:u32(),
    retire_bits = hls_type:zero() :: hls_nums:uN(6)
}).

%% Private transfer parity is independent of neighbor arrival order.
-record(transfer_sum, {
    edges = hls_type:zero() :: hls_nums:uN(6),
    defect = hls_type:zero() :: hls_bool:bool()
}).

%% The endpoint mask controls physical sends; message direction is the receiver's view.
-define(SF_CAST(Cell, Bit, Port, Message),
    case (Cell)#cell.neighbors band Bit =/= 0 of
        true -> [{cast, Port, Message}];
        false -> []
    end
).

%% Retain ready entry before running the unconditional successor as a private event.
-define(SF_LOCAL_READY(Next),
    ?SF_ADVANCE_SELECT(
        {ready, Next, consume, [{next_event, internal, advance}]},
        {ready, Next, consume}
    )
).

%% Callback states and accepted mailbox traffic are finite protocol alternatives.
-type phase() ::
    geometry
    | configuring
    | configured
    | ready
    | shifting
    | snapshotting
    | transferring.
%% Accepted inbound protocol records; output reports are never valid requests.
-type message() ::
    #sf_geometry{}
    | #sf_vertex_config{}
    | #sf_phase{}
    | #sf_snapshot{}
    | #sf_transfer{}
    | #sf_shift{}.

-doc "Starts unconfigured; no decoder work or neighbor traffic is accepted yet.".
-spec init([]) -> {ok, geometry, #cell{}}.
init([]) -> {ok, geometry, #cell{}}.

-doc "Accepts the global cluster-ID translation constants before local configuration.".
-spec geometry
    (enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, message(), #cell{}) -> hls_statem:cast_result(phase(), #cell{}).
geometry(enter, _, Cell) ->
    {Cell, []};
geometry(
    cast,
    #sf_geometry{
        boundary_limit = Limit,
        boundary_shift = BoundaryShift,
        bulk_shift = BulkShift
    },
    Cell
) ->
    true = Limit > 0 andalso BoundaryShift > 0 andalso BulkShift > 0,
    {configuring,
        Cell#cell{
            boundary_limit = Limit,
            boundary_shift = BoundaryShift,
            bulk_shift = BulkShift
        },
        consume};
geometry(cast, #sf_vertex_config{}, Cell) ->
    {geometry, Cell, fail};
geometry(cast, #sf_phase{}, Cell) ->
    {geometry, Cell, fail};
geometry(cast, #sf_snapshot{}, Cell) ->
    {geometry, Cell, fail};
geometry(cast, #sf_transfer{}, Cell) ->
    {geometry, Cell, fail};
geometry(cast, #sf_shift{}, Cell) ->
    {geometry, Cell, fail}.

-doc "Initializes the vertex identity, connectivity and unique correction ownership.".
-spec configuring
    (enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, message(), #cell{}) -> hls_statem:cast_result(phase(), #cell{}).
configuring(enter, _, Cell) ->
    {Cell, []};
configuring(
    cast,
    #sf_vertex_config{
        source = Source,
        id = Id,
        neighbors = Neighbors,
        syndrome_bit = SyndromeBit,
        retire_mask = RetireMask,
        height = Height,
        top = Top,
        bottom = Bottom,
        boundary = Boundary,
        below = Below
    },
    Cell
) ->
    true = Id >= 0 andalso Neighbors < 64 andalso Height > 0,
    true = (SyndromeBit < 32 orelse SyndromeBit =:= 255),
    true = RetireMask band Neighbors =:= RetireMask,
    {configured,
        Cell#cell{
            node = reset(Id),
            source = Source,
            id = Id,
            neighbors = Neighbors,
            syndrome_bit = SyndromeBit,
            retire_mask = RetireMask,
            height = Height,
            top = Top,
            bottom = Bottom,
            boundary = Boundary,
            below = Below
        },
        consume};
configuring(cast, #sf_geometry{}, Cell) ->
    {configuring, Cell, fail};
configuring(cast, #sf_phase{}, Cell) ->
    {configuring, Cell, fail};
configuring(cast, #sf_snapshot{}, Cell) ->
    {configuring, Cell, fail};
configuring(cast, #sf_transfer{}, Cell) ->
    {configuring, Cell, fail};
configuring(cast, #sf_shift{}, Cell) ->
    {configuring, Cell, fail}.

-doc "Acknowledges startup and waits for epoch zero; early peer traffic remains queued.".
-spec configured
    (enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, message(), #cell{}) -> hls_statem:cast_result(phase(), #cell{}).
configured(enter, _, Cell) ->
    {Cell, [{cast, status, #sf_ready{source = Cell#cell.source}}]};
configured(cast, #sf_phase{epoch = Epoch, kind = Kind, mask = Mask}, Cell = #cell{epoch = Epoch}) ->
    true = Kind < 5,
    Next = begin_phase(Kind, Mask, Cell),
    case Kind of
        0 ->
            case Cell#cell.top of
                true -> {shifting, Next, consume, [{next_event, internal, local_drop}]};
                false -> {shifting, Next, consume}
            end;
        _ ->
            {snapshotting, Next, consume}
    end;
configured(cast, #sf_snapshot{epoch = Epoch}, Cell = #cell{epoch = Epoch}) ->
    {configured, Cell, postpone};
configured(cast, #sf_transfer{epoch = Epoch}, Cell = #cell{epoch = Epoch}) ->
    {configured, Cell, postpone};
configured(cast, #sf_shift{epoch = Epoch}, Cell = #cell{epoch = Epoch}) ->
    {configured, Cell, postpone};
configured(cast, #sf_geometry{}, Cell) ->
    {configured, Cell, fail};
configured(cast, #sf_vertex_config{}, Cell) ->
    {configured, Cell, fail};
configured(cast, #sf_phase{}, Cell) ->
    {configured, Cell, fail};
%% An adjacent peer may publish the one unconditional successor before this phase commits.
configured(cast, #sf_snapshot{epoch = _Epoch, direction = _Direction}, Cell) ->
    ?SF_ADVANCE_SELECT(
        case successor_snapshot(_Epoch, _Direction, Cell) of
            true -> {configured, Cell, postpone};
            false -> {configured, Cell, fail}
        end,
        {configured, Cell, fail}
    );
configured(cast, #sf_transfer{}, Cell) ->
    {configured, Cell, fail};
configured(cast, #sf_shift{}, Cell) ->
    {configured, Cell, fail}.

-doc "Publishes committed state completion, then waits for the next exact phase epoch.".
-spec ready
    (enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, message(), #cell{}) -> hls_statem:cast_result(phase(), #cell{});
    (internal, advance, #cell{}) -> hls_statem:internal_result(phase(), #cell{}).
ready(enter, _, Cell) ->
    Corrections =
        case Cell#cell.retire_valid of
            true ->
                [
                    {cast, correction, #sf_correction{
                        sheet = Cell#cell.retire_sheet,
                        source = Cell#cell.source,
                        edges = Cell#cell.retire_bits
                    }}
                ];
            false ->
                []
        end,
    Done = #sf_done{
        source = Cell#cell.source,
        epoch = Cell#cell.epoch,
        kind = Cell#cell.kind,
        busy = (Cell#cell.node)#node.busy
    },
    Actions = ?SF_ADVANCE_SELECT(
        case Cell#cell.kind =:= 0 orelse Cell#cell.kind =:= 1 orelse Cell#cell.kind =:= 3 of
            true -> Corrections;
            false -> Corrections ++ [{cast, status, Done}]
        end,
        Corrections ++ [{cast, status, Done}]
    ),
    {Cell#cell{epoch = hls_serial:add(hls_serial:counter(32), Cell#cell.epoch, 1)}, Actions};
%% Entry publication, including corrections, must finish before the local successor starts.
ready(internal, advance, Cell) ->
    ?SF_ADVANCE_SELECT(
        begin
            true = Cell#cell.kind =:= 0 orelse Cell#cell.kind =:= 1 orelse Cell#cell.kind =:= 3,
            Next = begin_phase(Cell#cell.kind + 1, Cell#cell.mask, Cell),
            {snapshotting, Next, consume}
        end,
        {ready, Cell, fail}
    );
ready(cast, #sf_phase{epoch = Epoch, kind = Kind, mask = Mask}, Cell = #cell{epoch = Epoch}) ->
    true = Kind < 5,
    Next = begin_phase(Kind, Mask, Cell),
    case Kind of
        0 ->
            case Cell#cell.top of
                true -> {shifting, Next, consume, [{next_event, internal, local_drop}]};
                false -> {shifting, Next, consume}
            end;
        _ ->
            {snapshotting, Next, consume}
    end;
ready(cast, #sf_snapshot{epoch = Epoch}, Cell = #cell{epoch = Epoch}) ->
    {ready, Cell, postpone};
ready(cast, #sf_transfer{epoch = Epoch}, Cell = #cell{epoch = Epoch}) ->
    {ready, Cell, postpone};
ready(cast, #sf_shift{epoch = Epoch}, Cell = #cell{epoch = Epoch}) ->
    {ready, Cell, postpone};
ready(cast, #sf_geometry{}, Cell) ->
    {ready, Cell, fail};
ready(cast, #sf_vertex_config{}, Cell) ->
    {ready, Cell, fail};
ready(cast, #sf_phase{}, Cell) ->
    {ready, Cell, fail};
%% After a half-merge, the next root command may begin the independently shifted sheet.
ready(cast, #sf_snapshot{epoch = _Epoch, direction = _Direction}, Cell) ->
    ?SF_ADVANCE_SELECT(
        case
            Cell#cell.kind =:= 4 andalso
                successor_snapshot(_Epoch, _Direction, Cell#cell{kind = 0})
        of
            true -> {ready, Cell, postpone};
            false -> {ready, Cell, fail}
        end,
        {ready, Cell, fail}
    );
ready(cast, #sf_transfer{}, Cell) ->
    {ready, Cell, fail};
ready(cast, #sf_shift{}, Cell) ->
    {ready, Cell, fail}.

-doc "Sends the old layer downward before copying the upper layer or refreshing the top.".
-spec shifting
    (enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, message(), #cell{}) -> hls_statem:cast_result(phase(), #cell{});
    (internal, local_drop, #cell{}) -> hls_statem:internal_result(phase(), #cell{}).
shifting(enter, _, Cell) ->
    Shift =
        case Cell#cell.below of
            true ->
                [
                    {cast, below, #sf_shift{
                        epoch = Cell#cell.epoch,
                        node = Cell#cell.node,
                        growth = Cell#cell.growth,
                        correction = Cell#cell.correction
                    }}
                ];
            false ->
                []
        end,
    {Cell, Shift};
shifting(internal, local_drop, Cell = #cell{top = true}) ->
    ?SF_LOCAL_READY(commit_drop(Cell#cell.node, 0, 0, Cell));
shifting(
    cast,
    #sf_shift{epoch = Epoch, node = Source, growth = Growth, correction = Correction},
    Cell = #cell{epoch = Epoch, top = false}
) ->
    ?SF_LOCAL_READY(commit_drop(Source, Growth, Correction, Cell));
shifting(cast, #sf_geometry{}, Cell) ->
    {shifting, Cell, fail};
shifting(cast, #sf_vertex_config{}, Cell) ->
    {shifting, Cell, fail};
shifting(cast, #sf_phase{}, Cell) ->
    {shifting, Cell, fail};
%% An adjacent peer may publish the one unconditional successor before this phase commits.
shifting(cast, #sf_snapshot{epoch = _Epoch, direction = _Direction}, Cell) ->
    ?SF_ADVANCE_SELECT(
        case successor_snapshot(_Epoch, _Direction, Cell) of
            true -> {shifting, Cell, postpone};
            false -> {shifting, Cell, fail}
        end,
        {shifting, Cell, fail}
    );
shifting(cast, #sf_transfer{}, Cell) ->
    {shifting, Cell, fail};
shifting(cast, #sf_shift{}, Cell) ->
    {shifting, Cell, fail}.

-doc "Collects one immutable snapshot per existing neighbor before any local phase computation.".
-spec snapshotting
    (enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, message(), #cell{}) -> hls_statem:cast_result(phase(), #cell{});
    (internal, hls_statem:gather_complete(), #cell{}) ->
        hls_statem:internal_result(phase(), #cell{}).
snapshotting(enter, _, Cell) ->
    Message = #sf_snapshot{epoch = Cell#cell.epoch, node = Cell#cell.node},
    Open = [
        {open_gather, snapshots, Cell#cell.epoch, {members_mask, 6, Cell#cell.neighbors}, #node{}}
    ],
    {Cell,
        Open ++ ?SF_CAST(Cell, 1, west, Message#sf_snapshot{direction = 2}) ++
            ?SF_CAST(Cell, 2, east, Message#sf_snapshot{direction = 1}) ++
            ?SF_CAST(Cell, 4, down, Message#sf_snapshot{direction = 4}) ++
            ?SF_CAST(Cell, 8, up, Message#sf_snapshot{direction = 3}) ++
            ?SF_CAST(Cell, 16, north, Message#sf_snapshot{direction = 6}) ++
            ?SF_CAST(Cell, 32, south, Message#sf_snapshot{direction = 5})};
snapshotting(
    cast,
    #sf_snapshot{epoch = Epoch, direction = Direction, node = Node},
    Cell = #cell{epoch = Epoch}
) when Direction >= 1, Direction =< 6 ->
    {snapshotting, Cell,
        {gather, snapshots, Epoch, hls_type:as(hls_nums:u32(), Direction - 1), Node}};
%% The immutable indexed view is consumed here, before releasing its storage.
snapshotting(
    internal,
    {gather_complete, snapshots, Epoch, Members, Values},
    Cell = #cell{epoch = Epoch}
) ->
    true = Members =:= hls_type:as(hls_nums:uN(6), Cell#cell.neighbors),
    case Cell#cell.kind =:= 1 orelse Cell#cell.kind =:= 3 of
        true ->
            ?SF_LOCAL_READY(commit_grow(Cell#cell{seen = Cell#cell.neighbors}, Values));
        false ->
            Next = propose_merge(Cell, Values),
            case Members =:= 0 of
                true -> {transferring, Next, consume, [{next_event, internal, complete}]};
                false -> {transferring, Next, consume}
            end
    end;
snapshotting(cast, #sf_transfer{epoch = Epoch}, Cell = #cell{epoch = Epoch}) ->
    {snapshotting, Cell, postpone};
snapshotting(cast, #sf_geometry{}, Cell) ->
    {snapshotting, Cell, fail};
snapshotting(cast, #sf_vertex_config{}, Cell) ->
    {snapshotting, Cell, fail};
snapshotting(cast, #sf_phase{}, Cell) ->
    {snapshotting, Cell, fail};
%% An adjacent peer may publish the one unconditional successor before this phase commits.
snapshotting(cast, #sf_snapshot{epoch = _Epoch, direction = _Direction}, Cell) ->
    ?SF_ADVANCE_SELECT(
        case successor_snapshot(_Epoch, _Direction, Cell) of
            true -> {snapshotting, Cell, postpone};
            false -> {snapshotting, Cell, fail}
        end,
        {snapshotting, Cell, fail}
    );
snapshotting(cast, #sf_transfer{}, Cell) ->
    {snapshotting, Cell, fail};
snapshotting(cast, #sf_shift{}, Cell) ->
    {snapshotting, Cell, fail}.

-doc "Publishes the completed merge proposal and combines every incoming transfer by parity.".
-spec transferring
    (enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, message(), #cell{}) -> hls_statem:cast_result(phase(), #cell{});
    (internal, complete | hls_statem:reduction_complete(), #cell{}) ->
        hls_statem:internal_result(phase(), #cell{}).
transferring(enter, _, Cell) ->
    Message = #sf_transfer{epoch = Cell#cell.epoch, outgoing = Cell#cell.outgoing},
    Open =
        case Cell#cell.neighbors of
            0 ->
                [];
            _ ->
                [
                    {open_reduction, transfers, Cell#cell.epoch,
                        {members_mask, 6, Cell#cell.neighbors},
                        {commutative_monoid, #transfer_sum{edges = 0, defect = false}}}
                ]
        end,
    {Cell,
        Open ++ ?SF_CAST(Cell, 1, west, Message#sf_transfer{direction = 2}) ++
            ?SF_CAST(Cell, 2, east, Message#sf_transfer{direction = 1}) ++
            ?SF_CAST(Cell, 4, down, Message#sf_transfer{direction = 4}) ++
            ?SF_CAST(Cell, 8, up, Message#sf_transfer{direction = 3}) ++
            ?SF_CAST(Cell, 16, north, Message#sf_transfer{direction = 6}) ++
            ?SF_CAST(Cell, 32, south, Message#sf_transfer{direction = 5})};
transferring(
    cast,
    #sf_transfer{epoch = Epoch, direction = Direction, outgoing = Outgoing},
    Cell = #cell{epoch = Epoch}
) when Direction >= 1, Direction =< 6, Outgoing =< 6 ->
    {transferring, Cell,
        {contribute, transfers, Epoch, hls_type:as(hls_nums:u32(), Direction - 1), #transfer_sum{
            edges =
                case Outgoing =:= opposite(Direction) of
                    true -> hls_type:as(hls_nums:uN(6), direction_bit(Direction));
                    false -> 0
                end,
            defect = Outgoing =:= opposite(Direction)
        }}};
transferring(
    internal,
    {reduction_complete, transfers, Epoch, #transfer_sum{edges = Edges, defect = Defect}},
    Cell = #cell{epoch = Epoch}
) ->
    Node = Cell#cell.node,
    {ready,
        Cell#cell{
            seen = Cell#cell.neighbors,
            correction = Cell#cell.correction bxor Edges,
            node = Node#node{defect = Node#node.defect =/= Defect}
        },
        consume};
transferring(internal, complete, Cell) ->
    {ready, Cell, consume};
transferring(cast, #sf_geometry{}, Cell) ->
    {transferring, Cell, fail};
transferring(cast, #sf_vertex_config{}, Cell) ->
    {transferring, Cell, fail};
transferring(cast, #sf_phase{}, Cell) ->
    {transferring, Cell, fail};
transferring(cast, #sf_snapshot{}, Cell) ->
    {transferring, Cell, fail};
transferring(cast, #sf_transfer{}, Cell) ->
    {transferring, Cell, fail};
transferring(cast, #sf_shift{}, Cell) ->
    {transferring, Cell, fail}.

-doc "Combines independent transfer parities without changing application state.".
-spec reduce(transfers, #transfer_sum{}, #transfer_sum{}) -> #transfer_sum{}.
reduce(transfers, #transfer_sum{edges = A, defect = X}, #transfer_sum{edges = B, defect = Y}) ->
    #transfer_sum{edges = A bxor B, defect = X =/= Y}.

-doc "Decodes callback state obtained through hls_statem:info, including vertex and incident-edge replicas.".
-spec snapshot(#cell{}) -> map().
snapshot(Cell) ->
    #{
        node => Cell#cell.node,
        growth => Cell#cell.growth,
        correction => Cell#cell.correction,
        epoch => Cell#cell.epoch,
        kind => Cell#cell.kind,
        seen => Cell#cell.seen,
        outgoing => Cell#cell.outgoing,
        drop_count => Cell#cell.drop_count
    }.

-if(?SNOWFLAKE_LOCAL_ADVANCE).
%% Only growth/merge snapshots one unconditional phase ahead may await local completion.
-spec successor_snapshot(hls_nums:u32(), hls_nums:u8(), #cell{}) -> boolean().
successor_snapshot(Epoch, Direction, Cell) ->
    (Cell#cell.kind =:= 0 orelse Cell#cell.kind =:= 1 orelse Cell#cell.kind =:= 3) andalso
        Epoch =:= hls_serial:add(hls_serial:counter(32), Cell#cell.epoch, 1) andalso
        Direction >= 1 andalso Direction =< 6 andalso
        Cell#cell.neighbors band direction_bit(Direction) =/= 0.
-endif.

%% Clear phase metadata without changing the local vertex or incident-edge state.
-spec begin_phase(hls_nums:u8(), hls_nums:u32(), #cell{}) -> #cell{}.
begin_phase(Kind, Mask, Cell) ->
    Cell#cell{
        kind = Kind,
        mask = Mask,
        seen = 0,
        outgoing = 0,
        retire_valid = false
    }.

%% Drop retirement observes old edges; warmup saturation survives wrapping sheet tags.
-spec commit_drop(#node{}, hls_nums:uN(12), hls_nums:uN(6), #cell{}) -> #cell{}.
commit_drop(Source, Growth, Correction, Cell) ->
    Shift =
        case Source#node.cid < Cell#cell.boundary_limit of
            true -> Cell#cell.boundary_shift;
            false -> Cell#cell.bulk_shift
        end,
    Syndrome =
        case Cell#cell.syndrome_bit < 32 of
            true ->
                Cell#cell.mask band (hls_type:as(hls_nums:u32(), 1) bsl Cell#cell.syndrome_bit) =/=
                    0;
            false ->
                false
        end,
    Warmup =
        case Cell#cell.warmup < Cell#cell.height of
            true -> Cell#cell.warmup + 1;
            false -> Cell#cell.warmup
        end,
    Cell#cell{
        node = drop(Source, Shift, Cell#cell.top, Syndrome),
        growth = mask_growth(Growth, Cell#cell.neighbors),
        correction = Correction band hls_type:as(hls_nums:uN(6), Cell#cell.neighbors),
        drop_count = (Cell#cell.drop_count + 1) band 16#ffffffff,
        warmup = Warmup,
        retire_valid = Cell#cell.warmup =:= Cell#cell.height andalso Cell#cell.retire_mask =/= 0,
        retire_sheet =
            (Cell#cell.drop_count - hls_type:as(hls_nums:u32(), Cell#cell.height)) band 16#ffffffff,
        retire_bits = Cell#cell.correction band hls_type:as(hls_nums:uN(6), Cell#cell.retire_mask)
    }.

%% Both endpoint replicas add the same old-snapshot contributions before clipping.
-spec commit_grow(#cell{}, hls_lists:list(#node{}, 6)) -> #cell{}.
commit_grow(Cell, Values) ->
    Whole = Cell#cell.kind =:= 1,
    {Node, WillGrow} = grow(Cell#cell.node, Whole, Cell#cell.bottom),
    G = Cell#cell.growth,
    M = Cell#cell.neighbors,
    West = edge_growth(G band 3, WillGrow, hls_lists:nth(1, Values), Whole, M band 1 =/= 0),
    East = edge_growth((G bsr 2) band 3, WillGrow, hls_lists:nth(2, Values), Whole, M band 2 =/= 0),
    Down = edge_growth((G bsr 4) band 3, WillGrow, hls_lists:nth(3, Values), Whole, M band 4 =/= 0),
    Up = edge_growth((G bsr 6) band 3, WillGrow, hls_lists:nth(4, Values), Whole, M band 8 =/= 0),
    North = edge_growth(
        (G bsr 8) band 3, WillGrow, hls_lists:nth(5, Values), Whole, M band 16 =/= 0
    ),
    South = edge_growth(
        (G bsr 10) band 3, WillGrow, hls_lists:nth(6, Values), Whole, M band 32 =/= 0
    ),
    Cell#cell{
        node = Node,
        growth =
            West bor (East bsl 2) bor (Down bsl 4) bor
                (Up bsl 6) bor (North bsl 8) bor (South bsl 10)
    }.

%% A missing edge has no replica; growth contribution eligibility ignores the bottom flag.
-spec edge_growth(hls_nums:uN(12), boolean(), #node{}, boolean(), boolean()) -> hls_nums:uN(12).
edge_growth(Growth, Own, Other, Whole, Present) ->
    case Present of
        false ->
            0;
        true ->
            {_, Neighbor} = grow(Other, Whole, false),
            OwnBit =
                case Own of
                    true -> 1;
                    false -> 0
                end,
            OtherBit =
                case Neighbor of
                    true -> 1;
                    false -> 0
                end,
            Sum = Growth + OwnBit + OtherBit,
            case Sum > 2 of
                true -> 2;
                false -> Sum
            end
    end.

%% Only fully grown edges expose neighbors to the unchanged reference kernel.
-spec propose_merge(#cell{}, hls_lists:list(#node{}, 6)) -> #cell{}.
propose_merge(Cell, Values) ->
    G = Cell#cell.growth,
    {W, WB} = accessible(hls_lists:nth(1, Values), G band 3, 1),
    {E, EB} = accessible(hls_lists:nth(2, Values), (G bsr 2) band 3, 2),
    {D, DB} = accessible(hls_lists:nth(3, Values), (G bsr 4) band 3, 4),
    {U, UB} = accessible(hls_lists:nth(4, Values), (G bsr 6) band 3, 8),
    {N, NB} = accessible(hls_lists:nth(5, Values), (G bsr 8) band 3, 16),
    {S, SB} = accessible(hls_lists:nth(6, Values), (G bsr 10) band 3, 32),
    {Node, Outgoing} = merge_surface(
        Cell#cell.node,
        W,
        E,
        D,
        U,
        N,
        S,
        WB bor EB bor DB bor UB bor NB bor SB,
        Cell#cell.kind =:= 2,
        Cell#cell.boundary,
        Cell#cell.id
    ),
    Own =
        case Outgoing of
            0 -> 0;
            _ -> direction_bit(Outgoing)
        end,
    true = Own band Cell#cell.neighbors =:= Own,
    Cell#cell{
        node = Node,
        outgoing = Outgoing,
        seen = 0,
        correction = Cell#cell.correction bxor hls_type:as(hls_nums:uN(6), Own)
    }.

%% Inaccessible neighbors are all-zero values, including when a pointer still names one.
-spec accessible(#node{}, hls_nums:uN(12), hls_nums:u8()) -> {#node{}, hls_nums:u8()}.
accessible(Node, Growth, Bit) ->
    case Growth =:= 2 of
        true -> {Node, Bit};
        false -> {#node{}, 0}
    end.

%% Direction masks share the same bit positions as correction replicas.
-spec direction_bit(hls_nums:u8()) -> hls_nums:u8().
direction_bit(Direction) -> hls_type:as(hls_nums:u8(), 1) bsl (Direction - 1).

%% Convert a receiver-relative sender direction to the sender's direction toward this vertex.
-spec opposite(hls_nums:u8()) -> hls_nums:u8().
opposite(Direction) ->
    case Direction of
        1 -> 2;
        2 -> 1;
        3 -> 4;
        4 -> 3;
        5 -> 6;
        6 -> 5
    end.

%% Shifted edge replicas absent at the destination are discarded.
-spec mask_growth(hls_nums:uN(12), hls_nums:u8()) -> hls_nums:uN(12).
mask_growth(Growth, Mask) ->
    W =
        case Mask band 1 =/= 0 of
            true -> Growth band 3;
            false -> 0
        end,
    E =
        case Mask band 2 =/= 0 of
            true -> Growth band 12;
            false -> 0
        end,
    D =
        case Mask band 4 =/= 0 of
            true -> Growth band 48;
            false -> 0
        end,
    U =
        case Mask band 8 =/= 0 of
            true -> Growth band 192;
            false -> 0
        end,
    N =
        case Mask band 16 =/= 0 of
            true -> Growth band 768;
            false -> 0
        end,
    S =
        case Mask band 32 =/= 0 of
            true -> Growth band 3072;
            false -> 0
        end,
    W bor E bor D bor U bor N bor S.

%% Reuse the reference-derived numerical transitions without a second implementation.
-define(SNOWFLAKE_SURFACE_ONLY, true).
-include("snowflake_node_impl.hrl").
