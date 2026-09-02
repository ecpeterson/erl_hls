%%%% phi_noise_topology_dslx
%%%%
%%%% Physical DSLX profile for the regular phi/noise geometry.

-module(phi_noise_topology_dslx).
-moduledoc """
Generates the regular multi-family phi/noise DSLX graph.

The default artifact uses the nondegenerate distance-three semantic topology.
`to_dslx/1` exists so the pinned XLS regression can exercise the same six
family types and cross-family routes at a smaller elaborated distance.

The physical profile retains one complete actor entry-effect burst across the
registered producer output and its FIFO. A uniform depth-one D2 mapping was
smaller, but the depth-zero and depth-one D1 smoke graphs both failed to reach
quiet decoder status within 200,000 cycles.
""".

-export([
    profile/0,
    scheduler_groups/0,
    scheduler_plan/0,
    to_dslx/0,
    to_dslx/1,
    to_dslx/2
]).

-doc "Returns the physical profile shared by the review and smoke artifacts.".
-spec profile() -> xls_topology_dslx:profile().
profile() ->
    #{
        name => phi_noise_topology,
        channel_depth => 1,
        actor_egress_depth => burst
    }.

-doc "Returns the provisional homogeneous sharing groups for this topology.".
-spec scheduler_groups() -> hls_scheduler_plan:spec().
scheduler_groups() ->
    #{
        data => #{
            members => [{family, data_even}, {family, data_odd}],
            state_storage => block_ram,
            mailbox_storage => block_ram
        },
        phi => #{
            members => [{family, phi_x}, {family, phi_z}],
            state_storage => block_ram,
            mailbox_storage => block_ram
        },
        syndrome => #{
            members => [{family, syndrome_x}, {family, syndrome_z}],
            state_storage => block_ram,
            mailbox_storage => block_ram
        }
    }.

-doc "Normalizes the distance-three shared-scheduler deployment plan.".
-spec scheduler_plan() -> hls_scheduler_plan:plan().
scheduler_plan() ->
    hls_scheduler_plan:normalize(
        hls_topology:from_module(phi_noise_topology),
        scheduler_groups()
    ).

-doc "Generates the default nondegenerate distance-three DSLX source.".
-spec to_dslx() -> iolist().
to_dslx() ->
    to_dslx(3).

-doc "Generates DSLX for one bounded semantic distance.".
-spec to_dslx(pos_integer()) -> iolist().
to_dslx(Distance) ->
    Plan = hls_topology:normalize(phi_noise_topology:topology(Distance)),
    xls_topology_dslx:emit(Plan, profile()).

-doc "Generates DSLX with an explicit `u32` phenomenological-noise rate.".
-spec to_dslx(pos_integer(), hls_nums:u32()) -> iolist().
to_dslx(Distance, NoiseRate) ->
    Plan = hls_topology:normalize(
        phi_noise_topology:topology(Distance, NoiseRate)
    ),
    xls_topology_dslx:emit(Plan, profile()).
