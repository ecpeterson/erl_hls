-module(phi_noise_topology_dslx).
-moduledoc "Dedicated actor deployment of the closed phi/noise topology.".
-export([profile/0, to_dslx/0, to_dslx/1, to_dslx/2]).
-doc "Returns channel and egress capacities for dedicated actor services.".
-spec profile() -> xls_topology_dslx:profile().
profile() -> #{name => phi_noise_topology, channel_depth => 1, actor_egress_depth => burst}.
-doc "Emits the distance-three closed-noise topology.".
-spec to_dslx() -> iodata().
to_dslx() -> xls_topology_dslx:from_module(phi_noise_topology, profile()).
-doc "Emits a dedicated topology at the requested distance.".
-spec to_dslx(pos_integer()) -> iodata().
to_dslx(D) -> to_dslx(D, 16#80000000).
-doc "Emits a dedicated topology at an explicit distance and noise threshold.".
-spec to_dslx(pos_integer(), hls_nums:u32()) -> iodata().
to_dslx(D, Noise) -> xls_topology_dslx:emit(hls_topology:normalize(phi_noise_topology:topology(D, Noise)), profile()).
