-module(xls_nums).
-moduledoc """

""".

-behavior(xls_type).
-export([width/2, zero/2, transpile/2, pack/3, unpack/3, print_type/2]).  % xls_type callbacks

-export([u8/0, s8/0, u16/0, s16/0, u32/0, s32/0, u64/0, s64/0]).    % integers
-export_type([u8/0, s8/0, u16/0, s16/0, u32/0, s32/0, u64/0, s64/0]).
-export([float64/0, float32/0, float16/0]).                         % floats
-export_type([float64/0, float32/0, float16/0]).

%%% unsigned integers
-type u8() :: 0 .. (1 bsl 8 - 1).
-type u16() :: 0 .. (1 bsl 16 - 1).
-type u32() :: 0 .. (1 bsl 32 - 1).
-type u64() :: 0 .. (1 bsl 64 - 1).

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

u8()      -> {xls_type, ?MODULE, ?FUNCTION_NAME, []}.
u16()     -> {xls_type, ?MODULE, ?FUNCTION_NAME, []}.
u32()     -> {xls_type, ?MODULE, ?FUNCTION_NAME, []}.
u64()     -> {xls_type, ?MODULE, ?FUNCTION_NAME, []}.
s8()      -> {xls_type, ?MODULE, ?FUNCTION_NAME, []}.
s16()     -> {xls_type, ?MODULE, ?FUNCTION_NAME, []}.
s32()     -> {xls_type, ?MODULE, ?FUNCTION_NAME, []}.
s64()     -> {xls_type, ?MODULE, ?FUNCTION_NAME, []}.
float16() -> {xls_type, ?MODULE, ?FUNCTION_NAME, []}.
float32() -> {xls_type, ?MODULE, ?FUNCTION_NAME, []}.
float64() -> {xls_type, ?MODULE, ?FUNCTION_NAME, []}.

width(u8,      []) -> 8;
width(u16,     []) -> 16;
width(u32,     []) -> 32;
width(u64,     []) -> 64;
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
zero(s8,      []) -> 0;
zero(s16,     []) -> 0;
zero(s32,     []) -> 0;
zero(s64,     []) -> 0;
zero(float16, []) -> 0.0;
zero(float32, []) -> 0.0;
zero(float64, []) -> 0.0 .

transpile(Type, []) -> {phantom, type, ?MODULE:Type()}.

pack(Value, u8,  []) -> <<Value:8/unsigned-little-integer>>;
pack(Value, u16, []) -> <<Value:16/unsigned-little-integer>>;
pack(Value, u32, []) -> <<Value:32/unsigned-little-integer>>;
pack(Value, u64, []) -> <<Value:64/unsigned-little-integer>>;
pack(Value, s8,  []) -> <<Value:8/signed-little-integer>>;
pack(Value, s16, []) -> <<Value:16/signed-little-integer>>;
pack(Value, s32, []) -> <<Value:32/signed-little-integer>>;
pack(Value, s64, []) -> <<Value:64/signed-little-integer>>;
pack(Value, float16, []) -> <<Value:16/little-float>>;
pack(Value, float32, []) -> <<Value:32/little-float>>;
pack(Value, float64, []) -> <<Value:64/little-float>>.

unpack(<<Value:8/unsigned-little-integer,  Rest/binary>>, u8,      []) -> {Value, Rest};
unpack(<<Value:16/unsigned-little-integer, Rest/binary>>, u16,     []) -> {Value, Rest};
unpack(<<Value:32/unsigned-little-integer, Rest/binary>>, u32,     []) -> {Value, Rest};
unpack(<<Value:64/unsigned-little-integer, Rest/binary>>, u64,     []) -> {Value, Rest};
unpack(<<Value:8/signed-little-integer,    Rest/binary>>, s8,      []) -> {Value, Rest};
unpack(<<Value:16/signed-little-integer,   Rest/binary>>, s16,     []) -> {Value, Rest};
unpack(<<Value:32/signed-little-integer,   Rest/binary>>, s32,     []) -> {Value, Rest};
unpack(<<Value:64/signed-little-integer,   Rest/binary>>, s64,     []) -> {Value, Rest};
unpack(<<Value:16/little-float,            Rest/binary>>, float16, []) -> {Value, Rest};
unpack(<<Value:32/little-float,            Rest/binary>>, float32, []) -> {Value, Rest};
unpack(<<Value:64/little-float,            Rest/binary>>, float64, []) -> {Value, Rest}.

print_type(u8,      []) -> "u8";
print_type(u16,     []) -> "u16";
print_type(u32,     []) -> "u32";
print_type(u64,     []) -> "u64";
print_type(s8,      []) -> "s8";
print_type(s16,     []) -> "s16";
print_type(s32,     []) -> "s32";
print_type(s64,     []) -> "s64";
print_type(float16, []) -> "float16";
print_type(float32, []) -> "float32";
print_type(float64, []) -> "float64".
