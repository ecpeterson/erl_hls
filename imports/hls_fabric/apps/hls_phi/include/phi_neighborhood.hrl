%% Compile-time geometry shared by the physical and decoder-only actors.
%% Wrappers select a line; absent directions are not channels or actions.
-ifdef(PHI_REPETITION).
-define(NEIGHBOR_COUNT, 2).
-define(NEIGHBOR_MASK, 6).
-define(NEIGHBOR_PORTS, [east, west]).
-define(NEIGHBOR_MEMBERS, [2, 4]).
-define(NEIGHBOR_TYPE, east | west).
%% Ordered output, local direction bit, and source bit seen by the receiver.
-define(NEIGHBORS, [{east, 2, 4}, {west, 4, 2}]).
-define(DATA_ERROR, z).
-define(SOURCE_VALID(Source), (Source =:= 2 orelse Source =:= 4)).
-else.
-define(NEIGHBOR_COUNT, 4).
-define(NEIGHBOR_MASK, 15).
-define(NEIGHBOR_PORTS, [north, east, west, south]).
-define(NEIGHBOR_MEMBERS, [1, 2, 4, 8]).
-define(NEIGHBOR_TYPE, north | east | west | south).
%% Ordered output, local direction bit, and source bit seen by the receiver.
-define(NEIGHBORS, [{north, 1, 8}, {east, 2, 4}, {west, 4, 2}, {south, 8, 1}]).
-define(DATA_ERROR, y).
-define(SOURCE_VALID(Source),
    (Source =:= 1 orelse Source =:= 2 orelse
        Source =:= 4 orelse Source =:= 8)
).
-endif.
