-module(hls_partition_tile).
-moduledoc "Canonical physical roles and constant configuration for congruent partition tiles.".
-export([prepare/3, schedule/3, local/2, incoming/2, planning/1, projection/2,
    parameters/1, names/1, constants/2, lane_id/1]).

-doc "Assigns tile-local actor/lane indices and directional peer order. Roles must uniquely cover each device; peer roles must uniquely cover its remote neighbors. Logical identities and packed startup values are retained.".
-spec prepare(map(), map(), map()) -> map().
prepare(P = #{actors := Actors, devices := Devices, lanes := Lanes, ingresses := Ingresses}, Roles, Peers) ->
    true = lists:sort(maps:keys(Roles)) =:= lists:sort([Id || #{identity := Id} <- Actors]),
    Ordered = lists:append([begin
        Local = lists:sort([{maps:get(Id, Roles), A} || A = #{identity := Id, device := D} <- Actors, D =:= Device]),
        true = length(Local) =:= length(lists:usort([R || {R, _} <- Local])),
        [A#{index := I, tile_role => R} || {I, {R, A}} <- lists:enumerate(0, Local)]
    end || Device <- Devices]),
    Index = maps:from_list([{Id, A} || A = #{identity := Id} <- Ordered]),
    [begin
        Neighbors = lists:usort([T || #{source_device := S, destination_device := T, kind := remote} <- Lanes, S =:= D]),
        Keys = [maps:get({D, N}, Peers) || N <- Neighbors],
        true = length(Keys) =:= length(lists:usort(Keys))
    end || D <- Devices],
    Sorted = lists:sort([{lane_key(L, Index, Peers), L} || L <- Lanes]),
    {Numbered, _} = lists:mapfoldl(fun({_Key, L = #{source_device := D, destination_device := T, kind := Kind}}, Counts) ->
        Local = maps:get({local, D}, Counts, 0),
        Next = Counts#{{local, D} => Local+1},
        case Kind of
            remote ->
                Wire = maps:get({wire, D, T}, Counts, 0),
                {L#{rtl_id => Local, wire_id := Wire}, Next#{{wire, D, T} => Wire+1}};
            _ -> {L#{rtl_id => Local}, Next}
        end
    end, #{}, Sorted),
    ByLane = maps:from_list([{Id, L} || L = #{id := Id} <- Numbered]),
    Tile = P#{actors := Ordered, lanes := Numbered, tile_peers => Peers,
        ingresses := [I#{bindings := lists:sort(fun(#{device := D1, index := I1}, #{device := D2, index := I2}) ->
            {D1, I1} < {D2, I2} end,
            [A#{index := maps:get(index, maps:get(Id, Index))} || A = #{identity := Id} <- Bindings])}
            || I = #{bindings := Bindings} <- Ingresses]},
    Tile#{reduction_inputs => maps:map(fun(Id, Inputs) ->
        OrderedInputs = incoming(Id, Tile),
        Captured = maps:from_list([{Lane, N} || #{id := Lane, multiplicity := N} <- Inputs]),
        [(maps:get(Lane, ByLane))#{multiplicity => maps:get(Lane, Captured)}
            || #{id := Lane} <- OrderedInputs, maps:is_key(Lane, Captured)]
    end, maps:get(reduction_inputs, P, #{}))}.

%% Sort source-local outputs independently of the numerical identities of their neighbors.
-spec lane_key(map(), map(), map()) -> term().
lane_key(#{source := S, destination := Target, source_device := D, destination_device := T, ports := Ports}, Index, Peers) ->
    #{index := I} = maps:get(S, Index),
    End = case Target of {external, Name} -> {external, Name};
        {actor, A} -> {actor, case D =:= T of true -> local; false -> maps:get({D, T}, Peers) end,
            maps:get(index, maps:get(A, Index))} end,
    {D, I, Ports, End}.

-doc "Balances RAM groups in physical-role order while preserving each actor's logical identity.".
-spec schedule(map(), pos_integer(), map()) -> map().
schedule(P = #{actors := Actors}, Limit, Overrides) ->
    Aliases = [A#{identity := {D, I}} || A = #{device := D, index := I} <- Actors],
    Index = maps:from_list([{{D, I}, A} || A = #{device := D, index := I} <- Actors]),
    #{schedulers := Groups} = hls_partition_schedule:shared_by_module(P#{actors := Aliases}, Limit, Overrides),
    P#{schedulers => [G#{actors := [(maps:get(Alias, Index))#{slot => Slot}
        || #{identity := Alias, slot := Slot} <- Members]} || G = #{actors := Members} <- Groups]}.

-doc "Orders a device's physical ports by its explicit peer roles; ordinary partitions pass through.".
-spec local(map(), map()) -> map().
local(#{tile_peers := Peers}, Local = #{id := D, links := Links}) ->
    Ordered = lists:sort([{maps:get({D, P}, Peers), L} || L = #{peer := P} <- Links]),
    Local#{tile => true, links := [L#{index := I} || {I, {_, L}} <- lists:enumerate(0, Ordered)]};
local(_, Local) -> Local.

-doc "Returns incoming lanes in destination-local peer/source-role order, retaining ordinary order otherwise.".
-spec incoming(term(), map()) -> [map()].
incoming(Id, P = #{lanes := Lanes}) ->
    Selected = [L || L = #{destination := {actor, Target}} <- Lanes, Target =:= Id],
    case P of
        #{tile_peers := Peers, actors := Actors} ->
            Index = maps:from_list([{A, I} || #{identity := A, index := I} <- Actors]),
            [L || {_, L} <- lists:sort([{begin
                Peer = case S =:= D of true -> -1; false -> maps:get({D, S}, Peers) end,
                {Peer, maps:get(Source, Index), Ports}
            end, L} || L = #{source := Source, source_device := S, destination_device := D, ports := Ports} <- Selected])];
        _ -> Selected
    end.

-doc "Returns the public physical scheduler plan, with the logical identity retained on each actor for debug binding.".
-spec planning(map()) -> {map(), map()}.
planning(#{tile := true, actors := Actors, schedulers := Groups}) ->
    Aliases = maps:from_list([{Id, I} || #{identity := Id, index := I} <- Actors]),
    Plan = hls_partition_schedule:topology([A#{identity := I, logical_identity => Id}
        || A = #{identity := Id, index := I} <- Actors]),
    Specs = hls_partition_schedule:specs([G#{actors := [A#{identity := maps:get(Id, Aliases)}
        || A = #{identity := Id} <- Members]} || G = #{actors := Members} <- Groups]),
    {Plan, Specs};
planning(#{actors := Actors, schedulers := Groups}) ->
    {hls_partition_schedule:topology(Actors), hls_partition_schedule:specs(Groups)}.

-doc "Labels physical slots with logical actors, binding both views in the generated projection.".
-spec projection(map(), map()) -> map().
projection(#{tile := true, schedulers := Groups}, P = #{<<"banks">> := Banks}) ->
    Logical = maps:from_list([{{I, Slot}, Id} || #{index := I, actors := Actors} <- Groups,
        #{identity := Id, slot := Slot} <- Actors]),
    P#{<<"tile_physical">> => P, <<"banks">> := [B#{<<"actors">> := [begin
        Id = {actor, maps:get({I, Slot}, Logical)},
        A#{<<"name">> := iolist_to_binary(io_lib:format("~w", [Id])),
            <<"key">> := xls_actor_debug:actor_key(Id)}
    end || A = #{<<"slot">> := Slot} <- Actors]} || B = #{<<"index">> := I, <<"actors">> := Actors} <- Banks]};
projection(_, P) -> P.

-doc "Returns constant-channel declarations for startup tables and global ingress points.".
-spec parameters(map()) -> [iodata()].
parameters(Local = #{tile := true}) ->
    [[Name, ": chan<bits[", integer_to_list(Width), "]> in"] || {Name, Width, _} <- graph_constants(Local)];
parameters(_) -> [].

-doc "Returns constant-channel names in declaration order.".
-spec names(map()) -> [string()].
names(Local = #{tile := true}) -> [Name || {Name, _, _} <- graph_constants(Local)];
names(_) -> [].

-doc "Returns stable input values, which the configuration wrapper must hold throughout reset and execution.".
-spec constants(map(), map()) -> [{string(), pos_integer(), non_neg_integer()}].
constants(Local, #{identity := Identity, host := Host}) ->
    graph_constants(Local) ++ [{"tile_gateway", 272, (binary:decode_unsigned(Identity, little) bsl 16) bor Host},
        {"tile_host", 16, Host}].

%% Little-indexed tables match DSLX's dynamic bit slices; all frame bits are explicit.
-spec graph_constants(map()) -> [{string(), pos_integer(), non_neg_integer()}].
graph_constants(Local = #{schedulers := Groups, ingresses := [#{bindings := Bindings}]}) ->
    Layout = maps:get(frame_layout, Local, hls_frame_layout:default()),
    FrameBits = hls_frame_layout:frame_bits(Layout),
    [{"tile_startup_" ++ integer_to_list(I), length(Frames)*FrameBits, table(Frames, FrameBits)}
        || #{index := I, actors := Actors} <- Groups,
           Frames <- [[frame(F, Layout) || #{startup := Fs} <- Actors, F <- Fs]]] ++
    [{"tile_points", 32*length(Bindings), table([(X bsl 16) bor Y || #{point := [X, Y]} <- Bindings], 32)}].

%% Pack a table with entry zero in the least significant bits.
-spec table([non_neg_integer()], pos_integer()) -> non_neg_integer().
table(Values, Width) -> lists:sum([V bsl (I*Width) || {I, V} <- lists:enumerate(0, Values)]).

%% The startup wire table uses axis::bits_from_frame, not the native struct layout.
-spec frame(map(), hls_frame_layout:layout()) -> non_neg_integer().
frame(#{selector := Tag, payload := Payload}, Layout) ->
    hls_frame_layout:pack_integer(Layout, Tag, Payload).

-doc "Returns a source-local RTL lane name index, or the ordinary deployment index.".
-spec lane_id(map()) -> non_neg_integer().
lane_id(L = #{id := Id}) -> maps:get(rtl_id, L, Id).
