-module(phi_field).
-moduledoc """
Two-layer phi fields composed from fixed-size vectors of signed Q15.16 scalars.

The BEAM representation is a pair of scaled integers in a list; DSLX uses an
s32[2] array with the same wire order. Scalar conversions, checked packing,
rounding, and saturation belong to hls_fixed; vector shape and weighted sums
belong to hls_vec. This module owns the decoder's two-layer recurrence.

Grid recurrences sum four physical neighbors; relax_line/4 sums two. Both
retain two auxiliary field layers. Their weighted numerators fit signed 37
and 36 bits respectively; the accumulator ABI remains s64.

Saturation prevents a long-running uniform gauge mode from wrapping across
the sign boundary. Each experiment must still validate its numerical range
and decide whether gauge recentering is preferable.

Used by the phi cell callbacks as an application arithmetic/type provider. XLS lowering imports the adjacent phi_field.x companion through dslx_imports/0.
""".
-behavior(hls_type).
-behaviour(xls_type).
%% Application constructors and field arithmetic.
-export([
    scalar/0,
    field/0,
    from_integer/1,
    from_ratio/2,
    to_float/1,
    accumulate/2,
    relax/4,
    relax_center/4,
    relax_bulk/3,
    relax_line/4,
    line_numerators/0, line_numerators/3,
    finish_line/2
]).

%% Host codec and XLS lowering callbacks.
-export([width/2, zero/2, transpile/3, pack/3, unpack/3, print_type/2, dslx_imports/0]).

%% Shared type contracts.
-export_type([scalar/0, field/0, accumulator/0, line_numerators/0]).

-doc "Signed Q15.16 scalar stored as its scaled 32-bit integer.".
-type scalar() :: hls_fixed:signed(32, 16).
-doc "Two ordered field layers: center followed by auxiliary bulk.".
-type field() :: hls_vec:vector(scalar(), 2).
-doc "Weighted center and bulk numerators retained across a line diffusion transition.".
-type line_numerators() :: hls_vec:vector(hls_nums:sN(36), 2).
-doc "Unscaled integer sum of at most four signed 32-bit scalar contributions.".
-type accumulator() :: -(4 bsl 31)..(4 * ((1 bsl 31) - 1)).

-doc "Returns the custom descriptor for one Q15.16 scalar.".
-spec scalar() -> hls_type:descriptor().
scalar() -> {hls_type, ?MODULE, scalar, []}.
-doc "Returns the custom descriptor for a two-layer Q15.16 field.".
-spec field() -> hls_type:descriptor().
field() -> {hls_type, ?MODULE, field, []}.

-doc "Returns the shared vector descriptor for two signed 36-bit numerators.".
-spec line_numerators() -> hls_type:descriptor().
line_numerators() -> {hls_type, ?MODULE, line_numerators, []}.

%% Delegate scalar representation and vector ordering to the shared runtime providers.
-spec component_type(scalar | field | line_numerators) -> hls_type:descriptor().
component_type(scalar) -> hls_fixed:signed(32, 16);
component_type(field) -> hls_vec:vector(component_type(scalar), 2);
component_type(line_numerators) -> hls_vec:vector(hls_nums:sN(36), 2).

-doc "Scales an integer into Q15.16 and rejects values outside the signed 32-bit range.".
-spec from_integer(integer()) -> scalar().
from_integer(Value) -> hls_fixed:from_integer(component_type(scalar), Value).

-doc "Rounds a rational to Q15.16 with the shared fixed-point rule and checks its signed range.".
-spec from_ratio(integer(), pos_integer()) -> scalar().
from_ratio(Numerator, Denominator) ->
    hls_fixed:from_ratio(component_type(scalar), Numerator, Denominator).

-doc "Converts the scaled scalar to a host floating-point value for inspection.".
-spec to_float(scalar()) -> float().
to_float(Value) -> hls_fixed:to_float(component_type(scalar), Value).

%% At most four scalar contributions fit in the diffusion accumulator.
-doc "Adds one scalar contribution; callers must keep the sum within the four-neighbor accumulator bound.".
-spec accumulate(accumulator(), scalar()) -> accumulator().
accumulate(Sum, Value) -> Sum + Value.

-doc "Updates both grid layers from four-neighbor sums, injecting the anyon into the center layer and saturating each result.".
-spec relax(hls_nums:u32(), field(), accumulator(), accumulator()) -> field().
relax(Anyon, [Phi0, Phi1], Sum0, Sum1) ->
    [relax_center(Anyon, Phi0, Phi1, Sum0), relax_bulk(Phi0, Phi1, Sum1)].

-doc "Rounds the weighted center recurrence by twelve, adds the anyon source, and saturates to Q15.16.".
-spec relax_center(hls_nums:u32(), scalar(), scalar(), accumulator()) -> scalar().
relax_center(Anyon, Phi0, Phi1, NeighborSum) ->
    Numerator = hls_vec:dot(hls_nums:s64(), [Phi0, Phi1], [6, 2]) + NeighborSum,
    hls_fixed:saturate(
        component_type(scalar),
        (Anyon bsl 16) + hls_fixed:round_ratio(Numerator, 12)
    ).

