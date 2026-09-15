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
    checked_call("nth", [index(Index), List]);
transpile(set, [Index, List, Value], _State) ->
    checked_call("set", [index(Index), List, Value]);
transpile(new, [Subtype, Count], State) ->
    NewState = transpile(list, [Subtype, Count], State),
    transpile(zero, [xls_parse:reference(NewState)], NewState);
transpile(zero, [{phantom, type, {hls_type, hls_lists, list, [Subtype, Count]}}], _State) ->
    %% NOTE: Here we enforce that the arguments to `new/2` are static.
    ["zero!<", print_type(list, [Subtype, Count]), ">()"];
transpile(sublist, [Descriptor, List, Start, Count], _State) ->
    checked_slice_call("sublist", Descriptor, List, [index(Start), index(Count)]);
transpile(array_slice, [Descriptor, List, Start, {static, integer, Length}], _State)
        when Length > 0 ->
    checked_slice_call(["slice<u32:", integer_to_list(Length), ">"],
        Descriptor, List, [index(Start)]);
transpile(array_slice, [_Descriptor, _List, _Start, {static, integer, 0}], _State) ->
    error(empty_xls_collection);
transpile(array_slice, [_Descriptor, _List, _Start, Length], _State) ->
    error({invalid_array_slice_length, Length}).

checked_call(Name, Args) ->
    {fallible, badarg, ["hls_lists::", Name, "(", lists:join(", ", Args), ")"]}.

checked_slice_call(Name, {phantom, type, Type = {hls_type, ?MODULE, list, _}}, List, Args) ->
    {fallible, badarg, Call} = checked_call(Name, ["slice_values" | Args]),
    {fallible, badarg, ["{ let slice_values: ", hls_type:print_type(Type), " = ",
        List, "; ", Call, " }"]}.

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
        true -> [hls_lists];
        false -> []
    end.

pack(List, list, [ElementType, Length]) when length(List) =:= Length ->
    %% XLS casts array element zero to the most-significant bits, while the AXIS
    %% serializer sends the least-significant word first. Accumulate in reverse
    %% wire order so the XLS side can use a zero-cost array/bit cast, then
    %% flatten the iolist once without a separate list-reversal pass.
    iolist_to_binary(lists:foldl(
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

dslx_codec(list, [Subtype, Count]) ->
    case hls_type:dslx_codec(Subtype) of
        bit_cast -> bit_cast;
        _ ->
            BitsType = ["bits[", integer_to_list(hls_type:width(Subtype)), "]"],
            ArrayType = print_type(list, [Subtype, Count]),
            {fun(Bits) ->
                codec_map([Bits, " as ", BitsType, "[", integer_to_list(Count), "]"],
                    ArrayType, Count, fun(V) -> hls_type:dslx_from_bits(Subtype, V) end)
             end,
             fun(Values) ->
                ["(", codec_map(Values, [BitsType, "[", integer_to_list(Count), "]"],
                    Count, fun(V) -> hls_type:dslx_to_bits(Subtype, V) end),
                    ") as bits[", integer_to_list(hls_type:width(Subtype) * Count), "]"]
             end}
    end.

%% Bind input before entering the loop so recursively nested codecs may reuse
%% these local names without capturing an enclosing array's index.
codec_map(Input, OutputType, Count, Convert) ->
    ["{ let codec_input = ", Input, "; for (codec_index, codec_output): (u32, ",
        OutputType, ") in u32:0..u32:", integer_to_list(Count),
        " { update(codec_output, codec_index, ", Convert("codec_input[codec_index]"),
        ") } (zero!<", OutputType, ">()) }"].
