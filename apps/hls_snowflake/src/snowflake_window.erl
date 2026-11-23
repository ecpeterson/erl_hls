-module(snowflake_window).
%% Follows localuf's MIT-licensed phase order; see ../reference/LICENSE.localuf.
-moduledoc """
BEAM driver for bounded repetition and planar surface-code Snowflake windows.

Distance and window height fix the node/edge arrays at construction. Every
decode admits one top-sheet detector mask and retires the old bottom edges,
including empty correction sheets. The driver preserves the reference's
global phase barriers; its ticks are algorithm steps, not hardware clocks.
Only snowflake_node's transitions are intended for direct XLS lowering.
""".
-export([new/3, decode/2, snapshot/1, stream/4, profile/4]).
-export_type([state/0, report/0]).
-include("snowflake_node.hrl").

%% Mutable algorithm fields of an edge; topology is separate and constant.
-record(edge, {growth = 0 :: 0..2, correction = false :: boolean()}).
%% Geometry comes from one authority shared by stream execution and profiling.
-type geometry() :: snowflake_geometry:geometry().
%% A coordinate identifies a vertex independently of its storage ordering.
-type coordinate() :: snowflake_geometry:coordinate().
%% Neighbor indices use the geometry's constant direction ordering.
-type neighbor() :: snowflake_geometry:neighbor().

-doc "A fixed-size decoding window plus monotonically increasing input-sheet and algorithm-step counters.".
-opaque state() :: #{
    geometry := geometry(),
    nodes := tuple(),
    edges := tuple(),
    sheet := non_neg_integer(),
    tick := non_neg_integer()
}.

-doc "Ordered retired corrections and the complete phase snapshots for one admitted sheet.".
-type report() :: #{
    input_mask := non_neg_integer(),
    retired_sheet := integer(),
    retired_spatial_mask := non_neg_integer(),
    retired_temporal_mask := non_neg_integer(),
    phase_counts := map(),
    ticks := non_neg_integer(),
    state := map(),
    trace := [map()]
}.