-doc "Rounds the weighted auxiliary recurrence by twelve and saturates to Q15.16.".
-spec relax_bulk(scalar(), scalar(), accumulator()) -> scalar().
relax_bulk(Phi0, Phi1, NeighborSum) ->
    Numerator = hls_vec:dot(hls_nums:s64(), [Phi0, Phi1], [1, 7]) + NeighborSum,
    hls_fixed:saturate(component_type(scalar), hls_fixed:round_ratio(Numerator, 12)).

-doc "Relaxes a two-neighbor line's two-layer field at eta=1/2; each sum contains two scalars.".
-spec relax_line(hls_nums:u32(), field(), accumulator(), accumulator()) -> field().
relax_line(Anyon, Field, Sum0, Sum1) ->
    finish_line(Anyon, line_numerators(Field, Sum0, Sum1)).

-doc "Computes unrounded line numerators; each neighbor sum must contain at most two signed 32-bit scalars.".
-spec line_numerators(field(), accumulator(), accumulator()) -> line_numerators().
line_numerators([Phi0, Phi1], Sum0, Sum1) ->
    [4 * Phi0 + 2 * Phi1 + Sum0, Phi0 + 5 * Phi1 + Sum1].

-doc "Rounds line numerators, injects the anyon into the center layer, then saturates both layers.".
-spec finish_line(hls_nums:u32(), line_numerators()) -> field().
finish_line(Anyon, [Center, Bulk]) ->
    [
        hls_fixed:saturate(
            component_type(scalar),
            (Anyon bsl 16) + hls_fixed:round_ratio(Center, 8)
        ),
        hls_fixed:saturate(component_type(scalar), hls_fixed:round_ratio(Bulk, 8))
    ].

-doc "Returns 32 bits for a scalar, 64 for a field, or 72 for line numerators.".
-spec width(scalar | field | line_numerators, []) -> 32 | 64 | 72.
width(Type, []) -> hls_type:width(component_type(Type)).
-doc "Returns the shared provider zero: integer zero or a two-element zero vector.".
-spec zero(scalar | field | line_numerators, []) -> scalar() | field() | line_numerators().
zero(Type, []) -> hls_type:zero(component_type(Type)).
-doc "Packs the selected representation with the shared checked scalar/vector codec.".
-spec pack(scalar() | field() | line_numerators(), scalar | field | line_numerators, []) ->
    bitstring().
pack(Value, Type, []) -> hls_type:pack(Value, component_type(Type)).
-doc "Consumes one value of the selected representation and retains trailing bits.".
-spec unpack(bitstring(), scalar | field | line_numerators, []) ->
    {scalar() | field() | line_numerators(), bitstring()}.
unpack(Packed, Type, []) -> hls_type:unpack(Packed, component_type(Type)).
-doc "Names the matching type exported by the phi_field DSLX companion.".
-spec print_type(scalar | field | line_numerators, []) -> string().
print_type(scalar, []) -> "phi_field::Scalar";
print_type(field, []) -> "phi_field::Field";
print_type(line_numerators, []) -> "phi_field::LineNumerators".
-doc "Requires the companion that implements the same saturated field recurrences.".
-spec dslx_imports() -> [phi_field].
dslx_imports() -> [phi_field].

-doc "Lowers field types and arithmetic calls to the matching static DSLX module.".
-spec transpile(atom(), [xls_clause_lower:ir()], xls_clause_lower:clause_state()) ->
    xls_clause_lower:ir().
transpile(scalar, [], State) ->
    xls_clause_lower:reference(State, {phantom, type, scalar()});
transpile(field, [], State) ->
    xls_clause_lower:reference(State, {phantom, type, field()});
transpile(line_numerators, [], State) ->
    xls_clause_lower:reference(State, {phantom, type, line_numerators()});
transpile(line_numerators, [Field, Sum0, Sum1], _State) ->
    ["phi_field::line_numerators(", Field, ", ", Sum0, ", ", Sum1, ")"];
transpile(finish_line, [Anyon, Numerators], _State) ->
    ["phi_field::finish_line(", Anyon, ", ", Numerators, ")"];
transpile(accumulate, [Sum, Value], _State) ->
    ["phi_field::accumulate(", Sum, ", ", Value, ")"];
transpile(relax, [Anyon, Field, Sum0, Sum1], _State) ->
    ["phi_field::relax(", Anyon, ", ", Field, ", ", Sum0, ", ", Sum1, ")"];
transpile(relax_line, [Anyon, Field, Sum0, Sum1], _State) ->
    ["phi_field::relax_line(", Anyon, ", ", Field, ", ", Sum0, ", ", Sum1, ")"];
transpile(relax_center, [Anyon, Phi0, Phi1, NeighborSum], _State) ->
    ["phi_field::relax_center(", Anyon, ", ", Phi0, ", ", Phi1, ", ", NeighborSum, ")"];
transpile(relax_bulk, [Phi0, Phi1, NeighborSum], _State) ->
    ["phi_field::relax_bulk(", Phi0, ", ", Phi1, ", ", NeighborSum, ")"].
