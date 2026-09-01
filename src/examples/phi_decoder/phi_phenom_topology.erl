%%%% phi_phenom_topology
%%%%
%%%% Semantic description of the existing closed phi/noise RTL fixture.

-module(phi_phenom_topology).
-moduledoc """
The closed phi/noise experiment as an ordinary Erlang topology term.

The companion `phi_phenom_topology.x` is generated from this term plus a
separate DSLX deployment profile. This module contains no channels, muxes,
frames, or numeric tags.

The entries called `externals` below are typed topology boundaries. In the
generated fixture they become top-level DSLX output channels consumed by the
RTL testbench. No current mechanism automatically forwards them through the
PL-PS bridge or chooses an ERTS recipient; that requires an explicit deployment
adapter which has not been built for the phi example.
""".

-include("phi_protocol.hrl").

-export([topology/0]).

-define(DATA_PRNG_SEED, 16#9e3779b9).
-define(SYNDROME_PRNG_SEED, 16#85ebca6b).
-define(PHI_PRNG_SEED, 16#6d2b79f5).
-define(HALF_THRESHOLD, 16#80000000).

-doc "Returns the semantic topology for the three-actor fixture.".
-spec topology() -> hls_topology:spec().
topology() ->
    Directions = [north, east, west, south],
    #{
        version => 1,
        ingresses => [],
        actors => #{
            phi => phi_halo_cell,
            syndrome => phenom_syndrome_cell,
            data => phenom_data_cell
        },
        families => #{},
        externals => [
            {announcement, out, [phenom_anyon]},
            {decoder_events, out, [phi_correction, phi_status]},
            {data_measurements, out, [pauli_reply]}
        ],
        routes =>
            routes(phi, Directions, phi) ++
            [
                {{phi, syndrome}, [{actor, syndrome}]},
                {{phi, correction}, [{external, decoder_events}]},
                {{phi, status}, [{external, decoder_events}]}
            ] ++
            routes(syndrome, Directions, data) ++
            [{{syndrome, phi}, queued, [
                {actor, phi},
                {external, announcement}
            ]}] ++
            routes(data, Directions, syndrome) ++
            [
                {{data, measurement}, [{external, data_measurements}]}
            ],
        route_relations => [],
        startup => [
            {data, [#phenom_config{
                seed = ?DATA_PRNG_SEED,
                threshold = ?HALF_THRESHOLD,
                x = 0,
                y = 0
            }]},
            {syndrome, [#phenom_config{
                seed = ?SYNDROME_PRNG_SEED,
                threshold = ?HALF_THRESHOLD,
                x = 0,
                y = 0
            }]},
            {phi, [#phi_config{seed = ?PHI_PRNG_SEED}]}
        ]
    }.

routes(Source, Ports, Destination) ->
    [
        {{Source, Port}, [{actor, Destination}]}
        || Port <- Ports
    ].
