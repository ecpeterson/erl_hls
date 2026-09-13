-module(hls_float).
-moduledoc """
Explicit binary16/32/64 operations on ordinary Erlang floats.

Each operation rounds its operands to Type, treats subnormals as signed zero,
and rounds its result to nearest, ties to even, flushing subnormal results.
Overflow raises badarith on BEAM and reports a source-located arithmetic
failure in hardware. Codecs still preserve subnormals. No operation is fused.

Use literal/2 for typed constants in translated code. Variables must already
have the declared XLS precision; implicit conversion between formats and
ordinary Erlang operators on float structs are unsupported. See
docs/numeric-contract.md for the arithmetic and wire contracts.
""".
-export([literal/2, add/3, sub/3, mul/3, eq/3, lt/3]).
-export([transpile/3, dslx_imports/0, format/1]).

-spec literal(hls_type:descriptor(), number()) -> float().
literal(Type, Value) ->
    _ = format(Type),
    hls_type:normalize(Type, Value).

-spec add(hls_type:descriptor(), float(), float()) -> float().
add(Type, X, Y) -> arithmetic(add, Type, X, Y).
-spec sub(hls_type:descriptor(), float(), float()) -> float().
sub(Type, X, Y) -> arithmetic(sub, Type, X, Y).
-spec mul(hls_type:descriptor(), float(), float()) -> float().
mul(Type, X, Y) -> arithmetic(mul, Type, X, Y).

-spec eq(hls_type:descriptor(), float(), float()) -> boolean().
eq(Type, X, Y) -> operand_value(Type, X) == operand_value(Type, Y).
-spec lt(hls_type:descriptor(), float(), float()) -> boolean().
lt(Type, X, Y) -> operand_value(Type, X) < operand_value(Type, Y).

-spec format(hls_type:descriptor()) -> {pos_integer(), pos_integer()}.
format({hls_type, hls_nums, float16, []}) -> {5, 10};
format({hls_type, hls_nums, float32, []}) -> {8, 23};
format({hls_type, hls_nums, float64, []}) -> {11, 52}.

operand_value(Type, X) ->
    {E, F} = format(Type),
    Bits = operand_bits(Type, X, E, F),
    value(Type, Bits, 1 + E + F).

operand_bits(Type, X, E, F) ->
    Width = 1 + E + F,
    %% A failed narrowing is an arithmetic failure, just like result overflow.
    Bits = try hls_type:pack(X, Type) of
        <<Packed:Width/little>> -> Packed
    catch error:badarg -> error(badarith)
    end,
    case (Bits bsr F) band ((1 bsl E) - 1) of
        0 -> (Bits bsr (E + F)) bsl (E + F);
        _ -> Bits
    end.

arithmetic(Operation, Type, X, Y) ->
    {E, F} = format(Type),
    A = decode(operand_bits(Type, X, E, F), E, F),
    B = decode(operand_bits(Type, Y, E, F), E, F),
    {Sign, Magnitude, Exponent} = exact(Operation, A, B),
    Bits = rounded(Sign, Magnitude, Exponent, E, F),
    value(Type, Bits, 1 + E + F).

%% A finite dyadic number is (-1)^Sign * Magnitude * 2^Exponent. Keep an explicit
%% sign even for zero. Integer significands avoid binary64 double rounding and
%% allow binary64 multiplication to retain all 106 product bits until rounding.
decode(Bits, E, F) ->
    Sign = Bits bsr (E + F),
    case (Bits bsr F) band ((1 bsl E) - 1) of
        0 -> {Sign, 0, 0};
        Exponent -> {Sign, (1 bsl F) bor (Bits band ((1 bsl F) - 1)),
            Exponent - ((1 bsl (E - 1)) - 1) - F}
    end.

exact(mul, {SA, A, EA}, {SB, B, EB}) -> {SA bxor SB, A * B, EA + EB};
exact(sub, A, {SB, B, EB}) -> exact(add, A, {SB bxor 1, B, EB});
exact(add, {SA, A, EA}, {SB, B, EB}) ->
    E = min(EA, EB),
    Sum = signed(SA, A bsl (EA - E)) + signed(SB, B bsl (EB - E)),
    Sign = case Sum of
        0 -> SA band SB;
        _ when Sum < 0 -> 1;
        _ -> 0
    end,
    {Sign, abs(Sum), E}.

signed(0, N) -> N;
signed(1, N) -> -N.

rounded(Sign, 0, _Exponent, E, F) -> Sign bsl (E + F);
rounded(Sign, Magnitude, Exponent, E, F) ->
    Bias = (1 bsl (E - 1)) - 1,
    Top = integer_bits(Magnitude) - 1,
    %% Include gradual rounding at the normal/subnormal boundary before FTZ.
    %% A value just below the minimum normal can round up to that normal.
    Shift = max(Top - F, 1 - Bias - F - Exponent),
    Mantissa = nearest_even(Magnitude, Shift),
    RoundedTop = integer_bits(Mantissa) - 1,
    Bexp = Exponent + Shift + RoundedTop + Bias,
    case Bexp of
        _ when Mantissa =:= 0; Bexp =< 0 -> Sign bsl (E + F);
        _ when Bexp >= (1 bsl E) - 1 -> error(badarith);
        _ ->
            Fraction = (Mantissa bsr (RoundedTop - F)) band ((1 bsl F) - 1),
            (Sign bsl (E + F)) bor (Bexp bsl F) bor Fraction
    end.

nearest_even(N, Shift) when Shift =< 0 -> N bsl -Shift;
nearest_even(N, Shift) ->
    High = N bsr Shift,
    Tail = N - (High bsl Shift),
    Half = 1 bsl (Shift - 1),
    case Tail > Half orelse (Tail =:= Half andalso High band 1 =:= 1) of
        true -> High + 1;
        false -> High
    end.

integer_bits(0) -> 0;
integer_bits(N) ->
    <<First, Rest/binary>> = binary:encode_unsigned(N),
    8 * byte_size(Rest) + byte_bits(First).
byte_bits(0) -> 0;
byte_bits(N) -> 1 + byte_bits(N bsr 1).

value(Type, Bits, Width) ->
    {Value, <<>>} = hls_type:unpack(<<Bits:Width/little>>, Type),
    Value.

dslx_imports() -> [apfloat, hls_float].

transpile(literal, [{phantom, type, Type}, {static, Kind, Value}], _State)
        when Kind =:= float; Kind =:= integer ->
    {E, F} = format(Type),
    Width = 1 + E + F,
    <<Bits:Width/little>> = hls_type:pack(Value, Type),
    ["apfloat::unflatten<u32:", integer_to_list(E), ", u32:", integer_to_list(F),
        ">(uN[", integer_to_list(Width), "]:", integer_to_list(Bits), ")"];
transpile(literal, _Args, _State) ->
    error(nonconstant_float_literal);
transpile(Operation, [{phantom, type, Type}, X, Y], _State)
        when Operation =:= add; Operation =:= sub; Operation =:= mul;
             Operation =:= eq; Operation =:= lt ->
    {E, F} = format(Type),
    {fallible, badarith, ["hls_float::", atom_to_list(Operation), "<u32:",
        integer_to_list(E), ", u32:", integer_to_list(F), ">(", X, ", ", Y, ")"]}.
