-module(snowflake_geometry).
-moduledoc "Fixed phenomenological repetition and planar surface-code windows for Snowflake.".
-export([new/3]).
-export_type([code/0, coordinate/0, neighbor/0, geometry/0]).

-doc "The repetition graph or one CSS sector of the unrotated planar surface code.".
-type code() :: repetition | surface.
-doc "A spatial site and its nonnegative window time, including west/east boundaries.".
-type coordinate() ::
    {integer(), non_neg_integer()}
    | {non_neg_integer(), integer(), non_neg_integer()}.
-doc "Direction, one-based neighboring vertex index and one-based shared edge index.".
-type neighbor() :: {1..6, pos_integer(), pos_integer()}.
-doc "Bounded lookup tables; storage ordering is distinct from CID and neighbor priority.".
-type geometry() :: #{
    kind := code(),
    distance := pos_integer(),
    height := pos_integer(),
    coordinates := tuple(),
    endpoints := tuple(),
    neighbors := tuple(),
    ids := tuple(),
    boundaries := tuple(),
    bottoms := tuple(),
    syndrome_bits := tuple(),
    syndrome_width := pos_integer(),
    node_above := tuple(),
    edge_above := tuple(),
    retired_spatial := tuple(),
    retired_temporal := tuple(),
    cid_boundary_limit := pos_integer(),
    cid_boundary_shift := pos_integer(),
    cid_bulk_shift := pos_integer()
}.

-doc "Constructs a window with distance and height between 2 and 255. Directions retain the reference's code-specific priority.".
-spec new(code(), 2..((1 bsl 8) - 1), 2..((1 bsl 8) - 1)) -> geometry().
new(Code, Distance, Height) when
    (Code =:= repetition orelse Code =:= surface),
    Distance >= 2,
    Distance =< 255,
    Height >= 2,
    Height =< 255
->
    Coordinates = coordinates(Code, Distance, Height),
    Endpoints = endpoints(Code, Distance, Height),
    NodeIndex = maps:from_list(lists:zip(Coordinates, lists:seq(1, length(Coordinates)))),
    EdgeIndex = maps:from_list(lists:zip(Endpoints, lists:seq(1, length(Endpoints)))),
    {BoundaryShift, BulkShift, SyndromeWidth} =
        case Code of
            repetition -> {2, Distance - 1, Distance - 1};
            surface -> {2 * Distance, Distance * (Distance - 1), Distance * (Distance - 1)}
        end,
    #{
        kind => Code,
        distance => Distance,
        height => Height,
        coordinates => list_to_tuple(Coordinates),
        endpoints => list_to_tuple(Endpoints),
        neighbors => list_to_tuple([neighbors(C, NodeIndex, EdgeIndex) || C <- Coordinates]),
        ids => list_to_tuple([node_id(C, Distance, Height) || C <- Coordinates]),
        boundaries => list_to_tuple([boundary(C, Distance) || C <- Coordinates]),
        bottoms => list_to_tuple([time(C) =:= 0 || C <- Coordinates]),
        syndrome_bits => list_to_tuple([syndrome_bit(C, Distance, Height) || C <- Coordinates]),
        syndrome_width => SyndromeWidth,
        node_above => list_to_tuple([maps:get(above(C), NodeIndex, 0) || C <- Coordinates]),
        edge_above => list_to_tuple([
            maps:get({above(A), above(B)}, EdgeIndex, 0)
         || {A, B} <- Endpoints
        ]),
        retired_spatial => list_to_tuple([
            maps:get(E, EdgeIndex)
         || E <- Endpoints,
            {A, B} <- [E],
            time(A) =:= 0,
            time(B) =:= 0
        ]),
        retired_temporal => list_to_tuple([
            maps:get(E, EdgeIndex)
         || E <- Endpoints,
            {A, B} <- [E],
            time(A) =:= 0,
            time(B) =:= 1
        ]),
        cid_boundary_limit => BoundaryShift * Height,
        cid_boundary_shift => BoundaryShift,
        cid_bulk_shift => BulkShift
    }.

%% Stable flat storage ordering; witnesses compare by coordinate rather than position.
-spec coordinates(code(), pos_integer(), pos_integer()) -> [coordinate()].
coordinates(repetition, D, H) ->
    [{J, T} || J <- lists:seq(-1, D - 1), T <- lists:seq(0, H - 1)];
coordinates(surface, D, H) ->
    [
        {I, J, T}
     || I <- lists:seq(0, D - 1),
        J <- lists:seq(-1, D - 1),
        T <- lists:seq(0, H - 1)
    ].

