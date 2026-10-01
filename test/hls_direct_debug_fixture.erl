-module(hls_direct_debug_fixture).
-export([fixture/1, artifacts/2]).
-doc "Builds the selected test topology and its matching execution profile.".
-spec fixture('direct_reduction') -> {term(),map()}.
fixture(direct_reduction) ->
    Plan = hls_topology:normalize(#{version => 1, actors => #{},
        families => #{cell => #{module => hls_reduction_failure_fixture, shape => [5, 1]}},
        ingresses => [{commands, {rectangle, [5, 1]}, [
            {configure, [configure], [{family, cell, {embed, [1, 1], [0, 0]}}]}]}],
        externals => [{reports, out, [report]}], routes => [],
        route_relations => [{{cell, out}, [{external, reports}]} | [
            {{cell, Port}, [{family, cell, {translate, [Offset, 0], wrap}}]}
            || {Port, Offset} <- [{left, -1}, {middle, 0}, {right, 1}]]],
        startup => []}),
    {Plan, #{}}.

-doc "Translates the fixture's actors with options matching their physical placement.".
-spec artifacts('direct_reduction',term()) -> map().
artifacts(direct_reduction, Options) ->
    #{hls_reduction_failure_fixture => xls_parse:to_xls("test/hls_reduction_failure_fixture.erl", Options)}.
