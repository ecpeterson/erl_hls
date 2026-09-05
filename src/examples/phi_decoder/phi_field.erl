-module(phi_field).
-moduledoc """
Signed Q15.16 arithmetic for the phi-decoder example.

A field value is stored as a signed 32-bit integer with sixteen fractional
bits. The BEAM and generated representations are identical; conversion helpers
exist only for tests and host-side inspection. Diffusion rounds to nearest
with ties away from zero before the result is saturated to Q15.16.

The generated recurrence uses the fact that a neighbor sum contains exactly
four field values. Each weighted numerator therefore fits in signed 37 bits.
Its magnitude fits in 36 unsigned bits, including the rounding offset. The
power of two is removed from 12 before the remaining unsigned division by 3.
These widths are lowering details rather than a narrower field ABI.

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
-define(MIN_NEIGHBOR_SUM, (4 * ?S32_MIN)).
-define(MAX_NEIGHBOR_SUM, (4 * ?S32_MAX)).
-define(NUMERATOR_BITS, 37).
-define(MAGNITUDE_BITS, 36).
-define(QUOTIENT_BITS, 33).
-define(MIN_REPRESENTABLE_INTEGER, (-(1 bsl 15))).
-define(MAX_REPRESENTABLE_INTEGER, ((1 bsl 15) - 1)).

-type field() :: hls_nums:s32().
-type accumulator() :: ?MIN_NEIGHBOR_SUM..?MAX_NEIGHBOR_SUM.

-doc "Returns the custom signed Q15.16 type descriptor.".
-spec field() -> {hls_type, module(), field, []}.
field() ->
    {hls_type, ?MODULE, ?FUNCTION_NAME, []}.

-doc "Encodes an exactly representable integer as Q15.16.".
-spec from_integer(integer()) -> field().
from_integer(Value)
        when Value >= ?MIN_REPRESENTABLE_INTEGER,
             Value =< ?MAX_REPRESENTABLE_INTEGER ->
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

-doc """
Adds one field value to a widened diffusion accumulator.

The accumulator begins at zero and receives at most four `field()` values.
Its bounded type is the contract which justifies the narrower generated
arithmetic even though the actor stores it in an `s64` register.
""".
-spec accumulate(accumulator(), field()) -> accumulator().
accumulate(Sum, Value) ->
    Sum + Value.

-doc "Applies center-plane relaxation to one four-neighbor sum.".
-spec relax_center(hls_nums:u32(), field(), field(), accumulator()) -> field().
relax_center(Anyon, Phi0, Phi1, NeighborSum0) ->
    Charge = Anyon bsl ?FRACTION_BITS,
    Smoothed = round_ratio(6 * Phi0 + 2 * Phi1 + NeighborSum0, 12),
    saturate_s32(Charge + Smoothed).

-doc "Applies terminal bulk-plane relaxation to one four-neighbor sum.".
-spec relax_bulk(field(), field(), accumulator()) -> field().
relax_bulk(Phi0, Phi1, NeighborSum1) ->
    saturate_s32(round_ratio(Phi0 + 7 * Phi1 + NeighborSum1, 12)).

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
transpile(relax_center, [Anyon, Phi0, Phi1, NeighborSum0], State0) ->
    State1 = weighted_numerator(
        State0, Phi0, 6, Phi1, 2, NeighborSum0
    ),
    State2 = rounded_division(State1, 12, 2, 3),
    State3 = xls_parse:instr(State2, [
        "((", Anyon, " as s64) << u32:16) + ",
        xls_parse:reference(State2)
    ]),
    saturated_s32(State3);
transpile(relax_bulk, [Phi0, Phi1, NeighborSum1], State0) ->
    State1 = weighted_numerator(
        State0, Phi0, 1, Phi1, 7, NeighborSum1
    ),
    State2 = rounded_division(State1, 12, 2, 3),
    saturated_s32(State2).

weighted_numerator(
        State, Phi0, Phi0Weight, Phi1, Phi1Weight, NeighborSum
) ->
    Type = xls_nums:signed_type(?NUMERATOR_BITS),
    xls_parse:instr(State, ["((", Phi0, " as ", Type, ") * ", Type, ":",
        integer_to_list(Phi0Weight), " + (", Phi1, " as ", Type,
        ") * ", Type, ":", integer_to_list(Phi1Weight), " + (",
        NeighborSum, " as ", Type, "))"]).

rounded_division(State0, Denominator, FactorShift, OddDivisor) ->
    SignedNumerator = xls_nums:signed_type(?NUMERATOR_BITS),
    MagnitudeType = xls_nums:unsigned_type(?MAGNITUDE_BITS),
    DividendBits = ?MAGNITUDE_BITS - FactorShift,
    DividendType = xls_nums:unsigned_type(DividendBits),
    SignedQuotient = xls_nums:signed_type(?QUOTIENT_BITS),
    Numerator = xls_parse:reference(State0),
    State1 = xls_parse:instr(State0, [
        Numerator, " < ", SignedNumerator, ":0"
    ]),
    Negative = xls_parse:reference(State1),
    State2 = xls_parse:instr(State1, [
        "((if ", Negative, " { -(", Numerator, ") } else { ",
        Numerator, " }) as ", MagnitudeType, ")"
    ]),
    Magnitude = xls_parse:reference(State2),
    State3 = xls_parse:instr(State2, [
        "(((", Magnitude, " + ", MagnitudeType, ":",
        integer_to_list(Denominator div 2), ") >> u32:",
        integer_to_list(FactorShift), ") as ", DividendType, ")"
    ]),
    RoundedDividend = xls_parse:reference(State3),
    State4 = xls_parse:instr(State3, [
        "((", RoundedDividend, " / ", DividendType, ":",
        integer_to_list(OddDivisor), ") as ", SignedQuotient, ")"
    ]),
    Quotient = xls_parse:reference(State4),
    xls_parse:instr(State4, [
        "((if ", Negative, " { -(", Quotient, ") } else { ",
        Quotient, " }) as s64)"
    ]).

saturated_s32(State) ->
    Value = xls_parse:reference(State),
    xls_parse:instr(State, [
        "(if ", Value, " > s64:2147483647 { s32:2147483647 } ",
        "else if ", Value, " < s64:-2147483648 { s32:-2147483648 } ",
        "else { ", Value, " as s32 })"
    ]).

round_ratio(Numerator, Denominator) when Numerator >= 0 ->
    (Numerator + Denominator div 2) div Denominator;
round_ratio(Numerator, Denominator) ->
    -round_ratio(-Numerator, Denominator).

saturate_s32(Value) when Value > ?S32_MAX -> ?S32_MAX;
saturate_s32(Value) when Value < ?S32_MIN -> ?S32_MIN;
saturate_s32(Value) -> Value.
