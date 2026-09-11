-module(hls_codec).
-moduledoc false.
-export([checked_integer/3, pack_integer/3, wrap_integer/3, pack_float/2]).

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
pack_float(Value, Width) ->
    Packed = <<Value:Width/little-float>>,
    %% Narrowing can produce infinity even from a finite BEAM value. Float
    %% matching accepts only finite values, so use the VM's own decoder to
    %% enforce that every successful pack can subsequently be unpacked.
    case Packed of
        <<_Finite:Width/little-float>> -> Packed;
        _ -> error(badarg)
    end.
