-module(xls_pattern_totality).
-moduledoc false.

-export([prove/2, assertions/2]).

%% A successful proof returns precisely the array dimensions it used. These
%% are rechecked against actual DSLX types; source aliases alone cannot grant
%% authority to intercept a whole message schema at a reduction source.
-spec prove(erl_parse:af_pattern(), xls_type_shape:shape()) -> none | [tuple()].
prove(Pattern, Shape) ->
    case prove(Pattern, Shape, [], #{}, []) of
        none -> none;
        {_Bound, Checks} -> lists:usort(Checks)
    end.

prove({var, _, '_'}, _Shape, _Path, Bound, Checks) -> {Bound, Checks};
prove({var, _, Name}, _Shape, _Path, Bound, Checks) ->
    case maps:is_key(Name, Bound) of
        true -> none;
        false -> {Bound#{Name => true}, Checks}
    end;
prove({match, _, Left, Right}, Shape, Path, Bound, Checks) ->
    then(prove(Left, Shape, Path, Bound, Checks), fun(B, C) ->
        prove(Right, Shape, Path, B, C)
    end);
prove({record, _, Name, Fields}, {record, Name, Shapes}, Path, Bound, Checks) ->
    lists:foldl(fun
        ({record_field, _, {atom, _, Field}, Pattern}, Acc) ->
            then(Acc, fun(B, C) ->
                prove(Pattern, maps:get(Field, Shapes, unknown),
                    Path ++ [{field, Field}], B, C)
            end);
        (_, _Acc) -> none
    end, {Bound, Checks}, Fields);
prove(Pattern = {cons, _, _, _}, {array, Element, Count}, Path, Bound, Checks) ->
    list(Pattern, Element, Count, 0, Path, Bound, [{Path, Count} | Checks]);
prove({nil, _}, {array, _, 0}, Path, Bound, Checks) ->
    {Bound, [{Path, 0} | Checks]};
prove(_Pattern, _Shape, _Path, _Bound, _Checks) -> none.

list({cons, _, Head, Tail}, Element, Count, Offset, Path, Bound, Checks)
        when Offset < Count ->
    then(prove(Head, Element, Path ++ [{index, Offset}], Bound, Checks), fun(B, C) ->
        list(Tail, Element, Count, Offset + 1, Path, B, C)
    end);
list({nil, _}, _Element, Count, Count, _Path, Bound, Checks) -> {Bound, Checks};
list({var, _, '_'}, _Element, _Count, _Offset, _Path, Bound, Checks) -> {Bound, Checks};
list(Pattern = {var, _, _}, Element, Count, Offset, Path, Bound, Checks)
        when Offset < Count ->
    %% A bound tail must be nonempty in the current DSLX representation.
    prove(Pattern, {array, Element, Count - Offset}, Path, Bound, Checks);
list({match, _, Left, Right}, Element, Count, Offset, Path, Bound, Checks) ->
    then(list(Left, Element, Count, Offset, Path, Bound, Checks), fun(B, C) ->
        list(Right, Element, Count, Offset, Path, B, C)
    end);
list(_Pattern, _Element, _Count, _Offset, _Path, _Bound, _Checks) -> none.

then(none, _Continue) -> none;
then({Bound, Checks}, Continue) -> Continue(Bound, Checks).

-spec assertions(string(), [tuple()]) -> iolist().
assertions(Type, Checks) ->
    [["const_assert!(array_size((zero!<", Type,
        ">())", [projection(Step) || Step <- Path], ") == u32:",
        integer_to_list(Count), ");\n"] || {Path, Count} <- Checks].

projection({field, Field}) -> [".", atom_to_list(Field)];
projection({index, Index}) -> ["[u32:", integer_to_list(Index), "]"].
