-module(snowflake_phase_witness).
-moduledoc "Complete phase-boundary witnesses for finite Snowflake implementation comparisons.".
-export([stream/4]).

-doc "Returns initial state, constant geometry, phase commands, proposals and expected committed state for the supplied masks. Addresses are zero-based; null denotes an absent upper-layer source. Words use the explicit fixture layout, not the actor transport ABI.".
-spec stream(snowflake_geometry:code(), 2 .. ((1 bsl 8) - 1), 2 .. ((1 bsl 8) - 1), [non_neg_integer()]) -> map().
stream(Code, Distance, Height, Masks) ->
    Geometry = snowflake_geometry:new(Code, Distance, Height),
    #{geometry := BaseGeometry} = snowflake_window:profile(Code, Distance, Height, []),
    Reports = snowflake_window:stream(Code, Distance, Height, Masks),
    #{schema => <<"snowflake-phase-witness-v1">>, code => Code,
        distance => Distance, window_height => Height,
        node_word_layout => #{width => 46, active => [0, 1], whole => [1, 1], cid => [2, 32],
            defect => [34, 1], pointer => [35, 8], grown => [43, 1], unrooted => [44, 1], busy => [45, 1]},
        edge_word_layout => #{width => 3, growth => [0, 2], correction => [2, 1]},
        geometry => witness_geometry(Geometry, BaseGeometry),
        initial => words(snowflake_window:snapshot(snowflake_window:new(Code, Distance, Height))),
        phases => [phase(Entry, Report, Geometry) || Report <- Reports,
            Entry <- maps:get(trace, Report)]}.

%% All missing upper-layer sources are explicit, so a consumer need not infer window geometry.
-spec witness_geometry(snowflake_geometry:geometry(), map()) -> map().
witness_geometry(Geometry = #{node_above := NodeAbove, edge_above := EdgeAbove}, Base) ->
    maps:merge(Base, (maps:with([syndrome_width, cid_boundary_limit,
        cid_boundary_shift, cid_bulk_shift], Geometry))#{
        node_above => [address(I) || I <- tuple_to_list(NodeAbove)],
        edge_above => [address(I) || I <- tuple_to_list(EdgeAbove)]}).

%% The internal zero sentinel is distinct from the external first array address.
-spec address(non_neg_integer()) -> null | non_neg_integer().
address(0) -> null;
address(I) -> I - 1.

%% Retirements are observed before the drop; other phases carry no correction output.
-spec phase(map(), snowflake_window:report(), snowflake_geometry:geometry()) -> map().
phase(Entry = #{phase := Kind, state := State = #{nodes := Nodes}}, Report,
    #{neighbors := Neighbors}) ->
    Transfers = maps:get(transfers, Entry, []),
    Directions = maps:from_list([{Source, begin
        [{Direction, Target, Edge}] = [N || N = {_, T, E} <- element(Source, Neighbors),
            T =:= Target, E =:= Edge], Direction
    end} || {Source, Target, Edge} <- Transfers]),
    Growing = maps:from_list([{I, true} || I <- maps:get(growth_nodes, Entry, [])]),
    Base = (maps:with([phase, tick, sheet, epoch], Entry))#{
        input_mask => maps:get(input_mask, Report), expected => words(State),
        busy_any => lists:any(fun(#{busy := Busy}) -> Busy end, Nodes),
        growth_flags => [maps:get(I, Growing, false) || I <- lists:seq(1, length(Nodes))],
        transfer_directions => [maps:get(I, Directions, 0) || I <- lists:seq(1, length(Nodes))],
        transfers => [[S - 1, T - 1, E - 1] || {S, T, E} <- Transfers]},
    case Kind of
        drop -> Base#{retirement => maps:with([retired_sheet, retired_spatial_mask,
            retired_temporal_mask], Report)};
        _ -> Base
    end.

%% Each word retains every mutable field; coordinate and identity live in the geometry.
-spec words(map()) -> map().
words(#{nodes := Nodes, edges := Edges}) ->
    #{nodes => [node_word(Node) || Node <- Nodes],
        edges => [Growth bor (bit(Correction) bsl 2)
            || #{growth := Growth, correction := Correction} <- Edges]}.

%% Signed CIDs use two's complement, including the -1 full-unrooting marker.
-spec node_word(map()) -> non_neg_integer().
node_word(#{active := Active, whole := Whole, cid := Cid, defect := Defect,
    pointer := Pointer, grown := Grown, unrooted := Unrooted, busy := Busy}) ->
    bit(Active) bor (bit(Whole) bsl 1) bor ((Cid band 16#ffffffff) bsl 2)
        bor (bit(Defect) bsl 34) bor (Pointer bsl 35) bor (bit(Grown) bsl 43)
        bor (bit(Unrooted) bsl 44) bor (bit(Busy) bsl 45).

%% Boolean fields remain independent of JSON's textual representation.
-spec bit(boolean()) -> 0..1.
bit(false) -> 0;
bit(true) -> 1.
