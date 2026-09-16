-module(hls_lists).
-moduledoc """
Fixed-size lists with one-based, checked access on BEAM and XLS.

Indices must identify an element. Slices must fit entirely; a zero-length slice
may start one past the end. Invalid bounds raise `badarg`, or a source-located
failure in hardware. `sublist/4` retains the declared length by zero-padding
after the selected range. `array_slice/4` returns exactly the requested length,
which must be a positive compile-time constant when translating to XLS. Empty
collections are supported by the host codecs; XLS does not support their values.
""".
-export([list/2]).
-export_type([list/2]).
-export([new/2, sublist/4, nth/2, set/3, array_slice/4]).
-export([zero/2, transpile/3, pack/3, unpack/3, width/2, print_type/2]).
-export([dslx_codec/2, dslx_imports/1]).
-export([value_width/2]).
-behavior(hls_type).

-type list(ElementType, Count) :: list(ElementType) | {no_return(), Count}.

%% TODO: separate `new/2` from `zero/2`

-doc "Type constructor.".
list(Subtype, Count) ->
    {hls_type, hls_lists, list, [Subtype, Count]}.

-doc "Erlang value constructor.  (XLS value constructor is transpile branch on this instr.)".
new(Subtype, Count) ->
    [hls_type:zero(Subtype) || _ <- lists:seq(1, Count)].

-doc "Extracts the sublist [Start, Start + Count) without modifying parent list length.".
sublist({hls_type, hls_lists, list, [Subtype, BigLength]}, List, Start, Count) ->
    Selected = checked_slice(List, Start, Count, BigLength),
    Padding = lists:duplicate(BigLength - Count, hls_type:zero(Subtype)),
    Selected ++ Padding.

array_slice({hls_type, hls_lists, list, [_Subtype, Size]}, List, Start, Length) ->
    checked_slice(List, Start, Length, Size).

checked_slice(List, Start, Count, Size)
        when length(List) =:= Size, is_integer(Start), is_integer(Count),
             Start >= 1, Start =< Size + 1, Count >= 0, Count =< Size + 1 - Start ->
    lists:sublist(List, Start, Count);
checked_slice(_List, _Start, _Count, _Size) -> error(badarg).

-spec nth(integer(), hls_lists:list(T, _C)) -> T.
-doc "Extracts the nth element from the list.".
nth(Index, List) when is_integer(Index), Index >= 1, Index =< length(List) ->
    lists:nth(Index, List);
nth(_Index, _List) -> error(badarg).

-spec set(integer(), hls_lists:list(T, C), T) -> hls_lists:list(T, C).
-doc "Replaces List's value at Index with the Item.".
set(Index, List, Item) when is_integer(Index), Index >= 1, Index =< length(List) ->
    set_at(Index, List, Item);
set(_Index, _List, _Item) -> error(badarg).

set_at(1, [_Old | Rest], Item) -> [Item | Rest];
set_at(Index, [Old | Rest], Item) -> [Old | set_at(Index - 1, Rest, Item)].

zero(list, [Subtype, Count]) ->
    new(Subtype, Count).

%% TODO: bake new into record construction?

transpile(list, [{phantom, type, Subtype}, {static, integer, Count}], State) ->
    xls_parse:reference(State, {phantom, type, list(Subtype, Count)});
transpile(nth, [Index, List], _State) ->
    checked_element(Index, List, "collection_values[collection_index]");
transpile(set, [Index, List, Value], _State) ->
    checked_element(Index, List, ["update(collection_values, collection_index, ", Value, ")"]);
transpile(new, [Subtype, Count], State) ->
    NewState = transpile(list, [Subtype, Count], State),
    transpile(zero, [xls_parse:reference(NewState)], NewState);
transpile(zero, [{phantom, type, {hls_type, hls_lists, list, [Subtype, Count]}}], _State) ->
    %% NOTE: Here we enforce that the arguments to `new/2` are static.
    ["zero!<", print_type(list, [Subtype, Count]), ">()"];
transpile(sublist, [Descriptor, List, Start, Count], _State) ->
    checked_slice_call(sublist, Descriptor, List, Start, Count);
transpile(array_slice, [Descriptor, List, Start, {static, integer, Length}], _State)
        when Length > 0 ->
    checked_slice_call({array_slice, Length}, Descriptor, List, Start, {static, integer, Length});
transpile(array_slice, [_Descriptor, _List, _Start, {static, integer, 0}], _State) ->
    error(empty_xls_collection);
transpile(array_slice, [_Descriptor, _List, _Start, Length], _State) ->
    error({invalid_array_slice_length, Length}).

%% Keep element types at the call site: XLS currently emits invalid IR names
%% for type-generic functions instantiated with parameterized structs (including
%% APFloat, also nested in arrays). Bounds arithmetic lives in the static module.
%% TODO: move these typed operations into that module once XLS fixes its mangling.
checked_element(Index, List, Result) ->
    {fallible, badarg, ["{ let collection_values = ", List, "; ",
        "let (collection_index, collection_invalid) = hls_lists::checked_index<",
        "{array_size(collection_values)}>(", index(Index), "); (", Result,
        ", collection_invalid) }"]}.

