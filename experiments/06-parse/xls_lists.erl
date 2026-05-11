-module(xls_lists).
-export([]).
-compile(export_all).
-behavior(xls_type).

% TODO: export translation logic

new([Descriptor, Count]) ->
    [xls_types:new(Descriptor) || _ <- lists:seq(1, Count)].

sublist(List, Start, Count) ->
    lists:sublist(List, Start, Count).

nth(Index, List) ->
    lists:nth(Index, List).

set(Index, List, Value) ->
    case {Index, List} of
        {1, [_Old | Rest]} -> [Value | Rest];
        {_, [Old | Rest]} -> [Old | set(Index - 1, Rest, Value)]
    end.

transpile(nth, [Index, List]) ->
    [List, "[", Index, " - u32:1]"];
transpile(set, [Index, List, Value]) ->
    ["update(", List, ", ", Index, " - u32:1, ", Value, ")"];
transpile(new, [[Subtype, Count]]) ->
    ["zero!<", atom_to_list(Subtype), "[", integer_to_list(Count), "]>()"].

type(list, [ElementType, Count]) ->
    % TODO: this should recurse
    [atom_to_list(ElementType), "[", integer_to_list(Count), "]"].
