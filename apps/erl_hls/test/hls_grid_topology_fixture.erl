-module(hls_grid_topology_fixture).
-moduledoc "Small periodic family fixture for compact routes, aliases and per-coordinate startup.".

-include("hls_routing_fixture.hrl").

%% Logical application topology.
-export([topology/0, topology/2, profile/0, to_dslx/0]).

-define(MAX_WITNESS_DIMENSION, 50).

-doc "Returns the compact two-by-three torus used by family-routing and source-generation tests.".
-spec topology() -> hls_topology:spec().
topology() ->
    topology(2, 3).

-doc "Returns a compact `Width` by `Height` periodic grid family.".
-spec topology(pos_integer(), pos_integer()) -> hls_topology:spec().
topology(Width, Height) when
    Width > 0,
    Width =< ?MAX_WITNESS_DIMENSION,
    Height > 0,
    Height =< ?MAX_WITNESS_DIMENSION
->
    #{
        version => 1,
        actors => #{},
        ingresses => [],
        families => #{
            grid => #{
                module => hls_grid_cell_fixture,
                shape => [Width, Height]
            }
        },
        externals => [
            {request_events, out, [request]},
            {result_events, out, [result, status]}
        ],
        routes => [],
        route_relations => [
            relation(north, [0, -1]),
            relation(east, [1, 0]),
            relation(west, [-1, 0]),
            relation(south, [0, 1]),
            {{grid, query}, [{external, request_events}]},
            {{grid, result}, [{external, result_events}]},
            {{grid, status}, [{external, result_events}]}
        ],
        startup => startup(Width, Height)
    };
topology(_Width, _Height) ->
    error(badarg).

%% Keeps the family route as a wrapped relation rather than enumerating actors.
-spec relation(atom(), [integer()]) -> tuple().
relation(Port, Offset) ->
    {{grid, Port}, [
        {family, grid, {translate, Offset, wrap}}
    ]}.

%% Assigns each coordinate a distinct small startup value.
-spec startup(pos_integer(), pos_integer()) -> [tuple()].
startup(Width, Height) ->
    [
        {{grid, X, Y}, [
            #seed{
                seed = seed(Height, X, Y)
            }
        ]}
     || X <- lists:seq(0, Width - 1),
        Y <- lists:seq(0, Height - 1)
    ].

%% Encodes the bounded coordinate as a nonzero u32 value.
-spec seed(pos_integer(), non_neg_integer(), non_neg_integer()) -> pos_integer().
seed(Height, X, Y) ->
    Index = X * Height + Y + 1,
    Index.

-doc "Returns the compact-family test deployment policy.".
-spec profile() -> xls_topology_dslx:profile().
profile() -> #{name => hls_grid_topology_fixture, channel_depth => 1, actor_egress_depth => burst}.

-doc "Generates the compact routing witness without invoking external tools.".
-spec to_dslx() -> iolist().
to_dslx() -> xls_topology_dslx:from_module(?MODULE, profile()).
