-module(hls_nums).
-moduledoc """
Byte-aligned numeric types. Integer packing rejects values outside the declared
signed or unsigned range; wrap/2 explicitly requests modular conversion.
Float packing rounds to binary16/32/64 and rejects nonfinite results. Live
values remain ordinary BEAM numbers. See docs/numeric-contract.md for the
normalization laws and the distinction from XLS arithmetic semantics.
""".

-behavior(hls_type).
-export([width/2, zero/2, transpile/3, pack/3, unpack/3, print_type/2]).  % hls_type callbacks

-export([u8/0, s8/0, u16/0, s16/0, u32/0, s32/0, u64/0, s64/0, uN/1]).
-export_type([u8/0, s8/0, u16/0, s16/0, u32/0, s32/0, u64/0, s64/0, uN/1]).
-export([float64/0, float32/0, float16/0]).                         % floats
-export([wrap/2]).
-export_type([float64/0, float32/0, float16/0]).

%%% unsigned integers
-type u8() :: 0 .. (1 bsl 8 - 1).
-type u16() :: 0 .. (1 bsl 16 - 1).
-type u32() :: 0 .. (1 bsl 32 - 1).
-type u64() :: 0 .. (1 bsl 64 - 1).
-type uN(_Width) :: non_neg_integer().

%%% signed integers
-type s8() :: -(1 bsl 7) .. (1 bsl 7 - 1) .
-type s16() :: -(1 bsl 15) .. (1 bsl 15 - 1).
-type s32() :: -(1 bsl 31) .. (1 bsl 31 - 1).
-type s64() :: -(1 bsl 63) .. (1 bsl 63 - 1).

%%% floats
%%% NOTE: Erlang only understands float64 "live", but it can write some others.
-type float64() :: float().  % e11m52
-type float32() :: float().  % e8m23
-type float16() :: float().  % e5m10

u8()      -> {hls_type, ?MODULE, ?FUNCTION_NAME, []}.
u16()     -> {hls_type, ?MODULE, ?FUNCTION_NAME, []}.
u32()     -> {hls_type, ?MODULE, ?FUNCTION_NAME, []}.
u64()     -> {hls_type, ?MODULE, ?FUNCTION_NAME, []}.
-doc """
A byte-aligned, otherwise arbitrary-width unsigned integer type.

Sub-byte widths remain unsupported until record and list packing define their
intra-byte wire order and no longer require `binary()` values.
""".
uN(Width) when is_integer(Width), Width > 0, Width rem 8 =:= 0 ->
    {hls_type, ?MODULE, ?FUNCTION_NAME, [Width]}.
s8()      -> {hls_type, ?MODULE, ?FUNCTION_NAME, []}.
s16()     -> {hls_type, ?MODULE, ?FUNCTION_NAME, []}.
s32()     -> {hls_type, ?MODULE, ?FUNCTION_NAME, []}.
s64()     -> {hls_type, ?MODULE, ?FUNCTION_NAME, []}.
float16() -> {hls_type, ?MODULE, ?FUNCTION_NAME, []}.
float32() -> {hls_type, ?MODULE, ?FUNCTION_NAME, []}.
float64() -> {hls_type, ?MODULE, ?FUNCTION_NAME, []}.

-doc """
Reduces an integer modulo 2^Width and interprets it with the target signedness.
Accepts arbitrary BEAM integers. On XLS this is an explicit integer cast; the
input expression must already have sufficient width for its intended value.
""".
-spec wrap(hls_type:descriptor(), integer()) -> integer().
wrap({hls_type, ?MODULE, Name, Args}, Value) ->
    hls_codec:wrap_integer(Value, width(Name, Args), signedness(Name)).

signedness(Type) when Type =:= u8; Type =:= u16; Type =:= u32;
        Type =:= u64; Type =:= uN -> unsigned;
signedness(Type) when Type =:= s8; Type =:= s16; Type =:= s32;
        Type =:= s64 -> signed.

width(u8,      []) -> 8;
width(u16,     []) -> 16;
width(u32,     []) -> 32;
width(u64,     []) -> 64;
width(uN, [Width]) when is_integer(Width), Width > 0,
        Width rem 8 =:= 0 -> Width;
