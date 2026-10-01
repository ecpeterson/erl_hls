%%%% phi_noise_topology
%%%%
%%%% Compact semantic topology for a nondegenerate periodic phi/noise mesh.

-module(phi_noise_topology).
-moduledoc """
A compact periodic phi-decoder and phenomenological-noise geometry.

The default distance-three topology represents a six-by-six checkerboard with
two three-by-three syndrome planes.  Each syndrome plane has a matching
`phi_halo_cell` family.  Alternating data rows are represented by the
`data_even` and `data_odd` families, which lets every neighborhood remain an
ordinary wrapped translation between equal-shaped families.

Each decoder plane has one event output carrying sparse corrections and one
post-move status per coordinate. It preserves each source cell's
correction-before-status order; cross-cell merge order is unspecified.
Together, plane, syndrome coordinate, and correction direction identify the
neighboring data-qubit edge to correct. Syndrome announcements travel only to
their paired phi plane. Earlier lossless copies at the application boundary
existed solely for visualization and needlessly consumed application
bandwidth; they are candidates for a future best-effort debug event stream.
Both data-family measurement replies share one external output; their payload
coordinates use the physical data-qubit lattice and do not expose the internal
even/odd family split.

The `control_router` ingress names one stable router service at the application
boundary. A host or distribution adapter addresses its envelope to that one
service; the envelope's target and rectangle are inner multicast selectors,
not ERTS process destinations. The data target embeds `data_even[X,Y]` at
physical coordinate `[X,2Y]` and `data_odd[X,Y]` at `[X,2Y+1]`, so one
rectangle can select a physical line or the whole data grid without naming
either implementation family. Its noise target reaches both data families and
both syndrome planes; a whole-address-space cutoff therefore uses one host
command.

This rectangle names coordinates inside one generated fabric. The current
router neither distributes one command over several FPGAs nor makes such a
broadcast atomic. A multi-FPGA adapter must intersect a global rectangle with
the deployed partitions and send an explicitly addressed command to each
fabric router. Partial availability, failure, and retry semantics remain open.

Coordinates name stable logical services, like registered process names, not
particular actor incarnations. Router acceptance is bounded network admission,
not atomic admission to every selected actor mailbox. Each family distributor
retains order and completes its selected sends before taking another envelope,
but a lifecycle change may still discard resident copies. The present
whole-topology reset discards router and actor traffic together; independent
actor restart will require the lifecycle layer to close and flush affected
fanout or to add incarnation-aware leaf delivery.

"External" means a typed channel on the generated DSLX top proc.
`phi_memory_gateway` adapts those channels to one routed AXI-stream boundary,
and `phi_memory_runner` connects that boundary to the pure
`phi_memory_experiment` reducer through `hls_fabric`. The reducer maps sparse
corrections to point-addressed Pauli updates, waits for complete same-step
quiet and empty status sets from both planes, then issues one whole-grid query
in the selected basis and XORs the requested line's replies. A complementary
basis requires a separate reset and run. The real DMA driver still needs this
routed boundary. The adapter
preserves command order and each source's event order, validates the encoding,
and delivers Pauli updates at most once. This first protocol assigns no
recovery semantics to a reset or gateway failure; the experiment aborts.
Cutoffs are scheduled far enough ahead to reach every leaf, and experiments
quiesce before the u32 step counter rolls over.

All family coordinates are zero-based `{X, Y}` pairs.  The topology has six
`Distance`-by-`Distance` families and 34 route relations regardless of
distance.  Distance three is the smallest witness in which the four cardinal
phi neighbors are distinct.

Every actor receives one explicit configuration message.  The PRNG seeds are
deterministic, nonzero, and distinct across all six families; the high common
noise rate is intended to exercise the generated graph rather than specify a
physical noise model. The rate is encoded as the `u32` threshold used by each
cell's Bernoulli comparison. Because this example materializes those
configurations as an ordinary list, it accepts witness distances only up to
50; that is not a bound in the compact family or route model.
""".

-include("phi_protocol.hrl").

-export([topology/0, topology/1, topology/2, correction_update/3]).

