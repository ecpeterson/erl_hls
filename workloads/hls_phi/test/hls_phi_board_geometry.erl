-module(hls_phi_board_geometry).
-moduledoc "Physical checkerboard placement and directional wire budgets for 4×2-qubit phi boards.".
-export([physical/2, placement/1, tile_roles/1, report/2, write/1]).

-doc "Maps a family index to its site on the periodic 2d×2d qubit checkerboard; a phi actor occupies its syndrome's site.".
-spec physical(pos_integer(), {family, atom(), [non_neg_integer()]}) -> {non_neg_integer(), non_neg_integer()}.
physical(Distance, {family, Family, [X, Y]}) ->
    {DX, DY} = case Family of
        data_even -> {0, 0};
        data_odd -> {1, 1};
        syndrome_x -> {1, 0};
        phi_x -> {1, 0};
        syndrome_z -> {2, 1};
        phi_z -> {2, 1}
    end,
    {(2*X+DX) rem (2*Distance), (2*Y+DY) rem (2*Distance)}.

-doc "Assigns complete physical 4×2 patches to row-major device IDs. An even distance is required for exact tiling.".
-spec placement(pos_integer()) -> map().
placement(Distance) when Distance >= 2, Distance rem 2 =:= 0 ->
    maps:from_list([{Id, begin
        {X, Y} = physical(Distance, Id),
        (Y div 2)*(Distance div 2)+(X div 4)
    end} || Id <- identities(Distance)]);
placement(Distance) -> error({untiled_distance, Distance}).

-doc "Returns physical actor roles and south/east/north/west peer ranks for an even torus with four distinct neighbors per board.".
-spec tile_roles(pos_integer()) -> {map(), map()}.
tile_roles(Distance) when Distance >= 6, Distance rem 2 =:= 0 ->
    Columns = Distance div 2,
    Roles = maps:from_list([{Id, begin
        {PX, PY} = physical(Distance, Id), {Family, PX rem 4, PY rem 2}
    end} || Id = {family, Family, _} <- identities(Distance)]),
    Peers = maps:from_list([{{Y*Columns+X, ((Y+DY) rem Distance)*Columns+(X+DX) rem Columns}, Rank}
        || Y <- lists:seq(0, Distance-1), X <- lists:seq(0, Columns-1),
           {Rank, {DX, DY}} <- lists:enumerate(0, [{0, 1}, {1, 0}, {0, Distance-1}, {Columns-1, 0}])]),
    {Roles, Peers};
tile_roles(Distance) -> error({aliased_tile_neighbors, Distance}).

-doc "Counts local/remote application messages from actual topology routes, preserving directional aliases. Assumes the supplied field rounds per application step and the current five-word frame plus reverse credit.".
-spec report(pos_integer(), pos_integer()) -> map().
report(Distance, Rounds) when Rounds > 0 ->
    Placement = placement(Distance),
    Plan = hls_topology:normalize(phi_noise_topology:topology(Distance)),
    Edges = lists:append([begin
        [#{source => Id, target => {family, F, [TX, TY]}, direction => Port,
            schemas => messages(Family, Rounds)}
            || #{source := {_, Port}, recipients := Recipients} <- hls_logical_topology:routes_for_instance(Plan, Family, [X, Y]),
               lists:member(Port, [north, east, west, south]), {actor, {F, TX, TY}} <- Recipients]
    end || Id = {family, Family, [X, Y]} <- identities(Distance)]),
    Cuts = lists:foldl(fun(#{source := Source, target := Target, direction := Direction, schemas := Schemas}, Acc) ->
        D = maps:get(Source, Placement),
        Peer = maps:get(Target, Placement),
        Key = {D, Direction, Peer},
        maps:update_with(Key, fun(Counts) -> add(Counts, Schemas) end, Schemas, Acc)
    end, #{}, Edges),
    Links = [begin
        Reverse = maps:get({Peer, opposite(Direction), D}, Cuts, #{}),
        Frames = lists:sum(maps:values(Counts)),
        Credits = lists:sum(maps:values(Reverse)),
        #{device => D, direction => Direction, peer => Peer, local => D =:= Peer,
            frames => Frames, schemas => Counts,
            wire_words => case D =:= Peer of true -> 0; false -> 5*Frames+Credits end}
    end || {{D, Direction, Peer}, Counts} <- lists:sort(maps:to_list(Cuts))],
    Boards = [begin
        Actors = [Id || {Id, Owner} <- maps:to_list(Placement), Owner =:= D],
        Counts = lists:foldl(fun({family, F, _}, Acc) -> maps:update_with(F, fun(N) -> N+1 end, 1, Acc) end, #{}, Actors),
        #{device => D, families => Counts, actors => length(Actors)}
    end || D <- lists:usort(maps:values(Placement))],
    #{distance => Distance, physical_shape => [2*Distance, 2*Distance], patch => [4, 2],
        board_shape => [Distance div 2, Distance], field_rounds => Rounds, boards => Boards, directions => Links}.

-doc "Writes geometry and traffic budgets for d=2, d=4 and the first even distance with four distinct remote neighbors, d=6.".
-spec write(file:filename()) -> ok.
write(File) ->
    file:write_file(File, json:encode([report(D, 12) || D <- [2, 4, 6]])).

%% Preserve each logical family identity independently of physical site aliases.
-spec identities(pos_integer()) -> [tuple()].
identities(Distance) ->
    [{family, F, [X, Y]} || F <- [data_even, data_odd, syndrome_x, syndrome_z, phi_x, phi_z],
        X <- lists:seq(0, Distance-1), Y <- lists:seq(0, Distance-1)].

%% The steady per-step protocol sends fields every relaxation, final fields/moves once, and one data/query exchange per edge.
-spec messages(atom(), pos_integer()) -> map().
messages(F, Rounds) when F =:= phi_x; F =:= phi_z -> #{phi => Rounds, phi0 => 1, anyon_move => 1};
messages(F, _) when F =:= data_even; F =:= data_odd -> #{phenom_data => 1};
messages(F, _) when F =:= syndrome_x; F =:= syndrome_z -> #{phenom_query => 1}.

%% Combine message populations without collapsing aliased logical sends.
-spec add(map(), map()) -> map().
add(A, B) -> maps:fold(fun(K, V, Acc) -> maps:update_with(K, fun(N) -> N+V end, V, Acc) end, A, B).

%% Credit returns consume the reverse physical direction's bandwidth.
-spec opposite(north | east | west | south) -> north | east | west | south.
opposite(north) -> south;
opposite(south) -> north;
opposite(east) -> west;
opposite(west) -> east.
