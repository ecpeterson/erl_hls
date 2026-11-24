-module(hls_lists).
-moduledoc """
Fixed-size lists with one-based, checked access on BEAM and XLS.

Indices must identify an element. Slices must fit entirely; a zero-length slice
may start one past the end. Invalid bounds raise `badarg`, or a source-located
failure in hardware. `sublist/4` retains the declared length by zero-padding
after the selected range. `array_slice/4` returns exactly the requested length,
which must be a positive compile-time constant when translating to XLS. Empty
collections are supported by the host codecs; XLS does not support their values.

Used as both an application operation library and an hls_type provider. Host codecs compose element providers; xls_type selects the compiler companion for XLS operations and codecs.
""".
%% Application constructor and bounded operations.
-export([list/2, new/2, sublist/4, nth/2, set/3, array_slice/4]).

%% hls_type provider callbacks.
-export([zero/2, pack/3, unpack/3, width/2, value_width/2]).
%% Shared type contracts.
-export_type([list/2]).

-behavior(hls_type).

-type list(ElementType, Count) :: list(ElementType) | {no_return(), Count}.

%% TODO: separate `new/2` from `zero/2`

-doc "Type constructor.".
list(Subtype, Count) ->
    {hls_type, hls_lists, list, [Subtype, Count]}.

-doc "Constructs a fixed-size list of type-directed zero values.".
-spec new(hls_type:descriptor(), non_neg_integer()) -> [term()].
new(Subtype, Count) ->
    [hls_type:zero(Subtype) || _ <- lists:seq(1, Count)].

-doc "Extracts the sublist [Start, Start + Count) without modifying parent list length.".
sublist({hls_type, hls_lists, list, [Subtype, BigLength]}, List, Start, Count) ->
    Selected = checked_slice(List, Start, Count, BigLength),
    Padding = lists:duplicate(BigLength - Count, hls_type:zero(Subtype)),
    Selected ++ Padding.

array_slice({hls_type, hls_lists, list, [_Subtype, Size]}, List, Start, Length) ->
    checked_slice(List, Start, Length, Size).

checked_slice(List, Start, Count, Size) when
    length(List) =:= Size,
    is_integer(Start),
    is_integer(Count),
    Start >= 1,
    Start =< Size + 1,
    Count >= 0,
    Count =< Size + 1 - Start
->
    lists:sublist(List, Start, Count);
checked_slice(_List, _Start, _Count, _Size) ->
    error(badarg).

-spec nth(integer(), hls_lists:list(T, _C)) -> T.
-doc "Extracts the nth element from the list.".
nth(Index, List) when is_integer(Index), Index >= 1, Index =< length(List) ->
    lists:nth(Index, List);
nth(_Index, _List) ->
    error(badarg).

-spec set(integer(), hls_lists:list(T, C), T) -> hls_lists:list(T, C).
-doc "Replaces List's value at Index with the Item.".
set(Index, List, Item) when is_integer(Index), Index >= 1, Index =< length(List) ->
    set_at(Index, List, Item);
set(_Index, _List, _Item) ->
    error(badarg).

set_at(1, [_Old | Rest], Item) -> [Item | Rest];
set_at(Index, [Old | Rest], Item) -> [Old | set_at(Index - 1, Rest, Item)].

zero(list, [Subtype, Count]) ->
    new(Subtype, Count).

pack(List, list, [ElementType, Length]) when length(List) =:= Length ->
    %% Retain the established reverse element order on the wire. The DSLX
    %% codec permutes bits; the host only concatenates native bitstrings.
    hls_codec:join(
        lists:foldl(
            fun(Element, Acc) -> [hls_type:pack(Element, ElementType) | Acc] end,
            [],
            List
        )
    );
pack(_List, list, [_ElementType, _Length]) ->
    error(badarg).

unpack(Packed, list, [ElementType, Length]) ->
    {Rest, Backwards} = lists:foldl(
        fun(_Index, {AccIn, AccOut}) ->
            {Element, Rest} = hls_type:unpack(AccIn, ElementType),
            {Rest, [Element | AccOut]}
        end,
        {Packed, []},
        lists:seq(1, Length)
    ),
    %% Backwards reverses the least-significant-word-first wire representation
    %% back into the logical Erlang list order.
    {Backwards, Rest}.

width(list, [Subtype, Count]) ->
    hls_type:width(Subtype) * Count.

value_width(list, [Subtype, Count]) ->
    hls_type:value_width(Subtype) * Count.