-doc "Creates a phenomenological code window; distance and height must be between 2 and 255.".
-spec new(snowflake_geometry:code(), 2..((1 bsl 8) - 1), 2..((1 bsl 8) - 1)) -> state().
new(Code, Distance, Height) ->
    Geometry =
        #{ids := Ids, endpoints := Endpoints} = snowflake_geometry:new(Code, Distance, Height),
    #{
        geometry => Geometry,
        nodes => list_to_tuple([snowflake_node:reset(Id) || Id <- tuple_to_list(Ids)]),
        edges => list_to_tuple([#edge{} || _ <- tuple_to_list(Endpoints)]),
        sheet => 0,
        tick => 0
    }.

-doc "Admits one detector mask and returns the next window and ordered retirements. Raises merge_budget_exhausted after 10,000 nonquiescent merge steps.".
-spec decode(non_neg_integer(), state()) -> {state(), report()}.
decode(Mask, State = #{geometry := Geometry, sheet := Sheet, tick := Tick}) ->
    #{syndrome_width := SyndromeWidth, height := Height} = Geometry,
    true = Mask >= 0 andalso Mask < (1 bsl SyndromeWidth),
    {Spatial, Temporal} = retire(State),
    Dropped = drop(Mask, State),
    {WholeGrown, WholeGrowth} = grow(true, Dropped),
    {WholeMerged, WholeTrace} = merge_until_idle(true, WholeGrown, 10000, []),
    {HalfGrown, HalfGrowth} = grow(false, WholeMerged),
    {HalfMerged, HalfTrace} = merge_until_idle(false, HalfGrown, 10000, []),
    Next = HalfMerged#{sheet := Sheet + 1},
    Trace =
        [trace(drop, Dropped, #{accesses => drop_accesses(State)}), WholeGrowth] ++
            WholeTrace ++ [HalfGrowth] ++ HalfTrace,
    Report = #{
        input_mask => Mask,
        retired_sheet => Sheet - Height,
        retired_spatial_mask => Spatial,
        retired_temporal_mask => Temporal,
        phase_counts => #{
            drop => 1,
            grow_whole => 1,
            merge_whole => length(WholeTrace),
            grow_half => 1,
            merge_half => length(HalfTrace)
        },
        ticks => maps:get(tick, Next) - Tick,
        state => snapshot(Next),
        trace => Trace
    },
    {Next, Report}.

-doc "Decodes masks in order and returns all reports without inserting unrequested drain sheets.".
-spec stream(snowflake_geometry:code(), 2..((1 bsl 8) - 1), 2..((1 bsl 8) - 1), [non_neg_integer()]) ->
    [report()].
stream(Code, Distance, Height, Masks) ->
    {Reports, _} = lists:mapfoldl(
        fun(Mask, State) ->
            {Next, Report} = decode(Mask, State),
            {Report, Next}
        end,
        new(Code, Distance, Height),
        Masks
    ),
    Reports.

-doc "Returns algorithm phases and a proposed node-centric memory-request mapping; neither is an accepted hardware schedule.".
-spec profile(snowflake_geometry:code(), 2..((1 bsl 8) - 1), 2..((1 bsl 8) - 1), [non_neg_integer()]) ->
    map().
profile(Code, Distance, Height, Masks) ->
    Reports = stream(Code, Distance, Height, Masks),
    #{geometry := Geometry} = new(Code, Distance, Height),
    #{
        schema => <<"snowflake-algorithm-trace-v1">>,
        code => Code,
        distance => Distance,
        window_height => Height,
        time_unit => <<"algorithm_phase">>,
        access_model =>
            <<"Proposed uncoalesced node-centric memory requests, not literal BEAM array operations or an accepted hardware schedule. Growth contributions and defect XORs require merging or arbitration.">>,
        geometry => profile_geometry(Geometry),
        sheets => [maps:without([state, trace], R) || R <- Reports],
        phases => [
            maps:without([state, growth_nodes, edge_increments, transfers], T)
         || R <- Reports, T <- maps:get(trace, R)
        ]
    }.

%% Export topology and mask ownership explicitly; consumers need not interpret coordinates.
-spec profile_geometry(geometry()) -> map().
profile_geometry(#{
    kind := Code,
    coordinates := Coordinates,
    endpoints := Endpoints,
    ids := Ids,
    neighbors := Neighbors,
    boundaries := Boundaries,
    bottoms := Bottoms,
    syndrome_bits := SyndromeBits,
    retired_spatial := Spatial,
    retired_temporal := Temporal
}) ->
    #{
        kind => Code,
        nodes => [
            #{
                address => I - 1,
                coordinate => tuple_to_list(element(I, Coordinates)),
                id => element(I, Ids),
                boundary => element(I, Boundaries),
                bottom => element(I, Bottoms),
                syndrome_bit =>
                    case element(I, SyndromeBits) of
                        -1 -> null;
                        Bit -> Bit
                    end,
                neighbors => [
                    #{direction => Direction, node => Node - 1, edge => Edge - 1}
                 || {Direction, Node, Edge} <- element(I, Neighbors)
                ]
            }
         || I <- lists:seq(1, tuple_size(Coordinates))
        ],
        edges => [
            begin
                {A, B} = element(I, Endpoints),
                #{address => I - 1, endpoints => [tuple_to_list(A), tuple_to_list(B)]}
            end
         || I <- lists:seq(1, tuple_size(Endpoints))
        ],
        retired_spatial_edges => [Edge - 1 || Edge <- tuple_to_list(Spatial)],
        retired_temporal_edges => [Edge - 1 || Edge <- tuple_to_list(Temporal)]
    }.

-doc "Returns geometry-addressed node/edge fields suitable for reference comparison.".
-spec snapshot(state()) -> map().
snapshot(#{geometry := Geometry, nodes := Nodes, edges := Edges}) ->
    #{coordinates := Coordinates, endpoints := Endpoints, ids := Ids} = Geometry,
    #{
        nodes => [
            node_snapshot(element(I, Coordinates), element(I, Nodes), element(I, Ids))
         || I <- lists:seq(1, tuple_size(Nodes))
        ],
        edges => [
            edge_snapshot(element(I, Endpoints), element(I, Edges))
         || I <- lists:seq(1, tuple_size(Edges))
        ]
    }.

