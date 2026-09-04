%%%% phi_decoder_profile_topology
%%%%
%%%% Decoder-only semantic topology for throughput attribution.

-module(phi_decoder_profile_topology).
-moduledoc """
Distance-three phi mesh with compact deterministic syndrome sources.

The two `phi_halo_cell` planes and all of their cardinal routes are identical
to `phi_noise_topology`. Each paired syndrome family is replaced by a compact
`phi_syndrome_replay_cell`, which responds to the existing request protocol
with a deterministic nontrivial stream. Only correction and status events
leave the graph.

This is a profiling topology, not another memory experiment.  It intentionally
omits the phenomenological data and syndrome actors, spatial control ingress,
announcement fanout, ERTS correction feedback, and final data-qubit query.  A
testbench stops after a fixed number of complete decoder rounds, so the source
does not attempt to quiesce or model convergence.
""".

-include("phi_protocol.hrl").

-export([topology/0, topology/1]).

-define(DEFAULT_DISTANCE, 3).
-define(HALF_RATE, 16#80000000).
-define(SEED_STRIDE, 16#9e3779b9).
-define(U32_MASK, 16#ffffffff).

-doc "Returns the checked distance-three decoder-only topology.".
-spec topology() -> hls_topology:spec().
topology() ->
    topology(?DEFAULT_DISTANCE).

-doc "Returns one bounded decoder-only topology.".
-spec topology(pos_integer()) -> hls_topology:spec().
topology(Distance) when Distance > 0, Distance =< 50 ->
    Shape = [Distance, Distance],
    #{
        version => 1,
        actors => #{},
        ingresses => [],
        families => #{
            phi_x => #{module => phi_halo_cell, shape => Shape},
            phi_z => #{module => phi_halo_cell, shape => Shape},
            syndrome_x => #{module => phi_syndrome_replay_cell, shape => Shape},
            syndrome_z => #{module => phi_syndrome_replay_cell, shape => Shape}
        },
        externals => [
            {x_decoder_events, out, [phi_correction, phi_status]},
            {z_decoder_events, out, [phi_correction, phi_status]}
        ],
        routes => [],
        route_relations =>
            plane_relations(phi_x, syndrome_x, x_decoder_events) ++
            plane_relations(phi_z, syndrome_z, z_decoder_events) ++
            [
                relation(syndrome_x, phi, phi_x, [0, 0]),
                relation(syndrome_z, phi, phi_z, [0, 0])
            ],
        startup =>
            source_startup(syndrome_x, 0, Distance) ++
            source_startup(syndrome_z, 1, Distance) ++
            phi_startup(phi_x, 2, Distance) ++
            phi_startup(phi_z, 3, Distance)
    };
topology(_Distance) ->
    error(badarg).

plane_relations(Phi, Syndrome, Events) ->
    [
        relation(Phi, north, Phi, [0, -1]),
        relation(Phi, east, Phi, [1, 0]),
        relation(Phi, west, Phi, [-1, 0]),
        relation(Phi, south, Phi, [0, 1]),
        relation(Phi, syndrome, Syndrome, [0, 0]),
        {{Phi, correction}, [{external, Events}]},
        {{Phi, status}, [{external, Events}]}
    ].

relation(Source, Port, Destination, Offset) ->
    {{Source, Port}, [
        {family, Destination, {translate, Offset, wrap}}
    ]}.

source_startup(Family, FamilyIndex, Distance) ->
    [
        {{Family, X, Y}, [#phenom_config{
            seed = seed(FamilyIndex, Distance, X, Y),
            threshold = ?HALF_RATE,
            x = X,
            y = Y
        }]}
        || X <- lists:seq(0, Distance - 1),
           Y <- lists:seq(0, Distance - 1)
    ].

phi_startup(Family, FamilyIndex, Distance) ->
    [
        {{Family, X, Y}, [#phi_config{
            seed = seed(FamilyIndex, Distance, X, Y)
        }]}
        || X <- lists:seq(0, Distance - 1),
           Y <- lists:seq(0, Distance - 1)
    ].

seed(FamilyIndex, Distance, X, Y) ->
    Linear = FamilyIndex * Distance * Distance + X * Distance + Y + 1,
    (Linear * ?SEED_STRIDE) band ?U32_MASK.
