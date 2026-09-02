%%%% xls_nums
%%%%
%%%% DSLX rendering for numeric HLS values.

-module(xls_nums).

-export([
    packed_unsigned_literal/1,
    signed_type/1,
    unsigned_literal/2,
    unsigned_type/1
]).

-doc "Prints the DSLX type for a signed value of the given width.".
-spec signed_type(pos_integer()) -> iolist().
signed_type(8) -> "s8";
signed_type(16) -> "s16";
signed_type(32) -> "s32";
signed_type(64) -> "s64";
signed_type(Width) when Width > 0 ->
    ["sN[", integer_to_list(Width), "]"].

-doc "Prints the DSLX type for an unsigned value of the given width.".
-spec unsigned_type(pos_integer()) -> iolist().
unsigned_type(Width) when Width > 0, Width < 8 ->
    ["u", integer_to_list(Width)];
unsigned_type(8) -> "u8";
unsigned_type(16) -> "u16";
unsigned_type(32) -> "u32";
unsigned_type(64) -> "u64";
unsigned_type(Width) when Width > 0 ->
    ["uN[", integer_to_list(Width), "]"].

-doc "Prints a byte-aligned unsigned value as a DSLX literal.".
-spec unsigned_literal(non_neg_integer(), pos_integer()) -> iolist().
unsigned_literal(Value, Width)
        when is_integer(Value), Value >= 0,
             is_integer(Width), Width > 0, Width rem 8 =:= 0,
             Value < (1 bsl Width) ->
    Digits = max(1, (Width + 3) div 4),
    Hex = integer_to_list(Value, 16),
    [unsigned_type(Width), ":0x",
        lists:duplicate(Digits - length(Hex), $0), Hex].

-doc "Prints a little-endian packed unsigned value as a DSLX literal.".
-spec packed_unsigned_literal(binary()) -> iolist().
packed_unsigned_literal(Packed) when is_binary(Packed) ->
    unsigned_literal(
        binary:decode_unsigned(Packed, little),
        bit_size(Packed)
    ).
