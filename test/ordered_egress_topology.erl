%%%% ordered_egress_topology
%%%%
%%%% Exact topology for the ordered-egress generated-RTL regression.

-module(ordered_egress_topology).

-export([profile/0, to_dslx/0, topology/0]).

topology() ->
    #{
        version => 1,
        ingresses => [],
        actors => #{ordered => ordered_egress_actor},
        families => #{},
        externals => [{ordered_values, out, [ordered_value]}],
        routes => [
            {{ordered, first}, [{external, ordered_values}]},
            {{ordered, second}, [{external, ordered_values}]},
            {{ordered, third}, [{external, ordered_values}]},
            {{ordered, loop}, [{actor, ordered}]}
        ],
        route_relations => [],
        startup => []
    }.

profile() ->
    #{
        name => ordered_egress_topology,
        channel_depth => 1
    }.

to_dslx() ->
    xls_topology_dslx:emit(hls_topology:normalize(topology()), profile()).
