%% Shared, unchanged localuf MIT-licensed vertex transitions.
%% Copyright and license: ../reference/LICENSE.localuf.
-doc "Creates an inactive vertex with its own nonnegative cluster identifier.".
-spec reset(hls_nums:s32()) -> #node{}.
reset(Id) -> #node{cid = Id, whole = true}.

-doc "Drops a quiescent upper vertex, or refreshes a fresh top vertex. Call only at a completed merge barrier.".
-spec drop(#node{}, hls_nums:s32(), boolean(), boolean()) -> #node{}.
drop(Source, IdShift, Top, Syndrome) ->
    case Top of
        true -> Source#node{active = false, defect = Syndrome,
            grown = false, unrooted = false};
        false -> Source#node{cid = Source#node.cid + IdShift,
            grown = false, unrooted = false}
    end.

-doc "Selects this vertex's growth contribution and detects an amputated downward pointer.".
-spec grow(#node{}, boolean(), boolean()) -> {#node{}, boolean()}.
grow(Node, WholeStep, Bottom) ->
    WillGrow = Node#node.active andalso
        ((WholeStep andalso Node#node.whole) orelse
        ((not WholeStep) andalso (not Node#node.whole) andalso (not Node#node.grown))),
    Next = Node#node{
        whole = Node#node.whole =/= WillGrow,
        grown = Node#node.grown orelse (WholeStep andalso WillGrow),
        unrooted = WholeStep andalso Node#node.unrooted},
    case WholeStep andalso Bottom andalso Node#node.pointer =:= 3 of
        true -> {Next#node{cid = -1, pointer = 0}, WillGrow};
        false -> {Next, WillGrow}
    end.

%% Surface actors omit the repetition-only entry point.
-ifndef(SNOWFLAKE_SURFACE_ONLY).
-doc "Advances one merge step and returns an optional outgoing defect direction.".
-spec merge(#node{}, #node{}, #node{}, #node{}, #node{}, hls_nums:u8(),
    boolean(), boolean(), hls_nums:s32()) -> {#node{}, hls_nums:u8()}.
merge(Node, West, East, Down, Up, Access, WholeStep, Boundary, Id) ->
    Base = Node#node{busy = false},
    Flooded = case WholeStep andalso Node#node.cid =:= -1 of
        true -> Base#node{cid = Id, unrooted = true, busy = true};
        false ->
            {N1, Stop1} = flood(Base, West, 1, Access band 1 =/= 0, WholeStep, false),
            {N2, Stop2} = flood(N1, East, 2, Access band 2 =/= 0, WholeStep, Stop1),
            {N3, Stop3} = flood(N2, Down, 3, Access band 4 =/= 0, WholeStep, Stop2),
            {N4, _Stop4} = flood(N3, Up, 4, Access band 8 =/= 0, WholeStep, Stop3),
            N4
    end,
    Pointer = Flooded#node.pointer,
    DetectorDefect = (not Boundary) andalso Node#node.defect,
    Active = case Pointer of
        0 -> DetectorDefect;
        1 -> West#node.active;
        2 -> East#node.active;
        3 -> Down#node.active;
        4 -> Up#node.active
    end,
    finish(Node, Flooded, Active, Boundary).

-endif.

%% An optional CID/pointer candidate; ordered joins keep the leftmost equal CID.
-define(FLOOD_CHOICE_T, {boolean(), hls_nums:s32(), hls_nums:u8()}).
%% A segment summarizes its candidate, stopping unroot request and visited growth.
-define(FLOOD_SEGMENT_T, {?FLOOD_CHOICE_T, boolean(), boolean()}).

-doc "Advances a six-neighbor phenomenological surface vertex in the reference's N/W/D/U/E/S priority.".
-spec merge_surface(#node{}, #node{}, #node{}, #node{}, #node{}, #node{}, #node{},
    hls_nums:u8(), boolean(), boolean(), hls_nums:s32()) -> {#node{}, hls_nums:u8()}.
merge_surface(Node, West, East, Down, Up, North, South, Access, WholeStep, Boundary, Id) ->
    Base = Node#node{busy = false},
    Flooded = case WholeStep andalso Node#node.cid =:= -1 of
        true -> Base#node{cid = Id, unrooted = true, busy = true};
        false ->
            C = {{true, Base#node.cid, Base#node.pointer}, false, Base#node.grown},
            N = flood_segment(North, 5, Access band 16 =/= 0, WholeStep, Node#node.unrooted),
            W = flood_segment(West, 1, Access band 1 =/= 0, WholeStep, Node#node.unrooted),
            D = flood_segment(Down, 3, Access band 4 =/= 0, WholeStep, Node#node.unrooted),
            U = flood_segment(Up, 4, Access band 8 =/= 0, WholeStep, Node#node.unrooted),
            E = flood_segment(East, 2, Access band 2 =/= 0, WholeStep, Node#node.unrooted),
            S = flood_segment(South, 6, Access band 32 =/= 0, WholeStep, Node#node.unrooted),
            Left = join_flood(join_flood(C, N), join_flood(W, D)),
            Right = join_flood(join_flood(U, E), S),
            apply_flood(Base, join_flood(Left, Right))
    end,
    Active = case Flooded#node.pointer of
        0 -> (not Boundary) andalso Node#node.defect;
        1 -> West#node.active;
        2 -> East#node.active;
        3 -> Down#node.active;
        4 -> Up#node.active;
        5 -> North#node.active;
        6 -> South#node.active
    end,
    finish(Node, Flooded, Active, Boundary).

%% Incoming XORs are applied later; activity follows the old pointee snapshot.
-spec finish(#node{}, #node{}, boolean(), boolean()) -> {#node{}, hls_nums:u8()}.
finish(Node, Flooded, Active, Boundary) ->
    Pointer = Flooded#node.pointer,
    Push = (not Boundary) andalso Node#node.defect andalso Pointer =/= 0,
    Transfer = case Push of true -> Pointer; false -> hls_nums:wrap(hls_nums:u8(), 0) end,
    {Flooded#node{active = Active, defect = Node#node.defect =/= Push,
        busy = Flooded#node.busy orelse Push orelse Node#node.active =/= Active}, Transfer}.

%% Repetition retains its serial implementation as an independent small control.
-ifndef(SNOWFLAKE_SURFACE_ONLY).
%% Visit one accessible neighbor in the reference's fixed priority order.
-spec flood(#node{}, #node{}, hls_nums:u8(), boolean(), boolean(), boolean()) ->
    {#node{}, boolean()}.
flood(Node, Neighbor, Direction, Accessible, WholeStep, Stopped) ->
    case Accessible andalso (not Stopped) of
        false -> {Node, Stopped};
        true ->
            case WholeStep andalso Neighbor#node.cid =:= -1 andalso (not Node#node.unrooted) of
                true -> {Node#node{cid = -1, pointer = 0, busy = true}, true};
                false ->
                    Compare = (not WholeStep) orelse Neighbor#node.cid =/= -1,
                    Lower = Compare andalso Neighbor#node.cid < Node#node.cid,
                    Chosen = case Lower of
                        true -> Node#node{cid = Neighbor#node.cid, pointer = Direction, busy = true};
                        false -> Node
                    end,
                    NewGrown = WholeStep andalso Neighbor#node.grown andalso (not Chosen#node.grown),
                    {Chosen#node{grown = Chosen#node.grown orelse NewGrown,
                        busy = Chosen#node.busy orelse NewGrown}, false}
            end
    end.
-endif.

%% Summarize one neighbor without depending on any preceding CID comparison.
-spec flood_segment(#node{}, hls_nums:u8(), boolean(), boolean(), boolean()) -> ?FLOOD_SEGMENT_T.
flood_segment(Neighbor, Direction, Accessible, WholeStep, Unrooted) ->
    Stop = Accessible andalso WholeStep andalso Neighbor#node.cid =:= -1 andalso (not Unrooted),
    Valid = Accessible andalso ((not WholeStep) orelse Neighbor#node.cid =/= -1),
    Grew = Accessible andalso WholeStep andalso Neighbor#node.grown andalso (not Stop),
    {{Valid, Neighbor#node.cid, Direction}, Stop, Grew}.

%% Ordered composition preserves ties and ignores growth after the first stop.
-spec join_flood(?FLOOD_SEGMENT_T, ?FLOOD_SEGMENT_T) -> ?FLOOD_SEGMENT_T.
join_flood({Left, LeftStop, LeftGrew}, {Right, RightStop, RightGrew}) ->
    {choose_flood(Left, Right), LeftStop orelse RightStop,
        LeftGrew orelse ((not LeftStop) andalso RightGrew)}.

%% The actor's own candidate comes first, so equal CIDs retain its old pointer.
-spec choose_flood(?FLOOD_CHOICE_T, ?FLOOD_CHOICE_T) -> ?FLOOD_CHOICE_T.
choose_flood(Left = {LeftValid, LeftCid, _}, Right = {RightValid, RightCid, _}) ->
    case RightValid andalso ((not LeftValid) orelse RightCid < LeftCid) of
        true -> Right;
        false -> Left
    end.

%% Unrooting overrides the winning CID but retains only growth seen before it.
-spec apply_flood(#node{}, ?FLOOD_SEGMENT_T) -> #node{}.
apply_flood(Node, {{_Valid, Cid, Pointer}, Stopped, Grown}) ->
    Node#node{cid = case Stopped of true -> -1; false -> Cid end,
        pointer = case Stopped of true -> 0; false -> Pointer end,
        grown = Grown, busy = Stopped orelse Cid =/= Node#node.cid
            orelse (Grown andalso (not Node#node.grown))}.
