-module(snowflake_window_tests).
-moduledoc "Differential stream checks against the pinned localuf fixture suite.".
-include_lib("eunit/include/eunit.hrl").
-include("snowflake_node.hrl").

%% Compare every retired sheet and every stored field, not only logical parity.
-spec named_streams_test_() -> [term()].
named_streams_test_() -> fixture_tests(repetition, "named.json").

%% Exhaust the documented d=3, three-sheet, weight-at-most-two fault space.
-spec enumerated_streams_test_() -> [term()].
enumerated_streams_test_() -> fixture_tests(repetition, "enumerated.json").

%% Surface witnesses exercise both spatial directions, boundaries, reset propagation and bursts.
-spec surface_named_streams_test_() -> [term()].
surface_named_streams_test_() -> fixture_tests(surface, "surface-named.json").

%% Exhaust every single fault among the stated three-sheet d=3 data/measurement sites.
-spec surface_enumerated_streams_test_() -> [term()].
surface_enumerated_streams_test_() -> fixture_tests(surface, "surface-enumerated.json").

%% Geometry metadata must preserve the reference's direction priority and mask ownership.
-spec surface_geometry_test_() -> [term()].
surface_geometry_test_() ->
    {ok, Bytes} = file:read_file(filename:join([code:priv_dir(hls_snowflake), "fixtures", "surface-named.json"])),
    #{<<"geometries">> := Geometries} = json:decode(Bytes),
    [?_test(check_geometry(G)) || G <- Geometries].

