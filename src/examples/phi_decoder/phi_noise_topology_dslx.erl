%%%% phi_noise_topology_dslx
%%%%
%%%% Physical DSLX profile for the regular phi/noise geometry.

-module(phi_noise_topology_dslx).
-moduledoc """
Generates the regular multi-family phi/noise DSLX graph.

The default artifact uses the nondegenerate distance-three semantic topology.
`to_dslx/1` exists so the checked XLS regression can exercise the same six
family types and cross-family routes at a smaller elaborated distance.

The physical profile assigns the two data, phi, and syndrome families to
homogeneous executors. The default uses one executor per family, giving two
shards for each actor module; `profile/1` retains the original one-executor-per-
module form for measurement. Every executor stores actor state and mailbox
frames in simple-dual-port RAMs with one read and one write port, owns the
mailbox metadata for its logical slots, and advances one resumable actor
microstep at a time. Compact
group routers carry addressed requests between executors; there are no
per-coordinate request, admission, or egress channel arrays.
""".

-export([
    profile/0,
    profile/1,
    scheduler_groups/0,
    scheduler_groups/1,
    scheduler_plan/0,
    scheduler_plan/1,
    to_dslx/0,
    to_dslx/1,
    to_dslx/2,
    to_dslx/3
]).

-doc "Returns the physical profile shared by the review and smoke artifacts.".
-spec profile() -> xls_topology_dslx:profile().
profile() ->
    profile(2).

-doc "Returns the physical profile for one or two module-level shards.".
-spec profile(1 | 2) -> xls_topology_dslx:profile().
profile(ShardCount) ->
    #{
        name => phi_noise_topology,
        channel_depth => 1,
        actor_egress_depth => burst,
        scheduler_groups => scheduler_groups(ShardCount)
    }.

-doc "Returns the provisional homogeneous sharing groups for this topology.".
-spec scheduler_groups() -> hls_scheduler_plan:spec().
scheduler_groups() ->
    scheduler_groups(2).

-doc "Returns one scheduler per module or one scheduler per family.".
-spec scheduler_groups(1 | 2) -> hls_scheduler_plan:spec().
scheduler_groups(1) ->
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
    };
scheduler_groups(2) ->
    maps:from_list([
        {Family, group([Family])}
        || Family <- [
            data_even,
            data_odd,
            phi_x,
            phi_z,
            syndrome_x,
            syndrome_z
        ]
    ]);
scheduler_groups(_ShardCount) ->
    error(badarg).

group(Families) ->
    #{
        members => [{family, Family} || Family <- Families],
        state_storage => block_ram,
        mailbox_storage => block_ram
    }.

-doc "Normalizes the distance-three shared-scheduler deployment plan.".
-spec scheduler_plan() -> hls_scheduler_plan:plan().
scheduler_plan() ->
    scheduler_plan(2).

-doc "Normalizes the distance-three plan at the selected shard count.".
-spec scheduler_plan(1 | 2) -> hls_scheduler_plan:plan().
scheduler_plan(ShardCount) ->
    hls_scheduler_plan:normalize(
        hls_topology:from_module(phi_noise_topology),
        scheduler_groups(ShardCount)
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
    to_dslx(Distance, NoiseRate, 2).

-doc "Generates DSLX at an explicit noise rate and scheduler shard count.".
-spec to_dslx(pos_integer(), hls_nums:u32(), 1 | 2) -> iolist().
to_dslx(Distance, NoiseRate, ShardCount) ->
    Plan = hls_topology:normalize(
        phi_noise_topology:topology(Distance, NoiseRate)
    ),
    xls_topology_dslx:emit(Plan, profile(ShardCount)).