%% Read each correction class in its explicit geometry bit order before reuse.
-spec retire(state()) -> {non_neg_integer(), non_neg_integer()}.
retire(#{geometry := #{retired_spatial := Spatial, retired_temporal := Temporal}, edges := Edges}) ->
    {retire_mask(Spatial, Edges), retire_mask(Temporal, Edges)}.

%% Retirement masks represent parity on edges; they do not classify logical outcomes.
-spec retire_mask(tuple(), tuple()) -> non_neg_integer().
retire_mask(Indices, Edges) ->
    lists:foldl(
        fun(Bit, Mask) ->
            case (element(element(Bit + 1, Indices), Edges))#edge.correction of
                true -> Mask bor (1 bsl Bit);
                false -> Mask
            end
        end,
        0,
        lists:seq(0, tuple_size(Indices) - 1)
    ).

%% Shift the entire previous window from snapshots, then inject the new top sheet.
-spec drop(non_neg_integer(), state()) -> state().
drop(Mask, State = #{geometry := Geometry, nodes := Nodes, edges := Edges, tick := Tick}) ->
    #{
        node_above := AboveNodes,
        edge_above := AboveEdges,
        syndrome_bits := SyndromeBits,
        cid_boundary_limit := Limit,
        cid_boundary_shift := BoundaryShift,
        cid_bulk_shift := BulkShift
    } = Geometry,
    NewNodes = [
        begin
            case element(I, AboveNodes) of
                0 ->
                    Bit = element(I, SyndromeBits),
                    snowflake_node:drop(
                        element(I, Nodes),
                        0,
                        true,
                        Bit >= 0 andalso Mask band (1 bsl Bit) =/= 0
                    );
                Above ->
                    Source = element(Above, Nodes),
                    Shift =
                        case Source#node.cid < Limit of
                            true -> BoundaryShift;
                            false -> BulkShift
                        end,
                    snowflake_node:drop(Source, Shift, false, false)
            end
        end
     || I <- lists:seq(1, tuple_size(Nodes))
    ],
    NewEdges = [
        case element(I, AboveEdges) of
            0 -> #edge{};
            Above -> element(Above, Edges)
        end
     || I <- lists:seq(1, tuple_size(Edges))
    ],
    State#{nodes := list_to_tuple(NewNodes), edges := list_to_tuple(NewEdges), tick := Tick + 1}.

%% Sum independent incident half-edge growth and clip at full growth.
-spec grow(boolean(), state()) -> {state(), map()}.
grow(Whole, State = #{geometry := Geometry, nodes := Nodes, edges := Edges, tick := Tick}) ->
    #{bottoms := Bottoms, neighbors := Neighbors} = Geometry,
    Decisions = [
        snowflake_node:grow(element(I, Nodes), Whole, element(I, Bottoms))
     || I <- lists:seq(1, tuple_size(Nodes))
    ],
    Growth = lists:foldl(
        fun({I, {_Node, WillGrow}}, Acc) ->
            case WillGrow of
                false ->
                    Acc;
                true ->
                    lists:foldl(
                        fun({_Direction, _Neighbor, Edge}, Counts) ->
                            maps:update_with(Edge, fun(N) -> N + 1 end, 1, Counts)
                        end,
                        Acc,
                        element(I, Neighbors)
                    )
            end
        end,
        #{},
        lists:zip(lists:seq(1, length(Decisions)), Decisions)
    ),
    NewEdges = [
        begin
            Edge = element(I, Edges),
            Edge#edge{growth = min(2, Edge#edge.growth + maps:get(I, Growth, 0))}
        end
     || I <- lists:seq(1, tuple_size(Edges))
    ],
    Next = State#{
        nodes := list_to_tuple([Node || {Node, _} <- Decisions]),
        edges := list_to_tuple(NewEdges),
        tick := Tick + 1
    },
    Stage =
        case Whole of
            true -> grow_whole;
            false -> grow_half
        end,
    {Next,
        trace(Stage, Next, #{
            growth_nodes => [
                I
             || {I, {_, true}} <-
                    lists:zip(lists:seq(1, length(Decisions)), Decisions)
            ],
            edge_increments => Growth,
            accesses => grow_accesses(State, Decisions)
        })}.

%% Stop after the first quiescent merge step; retain a finite diagnostic budget.
-spec merge_until_idle(boolean(), state(), non_neg_integer(), [map()]) -> {state(), [map()]}.
merge_until_idle(_Whole, _State, 0, _Acc) ->
    error(merge_budget_exhausted);
