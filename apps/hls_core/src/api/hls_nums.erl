-module(hls_nums).
-moduledoc """
Fixed-width numeric values with dense little-endian wire encodings. Integer packing
rejects values outside the declared signed or unsigned range; wrap/2 explicitly
requests modular conversion.
Float packing rounds to binary16/32/64 and rejects nonfinite results. Live
values remain ordinary BEAM numbers. See docs/numeric-contract.md for the
normalization laws and the distinction from XLS arithmetic semantics.

Actor annotations construct these descriptors. hls_type dispatches their host codecs; xls_type selects the compiler companion for generated types and operations.
""".

-behavior(hls_type).
%% Application type constructors and modular conversion.
-export([
    u8/0,
    s8/0,
    u16/0,
    s16/0,
    u32/0,
    s32/0,
    u64/0,
    s64/0,
    uN/1,
    sN/1,
    float64/0,
    float32/0,
    float16/0,
    wrap/2
]).

%% Integer domain query shared with compiler lowering.
-export([signedness/1]).

%% hls_type provider callbacks.
-export([width/2, zero/2, pack/3, unpack/3, value_width/2]).

%% Shared type contracts.
-export_type([u8/0, s8/0, u16/0, s16/0, u32/0, s32/0, u64/0, s64/0, uN/1, sN/1]).

%% Shared type contracts.
-export_type([float64/0, float32/0, float16/0]).

%%% unsigned integers
-doc "Unsigned 8-bit integer domain.".
-type u8() :: 0..((1 bsl 8) - 1).
-doc "Unsigned 16-bit integer domain.".
-type u16() :: 0..((1 bsl 16) - 1).
-doc "Unsigned 32-bit integer domain.".
-type u32() :: 0..((1 bsl 32) - 1).
-doc "Unsigned 64-bit integer domain.".
-type u64() :: 0..((1 bsl 64) - 1).
-type uN(_Width) :: non_neg_integer().

%%% signed integers
-doc "Two's-complement signed 8-bit integer domain.".
-type s8() :: -(1 bsl 7)..((1 bsl 7) - 1).
-doc "Two's-complement signed 16-bit integer domain.".
-type s16() :: -(1 bsl 15)..((1 bsl 15) - 1).
-doc "Two's-complement signed 32-bit integer domain.".
-type s32() :: -(1 bsl 31)..((1 bsl 31) - 1).
-doc "Two's-complement signed 64-bit integer domain.".
-type s64() :: -(1 bsl 63)..((1 bsl 63) - 1).
-type sN(_Width) :: integer().

%%% floats
%%% NOTE: Erlang only understands float64 "live", but it can write some others.

% e11m52
-type float64() :: float().
% e8m23
-type float32() :: float().
% e5m10
-type float16() :: float().

u8() -> {hls_type, ?MODULE, ?FUNCTION_NAME, []}.
u16() -> {hls_type, ?MODULE, ?FUNCTION_NAME, []}.
u32() -> {hls_type, ?MODULE, ?FUNCTION_NAME, []}.
u64() -> {hls_type, ?MODULE, ?FUNCTION_NAME, []}.
-doc """
An arbitrary positive-width unsigned integer occupying exactly Width bits.
""".
uN(Width) when is_integer(Width), Width > 0 ->
    {hls_type, ?MODULE, ?FUNCTION_NAME, [Width]}.
-doc "An arbitrary positive-width signed integer occupying exactly Width bits.".
sN(Width) when is_integer(Width), Width > 0 ->
    {hls_type, ?MODULE, ?FUNCTION_NAME, [Width]}.
s8() -> {hls_type, ?MODULE, ?FUNCTION_NAME, []}.
s16() -> {hls_type, ?MODULE, ?FUNCTION_NAME, []}.
s32() -> {hls_type, ?MODULE, ?FUNCTION_NAME, []}.
s64() -> {hls_type, ?MODULE, ?FUNCTION_NAME, []}.
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
    hls_codec:wrap_integer(Value, value_width(Name, Args), signedness(Name)).

-doc "Returns the signedness of an integer constructor; floating-point names are unsupported.".
-spec signedness(u8 | u16 | u32 | u64 | uN | s8 | s16 | s32 | s64 | sN) -> unsigned | signed.
signedness(Type) when
    Type =:= u8;
    Type =:= u16;
    Type =:= u32;
    Type =:= u64;
    Type =:= uN
->
    unsigned;
signedness(Type) when
    Type =:= s8;
    Type =:= s16;
    Type =:= s32;
    Type =:= s64;
    Type =:= sN
->
    signed.

width(Name, Args) -> value_width(Name, Args).

value_width(u8, []) ->
    8;
value_width(u16, []) ->
    16;
value_width(u32, []) ->
    32;
value_width(u64, []) ->
    64;
value_width(Type, [Width]) when
    (Type =:= uN orelse Type =:= sN),
    is_integer(Width),
    Width > 0
->
    Width;
value_width(s8, []) ->
    8;
value_width(s16, []) ->
    16;
value_width(s32, []) ->
    32;
value_width(s64, []) ->
    64;
value_width(float16, []) ->
    16;
value_width(float32, []) ->
    32;
value_width(float64, []) ->
    64.

zero(u8, []) ->
    0;
zero(u16, []) ->
    0;
zero(u32, []) ->
    0;
zero(u64, []) ->
    0;
zero(Type, [Width]) when Type =:= uN; Type =:= sN ->
    _ = value_width(Type, [Width]),
    0;
zero(s8, []) ->
    0;
zero(s16, []) ->
    0;
zero(s32, []) ->
    0;
zero(s64, []) ->
    0;
zero(float16, []) ->
    0.0;
zero(float32, []) ->
    0.0;
zero(float64, []) ->
    0.0.

pack(Value, Type, []) when Type =:= float16; Type =:= float32; Type =:= float64 ->
    hls_codec:pack_float(Value, width(Type, []));
pack(Value, Type, Args) ->
    Checked = hls_codec:checked_integer(Value, value_width(Type, Args), signedness(Type)),
    WireWidth = width(Type, Args),
    <<Checked:WireWidth/little-integer>>.

unpack(<<Value:8/unsigned-little-integer, Rest/binary>>, u8, []) ->
    {Value, Rest};
unpack(<<Value:16/unsigned-little-integer, Rest/binary>>, u16, []) ->
    {Value, Rest};
unpack(<<Value:32/unsigned-little-integer, Rest/binary>>, u32, []) ->
    {Value, Rest};
unpack(<<Value:64/unsigned-little-integer, Rest/binary>>, u64, []) ->
    {Value, Rest};
unpack(Packed, Type, Args) when Type =:= uN; Type =:= sN ->
    Width = width(Type, Args),
    <<Bits:Width/unsigned-little-integer, Rest/bitstring>> = Packed,
    {hls_codec:wrap_integer(Bits, value_width(Type, Args), signedness(Type)), Rest};
unpack(<<Value:8/signed-little-integer, Rest/binary>>, s8, []) ->
    {Value, Rest};
unpack(<<Value:16/signed-little-integer, Rest/binary>>, s16, []) ->
    {Value, Rest};
unpack(<<Value:32/signed-little-integer, Rest/binary>>, s32, []) ->
    {Value, Rest};
unpack(<<Value:64/signed-little-integer, Rest/binary>>, s64, []) ->
    {Value, Rest};
unpack(Packed, float16, []) ->
    hls_codec:unpack_float16(Packed);
unpack(<<Value:32/little-float, Rest/binary>>, float32, []) ->
    {Value, Rest};
unpack(<<Value:64/little-float, Rest/binary>>, float64, []) ->
    {Value, Rest}.
