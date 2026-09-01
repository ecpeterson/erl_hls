-module(phi_field).
-moduledoc """
Signed Q15.16 arithmetic for the phi-decoder example.

A field value is stored as a signed 32-bit integer with sixteen fractional
bits. The BEAM and generated representations are identical; conversion helpers
exist only for tests and host-side inspection. Diffusion uses signed 64-bit
intermediates and performs one division per recurrence, rounding to nearest
with ties away from zero before the result is saturated to Q15.16.

The current nonnegative charge model stays far inside the representable range.
Keeping the sign bit reserves the gauge choice in which empty cells contribute
a small negative background without changing the field ABI later.

The demo's present field range is far from overflow. Saturation prevents a
long-running uniform gauge mode from wrapping across the sign boundary; a
realistic experiment profile must still validate its field range and decide
whether gauge recentering is preferable.
""".

-behavior(hls_type).

-export([
    field/0,
    from_integer/1,
    from_ratio/2,
    to_float/1,
    accumulate/2,
    relax_center/4,
    relax_bulk/3
]).
-export([width/2, zero/2, transpile/3, pack/3, unpack/3, print_type/2]).
-export_type([field/0, accumulator/0]).

-define(FRACTION_BITS, 16).
-define(SCALE, (1 bsl ?FRACTION_BITS)).
-define(S32_BITS, 32).
-define(S32_SIGN, (1 bsl (?S32_BITS - 1))).
-define(S32_MIN, (-?S32_SIGN)).
-define(S32_MAX, (?S32_SIGN - 1)).
-define(MIN_INTEGER, (-(1 bsl 15))).
-define(MAX_INTEGER, ((1 bsl 15) - 1)).

-type field() :: hls_nums:s32().
-type accumulator() :: hls_nums:s64().

-doc "Returns the custom signed Q15.16 type descriptor.".
-spec field() -> {hls_type, module(), field, []}.
field() ->
    {hls_type, ?MODULE, ?FUNCTION_NAME, []}.

-doc "Encodes an exactly representable integer as Q15.16.".
-spec from_integer(integer()) -> field().
from_integer(Value) when Value >= ?MIN_INTEGER, Value =< ?MAX_INTEGER ->
    Value bsl ?FRACTION_BITS;
from_integer(_Value) ->
    error(badarg).

-doc "Rounds a rational value to the nearest Q15.16 value.".
-spec from_ratio(integer(), pos_integer()) -> field().
from_ratio(Numerator, Denominator) when Denominator > 0 ->
    Scaled = round_ratio(Numerator * ?SCALE, Denominator),
    case Scaled >= -?S32_SIGN andalso Scaled < ?S32_SIGN of
        true -> Scaled;
        false -> error(badarg)
    end;
from_ratio(_Numerator, _Denominator) ->
    error(badarg).

-doc "Converts a Q15.16 value to a BEAM float for inspection.".
-spec to_float(field()) -> float().
to_float(Value) ->
    Value / ?SCALE.

-doc "Adds one field value to a widened diffusion accumulator.".
-spec accumulate(accumulator(), field()) -> accumulator().
accumulate(Sum, Value) ->
    Sum + Value.

-doc "Applies the eta=1/4 center-plane relaxation recurrence.".
-spec relax_center(hls_nums:u32(), field(), field(), accumulator()) -> field().
relax_center(Anyon, Phi0, Phi1, NeighborSum0) ->
    Charge = Anyon bsl ?FRACTION_BITS,
    Smoothed = round_ratio(18 * Phi0 + 2 * Phi1 + NeighborSum0, 24),
    saturate_s32(Charge + Smoothed).

-doc "Applies the eta=1/4 terminal bulk-plane recurrence.".
-spec relax_bulk(field(), field(), accumulator()) -> field().
relax_bulk(Phi0, Phi1, NeighborSum1) ->
    saturate_s32(round_ratio(Phi0 + 15 * Phi1 + NeighborSum1, 20)).

%% hls_type callbacks

width(field, []) -> 32.

zero(field, []) -> 0.

pack(Value, field, []) ->
    <<Value:32/signed-little-integer>>.

unpack(<<Value:32/signed-little-integer, Rest/binary>>, field, []) ->
    {Value, Rest}.

print_type(field, []) -> "s32".

transpile(field, [], State) ->
    xls_parse:reference(State, {phantom, type, field()});
transpile(accumulate, [Sum, Value], _State) ->
    ["(", Sum, " + (", Value, " as s64))"];
transpile(relax_center, [Anyon, Phi0, Phi1, NeighborSum0], _State) ->
    Numerator = ["((", Phi0, " as s64) * s64:18 + (", Phi1,
        " as s64) * s64:2 + ", NeighborSum0, ")"],
    Result = ["((", Anyon, " as s64) << u32:16) + ",
        rounded_division(Numerator, 24)],
    saturated_s32(Result);
transpile(relax_bulk, [Phi0, Phi1, NeighborSum1], _State) ->
    Numerator = ["((", Phi0, " as s64) + (", Phi1,
        " as s64) * s64:15 + ", NeighborSum1, ")"],
    saturated_s32(rounded_division(Numerator, 20)).

rounded_division(Numerator, Denominator) ->
    Half = integer_to_list(Denominator div 2),
    Divisor = integer_to_list(Denominator),
    ["(if ", Numerator, " < s64:0 { (", Numerator, " - s64:", Half,
        ") / s64:", Divisor, " } else { (", Numerator, " + s64:", Half,
        ") / s64:", Divisor, " })"].

saturated_s32(Value) ->
    ["(if (", Value, ") > s64:2147483647 { s32:2147483647 } ",
        "else if (", Value, ") < s64:-2147483648 { s32:-2147483648 } ",
        "else { (", Value, ") as s32 })"].

round_ratio(Numerator, Denominator) when Numerator >= 0 ->
    (Numerator + Denominator div 2) div Denominator;
round_ratio(Numerator, Denominator) ->
    -round_ratio(-Numerator, Denominator).

saturate_s32(Value) when Value > ?S32_MAX -> ?S32_MAX;
saturate_s32(Value) when Value < ?S32_MIN -> ?S32_MIN;
saturate_s32(Value) -> Value.
