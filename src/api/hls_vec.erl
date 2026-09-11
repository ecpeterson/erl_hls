-module(hls_vec).
-moduledoc """
Fixed-size homogeneous vectors, represented by lists on BEAM and DSLX arrays.

Element types own their numeric representation. Indexing is one-based and
requires an index within the vector. Packing requires exactly the declared
number of elements and preserves hls_lists' least-significant-word-first wire
order. `dot/3` computes a widened dot product of raw signed integers; its first
argument declares the accumulator type. Every intermediate sum must fit that
type. Fixed-point products retain their combined scale; no rescaling is implicit.
""".
-behavior(hls_type).
-export([vector/2, nth/2, set/3, dot/3]).
-export([width/2, zero/2, pack/3, unpack/3, print_type/2, transpile/3, dslx_imports/0]).
-export_type([vector/2]).

-type vector(Element, Size) :: [Element] | {no_return(), Size}.

-spec vector(hls_type:descriptor(), pos_integer()) -> hls_type:descriptor().
vector(Subtype, Size) when is_integer(Size), Size > 0 ->
    {hls_type, ?MODULE, vector, [Subtype, Size]}.

-spec nth(pos_integer(), vector(Element, _Size)) -> Element.
nth(Index, Values) -> lists:nth(Index, Values).
-spec set(pos_integer(), vector(Element, Size), Element) -> vector(Element, Size).
set(Index, Values, Value) -> hls_lists:set(Index, Values, Value).

-spec dot(hls_type:descriptor(), [integer()], [integer()]) -> integer().
dot(_AccumulatorType, Left, Right) -> dot_sum(Left, Right, 0).
dot_sum([], [], Sum) -> Sum;
dot_sum([Left | LeftRest], [Right | RightRest], Sum) ->
    dot_sum(LeftRest, RightRest, Sum + Left * Right).

width(vector, [Subtype, Size]) ->
    _ = vector(Subtype, Size),
    hls_type:width(Subtype) * Size.
zero(vector, Args) -> hls_lists:zero(list, Args).
print_type(vector, Args) -> hls_lists:print_type(list, Args).
pack(Values, vector, Args) -> hls_lists:pack(Values, list, Args).
unpack(Packed, vector, Args) -> hls_lists:unpack(Packed, list, Args).
dslx_imports() -> [hls_vec].

transpile(vector, [{phantom, type, Subtype}, {static, integer, Size}], State) ->
    xls_parse:reference(State, {phantom, type, vector(Subtype, Size)});
transpile(nth, Args, State) -> hls_lists:transpile(nth, Args, State);
transpile(set, Args, State) -> hls_lists:transpile(set, Args, State);
transpile(dot, [{phantom, type, AccumulatorType}, Left, Right], _State) ->
    ["hls_vec::dot<u32:", integer_to_list(hls_type:width(AccumulatorType)),
        ">(", Left, ", ", Right, ")"].