%% Equal-CID neighbors expose the different fixed priorities without relying on random inputs.
-spec neighbor_tie_priority_test() -> ok.
neighbor_tie_priority_test() ->
    V = snowflake_node:reset(20), N = snowflake_node:reset(1),
    {Repetition, 0} = snowflake_node:merge(V, N, N, N, N, 15, false, false, 20),
    {Surface, 0} = snowflake_node:merge_surface(V, N, N, N, N, N, N, 63, false, false, 20),
    ?assertEqual(1, Repetition#node.pointer),
    ?assertEqual(5, Surface#node.pointer).

%% A stopping neighbor contributes no growth; only the prefix before it survives.
-spec unrooting_growth_prefix_test() -> ok.
unrooting_growth_prefix_test() ->
    V = snowflake_node:reset(20), Q = snowflake_node:reset(30),
    Grown = (snowflake_node:reset(1))#node{grown = true},
    Stop = Grown#node{cid = -1},
    {Before, 0} = snowflake_node:merge_surface(V, Stop, Q, Q, Q, Grown, Q, 17, true, false, 20),
    {After, 0} = snowflake_node:merge_surface(V, Grown, Q, Q, Q, Stop, Q, 17, true, false, 20),
    ?assertEqual({-1, 0, true, true}, {Before#node.cid, Before#node.pointer, Before#node.grown, Before#node.busy}),
    ?assertEqual({-1, 0, false, true}, {After#node.cid, After#node.pointer, After#node.grown, After#node.busy}).

%% An already-unrooted vertex ignores a whole-step -1 CID but accepts its growth.
-spec ignored_unroot_request_still_grows_test() -> ok.
ignored_unroot_request_still_grows_test() ->
    V = (snowflake_node:reset(20))#node{unrooted = true},
    Q = snowflake_node:reset(30), W = snowflake_node:reset(5),
    N = Q#node{cid = -1, grown = true},
    {Whole, 0} = snowflake_node:merge_surface(V, W, Q, Q, Q, N, Q, 17, true, false, 20),
    {Half, 0} = snowflake_node:merge_surface(V, W, Q, Q, Q, N, Q, 17, false, false, 20),
    ?assertEqual({5, 1, true}, {Whole#node.cid, Whole#node.pointer, Whole#node.grown}),
    ?assertEqual({-1, 5, false}, {Half#node.cid, Half#node.pointer, Half#node.grown}).

%% Fixture words preserve every field and each phase command, including warmup retirements.
-spec phase_witness_test() -> ok.
phase_witness_test() ->
    Masks = [1, 0, 2, 0, 0, 0],
    Reports = snowflake_window:stream(repetition, 3, 3, Masks),
    #{initial := Initial, phases := Phases, geometry := Geometry} =
        snowflake_phase_witness:stream(repetition, 3, 3, Masks),
    check_witness_words(snowflake_window:snapshot(snowflake_window:new(repetition, 3, 3)), Initial),
    Expected = [{Entry, Report} || Report <- Reports, Entry <- maps:get(trace, Report)],
    ?assertEqual(length(Expected), length(Phases)),
    lists:foreach(fun({{Entry, Report}, Actual}) ->
        ?assertEqual(maps:with([phase, tick, sheet, epoch], Entry),
            maps:with([phase, tick, sheet, epoch], Actual)),
        ?assertEqual(maps:get(input_mask, Report), maps:get(input_mask, Actual)),
        check_witness_words(maps:get(state, Entry), maps:get(expected, Actual)),
        #{state := #{nodes := PhaseNodes}} = Entry,
        ?assertEqual(lists:any(fun(#{busy := Busy}) -> Busy end, PhaseNodes), maps:get(busy_any, Actual)),
        ?assertEqual([lists:member(I, maps:get(growth_nodes, Entry, []))
            || I <- lists:seq(1, length(PhaseNodes))], maps:get(growth_flags, Actual)),
        ?assertEqual([[S - 1, T - 1, E - 1] || {S, T, E} <- maps:get(transfers, Entry, [])],
            maps:get(transfers, Actual)),
        case maps:get(phase, Entry) of
            drop -> ?assertEqual(maps:with([retired_sheet, retired_spatial_mask,
                retired_temporal_mask], Report), maps:get(retirement, Actual));
            _ -> ?assertEqual(false, maps:is_key(retirement, Actual))
        end
    end, lists:zip(Expected, Phases)),
    #{node_above := Above, nodes := Nodes, syndrome_width := 2} = Geometry,
    ?assertEqual([1, 2, null, 4, 5, null, 7, 8, null, 10, 11, null], Above),
    ?assertEqual([null, null, null, null, null, 0, null, null, 1, null, null, null],
        [maps:get(syndrome_bit, Node) || Node <- Nodes]).

%% A finite stress stream witnesses full unrooting, merged growth and two incoming XORs.
-spec phase_witness_surface_coverage_test() -> ok.
phase_witness_surface_coverage_test() ->
    {ok, Bytes} = file:read_file(filename:join([code:priv_dir(hls_snowflake), "fixtures", "surface-named.json"])),
    #{<<"cases">> := Cases} = json:decode(Bytes),
    [#{<<"sheets">> := Sheets}] = [C || C = #{<<"name">> := <<"surface_d3_burst">>} <- Cases],
    #{phases := Phases, geometry := #{nodes := Nodes}} = snowflake_phase_witness:stream(surface, 3, 3,
        [maps:get(<<"input_mask">>, Sheet) || Sheet <- Sheets]),
    ?assert(lists:any(fun(#{expected := #{nodes := Words}}) ->
        lists:any(fun(Word) -> (Word bsr 2) band 16#ffffffff =:= 16#ffffffff end, Words)
    end, Phases)),
    ?assert(lists:any(fun(#{transfers := Transfers}) ->
        Targets = [T || [_, T, _] <- Transfers], length(Targets) > length(lists:usort(Targets))
    end, Phases)),
    ?assert(lists:any(fun(#{growth_flags := Flags}) ->
        Contributions = [Edge || {#{neighbors := Neighbors}, true} <- lists:zip(Nodes, Flags),
            #{edge := Edge} <- Neighbors],
        length(Contributions) > length(lists:usort(Contributions))
    end, Phases)),
    lists:foreach(fun(#{transfers := Transfers, transfer_directions := Directions}) ->
        Expected = lists:sort([{Source, Direction} || [Source, Target, Edge] <- Transfers,
            #{direction := Direction, node := Target0, edge := Edge0} <-
                maps:get(neighbors, lists:nth(Source + 1, Nodes)), Target0 =:= Target, Edge0 =:= Edge]),
        ?assertEqual(Expected, [{I, D} || {I, D} <- lists:zip(lists:seq(0, length(Nodes) - 1), Directions), D =/= 0])
    end, Phases).

%% Decode independently by field widths to catch packing omissions and signedness changes.
-spec check_witness_words(map(), map()) -> ok.
check_witness_words(#{nodes := Nodes, edges := Edges}, #{nodes := NodeWords, edges := EdgeWords}) ->
    ?assertEqual(length(Nodes), length(NodeWords)),
    ?assertEqual(length(Edges), length(EdgeWords)),
    lists:foreach(fun({Node, Word}) ->
        <<Busy:1, Unrooted:1, Grown:1, Pointer:8, Defect:1, Cid:32/signed, Whole:1, Active:1>> = <<Word:46>>,
        ?assertEqual([numeric(maps:get(Field, Node)) ||
            Field <- [active, whole, cid, defect, pointer, grown, unrooted, busy]],
            [Active, Whole, Cid, Defect, Pointer, Grown, Unrooted, Busy])
    end, lists:zip(Nodes, NodeWords)),
    lists:foreach(fun({#{growth := Growth, correction := Correction}, Word}) ->
        <<Bit:1, ActualGrowth:2>> = <<Word:3>>,
        ?assertEqual({Growth, numeric(Correction)}, {ActualGrowth, Bit})
    end, lists:zip(Edges, EdgeWords)).

%% Build individually named cases so a failure identifies its first stream.
-spec fixture_tests(snowflake_geometry:code(), string()) -> [term()].
fixture_tests(Code, Name) ->
    Path = filename:join([code:priv_dir(hls_snowflake), "fixtures", Name]),
    {ok, Bytes} = file:read_file(Path),
    Fixture = #{<<"cases">> := Cases} = json:decode(Bytes),
    Geometries = maps:get(<<"geometries">>, Fixture, []),
    [{binary_to_list(maps:get(<<"name">>, Case)), fun() -> check_case(Code, Case, Geometries) end}
        || Case <- Cases].

%% Geometry ordering is explicit in fixtures and need not match driver storage.
-spec check_case(snowflake_geometry:code(), map(), [map()]) -> ok.
check_case(Code, #{<<"distance">> := Distance, <<"window_height">> := Height,
    <<"sheets">> := Sheets}, Geometries) ->
    Geometry = case [G || G = #{<<"distance">> := D, <<"window_height">> := H} <- Geometries,
        D =:= Distance, H =:= Height] of [G] -> G; [] -> #{} end,
    _Final = lists:foldl(fun(Expected, State) ->
        Mask = maps:get(<<"input_mask">>, Expected),
        {Next, Actual} = snowflake_window:decode(Mask, State),
        ?assertEqual(maps:get(<<"retired_sheet">>, Expected), maps:get(retired_sheet, Actual)),
        ?assertEqual(maps:get(<<"retired_spatial_mask">>, Expected), maps:get(retired_spatial_mask, Actual)),
        ?assertEqual(maps:get(<<"retired_temporal_mask">>, Expected), maps:get(retired_temporal_mask, Actual)),
        ?assertEqual(maps:get(<<"phase_counts">>, Expected),
            json:decode(iolist_to_binary(json:encode(maps:get(phase_counts, Actual))))),
        ?assertEqual(maps:get(<<"reference_runtime_all">>, Expected) + 1, maps:get(ticks, Actual)),
        check_transfers(Expected, Actual, Geometry),
        case maps:find(<<"state">>, Expected) of
            {ok, ExpectedState} -> ?assertEqual(ExpectedState, reference_state(maps:get(state, Actual), Geometry));
            error -> ok
        end,
        Next
    end, snowflake_window:new(Code, Distance, Height), Sheets),
    ok.

%% Compare coordinates rather than assuming fixture and implementation array positions coincide.
-spec check_geometry(map()) -> ok.
check_geometry(#{<<"distance">> := D, <<"window_height">> := H,
    <<"nodes">> := ExpectedNodes, <<"edges">> := ExpectedEdges,
    <<"spatial_edges">> := Spatial, <<"temporal_edges">> := Temporal}) ->
    #{geometry := #{kind := surface, nodes := ActualNodes, edges := ActualEdges,
        retired_spatial_edges := SpatialIds, retired_temporal_edges := TemporalIds}} =
        snowflake_window:profile(surface, D, H, []),
    ExpectedNodeTuple = list_to_tuple(ExpectedNodes), ExpectedEdgeTuple = list_to_tuple(ExpectedEdges),
    ActualNodeTuple = list_to_tuple(ActualNodes), ActualEdgeTuple = list_to_tuple(ActualEdges),
    ByCoordinate = maps:from_list([{maps:get(coordinate, N), N} || N <- ActualNodes]),
    lists:foreach(fun(#{<<"coordinate">> := C, <<"id">> := Id, <<"boundary">> := Boundary,
        <<"syndrome_bit">> := Bit, <<"neighbors">> := Neighbors}) ->
        #{id := Id, boundary := Boundary, syndrome_bit := Bit, neighbors := ActualNeighbors} =
            maps:get(C, ByCoordinate),
        Expected = [{Direction, maps:get(<<"coordinate">>, element(Node + 1, ExpectedNodeTuple)),
            element(Edge + 1, ExpectedEdgeTuple)} || #{<<"direction">> := Direction,
                <<"node_index">> := Node, <<"edge_index">> := Edge} <- Neighbors],
        Actual = [{Direction, maps:get(coordinate, element(Node + 1, ActualNodeTuple)),
            maps:get(endpoints, element(Edge + 1, ActualEdgeTuple))}
            || #{direction := Direction, node := Node, edge := Edge} <- ActualNeighbors],
        ?assertEqual(Expected, Actual)
    end, ExpectedNodes),
    ?assertEqual([[A ++ [0], B ++ [0]] || [A, B] <- Spatial],
        [maps:get(endpoints, element(I + 1, ActualEdgeTuple)) || I <- SpatialIds]),
    ?assertEqual(Temporal, [maps:get(endpoints, element(I + 1, ActualEdgeTuple)) || I <- TemporalIds]).

%% Surface fixtures retain transfer identity per phase; compare independently of storage order.
-spec check_transfers(map(), map(), map()) -> ok.
check_transfers(#{<<"phases">> := Phases}, #{trace := ActualPhases},
    #{<<"nodes">> := NodeGeometry, <<"edges">> := EdgeGeometry}) ->
    NodeIndex = maps:from_list([{C, I} || {#{<<"coordinate">> := C}, I} <-
        lists:zip(NodeGeometry, lists:seq(0, length(NodeGeometry) - 1))]),
    EdgeIndex = maps:from_list(lists:zip(EdgeGeometry, lists:seq(0, length(EdgeGeometry) - 1))),
    lists:foreach(fun({Expected, Actual}) ->
        ?assertEqual(maps:get(<<"phase">>, Expected), atom_to_binary(maps:get(phase, Actual))),
        #{state := #{nodes := PhaseNodes}} = Actual,
        ?assertEqual(maps:get(<<"active_nodes">>, Expected),
            length([N || N = #{active := true} <- PhaseNodes])),
        ?assertEqual(maps:get(<<"busy_nodes">>, Expected),
            length([N || N = #{busy := true} <- PhaseNodes])),
        ?assertEqual(maps:get(<<"reset_nodes">>, Expected),
            length([N || N = #{cid := -1} <- PhaseNodes])),
        case maps:find(<<"transfers">>, Expected) of
            {ok, Transfers} ->
                #{state := #{nodes := Nodes, edges := Edges}} = Actual,
                NodeIds = list_to_tuple([maps:get(maps:get(coordinate, N), NodeIndex) || N <- Nodes]),
                EdgeIds = list_to_tuple([maps:get(maps:get(endpoints, E), EdgeIndex) || E <- Edges]),
                ActualTransfers = [[element(S, NodeIds), element(T, NodeIds), element(E, EdgeIds)]
                    || {S, T, E} <- maps:get(transfers, Actual, [])],
                ?assertEqual(lists:sort(Transfers), lists:sort(ActualTransfers));
            error -> ok
        end
    end, lists:zip(Phases, ActualPhases));
check_transfers(_, _, _) -> ok.

%% Normalize Boolean fields to the reference's compact 0/1 rows.
-spec reference_state(map(), map()) -> map().
reference_state(#{nodes := Nodes, edges := Edges}, #{<<"nodes">> := NodeGeometry,
    <<"edges">> := EdgeGeometry}) ->
    NodeMap = maps:from_list([{maps:get(coordinate, N), N} || N <- Nodes]),
    EdgeMap = maps:from_list([{maps:get(endpoints, E), E} || E <- Edges]),
    Fields = [active, whole, cid, defect, pointer, grown, unrooted, busy],
    #{<<"nodes">> => [[numeric(maps:get(Field, maps:get(Coordinate, NodeMap))) || Field <- Fields]
        || #{<<"coordinate">> := Coordinate} <- NodeGeometry],
      <<"edges">> => [[numeric(maps:get(Field, maps:get(Endpoints, EdgeMap)))
        || Field <- [growth, correction]] || Endpoints <- EdgeGeometry]}.

%% Integers, including the reset marker, retain their exact value.
-spec numeric(boolean() | integer()) -> integer().
numeric(false) -> 0;
numeric(true) -> 1;
numeric(Value) -> Value.
