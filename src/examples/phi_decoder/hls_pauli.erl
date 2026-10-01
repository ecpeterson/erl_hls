-module(hls_pauli).
-moduledoc """
Projective single-qubit Pauli arithmetic with matching BEAM and generated
representations.

The Erlang representation uses the familiar atoms `i`, `x`, `y`, and `z`.
The generated representation uses the fixed symplectic encoding `i = 00`,
`x = 10`, `y = 11`, and `z = 01` in a `u32`. Multiplication discards
global phase and is therefore bitwise XOR.
""".

-behavior(hls_type).

-export([
    pauli/0,
    i/0,
    x/0,
    y/0,
    z/0,
    multiply/2,
    anticommutes/2,
    is_pauli/1
]).
-export([width/2, zero/2, transpile/3, pack/3, unpack/3, print_type/2]).
-export_type([pauli/0]).

-type pauli() :: i | x | y | z.

-doc "Returns the custom Pauli type descriptor.".
-spec pauli() -> {hls_type, module(), pauli, []}.
pauli() ->
    {hls_type, ?MODULE, ?FUNCTION_NAME, []}.

-spec i() -> pauli().
i() -> i.

-spec x() -> pauli().
x() -> x.

-spec y() -> pauli().
y() -> y.

-spec z() -> pauli().
z() -> z.

-doc "Multiplies two Paulis modulo global phase.".
-spec multiply(pauli(), pauli()) -> pauli().
multiply(Left, Right) ->
    decode(encode(Left) bxor encode(Right)).

-doc "Returns whether two Paulis anticommute.".
-spec anticommutes(pauli(), pauli()) -> boolean().
anticommutes(Left, Right) ->
    LeftCode = encode(Left),
    RightCode = encode(Right),
    SymplecticProduct =
        (((LeftCode bsr 1) band RightCode) bxor
         (LeftCode band (RightCode bsr 1))) band 1,
    SymplecticProduct =:= 1.

-doc "Returns whether a BEAM value is a Pauli letter.".
-spec is_pauli(term()) -> boolean().
is_pauli(i) -> true;
is_pauli(x) -> true;
is_pauli(y) -> true;
is_pauli(z) -> true;
is_pauli(_) -> false.

%% hls_type callbacks

width(pauli, []) -> 32.

zero(pauli, []) -> i.

pack(Value, pauli, []) ->
    Code = encode(Value),
    <<Code:32/little-unsigned-integer>>.

unpack(<<Code:32/little-unsigned-integer, Rest/binary>>, pauli, []) ->
    {decode(Code), Rest}.

print_type(pauli, []) -> "u32".

transpile(pauli, [], State) ->
    xls_parse:reference(State, {phantom, type, pauli()});
transpile(i, [], _State) -> "u32:0";
transpile(x, [], _State) -> "u32:2";
transpile(y, [], _State) -> "u32:3";
transpile(z, [], _State) -> "u32:1";
transpile(multiply, [Left, Right], _State) ->
    ["(", Left, " ^ ", Right, ")"];
transpile(anticommutes, [Left, Right], _State) ->
    ["((((", Left, " >> u32:1) & ", Right, ") ^ (", Left,
        " & (", Right, " >> u32:1))) & u32:1) == u32:1"];
transpile(is_pauli, [Value], _State) ->
    ["(", Value, " <= u32:3)"].

encode(i) -> 0;
encode(x) -> 2;
encode(y) -> 3;
encode(z) -> 1;
encode(_) -> error(badarg).

decode(0) -> i;
decode(2) -> x;
decode(3) -> y;
decode(1) -> z;
decode(_) -> error(badarg).
