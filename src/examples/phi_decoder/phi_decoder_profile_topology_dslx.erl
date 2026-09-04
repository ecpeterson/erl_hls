%%%% phi_decoder_profile_topology_dslx
%%%%
%%%% Physical profile for the decoder-only throughput diagnostic.

-module(phi_decoder_profile_topology_dslx).
-moduledoc """
Generates the decoder-only phi profiling graph.

The phi families use the same interleaved shared schedulers and external block
RAM as the complete memory topology.  Each small request-paced syndrome family
has a separate scheduler because the scheduled topology currently routes only
between schedulers.  Their counters remain distinct from the decoder counters.
""".

-export([profile/0, profile/1, scheduler_plan/0, scheduler_plan/1,
    to_dslx/0, to_dslx/1]).

-doc "Returns the checked three-shard physical profile.".
-spec profile() -> xls_topology_dslx:profile().
profile() ->
    profile(3).

-doc "Returns a physical profile with the selected shards per phi plane.".
-spec profile(pos_integer()) -> xls_topology_dslx:profile().
profile(ShardCount) when ShardCount > 0, ShardCount =< 9 ->
    #{
        name => phi_decoder_profile_topology,
        channel_depth => 1,
        actor_egress_depth => burst,
        scheduler_groups => scheduler_groups(ShardCount)
    };
profile(_ShardCount) ->
    error(badarg).

-doc "Normalizes the checked three-shard scheduler plan.".
-spec scheduler_plan() -> hls_scheduler_plan:plan().
scheduler_plan() ->
    scheduler_plan(3).

-doc "Normalizes a decoder-only scheduler plan.".
-spec scheduler_plan(pos_integer()) -> hls_scheduler_plan:plan().
scheduler_plan(ShardCount) ->
    hls_scheduler_plan:normalize(
        hls_topology:from_module(phi_decoder_profile_topology),
        scheduler_groups(ShardCount)
    ).

-doc "Generates the checked three-shard DSLX artifact.".
-spec to_dslx() -> iolist().
to_dslx() ->
    to_dslx(3).

-doc "Generates the decoder-only DSLX artifact at one shard count.".
-spec to_dslx(pos_integer()) -> iolist().
to_dslx(ShardCount) ->
    Plan = hls_topology:from_module(phi_decoder_profile_topology),
    xls_topology_dslx:emit(Plan, profile(ShardCount)).

scheduler_groups(ShardCount) when ShardCount > 0, ShardCount =< 9 ->
    maps:from_list(
        [
            {{0, syndrome_x}, group([{family, syndrome_x}])},
            {{1, syndrome_z}, group([{family, syndrome_z}])}
        ] ++
        [
            {{2, phi_x, Shard}, group([
                {family, phi_x, {interleaved, Shard, ShardCount}}
            ])}
            || Shard <- lists:seq(0, ShardCount - 1)
        ] ++
        [
            {{3, phi_z, Shard}, group([
                {family, phi_z, {interleaved, Shard, ShardCount}}
            ])}
            || Shard <- lists:seq(0, ShardCount - 1)
        ]
    );
scheduler_groups(_ShardCount) ->
    error(badarg).

group(Members) ->
    #{
        members => Members,
        state_storage => block_ram,
        mailbox_storage => block_ram
    }.
