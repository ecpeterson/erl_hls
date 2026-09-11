-module(hls_codec).
-moduledoc false.
-export([checked_integer/3, pack_integer/3, wrap_integer/3, pack_float/2,
    unpack_float16/1]).

%% Values enter from untyped host messages. Width and signedness come from the
%% type provider; packed widths must be positive and byte-aligned.
-spec checked_integer(term(), pos_integer(), signed | unsigned) -> integer().
checked_integer(Value, Width, unsigned) when is_integer(Value),
        Value >= 0, Value < (1 bsl Width) -> Value;
checked_integer(Value, Width, signed) when is_integer(Value),
        Value >= -(1 bsl (Width - 1)), Value < (1 bsl (Width - 1)) -> Value;
checked_integer(_Value, _Width, _Signedness) -> error(badarg).

-spec pack_integer(term(), pos_integer(), signed | unsigned) -> binary().
pack_integer(Value, Width, Signedness) ->
    Checked = checked_integer(Value, Width, Signedness),
    %% Bit syntax preserves the low Width bits of the checked value, including
    %% the two's-complement representation of negative signed integers.
    <<Checked:Width/little-integer>>.

-spec wrap_integer(integer(), pos_integer(), signed | unsigned) -> integer().
wrap_integer(Value, Width, unsigned) -> Value band ((1 bsl Width) - 1);
wrap_integer(Value, Width, signed) ->
    Sign = 1 bsl (Width - 1),
    ((Value + Sign) band ((1 bsl Width) - 1)) - Sign.

-spec pack_float(number(), 16 | 32 | 64) -> binary().
pack_float(Value, 16) ->
    %% OTP 28.0.2's fallback binary16 conversion differs from its native path
    %% for subnormals and double rounding. Convert binary64 bits directly so
    %% the wire contract does not depend on the host's half-float support.
    <<Sign:1, Exponent:11, Fraction:52>> = <<Value:64/float>>,
    Magnitude = half_magnitude(Exponent - 1023, Fraction),
    case Magnitude < 16#7c00 of
        true -> <<((Sign bsl 15) bor Magnitude):16/little>>;
        false -> error(badarg)
    end;
pack_float(Value, Width) when Width =:= 32; Width =:= 64 ->
    Packed = <<Value:Width/little-float>>,
    %% Narrowing can produce infinity even from a finite BEAM value. Float
    %% matching accepts only finite values, so use the VM's own decoder to
    %% enforce that every successful pack can subsequently be unpacked.
    case Packed of
        <<_Finite:Width/little-float>> -> Packed;
        _ -> error(badarg)
    end.

%% Binary16 subnormals are multiples of 2^-24. Normal values retain 11 of
%% binary64's 53 significand bits. Exponent is unbiased; values below 2^-25
%% round to zero. Rounding may carry into the next exponent or the normal range.
half_magnitude(Exponent, _Fraction) when Exponent < -25 -> 0;
half_magnitude(Exponent, Fraction) when Exponent < -14 ->
    round_even((1 bsl 52) bor Fraction, 52 - 24 - Exponent);
half_magnitude(Exponent, Fraction) ->
    ((Exponent + 15) bsl 10) + round_even((1 bsl 52) bor Fraction, 52 - 10) - 1024.

round_even(Value, Shift) ->
    Kept = Value bsr Shift,
    Remainder = Value band ((1 bsl Shift) - 1),
    Half = 1 bsl (Shift - 1),
    case Remainder > Half orelse (Remainder =:= Half andalso Kept band 1 =:= 1) of
        true -> Kept + 1;
        false -> Kept
    end.

-spec unpack_float16(binary()) -> {float(), binary()}.
unpack_float16(<<Bits:16/little, Rest/binary>>) when Bits band 16#7c00 =/= 16#7c00 ->
    Fraction = Bits band 16#3ff,
    Magnitude = case (Bits bsr 10) band 16#1f of
        0 -> Fraction * 5.960464477539063e-8; % exactly 2^-24
        Exponent ->
            <<Normal:64/float>> = <<0:1, (Exponent + 1023 - 15):11, Fraction:10, 0:42>>,
            Normal
    end,
    Value = case Bits bsr 15 of 0 -> Magnitude; 1 -> -Magnitude end,
    {Value, Rest}.
