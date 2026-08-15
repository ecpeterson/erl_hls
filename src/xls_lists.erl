-module(xls_lists).
-export([list/2]).
-export_type([list/2]).
-export([new/2, sublist/4, nth/2, set/3, array_slice/4]).
-export([zero/2, transpile/3, pack/3, unpack/3, width/2, print_type/2]).
-behavior(xls_type).

%% TODO: the module interface should probably closely match that of XLS, so that
%%  the Erlang programmer knows how to adapt their code to be convertible.
%%
%% NOTE: We adhere to Erlang-type indexing conventions, so that people introduce
%%  as few off-by-ones as possible when converting code.

-type list(ElementType, Count) :: list(ElementType) | {no_return(), Count}.

%% TODO: separate `new/2` from `zero/2`

-doc "Type constructor.".
list(Subtype, Count) ->
    {xls_type, xls_lists, list, [Subtype, Count]}.

-doc "Erlang value constructor.  (XLS value constructor is transpile branch on this instr.)".
new(Subtype, Count) ->
    [xls_type:zero(Subtype) || _ <- lists:seq(1, Count)].

-doc "Extracts the sublist [Start, Start + Count) without modifying parent list length.".
sublist(Descriptor, List, Start, Count) ->
    {xls_type, xls_lists, list, [Subtype, BigLength]} = Descriptor,
    Padding = lists:duplicate(BigLength - Count, xls_type:zero(Subtype)),
    lists:sublist(List, Start, Count) ++ Padding.

array_slice(_Descriptor, List, Start, Length) ->
    lists:sublist(List, Start, Length).

-spec nth(integer(), xls_lists:list(T, _C)) -> T.
-doc "Extracts the nth element from the list.".
nth(Index, List) ->
    lists:nth(Index, List).

-spec set(integer(), xls_lists:list(T, C), T) -> xls_lists:list(T, C).
-doc "Replaces List's value at Index with the Item.".
set(Index, List, Item) ->
    case {Index, List} of
        {1, [_Old | Rest]} -> [Item | Rest];
        {_, [Old | Rest]} -> [Old | set(Index - 1, Rest, Item)]
    end.

zero(list, {xls_type, xls_lists, list, [Subtype, Count]}) ->
    new(Subtype, Count).

%% TODO: bake new into record construction?

transpile(list, [{phantom, type, Subtype}, {static, integer, Count}], State) ->
    xls_parse:reference(State, {phantom, type, list(Subtype, Count)});
transpile(nth, [Index, List], _State) ->
    [List, "[", Index, " - u32:1]"];
transpile(set, [Index, List, Value], _State) ->
    ["update(", List, ", ", Index, " - u32:1, ", Value, ")"];
transpile(new, [Subtype, Count], State) ->
    NewState = transpile(list, [Subtype, Count], State),
    transpile(zero, [xls_parse:reference(NewState)], NewState);
transpile(zero, [{phantom, type, {xls_type, xls_lists, list, [Subtype, Count]}}], _State) ->
    %% NOTE: Here we enforce that the arguments to `new/2` are static.
    ["zero!<", print_type(list, [Subtype, Count]), ">()"];
transpile(sublist, [Descriptor, List, Start, Count], State1) ->
    % io:format("transpile @ ~p~n", [[sublist, [Descriptor, List, Start, Count], State1]]),
    {phantom, type, Type = {xls_type, xls_lists, list, [Subtype, _BigCount]}} = Descriptor,
    SmallSize = xls_type:width(Subtype),
    BigSize = xls_type:width(Type),

    State2 = xls_parse:instr(State1, [List, " as bits[", integer_to_list(BigSize), "]"]),
    State3 = xls_parse:instr(State2, [xls_parse:reference(State2), " >> ((", Start, " - u32:1) * ", integer_to_list(SmallSize), ")"]),
    State4 = xls_parse:instr(State3, [xls_parse:reference(State3), " & (all_ones!<bits[", integer_to_list(BigSize), "]>() << (", Count, " * ", integer_to_list(SmallSize), "))"]),
    xls_parse:instr(State4, [xls_parse:reference(State4), " as ", xls_type:print_type(Type)]);
transpile(array_slice, [{phantom, type, OldDescriptor}, List, {static, integer, Start}, {static, integer, Length}], _State) ->
    {xls_type, xls_lists, list, [Subtype, _OldLength]} = OldDescriptor,
    NewDescriptor = list(Subtype, Length),
    ["array_slice(", List, ", ", integer_to_list(Start - 1), ", zero!<", xls_type:print_type(NewDescriptor), ">() )"].

pack(List, list, [ElementType, _Length]) ->
    << (xls_type:pack(Element, ElementType)) || Element <- List >>.

unpack(Packed, list, [ElementType, Length]) ->
    {Rest, Backwards} = lists:foldl(
        fun(_Index, {AccIn, AccOut}) ->
            {Element, Rest} = xls_type:unpack(AccIn, ElementType),
            {Rest, [Element | AccOut]}
        end,
        {Packed, []}, lists:seq(1, Length)
    ),
    {lists:reverse(Backwards), Rest}.

print_type(list, [Subtype, Count]) ->
    [xls_type:print_type(Subtype), "[", integer_to_list(Count), "]"].

width(list, [Subtype, Count]) ->
    xls_type:width(Subtype) * Count.
