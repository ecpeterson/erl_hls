-module(phi_field).
-moduledoc """
Two-layer phi fields composed from fixed-size vectors of signed Q15.16 scalars.

The BEAM representation is a pair of scaled integers in a list; DSLX uses an
s32[2] array with the same wire order. Scalar conversions, checked packing,
rounding, and saturation belong to hls_fixed; vector shape and weighted sums
belong to hls_vec. This module owns the decoder's two-layer recurrence.

Each neighbor sum contains exactly four scalars. The weighted numerator fits
in signed 37 bits even though the actor stores its accumulator in s64. These
bounds are part of the recurrence contract, not a narrower field ABI.

Saturation prevents a long-running uniform gauge mode from wrapping across
the sign boundary. Each experiment must still validate its numerical range
and decide whether gauge recentering is preferable.
""".
-behavior(hls_type).
-export([scalar/0, field/0, from_integer/1, from_ratio/2, to_float/1,
    accumulate/2, relax/4, relax_center/4, relax_bulk/3]).
-export([width/2, zero/2, transpile/3, pack/3, unpack/3, print_type/2,
    dslx_imports/0]).
-export_type([scalar/0, field/0, accumulator/0]).

-type scalar() :: hls_fixed:signed(32, 16).
-type field() :: hls_vec:vector(scalar(), 2).
-type accumulator() :: -(4 bsl 31)..(4 * ((1 bsl 31) - 1)).

scalar() -> {hls_type, ?MODULE, scalar, []}.
field() -> {hls_type, ?MODULE, field, []}.

component_type(scalar) -> hls_fixed:signed(32, 16);
component_type(field) -> hls_vec:vector(component_type(scalar), 2).

-spec from_integer(integer()) -> scalar().
from_integer(Value) -> hls_fixed:from_integer(component_type(scalar), Value).

-spec from_ratio(integer(), pos_integer()) -> scalar().
from_ratio(Numerator, Denominator) ->
    hls_fixed:from_ratio(component_type(scalar), Numerator, Denominator).

-spec to_float(scalar()) -> float().
to_float(Value) -> hls_fixed:to_float(component_type(scalar), Value).

%% At most four scalar contributions fit in the diffusion accumulator.
-spec accumulate(accumulator(), scalar()) -> accumulator().
accumulate(Sum, Value) -> Sum + Value.

-spec relax(hls_nums:u32(), field(), accumulator(), accumulator()) -> field().
relax(Anyon, [Phi0, Phi1], Sum0, Sum1) ->
    [relax_center(Anyon, Phi0, Phi1, Sum0), relax_bulk(Phi0, Phi1, Sum1)].

-spec relax_center(hls_nums:u32(), scalar(), scalar(), accumulator()) -> scalar().
relax_center(Anyon, Phi0, Phi1, NeighborSum) ->
    Numerator = hls_vec:dot(hls_nums:s64(), [Phi0, Phi1], [6, 2]) + NeighborSum,
    hls_fixed:saturate(component_type(scalar),
        (Anyon bsl 16) + hls_fixed:round_ratio(Numerator, 12)).

-spec relax_bulk(scalar(), scalar(), accumulator()) -> scalar().
relax_bulk(Phi0, Phi1, NeighborSum) ->
    Numerator = hls_vec:dot(hls_nums:s64(), [Phi0, Phi1], [1, 7]) + NeighborSum,
    hls_fixed:saturate(component_type(scalar), hls_fixed:round_ratio(Numerator, 12)).

width(Type, []) -> hls_type:width(component_type(Type)).
zero(Type, []) -> hls_type:zero(component_type(Type)).
pack(Value, Type, []) -> hls_type:pack(Value, component_type(Type)).
unpack(Packed, Type, []) -> hls_type:unpack(Packed, component_type(Type)).
print_type(scalar, []) -> "phi_field::Scalar";
print_type(field, []) -> "phi_field::Field".
dslx_imports() -> [phi_field].

transpile(scalar, [], State) ->
    xls_parse:reference(State, {phantom, type, scalar()});
transpile(field, [], State) ->
    xls_parse:reference(State, {phantom, type, field()});
transpile(accumulate, [Sum, Value], _State) ->
    ["phi_field::accumulate(", Sum, ", ", Value, ")"];
transpile(relax, [Anyon, Field, Sum0, Sum1], _State) ->
    ["phi_field::relax(", Anyon, ", ", Field, ", ", Sum0, ", ", Sum1, ")"];
transpile(relax_center, [Anyon, Phi0, Phi1, NeighborSum], _State) ->
    ["phi_field::relax_center(", Anyon, ", ", Phi0, ", ", Phi1, ", ", NeighborSum, ")"];
transpile(relax_bulk, [Phi0, Phi1, NeighborSum], _State) ->
    ["phi_field::relax_bulk(", Phi0, ", ", Phi1, ", ", NeighborSum, ")"].
