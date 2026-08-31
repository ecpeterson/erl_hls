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

The two external announcement outputs retain the producing `{X, Y}`
coordinate. The output port identifies the X- or Z-syndrome plane, so a host
can reconstruct lattice activity without relying on merge order. The two
correction outputs similarly identify the decoder plane; together, plane,
syndrome coordinate, and direction identify the neighboring data-qubit edge
to correct.

"External" currently means a typed output channel on the generated DSLX top
proc. This example does not yet supply a PL-PS gateway or an ERTS process which
consumes those channels. That adapter must eventually decode the event and
apply or accumulate the corresponding data-qubit correction (unless correction
application instead remains wholly within PL).

All family coordinates are zero-based `{X, Y}` pairs.  The topology has six
`Distance`-by-`Distance` families and 30 route relations regardless of
distance.  Distance three is the smallest witness in which the four cardinal
phi neighbors are distinct.

Every noise actor receives one explicit configuration message.  The seeds are
deterministic, nonzero, and distinct across the four noise families; the high
common threshold is intended to exercise the generated graph rather than
specify a physical noise model.  Phi cells retain their actor-local fixture
seed for now. Because this example materializes those configurations as an
ordinary list, it accepts witness distances only up to 50; that is not a bound
in the compact family or route model.
""".

-include("phi_protocol.hrl").

-export([topology/0, topology/1]).

-define(DEFAULT_DISTANCE, 3).
-define(MAX_WITNESS_DISTANCE, 50).
-define(EXERCISE_THRESHOLD, 16#80000000).
-define(SEED_STRIDE, 16#9e3779b9).
-define(U32_MASK, 16#ffffffff).

-doc "Returns the compact distance-three phi/noise topology.".
-spec topology() -> hls_topology:spec().
topology() ->
    topology(?DEFAULT_DISTANCE).

-doc "Returns a compact periodic phi/noise topology of the given distance.".
-spec topology(pos_integer()) -> hls_topology:spec().
topology(Distance)
        when is_integer(Distance), Distance > 0,
             Distance =< ?MAX_WITNESS_DISTANCE ->
    Shape = [Distance, Distance],
    #{
        version => 1,
        actors => #{},
        families => #{
            phi_x => #{module => phi_halo_cell, shape => Shape},
            phi_z => #{module => phi_halo_cell, shape => Shape},
            syndrome_x => #{module => phenom_syndrome_cell, shape => Shape},
            syndrome_z => #{module => phenom_syndrome_cell, shape => Shape},
            data_even => #{module => phenom_data_cell, shape => Shape},
            data_odd => #{module => phenom_data_cell, shape => Shape}
        },
        externals => [
            {x_announcements, out, [phenom_anyon]},
            {z_announcements, out, [phenom_anyon]},
            {x_corrections, out, [phi_correction]},
            {z_corrections, out, [phi_correction]}
        ],
        routes => [],
        route_relations => route_relations(),
        startup => startup(Distance)
    };
topology(_Distance) ->
    error(badarg).

route_relations() ->
    phi_relations(phi_x, syndrome_x, x_corrections) ++
        phi_relations(phi_z, syndrome_z, z_corrections) ++
        syndrome_x_relations() ++
        syndrome_z_relations() ++
        data_even_relations() ++
        data_odd_relations().

phi_relations(Phi, Syndrome, Corrections) ->
    [
        relation(Phi, north, Phi, [0, -1]),
        relation(Phi, east, Phi, [1, 0]),
        relation(Phi, west, Phi, [-1, 0]),
        relation(Phi, south, Phi, [0, 1]),
        relation(Phi, syndrome, Syndrome, [0, 0]),
        {{Phi, correction}, [{external, Corrections}]}
    ].

syndrome_x_relations() ->
    [
        relation(syndrome_x, north, data_odd, [0, -1]),
        relation(syndrome_x, east, data_even, [1, 0]),
        relation(syndrome_x, west, data_even, [0, 0]),
        relation(syndrome_x, south, data_odd, [0, 0]),
        announcement_relation(syndrome_x, phi_x, x_announcements)
    ].

syndrome_z_relations() ->
    [
        relation(syndrome_z, north, data_even, [1, 0]),
        relation(syndrome_z, east, data_odd, [1, 0]),
        relation(syndrome_z, west, data_odd, [0, 0]),
        relation(syndrome_z, south, data_even, [1, 1]),
        announcement_relation(syndrome_z, phi_z, z_announcements)
    ].

data_even_relations() ->
    [
        relation(data_even, north, syndrome_z, [-1, -1]),
        relation(data_even, east, syndrome_x, [0, 0]),
        relation(data_even, west, syndrome_x, [-1, 0]),
        relation(data_even, south, syndrome_z, [-1, 0])
    ].

data_odd_relations() ->
    [
        relation(data_odd, north, syndrome_x, [0, 0]),
        relation(data_odd, east, syndrome_z, [0, 0]),
        relation(data_odd, west, syndrome_z, [-1, 0]),
        relation(data_odd, south, syndrome_x, [0, 1])
    ].

relation(Source, Port, Destination, Offset) ->
    {{Source, Port}, [
        {family, Destination, {translate, Offset, wrap}}
    ]}.

announcement_relation(Source, Destination, External) ->
    {{Source, phi}, queued, [
        {family, Destination, {translate, [0, 0], wrap}},
        {external, External}
    ]}.

startup(Distance) ->
    family_startup(data_even, 0, Distance) ++
        family_startup(data_odd, 1, Distance) ++
        family_startup(syndrome_x, 2, Distance) ++
        family_startup(syndrome_z, 3, Distance).

family_startup(Family, FamilyIndex, Distance) ->
    [
        {{Family, X, Y}, [#phenom_config{
            seed = seed(FamilyIndex, Distance, X, Y),
            threshold = ?EXERCISE_THRESHOLD,
            x = X,
            y = Y
        }]}
        || X <- lists:seq(0, Distance - 1),
           Y <- lists:seq(0, Distance - 1)
    ].

seed(FamilyIndex, Distance, X, Y) ->
    Index = FamilyIndex * Distance * Distance + X * Distance + Y + 1,
    (Index * ?SEED_STRIDE) band ?U32_MASK.