merge_until_idle(Whole, State, Budget, Acc) ->
    {Next, Entry} = merge(Whole, State),
    case lists:any(fun(#node{busy = Busy}) -> Busy end, tuple_to_list(maps:get(nodes, Next))) of
        false -> {Next, lists:reverse([Entry | Acc])};
        true -> merge_until_idle(Whole, Next, Budget - 1, [Entry | Acc])
    end.

%% Read only old neighbor fields; commit all self-updates and XOR transfers together.
-spec merge(boolean(), state()) -> {state(), map()}.
merge(Whole, State = #{geometry := Geometry, nodes := Nodes, edges := Edges, tick := Tick}) ->
    #{kind := Code, ids := Ids, neighbors := Neighbors, boundaries := Boundaries} = Geometry,
    Decisions = [
        begin
            Access = [
                N
             || N = {_, _, Edge} <- element(I, Neighbors),
                (element(Edge, Edges))#edge.growth =:= 2
            ],
            {Snapshots, Mask} = neighbor_snapshots(Access, Nodes),
            {Node, Direction} = merge_node(
                Code,
                element(I, Nodes),
                Snapshots,
                Mask,
                Whole,
                element(I, Boundaries),
                element(I, Ids)
            ),
            Transfer =
                case Direction of
                    0 ->
                        none;
                    _ ->
                        {Direction, Target, Edge} = lists:keyfind(Direction, 1, Access),
                        {Target, Edge}
                end,
            {Node, Transfer}
        end
     || I <- lists:seq(1, tuple_size(Nodes))
    ],
    BaseNodes = list_to_tuple([Node || {Node, _} <- Decisions]),
    {NewNodes, NewEdges} = lists:foldl(
        fun
            ({_Node, none}, Acc) ->
                Acc;
            ({_Node, {Target, Edge}}, {NodeAcc, EdgeAcc}) ->
                TargetNode = element(Target, NodeAcc),
                TargetEdge = element(Edge, EdgeAcc),
                {
                    setelement(Target, NodeAcc, TargetNode#node{defect = not TargetNode#node.defect}),
                    setelement(Edge, EdgeAcc, TargetEdge#edge{
                        correction = not TargetEdge#edge.correction
                    })
                }
        end,
        {BaseNodes, Edges},
        Decisions
    ),
    Next = State#{nodes := NewNodes, edges := NewEdges, tick := Tick + 1},
    Stage =
        case Whole of
            true -> merge_whole;
            false -> merge_half
        end,
    Transfers = [
        {I, Target, Edge}
     || {I, {_, {Target, Edge}}} <-
            lists:zip(lists:seq(1, length(Decisions)), Decisions)
    ],
    {Next,
        trace(Stage, Next, #{transfers => Transfers, accesses => merge_accesses(State, Transfers)})}.

%% Both graph types use the same fixed snapshot slots; absent neighbors are inaccessible.
-spec neighbor_snapshots([neighbor()], tuple()) -> {tuple(), 0..((1 bsl 6) - 1)}.
neighbor_snapshots(Access, Nodes) ->
    Empty = snowflake_node:reset(0),
    lists:foldl(
        fun({Direction, Neighbor, _Edge}, {Acc, Bits}) ->
            {setelement(Direction, Acc, element(Neighbor, Nodes)), Bits bor (1 bsl (Direction - 1))}
        end,
        {{Empty, Empty, Empty, Empty, Empty, Empty}, 0},
        Access
    ).

%% Geometry selects a fixed-arity kernel; its internal priority remains code-specific.
-spec merge_node(
    snowflake_geometry:code(),
    #node{},
    tuple(),
    0..((1 bsl 6) - 1),
    boolean(),
    boolean(),
    non_neg_integer()
) -> {#node{}, 0..6}.
merge_node(repetition, Node, {W, E, D, U, _, _}, Mask, Whole, Boundary, Id) ->
    snowflake_node:merge(Node, W, E, D, U, Mask, Whole, Boundary, Id);
merge_node(surface, Node, {W, E, D, U, N, S}, Mask, Whole, Boundary, Id) ->
    snowflake_node:merge_surface(Node, W, E, D, U, N, S, Mask, Whole, Boundary, Id).

%% Trace snapshots describe algorithm stages; no physical issue width is implied.
-spec trace(atom(), state(), map()) -> map().
trace(Stage, State = #{sheet := Sheet, tick := Tick}, Details) ->
    Details#{
        phase => Stage, sheet => Sheet, epoch => Sheet, tick => Tick - 1, state => snapshot(State)
    }.

%% Model node-centric requests; only explicitly tagged input snapshots permit read sharing.
-spec access(atom(), pos_integer(), pos_integer(), atom()) -> map().
access(Kind, Address, Actor, Action) ->
    Base = #{kind => Kind, address => Address - 1, actor => Actor - 1, action => Action},
    case
        (Kind =:= node_read orelse Kind =:= edge_read) andalso
            lists:member(Action, [snapshot, access, drop, retire])
    of
        true -> Base#{version => <<"input_snapshot">>};
        false -> Base
    end.

%% Shifts and retirement read old storage; each destination has exactly one writer.
-spec drop_accesses(state()) -> [map()].
drop_accesses(#{
    geometry := #{
        node_above := AboveNodes,
        edge_above := AboveEdges,
        retired_spatial := Spatial,
        retired_temporal := Temporal
    },
    nodes := Nodes,
    edges := Edges
}) ->
    lists:append([
        begin
            Source =
                case element(I, AboveNodes) of
                    0 -> I;
                    Above -> Above
                end,
            [access(node_read, Source, I, drop), access(node_write, I, I, drop)]
        end
     || I <- lists:seq(1, tuple_size(Nodes))
    ]) ++
        lists:append([
            begin
                SourceReads =
                    case element(I, AboveEdges) of
                        0 -> [];
                        Above -> [access(edge_read, Above, I, drop)]
                    end,
                RetireReads =
                    case
                        lists:member(I, tuple_to_list(Spatial)) orelse
                            lists:member(I, tuple_to_list(Temporal))
                    of
                        true -> [access(edge_read, I, I, retire)];
                        false -> []
                    end,
                SourceReads ++ RetireReads ++ [access(edge_write, I, I, drop)]
            end
         || I <- lists:seq(1, tuple_size(Edges))
        ]).

%% Model separate endpoint contributions; the BEAM driver instead sums them before its edge sweep.
-spec grow_accesses(state(), [{#node{}, boolean()}]) -> [map()].
grow_accesses(#{geometry := #{neighbors := Neighbors}}, Decisions) ->
    lists:append([
        begin
            EdgeAccesses =
                case WillGrow of
                    false ->
                        [];
                    true ->
                        lists:append([
                            [access(edge_read, Edge, I, grow), access(edge_write, Edge, I, grow)]
                         || {_, _, Edge} <- element(I, Neighbors)
                        ])
                end,
            [
                access(node_read, I, I, snapshot),
                access(node_write, I, I, self_update)
                | EdgeAccesses
            ]
        end
     || {I, {_, WillGrow}} <- lists:zip(lists:seq(1, length(Decisions)), Decisions)
    ]).

%% Retain incoming XOR read-modify-writes separately from each target's self write.
-spec merge_accesses(state(), [{pos_integer(), pos_integer(), pos_integer()}]) -> [map()].
merge_accesses(#{geometry := #{neighbors := Neighbors}, nodes := Nodes, edges := Edges}, Transfers) ->
    lists:append([
        [access(node_read, I, I, snapshot), access(node_write, I, I, self_update)] ++
            lists:append([
                [access(edge_read, Edge, I, access)] ++
                    case (element(Edge, Edges))#edge.growth of
                        2 -> [access(node_read, Neighbor, I, snapshot)];
                        _ -> []
                    end
             || {_, Neighbor, Edge} <- element(I, Neighbors)
            ])
     || I <- lists:seq(1, tuple_size(Nodes))
    ]) ++
        lists:append([
            [
                access(node_read, Target, Source, transfer_xor),
                access(node_write, Target, Source, transfer_xor),
                access(edge_read, Edge, Source, transfer_xor),
                access(edge_write, Edge, Source, transfer_xor)
            ]
         || {Source, Target, Edge} <- Transfers
        ]).

%% Stable named fields avoid relying on record tuple layout in external fixtures.
-spec node_snapshot(coordinate(), #node{}, non_neg_integer()) -> map().
node_snapshot(Coordinate, Node, Id) ->
    #{
        coordinate => tuple_to_list(Coordinate),
        id => Id,
        active => Node#node.active,
        whole => Node#node.whole,
        cid => Node#node.cid,
        defect => Node#node.defect,
        pointer => Node#node.pointer,
        grown => Node#node.grown,
        unrooted => Node#node.unrooted,
        busy => Node#node.busy
    }.

%% Expose correction parity and half-edge growth for every finite graph edge.
-spec edge_snapshot({coordinate(), coordinate()}, #edge{}) -> map().
edge_snapshot({A, B}, #edge{growth = Growth, correction = Correction}) ->
    #{
        endpoints => [tuple_to_list(A), tuple_to_list(B)],
        growth => Growth,
        correction => Correction
    }.
