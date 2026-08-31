%%%% phi_torus_topology
%%%%
%%%% Compact semantic witness for a regular periodic phi mesh.

-module(phi_torus_topology).
-moduledoc """
A compact, rule-preserving phi-cell torus.

The family dictionary contains one `phi_halo_cell` artifact with a bounded
two-dimensional shape. Four wrapped translation relations connect its mesh
ports. The remaining `syndrome` and `correction` outputs are exposed as
top-proc boundary streams, so this is a structural topology witness rather
than the complete phenomenological-noise deployment. They are not implicitly
attached to an Erlang process or PL-PS gateway.

No actor instance or route pair is enumerated here. A family member is named
`{phi, X, Y}` only when a consumer resolves a particular coordinate.
""".

-export([topology/0, topology/2]).

-doc "Returns the compact two-by-three torus used by the RTL witness.".
-spec topology() -> hls_topology:spec().
topology() ->
    topology(2, 3).

-doc "Returns a compact `Width` by `Height` periodic phi family.".
-spec topology(pos_integer(), pos_integer()) -> hls_topology:spec().
topology(Width, Height) ->
    #{
        version => 1,
        actors => #{},
        families => #{
            phi => #{
                module => phi_halo_cell,
                shape => [Width, Height]
            }
        },
        externals => [
            {syndrome_requests, out, [phenom_request]},
            {corrections, out, [phi_correction]}
        ],
        routes => [],
        route_relations => [
            relation(north, [0, -1]),
            relation(east, [1, 0]),
            relation(west, [-1, 0]),
            relation(south, [0, 1]),
            {{phi, syndrome}, [{external, syndrome_requests}]},
            {{phi, correction}, [{external, corrections}]}
        ],
        startup => []
    }.

relation(Port, Offset) ->
    {{phi, Port}, [
        {family, phi, {translate, Offset, wrap}}
    ]}.