width(s8,      []) -> 8;
width(s16,     []) -> 16;
width(s32,     []) -> 32;
width(s64,     []) -> 64;
width(float16, []) -> 16;
width(float32, []) -> 32;
width(float64, []) -> 64.

zero(u8,      []) -> 0;
zero(u16,     []) -> 0;
zero(u32,     []) -> 0;
zero(u64,     []) -> 0;
zero(uN, [Width]) when is_integer(Width), Width > 0,
        Width rem 8 =:= 0 -> 0;
zero(s8,      []) -> 0;
zero(s16,     []) -> 0;
zero(s32,     []) -> 0;
zero(s64,     []) -> 0;
zero(float16, []) -> 0.0;
zero(float32, []) -> 0.0;
zero(float64, []) -> 0.0 .

transpile(wrap, [{phantom, type, Type = {hls_type, ?MODULE, Name, _}}, Value], State) ->
    _ = signedness(Name),
    wrap_expression(Type, Value, State);
transpile(uN, [{static, integer, Width}], State) ->
    xls_parse:reference(
        State,
        {phantom, type, uN(Width)}
    );
transpile(Type, [], State) ->
    xls_parse:reference(State, {phantom, type, ?MODULE:Type()}).

%% A literal has no source width from which to cast. Normalize it before giving
%% it the target type so an out-of-range literal never reaches the DSLX parser.
wrap_expression(Type, {static, integer, Value}, _State) ->
    [hls_type:print_type(Type), ":", integer_to_list(wrap(Type, Value))];
wrap_expression(Type, Value, State) ->
    hls_type:transpile(as, [{phantom, type, Type}, Value], State).

pack(Value, Type, []) when Type =:= float16; Type =:= float32; Type =:= float64 ->
    hls_codec:pack_float(Value, width(Type, []));
pack(Value, Type, Args) ->
    hls_codec:pack_integer(Value, width(Type, Args), signedness(Type)).

unpack(<<Value:8/unsigned-little-integer,  Rest/binary>>, u8,      []) -> {Value, Rest};
unpack(<<Value:16/unsigned-little-integer, Rest/binary>>, u16,     []) -> {Value, Rest};
unpack(<<Value:32/unsigned-little-integer, Rest/binary>>, u32,     []) -> {Value, Rest};
unpack(<<Value:64/unsigned-little-integer, Rest/binary>>, u64,     []) -> {Value, Rest};
unpack(Packed, uN, [Width]) when is_integer(Width), Width > 0,
        Width rem 8 =:= 0 ->
    <<Value:Width/unsigned-little-integer, Rest/binary>> = Packed,
    {Value, Rest};
unpack(<<Value:8/signed-little-integer,    Rest/binary>>, s8,      []) -> {Value, Rest};
unpack(<<Value:16/signed-little-integer,   Rest/binary>>, s16,     []) -> {Value, Rest};
unpack(<<Value:32/signed-little-integer,   Rest/binary>>, s32,     []) -> {Value, Rest};
unpack(<<Value:64/signed-little-integer,   Rest/binary>>, s64,     []) -> {Value, Rest};
unpack(Packed, float16, []) -> hls_codec:unpack_float16(Packed);
unpack(<<Value:32/little-float,            Rest/binary>>, float32, []) -> {Value, Rest};
unpack(<<Value:64/little-float,            Rest/binary>>, float64, []) -> {Value, Rest}.

print_type(u8,      []) -> "u8";
print_type(u16,     []) -> "u16";
print_type(u32,     []) -> "u32";
print_type(u64,     []) -> "u64";
print_type(uN, [Width]) when is_integer(Width), Width > 0,
        Width rem 8 =:= 0 -> ["uN[", integer_to_list(Width), "]"];
print_type(s8,      []) -> "s8";
print_type(s16,     []) -> "s16";
print_type(s32,     []) -> "s32";
print_type(s64,     []) -> "s64";
print_type(float16, []) -> "float16";
print_type(float32, []) -> "float32";
print_type(float64, []) -> "float64".
