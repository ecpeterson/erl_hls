-module(hls_fabric_boundary_tests).
-moduledoc "Exercises communication planning without target or spacetime applications.".

-include_lib("eunit/include/eunit.hrl").

%% A finite dependency graph is communication policy, not physical placement or timing.
-spec communication_only_planning_test() -> ok.
communication_only_planning_test() ->
    Nodes = [receive_a, route_a, send_a],
    Edges = [
        #{waiter => route_a, prerequisite => receive_a, lag => 0, kind => dependency},
        #{waiter => send_a, prerequisite => route_a, lag => 0, kind => dependency}
    ],
    {ok, #{property := lexicographically_decreasing_wait, ranks := Ranks}} =
        hls_protocol_wait_graph:check(Nodes, Edges),
    ?assert(maps:get(receive_a, Ranks) < maps:get(route_a, Ranks)),
    ?assert(maps:get(route_a, Ranks) < maps:get(send_a, Ranks)).
