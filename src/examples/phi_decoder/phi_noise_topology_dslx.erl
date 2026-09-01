%%%% phi_noise_topology_dslx
%%%%
%%%% Physical DSLX profile for the regular phi/noise geometry.

-module(phi_noise_topology_dslx).
-moduledoc """
Generates the regular multi-family phi/noise DSLX graph.

The default artifact uses the nondegenerate distance-three semantic topology.
`to_dslx/1` exists so the pinned XLS regression can exercise the same six
family types and cross-family routes at a smaller elaborated distance.
""".

-export([profile/0, to_dslx/0, to_dslx/1, to_dslx/2]).

-doc "Returns the physical profile shared by the review and smoke artifacts.".
-spec profile() -> xls_topology_dslx:profile().
profile() ->
    #{
        name => phi_noise_topology,
        channel_depth => 1
    }.

-doc "Generates the default nondegenerate distance-three DSLX source.".
-spec to_dslx() -> iolist().
to_dslx() ->
    to_dslx(3).

-doc "Generates DSLX for one bounded semantic distance.".
-spec to_dslx(pos_integer()) -> iolist().
to_dslx(Distance) ->
    Plan = hls_topology:normalize(phi_noise_topology:topology(Distance)),
    xls_topology_dslx:emit(Plan, profile()).

-doc "Generates DSLX with an explicit phenomenological-noise threshold.".
-spec to_dslx(pos_integer(), hls_nums:u32()) -> iolist().
to_dslx(Distance, NoiseThreshold) ->
    Plan = hls_topology:normalize(
        phi_noise_topology:topology(Distance, NoiseThreshold)
    ),
    xls_topology_dslx:emit(Plan, profile()).
