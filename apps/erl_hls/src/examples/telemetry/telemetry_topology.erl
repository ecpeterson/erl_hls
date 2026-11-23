-module(telemetry_topology).
-moduledoc """
Connects the telemetry calibrator to its four-reading window summarizer.
One rectangle-addressed command ingress at coordinate [0,0] accepts
configuration and raw samples; the reports boundary carries summaries.
Both actors use dedicated bounded mailboxes. The topology selects neither
an XLS schedule nor a host/device transport.
""".

%% Logical actor instances, typed boundaries and routes.
-export([topology/0]).

-doc "Returns the two-actor graph with command ingress, summary output and no startup traffic.".
-spec topology() -> hls_topology:spec().
topology() ->
    #{
        version => 1,
        actors => #{calibrator => telemetry_calibrator, window => telemetry_window},
        families => #{},
        ingresses => [
            {commands, {rectangle, [1, 1]}, [
                {calibrator, [configure, raw], [{actor, calibrator, {at, [0, 0]}}]}
            ]}
        ],
        externals => [{reports, out, [summary]}],
        routes => [
            {{calibrator, readings}, [{actor, window}]},
            {{window, report}, [{external, reports}]}
        ],
        route_relations => [],
        startup => []
    }.
