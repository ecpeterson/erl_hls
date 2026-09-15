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

-doc "Returns a physical profile at a shard count or profile configuration.".
-spec profile(pos_integer() | map()) -> xls_topology_dslx:profile().
profile(Options) ->
    Config = phi_decoder_profile:normalize(Options),
    #{
        name => phi_decoder_profile_topology,
        channel_depth => 1,
        actor_egress_depth => burst,
        reduction_placements => maps:from_list([
            {Phi, source_fragments}
            || #{phi := Phi} <- phi_decoder_profile:planes(Config)
        ]),
        scheduler_groups => scheduler_groups(Config)
    }.

-doc "Normalizes the checked three-shard scheduler plan.".
-spec scheduler_plan() -> hls_scheduler_plan:plan().
scheduler_plan() ->
    scheduler_plan(3).

-doc "Normalizes a decoder-only scheduler plan.".
-spec scheduler_plan(pos_integer() | map()) -> hls_scheduler_plan:plan().
scheduler_plan(Options) ->
    Config = phi_decoder_profile:normalize(Options),
    hls_scheduler_plan:normalize(
        hls_topology:normalize(phi_decoder_profile_topology:topology(Config)),
        scheduler_groups(Config)
    ).

-doc "Generates the checked three-shard DSLX artifact.".
-spec to_dslx() -> iolist().
to_dslx() ->
    to_dslx(3).

-doc "Generates the decoder-only DSLX artifact at a shard count or configuration.".
-spec to_dslx(pos_integer() | map()) -> iolist().
to_dslx(Options) ->
    Config = phi_decoder_profile:normalize(Options),
    Plan = hls_topology:normalize(phi_decoder_profile_topology:topology(Config)),
    xls_topology_dslx:emit(Plan, profile(Config)).

scheduler_groups(Config = #{shards := ShardCount}) ->
    Planes = phi_decoder_profile:planes(Config),
    maps:from_list(
        [
            {{Seed, Source}, group([{family, Source}])}
            || #{source := Source, source_seed := Seed} <- Planes
        ] ++
        [
            {{Seed, Phi, Shard}, group([
                {family, Phi, {interleaved, Shard, ShardCount}}
            ])}
            || #{phi := Phi, phi_seed := Seed} <- Planes,
               Shard <- lists:seq(0, ShardCount - 1)
        ]
    ).

group(Members) ->
    #{
        members => Members,
        state_storage => block_ram,
        mailbox_storage => block_ram
    }.
