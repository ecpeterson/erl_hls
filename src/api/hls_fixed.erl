-module(hls_fixed).
-moduledoc """
Signed, byte-aligned fixed-point values represented by scaled BEAM integers.

`signed(Width, FractionBits)` includes the sign bit in Width. Packing and
conversion reject overflow; `saturate/2` explicitly clamps it. Rational
conversion and integer division round to nearest, with ties away from zero.
""".
-behavior(hls_type).
-export([signed/2, from_integer/2, from_ratio/3, to_float/2, saturate/2,
    round_ratio/2]).
-export([width/2, zero/2, pack/3, unpack/3, print_type/2, transpile/3,
    dslx_imports/0]).
-export_type([signed/2]).

-type signed(_Width, _FractionBits) :: integer().

-spec signed(pos_integer(), non_neg_integer()) -> hls_type:descriptor().
signed(Width, FractionBits) when is_integer(Width), Width > 0,
        Width rem 8 =:= 0, is_integer(FractionBits), FractionBits >= 0,
        FractionBits < Width ->
    {hls_type, ?MODULE, signed, [Width, FractionBits]}.

-spec from_integer(hls_type:descriptor(), integer()) -> integer().
from_integer({hls_type, ?MODULE, signed, [Width, FractionBits]}, Value) ->
    hls_codec:checked_integer(Value bsl FractionBits, Width, signed).

-spec from_ratio(hls_type:descriptor(), integer(), pos_integer()) -> integer().
from_ratio({hls_type, ?MODULE, signed, [Width, FractionBits]}, Numerator, Denominator) ->
    hls_codec:checked_integer(
        round_ratio(Numerator bsl FractionBits, Denominator), Width, signed).

-spec to_float(hls_type:descriptor(), integer()) -> float().
to_float({hls_type, ?MODULE, signed, [_Width, FractionBits]}, Value) ->
    Value / (1 bsl FractionBits).

-spec saturate(hls_type:descriptor(), integer()) -> integer().
saturate({hls_type, ?MODULE, signed, [Width, _FractionBits]}, Value) ->
    Limit = 1 bsl (Width - 1),
    max(-Limit, min(Limit - 1, Value)).

-spec round_ratio(integer(), pos_integer()) -> integer().
round_ratio(Numerator, Denominator) when Denominator > 0, Numerator >= 0 ->
    (Numerator + Denominator div 2) div Denominator;
round_ratio(Numerator, Denominator) when Denominator > 0 ->
    -round_ratio(-Numerator, Denominator);
round_ratio(_Numerator, _Denominator) ->
    error(badarg).

%% Source type annotations construct descriptors without calling signed/2.
width(signed, [Width, FractionBits]) ->
    _ = signed(Width, FractionBits),
    Width.
zero(signed, [_Width, _FractionBits]) -> 0.

pack(Value, signed, [Width, _FractionBits]) ->
    hls_codec:pack_integer(Value, Width, signed).

unpack(Packed, signed, [Width, _FractionBits]) ->
    <<Value:Width/signed-little-integer, Rest/binary>> = Packed,
    {Value, Rest}.

print_type(signed, [Width, _FractionBits]) -> xls_nums:signed_type(Width).
dslx_imports() -> [hls_fixed].

transpile(signed, [{static, integer, Width}, {static, integer, FractionBits}], State) ->
    xls_parse:reference(State, {phantom, type, signed(Width, FractionBits)});
transpile(saturate, [{phantom, type, Type}, Value], _State) ->
    ["hls_fixed::saturate<u32:", integer_to_list(hls_type:width(Type)),
        ">(", Value, ")"];
transpile(round_ratio, [Numerator, {static, integer, Denominator}], _State)
        when Denominator > 0, Denominator < (1 bsl 32) ->
    ["hls_fixed::round_ratio<u32:", integer_to_list(Denominator),
        ">(", Numerator, ")"].
