%%%% phi_torus_topology
%%%%
%%%% Compact semantic witness for a regular periodic phi mesh.

-module(phi_torus_topology).
-moduledoc """
A compact, rule-preserving phi-cell torus.

The family dictionary contains one `phi_halo_cell` artifact with a bounded
two-dimensional shape. Four wrapped translation relations connect its mesh
ports. The remaining `syndrome`, `correction`, and `status` outputs are exposed as
top-proc boundary streams, so this is a structural topology witness rather
than the complete phenomenological-noise deployment. They are not implicitly
attached to an Erlang process or PL-PS gateway.

No actor instance is flattened into the `actors` map, and no route pair is
enumerated here. The v0 startup model does still enumerate one configuration
message per family member so that every phi cell gets a distinct deterministic
tie-breaking seed. A family member is named `{phi, X, Y}` only by that instance
constant or when a consumer resolves a particular coordinate. This example
helper bounds each dimension at 50 because it materializes that startup list;
the compact family and route forms do not have that bound.
""".

-include("phi_protocol.hrl").

-export([topology/0, topology/2]).

-define(MAX_WITNESS_DIMENSION, 50).
-define(SEED_STRIDE, 16#9e3779b9).
-define(U32_MASK, 16#ffffffff).

-doc "Returns the compact two-by-three torus used by the RTL witness.".
-spec topology() -> hls_topology:spec().
topology() ->
    topology(2, 3).

-doc "Returns a compact `Width` by `Height` periodic phi family.".
-spec topology(pos_integer(), pos_integer()) -> hls_topology:spec().
topology(Width, Height)
        when Width > 0, Width =< ?MAX_WITNESS_DIMENSION,
             Height > 0, Height =< ?MAX_WITNESS_DIMENSION ->
    #{
        version => 1,
        actors => #{},
        ingresses => [],
        families => #{
            phi => #{
                module => phi_halo_cell,
                shape => [Width, Height]
            }
        },
        externals => [
            {syndrome_requests, out, [phenom_request]},
            {decoder_events, out, [phi_correction, phi_status]}
        ],
        routes => [],
        route_relations => [
            relation(north, [0, -1]),
            relation(east, [1, 0]),
            relation(west, [-1, 0]),
            relation(south, [0, 1]),
            {{phi, syndrome}, [{external, syndrome_requests}]},
            {{phi, correction}, [{external, decoder_events}]},
            {{phi, status}, [{external, decoder_events}]}
        ],
        startup => startup(Width, Height)
    };
topology(_Width, _Height) ->
    error(badarg).

relation(Port, Offset) ->
    {{phi, Port}, [
        {family, phi, {translate, Offset, wrap}}
    ]}.

startup(Width, Height) ->
    [
        {{phi, X, Y}, [#phi_config{
            seed = seed(Height, X, Y)
        }]}
        || X <- lists:seq(0, Width - 1),
           Y <- lists:seq(0, Height - 1)
    ].

seed(Height, X, Y) ->
    Index = X * Height + Y + 1,
    (Index * ?SEED_STRIDE) band ?U32_MASK.
