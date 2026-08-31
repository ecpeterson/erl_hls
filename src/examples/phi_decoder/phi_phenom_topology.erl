%%%% phi_phenom_topology
%%%%
%%%% Semantic description of the existing closed phi/noise RTL fixture.

-module(phi_phenom_topology).
-moduledoc """
The closed phi/noise experiment as an ordinary Erlang topology term.

The companion `phi_phenom_topology.x` is generated from this term plus a
separate DSLX deployment profile. This module contains no channels, muxes,
frames, or numeric tags.
""".

-include("phi_protocol.hrl").

-export([topology/0]).

-define(DATA_PRNG_SEED, 16#9e3779b9).
-define(SYNDROME_PRNG_SEED, 16#85ebca6b).
-define(HALF_THRESHOLD, 16#80000000).

-doc "Returns the version-0 semantic topology for the three-actor fixture.".
-spec topology() -> hls_topology:spec().
topology() ->
    Directions = [north, east, west, south],
    #{
        version => 0,
        actors => #{
            phi => phi_halo_cell,
            syndrome => phenom_syndrome_cell,
            data => phenom_data_cell
        },
        externals => [
            {announcement, out, [phenom_anyon]}
        ],
        routes =>
            routes(phi, Directions, phi) ++
            [{{phi, syndrome}, [{actor, syndrome}]}] ++
            routes(syndrome, Directions, data) ++
            [{{syndrome, phi}, queued, [
                {actor, phi},
                {external, announcement}
            ]}] ++
            routes(data, Directions, syndrome),
        startup => [
            {data, [#phenom_config{
                seed = ?DATA_PRNG_SEED,
                threshold = ?HALF_THRESHOLD
            }]},
            {syndrome, [#phenom_config{
                seed = ?SYNDROME_PRNG_SEED,
                threshold = ?HALF_THRESHOLD
            }]}
        ]
    }.

routes(Source, Ports, Destination) ->
    [
        {{Source, Port}, [{actor, Destination}]}
        || Port <- Ports
    ].