-define(DEFAULT_DISTANCE, 3).
-define(MAX_WITNESS_DISTANCE, 50).
-define(EXERCISE_RATE, 16#80000000).
-define(SEED_STRIDE, 16#9e3779b9).
-define(U32_MASK, 16#ffffffff).

-doc "Returns the compact distance-three phi/noise topology.".
-spec topology() -> hls_topology:spec().
topology() ->
    topology(?DEFAULT_DISTANCE).

-doc "Returns a compact periodic phi/noise topology of the given distance.".
-spec topology(pos_integer()) -> hls_topology:spec().
topology(Distance)
        when Distance > 0, Distance =< ?MAX_WITNESS_DISTANCE ->
    topology(Distance, ?EXERCISE_RATE);
topology(_Distance) ->
    error(badarg).

-doc "Returns a topology with an explicit `u32` phenomenological-noise rate.".
-spec topology(pos_integer(), hls_nums:u32()) -> hls_topology:spec().
topology(Distance, NoiseRate)
        when Distance > 0, Distance =< ?MAX_WITNESS_DISTANCE,
             NoiseRate >= 0, NoiseRate =< ?U32_MASK ->
    Shape = [Distance, Distance],
    #{
        version => 1,
        actors => #{},
        ingresses => [control_router_ingress(Distance)],
        families => #{
            phi_x => #{module => phi_halo_cell, shape => Shape},
            phi_z => #{module => phi_halo_cell, shape => Shape},
            syndrome_x => #{module => phenom_syndrome_cell, shape => Shape},
            syndrome_z => #{module => phenom_syndrome_cell, shape => Shape},
            data_even => #{module => phenom_data_cell, shape => Shape},
            data_odd => #{module => phenom_data_cell, shape => Shape}
        },
        externals => [
            {x_decoder_events, out, [phi_correction, phi_status]},
            {z_decoder_events, out, [phi_correction, phi_status]},
            {data_measurements, out, [pauli_reply]}
        ],
        routes => [],
        route_relations => route_relations(),
        startup => startup(Distance, NoiseRate)
    };
topology(_Distance, _NoiseRate) ->
    error(badarg).

-doc "Maps one sparse decoder move to its physical data-qubit update.".
-spec correction_update(
    x | z,
    #phi_correction{},
    pos_integer()
) -> {{non_neg_integer(), non_neg_integer()}, hls_pauli:pauli()}.
correction_update(
    Plane,
    #phi_correction{x = X, y = Y, direction = Direction},
    Distance
) when Distance > 0, X >= 0, X < Distance, Y >= 0, Y < Distance ->
    DataHeight = 2 * Distance,
    case {Plane, Direction} of
        {x, ?PHI_NORTH_MASK} ->
            {{X, wrap(2 * Y - 1, DataHeight)}, hls_pauli:z()};
        {x, ?PHI_EAST_MASK} ->
            {{wrap(X + 1, Distance), 2 * Y}, hls_pauli:z()};
        {x, ?PHI_WEST_MASK} ->
            {{X, 2 * Y}, hls_pauli:z()};
        {x, ?PHI_SOUTH_MASK} ->
            {{X, 2 * Y + 1}, hls_pauli:z()};
        {z, ?PHI_NORTH_MASK} ->
            {{wrap(X + 1, Distance), 2 * Y}, hls_pauli:x()};
        {z, ?PHI_EAST_MASK} ->
            {{wrap(X + 1, Distance), 2 * Y + 1}, hls_pauli:x()};
        {z, ?PHI_WEST_MASK} ->
            {{X, 2 * Y + 1}, hls_pauli:x()};
        {z, ?PHI_SOUTH_MASK} ->
            {{wrap(X + 1, Distance), wrap(2 * Y + 2, DataHeight)},
                hls_pauli:x()};
        _ ->
            error(badarg)
    end;
correction_update(_Plane, _Correction, _Distance) ->
    error(badarg).

wrap(Value, Modulus) ->
    (Value + Modulus) rem Modulus.

control_router_ingress(Distance) ->
    DataEven = {family, data_even, {embed, [1, 2], [0, 0]}},
    DataOdd = {family, data_odd, {embed, [1, 2], [0, 1]}},
    SyndromeX = {family, syndrome_x, {embed, [1, 2], [0, 0]}},
    SyndromeZ = {family, syndrome_z, {embed, [1, 2], [0, 0]}},
    {control_router, {rectangle, [Distance, 2 * Distance]}, [
        {data, [pauli_query, pauli_update], [DataEven, DataOdd]},
        {noise, [noise_cutoff], [
            DataEven,
            DataOdd,
            SyndromeX,
            SyndromeZ
        ]}
    ]}.

route_relations() ->
    phi_relations(phi_x, syndrome_x, x_decoder_events) ++
        phi_relations(phi_z, syndrome_z, z_decoder_events) ++
        syndrome_x_relations() ++
        syndrome_z_relations() ++
        data_even_relations() ++
        data_odd_relations().

phi_relations(Phi, Syndrome, DecoderEvents) ->
    [
        relation(Phi, north, Phi, [0, -1]),
        relation(Phi, east, Phi, [1, 0]),
        relation(Phi, west, Phi, [-1, 0]),
        relation(Phi, south, Phi, [0, 1]),
        relation(Phi, syndrome, Syndrome, [0, 0]),
        {{Phi, correction}, [{external, DecoderEvents}]},
        {{Phi, status}, [{external, DecoderEvents}]}
    ].

syndrome_x_relations() ->
    [
        relation(syndrome_x, north, data_odd, [0, -1]),
        relation(syndrome_x, east, data_even, [1, 0]),
        relation(syndrome_x, west, data_even, [0, 0]),
        relation(syndrome_x, south, data_odd, [0, 0]),
        relation(syndrome_x, phi, phi_x, [0, 0])
    ].

syndrome_z_relations() ->
    [
        relation(syndrome_z, north, data_even, [1, 0]),
        relation(syndrome_z, east, data_odd, [1, 0]),
        relation(syndrome_z, west, data_odd, [0, 0]),
        relation(syndrome_z, south, data_even, [1, 1]),
        relation(syndrome_z, phi, phi_z, [0, 0])
    ].

data_even_relations() ->
    [
        relation(data_even, north, syndrome_z, [-1, -1]),
        relation(data_even, east, syndrome_x, [0, 0]),
        relation(data_even, west, syndrome_x, [-1, 0]),
        relation(data_even, south, syndrome_z, [-1, 0]),
        {{data_even, measurement}, [{external, data_measurements}]}
    ].

data_odd_relations() ->
    [
        relation(data_odd, north, syndrome_x, [0, 0]),
        relation(data_odd, east, syndrome_z, [0, 0]),
        relation(data_odd, west, syndrome_z, [-1, 0]),
        relation(data_odd, south, syndrome_x, [0, 1]),
        {{data_odd, measurement}, [{external, data_measurements}]}
    ].

relation(Source, Port, Destination, Offset) ->
    {{Source, Port}, [
        {family, Destination, {translate, Offset, wrap}}
    ]}.

startup(Distance, NoiseRate) ->
    data_family_startup(data_even, 0, 0, Distance, NoiseRate) ++
        data_family_startup(data_odd, 1, 1, Distance, NoiseRate) ++
        noise_family_startup(syndrome_x, 2, Distance, NoiseRate) ++
        noise_family_startup(syndrome_z, 3, Distance, NoiseRate) ++
        phi_family_startup(phi_x, 4, Distance) ++
        phi_family_startup(phi_z, 5, Distance).

data_family_startup(
    Family,
    PhysicalYParity,
    FamilyIndex,
    Distance,
    NoiseRate
) ->
    [
        {{Family, X, Y}, [#phenom_config{
            seed = seed(FamilyIndex, Distance, X, Y),
            threshold = NoiseRate,
            x = X,
            y = 2 * Y + PhysicalYParity
        }]}
        || X <- lists:seq(0, Distance - 1),
           Y <- lists:seq(0, Distance - 1)
    ].

noise_family_startup(Family, FamilyIndex, Distance, NoiseRate) ->
    [
        {{Family, X, Y}, [#phenom_config{
            seed = seed(FamilyIndex, Distance, X, Y),
            threshold = NoiseRate,
            x = X,
            y = Y
        }]}
        || X <- lists:seq(0, Distance - 1),
           Y <- lists:seq(0, Distance - 1)
    ].

phi_family_startup(Family, FamilyIndex, Distance) ->
    [
        {{Family, X, Y}, [#phi_config{
            seed = seed(FamilyIndex, Distance, X, Y)
        }]}
        || X <- lists:seq(0, Distance - 1),
           Y <- lists:seq(0, Distance - 1)
    ].

seed(FamilyIndex, Distance, X, Y) ->
    Index = FamilyIndex * Distance * Distance + X * Distance + Y + 1,
    (Index * ?SEED_STRIDE) band ?U32_MASK.