%% Keep the author's edge order: south (surface only), east, then time.
-spec endpoints(code(), pos_integer(), pos_integer()) -> [{coordinate(), coordinate()}].
endpoints(repetition, D, H) ->
    [{{J, T}, {J + 1, T}} || J <- lists:seq(-1, D - 2), T <- lists:seq(0, H - 1)] ++
        [{{J, T}, {J, T + 1}} || J <- lists:seq(0, D - 2), T <- lists:seq(0, H - 2)];
endpoints(surface, D, H) ->
    [
        {{I, J, T}, {I + 1, J, T}}
     || I <- lists:seq(0, D - 2),
        J <- lists:seq(0, D - 2),
        T <- lists:seq(0, H - 1)
    ] ++
        [
            {{I, J, T}, {I, J + 1, T}}
         || I <- lists:seq(0, D - 1),
            J <- lists:seq(-1, D - 2),
            T <- lists:seq(0, H - 1)
        ] ++
        [
            {{I, J, T}, {I, J, T + 1}}
         || I <- lists:seq(0, D - 1),
            J <- lists:seq(0, D - 2),
            T <- lists:seq(0, H - 2)
        ].

%% IDs order boundaries before bulk and newer layers before older layers.
-spec node_id(coordinate(), pos_integer(), pos_integer()) -> non_neg_integer().
node_id({J, T}, D, H) ->
    case J of
        -1 -> 2 * (H - 1 - T);
        East when East =:= D - 1 -> 2 * (H - 1 - T) + 1;
        _ -> 2 * H + (D - 1) * (H - 1 - T) + J
    end;
node_id({I, J, T}, D, H) ->
    case J of
        -1 -> 2 * D * (H - 1 - T) + I;
        East when East =:= D - 1 -> 2 * D * (H - 1 - T) + D + I;
        _ -> 2 * D * H + D * (D - 1) * (H - 1 - T) + D * J + I
    end.

%% Only the west and east faces absorb defects; north and south have absent edges.
-spec boundary(coordinate(), pos_integer()) -> boolean().
boundary({J, _}, D) -> J =:= -1 orelse J =:= D - 1;
boundary({_, J, _}, D) -> J =:= -1 orelse J =:= D - 1.

%% Input bits increase west-to-east, then north-to-south for the surface graph.
-spec syndrome_bit(coordinate(), pos_integer(), pos_integer()) -> integer().
syndrome_bit({J, T}, D, H) when T =:= H - 1, J >= 0, J < D - 1 -> J;
syndrome_bit({I, J, T}, D, H) when T =:= H - 1, J >= 0, J < D - 1 -> I * (D - 1) + J;
syndrome_bit(_, _, _) -> -1.

%% The final coordinate is always the window time.
-spec time(coordinate()) -> non_neg_integer().
time({_, T}) -> T;
time({_, _, T}) -> T.

%% The logical source of a retained vertex or edge is one layer above it.
-spec above(coordinate()) -> coordinate().
above({J, T}) -> {J, T + 1};
above({I, J, T}) -> {I, J, T + 1}.

%% Preserve W/E/D/U for repetition and N/W/D/U/E/S for the surface reference.
-spec neighbors(coordinate(), map(), map()) -> [neighbor()].
neighbors(C, NodeIndex, EdgeIndex) ->
    [
        {Direction, maps:get(Neighbor, NodeIndex), maps:get(Edge, EdgeIndex)}
     || {Direction, Neighbor, Edge} <- candidates(C), maps:is_key(Edge, EdgeIndex)
    ].

%% Pointer numbers are stable; list position, not numeric direction, defines priority.
-spec candidates(coordinate()) -> [{1..6, coordinate(), {coordinate(), coordinate()}}].
candidates(C = {J, T}) ->
    [
        {1, {J - 1, T}, {{J - 1, T}, C}},
        {2, {J + 1, T}, {C, {J + 1, T}}},
        {3, {J, T - 1}, {{J, T - 1}, C}},
        {4, {J, T + 1}, {C, {J, T + 1}}}
    ];
candidates(C = {I, J, T}) ->
    [
        {5, {I - 1, J, T}, {{I - 1, J, T}, C}},
        {1, {I, J - 1, T}, {{I, J - 1, T}, C}},
        {3, {I, J, T - 1}, {{I, J, T - 1}, C}},
        {4, {I, J, T + 1}, {C, {I, J, T + 1}}},
        {2, {I, J + 1, T}, {C, {I, J + 1, T}}},
        {6, {I + 1, J, T}, {C, {I + 1, J, T}}}
    ].
