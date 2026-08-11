-module(xls_lists).
-export([list/2]).
-export_type([list/2]).
-export([new/2, sublist/3, nth/2, set/3]).
-export([zero/2, transpile/2, pack/2, unpack/2, width/2, print_type/2]).
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

-doc "Erlang value constructor.  (XLS value constructor is transpile/2 branch on this instr.)".
new(Subtype, Count) ->
    [xls_type:zero(Subtype) || _ <- lists:seq(1, Count)].

-doc "Extracts the sublist [Start, Start + Count).".
sublist(List, Start, Count) ->
    lists:sublist(List, Start, Count)
    %% pad right by zero?
    .

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

transpile(list, [Subtype, Count]) ->
    {phantom, type, list(Subtype, Count)};
transpile(nth, [Index, List]) ->
    [List, "[", Index, " - u32:1]"];
transpile(set, [Index, List, Value]) ->
    ["update(", List, ", ", Index, " - u32:1, ", Value, ")"];
transpile(new, [Subtype, Count]) ->
    transpile(zero, [transpile(list, [Subtype, Count])]);
transpile(zero, [{phantom, type, {xls_type, xls_lists, list, [Subtype, Count]}}]) ->
    %% NOTE: Here we enforce that the arguments to `new/2` are static.
    ["zero!<", print_type(list, [Subtype, Count]), ">()"].

pack(List, {remote_type, _1, [_xls_lists, _list, [ElementType, _Length]]}) ->
    << (xls_type:pack(Element, ElementType)) || Element <- List >>.

unpack(Packed, {remote_type, _1, [_xls_lists, _list, [ElementType, {integer, _4, Length}]]}) ->
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