checked_slice_call(Operation, {phantom, type, Type = {hls_type, ?MODULE, list, [Subtype, Size]}},
        List, Start, Count) ->
    OutputSize = case Operation of sublist -> Size; {array_slice, Length} -> Length end,
    OutputType = print_type(list, [Subtype, OutputSize]),
    {fallible, badarg, ["{ let slice_values: ", hls_type:print_type(Type), " = ", List,
        "; let (slice_start, slice_mask, slice_invalid) = hls_lists::slice_bounds<u32:",
        integer_to_list(Size), ", u32:", integer_to_list(OutputSize), ">(",
        index(Start), ", ", index(Count), "); ",
        "let sliced = array_slice(slice_values, slice_start, zero!<", OutputType, ">()); ",
        "let selected = for (i, result): (u32, ", OutputType, ") in u32:0..u32:",
        integer_to_list(OutputSize), " { update(result, i, if slice_mask[i] { sliced[i] } ",
        "else { zero!<", hls_type:print_type(Subtype), ">() }) } (zero!<", OutputType,
        ">()); (selected, slice_invalid) }"]}.

%% Preserve a literal's full value before checking bounds. Dynamic expressions
%% keep their inferred integer width and signedness too.
index({static, integer, Value}) when Value >= 0, Value =< 16#ffffffff ->
    ["u32:", integer_to_list(Value)];
index({static, integer, Value}) ->
    Width = max(32, bit_size(binary:encode_unsigned(abs(Value))) + 1),
    [xls_nums:signed_type(Width), ":", integer_to_list(Value)];
index(Value) -> Value.

dslx_imports(Names) ->
    case lists:any(fun(Name) -> lists:member(Name, [nth, set, sublist, array_slice]) end, Names) of
        true -> [hls_bits, hls_lists];
        false -> [hls_bits]
    end.

pack(List, list, [ElementType, Length]) when length(List) =:= Length ->
    %% Retain the established reverse element order on the wire. The DSLX
    %% codec permutes bits; the host only concatenates native bitstrings.
    hls_codec:join(lists:foldl(
        fun(Element, Acc) -> [hls_type:pack(Element, ElementType) | Acc] end,
        [],
        List
    ));
pack(_List, list, [_ElementType, _Length]) -> error(badarg).

unpack(Packed, list, [ElementType, Length]) ->
    {Rest, Backwards} = lists:foldl(
        fun(_Index, {AccIn, AccOut}) ->
            {Element, Rest} = hls_type:unpack(AccIn, ElementType),
            {Rest, [Element | AccOut]}
        end,
        {Packed, []}, lists:seq(1, Length)
    ),
    %% Backwards reverses the least-significant-word-first wire representation
    %% back into the logical Erlang list order.
    {Backwards, Rest}.

print_type(list, [Subtype, Count]) when Count > 0 ->
    [hls_type:print_type(Subtype), "[", integer_to_list(Count), "]"];
print_type(list, [_Subtype, 0]) -> error(empty_xls_collection).

width(list, [Subtype, Count]) ->
    hls_type:width(Subtype) * Count.

value_width(list, [Subtype, Count]) ->
    hls_type:value_width(Subtype) * Count.

dslx_codec(list, [Subtype, Count]) ->
    %% XLS cannot bit-cast a flattened value into a multidimensional array.
    %% Compose element codecs at every dimension; these static maps are wires.
    BitsType = ["bits[", integer_to_list(hls_type:width(Subtype)), "]"],
    ArrayType = print_type(list, [Subtype, Count]),
    {fun(Bits) ->
        codec_map(["hls_bits::to_stream(", Bits, ") as ", BitsType, "[", integer_to_list(Count), "]"],
            ArrayType, Count, fun(V) -> hls_type:dslx_from_bits(Subtype,
                ["hls_bits::from_stream(", V, ")"]) end)
     end,
     fun(Values) ->
        ["hls_bits::from_stream((", codec_map(Values, [BitsType, "[", integer_to_list(Count), "]"],
            Count, fun(V) -> ["hls_bits::to_stream(", hls_type:dslx_to_bits(Subtype, V), ")"] end),
            ") as bits[", integer_to_list(hls_type:width(Subtype) * Count), "])"]
     end}.

%% Bind input before entering the loop so recursively nested codecs may reuse
%% these local names without capturing an enclosing array's index.
codec_map(Input, OutputType, Count, Convert) ->
    ["{ let codec_input = ", Input, "; for (codec_index, codec_output): (u32, ",
        OutputType, ") in u32:0..u32:", integer_to_list(Count),
        " { update(codec_output, codec_index, ", Convert(["codec_input[u32:", integer_to_list(Count - 1), " - codec_index]"]),
        ") } (zero!<", OutputType, ">()) }"].
