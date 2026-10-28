-module(hls_routing_topology_fixture).
-moduledoc "Three tiny actors expose ordered fanout, aliased input lanes and startup packing.".

-include("hls_routing_fixture.hrl").

%% Logical application topology.
-export([topology/0, profile/0, to_dslx/0]).


-doc "Returns the semantic topology for the three-actor fixture.".
-spec topology() -> hls_topology:spec().
topology() ->
    Directions = [north, east, west, south],
    #{
        version => 1,
        ingresses => [],
        actors => #{
            grid => hls_grid_cell_fixture,
            query => hls_query_cell_fixture,
            data => hls_data_cell_fixture
        },
        families => #{},
        externals => [
            {announcement, out, [report]},
            {result_events, out, [result, status]},
            {data_measurements, out, [measurement]}
        ],
        routes =>
            routes(grid, Directions, grid) ++
            [
                {{grid, query}, [{actor, query}]},
                {{grid, result}, [{external, result_events}]},
                {{grid, status}, [{external, result_events}]}
            ] ++
            routes(query, Directions, data) ++
            [
                {{query, grid}, queued, [
                    {actor, grid},
                    {external, announcement}
                ]}
            ] ++
            routes(data, Directions, query) ++
            [
                {{data, measurement}, [{external, data_measurements}]}
            ],
        route_relations => [],
        startup => [
            {data, [
                #config{
                    seed = 1,
                    threshold = 4,
                    x = 0,
                    y = 0
                }
            ]},
            {query, [
                #config{
                    seed = 2,
                    threshold = 4,
                    x = 0,
                    y = 0
                }
            ]},
            {grid, [#seed{seed = 3}]}
        ]
    }.

%% Connects each declared port to the same target to exercise alias lanes.
-spec routes(atom(), [atom()], atom()) -> [tuple()].
routes(Source, Ports, Destination) ->
    [
        {{Source, Port}, [{actor, Destination}]}
     || Port <- Ports
    ].

-doc "Returns the test deployment policy, separate from the logical topology.".
-spec profile() -> xls_topology_dslx:profile().
profile() -> #{name => hls_routing_topology_fixture, channel_depth => 1, actor_egress_depth => burst}.

-doc "Generates the ordinary routing witness without invoking external tools.".
-spec to_dslx() -> iolist().
to_dslx() -> xls_topology_dslx:from_module(?MODULE, profile()).
