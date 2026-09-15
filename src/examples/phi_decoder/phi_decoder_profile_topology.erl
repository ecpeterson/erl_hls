%%%% phi_decoder_profile_topology
%%%%
%%%% Decoder-only semantic topology for throughput attribution.

-module(phi_decoder_profile_topology).
-moduledoc """
Rectangular phi mesh with compact deterministic syndrome sources.

By default the two `phi_halo_cell` planes and their cardinal routes match
`phi_noise_topology`. Each paired syndrome family is replaced by a compact
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

-doc "Returns a square-distance or explicitly configured decoder-only topology.".
-spec topology(pos_integer() | map()) -> hls_topology:spec().
topology(Distance) when is_integer(Distance), Distance > 0, Distance =< 50 ->
    topology(#{shape => [Distance, Distance]});
topology(Options) when is_map(Options) ->
    Config = #{shape := Shape} = phi_decoder_profile:normalize(Options),
    Planes = phi_decoder_profile:planes(Config),
    #{
        version => 1,
        actors => #{},
        ingresses => [],
        families => maps:from_list(lists:append([
            [{Phi, #{module => phi_halo_cell, shape => Shape}},
             {Source, #{module => phi_syndrome_replay_cell, shape => Shape}}]
            || #{phi := Phi, source := Source} <- Planes
        ])),
        externals => [
            {Events, out, [phi_correction, phi_status]}
            || #{events := Events} <- Planes
        ],
        routes => [],
        route_relations =>
            lists:append([plane_relations(Phi, Source, Events)
                || #{phi := Phi, source := Source, events := Events} <- Planes]) ++
            [relation(Source, phi, Phi, [0, 0])
                || #{phi := Phi, source := Source} <- Planes],
        startup =>
            lists:append([source_startup(Source, Seed, Shape)
                || #{source := Source, source_seed := Seed} <- Planes]) ++
            lists:append([phi_startup(Phi, Seed, Shape)
                || #{phi := Phi, phi_seed := Seed} <- Planes])
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

source_startup(Family, FamilyIndex, [Width, Height] = Shape) ->
    [
        {{Family, X, Y}, [#phenom_config{
            seed = seed(FamilyIndex, Shape, X, Y),
            threshold = ?HALF_RATE,
            x = X,
            y = Y
        }]}
        || X <- lists:seq(0, Width - 1),
           Y <- lists:seq(0, Height - 1)
    ].

phi_startup(Family, FamilyIndex, [Width, Height] = Shape) ->
    [
        {{Family, X, Y}, [#phi_config{
            seed = seed(FamilyIndex, Shape, X, Y)
        }]}
        || X <- lists:seq(0, Width - 1),
           Y <- lists:seq(0, Height - 1)
    ].

seed(FamilyIndex, [Width, Height], X, Y) ->
    Linear = FamilyIndex * Width * Height + X * Height + Y + 1,
    (Linear * ?SEED_STRIDE) band ?U32_MASK.
