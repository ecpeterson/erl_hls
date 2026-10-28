-module(hls_vec).
-moduledoc """
Fixed-size homogeneous vectors, represented by lists on BEAM and DSLX arrays.

Element types own their numeric representation. Indexing is one-based and
requires an index within the vector, otherwise raising `badarg` (a source-located
failure in hardware). Packing requires exactly the declared
number of elements and preserves hls_lists' least-significant-word-first wire
order. `dot/3` computes a widened dot product of raw signed integers; its first
argument declares the accumulator type. Every intermediate sum must fit that
type. Fixed-point products retain their combined scale; no rescaling is implicit.

hls_type composes host element codecs; xls_type selects the compiler companion for array types and operations. The phi_field example builds its field representation on these vectors.
""".
-behavior(hls_type).
%% Application constructor and vector operations.
-export([vector/2, nth/2, set/3, dot/3]).

%% hls_type provider callbacks.
-export([width/2, zero/2, pack/3, unpack/3, value_width/2]).

%% Shared type contracts.
-export_type([vector/2]).

-type vector(Element, Size) :: [Element] | {no_return(), Size}.

-spec vector(hls_type:descriptor(), pos_integer()) -> hls_type:descriptor().
vector(Subtype, Size) when is_integer(Size), Size > 0 ->
    {hls_type, ?MODULE, vector, [Subtype, Size]}.

-spec nth(pos_integer(), vector(Element, _Size)) -> Element.
nth(Index, Values) -> hls_lists:nth(Index, Values).
-spec set(pos_integer(), vector(Element, Size), Element) -> vector(Element, Size).
set(Index, Values, Value) -> hls_lists:set(Index, Values, Value).

-spec dot(hls_type:descriptor(), [integer()], [integer()]) -> integer().
dot(_AccumulatorType, Left, Right) -> dot_sum(Left, Right, 0).
dot_sum([], [], Sum) ->
    Sum;
dot_sum([Left | LeftRest], [Right | RightRest], Sum) ->
    dot_sum(LeftRest, RightRest, Sum + Left * Right).

width(vector, [Subtype, Size]) ->
    _ = vector(Subtype, Size),
    hls_type:width(Subtype) * Size.
value_width(vector, Args) -> hls_lists:value_width(list, Args).
zero(vector, Args) -> hls_lists:zero(list, Args).
pack(Values, vector, Args) -> hls_lists:pack(Values, list, Args).
unpack(Packed, vector, Args) -> hls_lists:unpack(Packed, list, Args).
