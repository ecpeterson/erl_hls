-module(hls_atom_types).
-moduledoc """
Resolves finite source atom unions to hls_enum descriptors for hls_records and
XLS helper preparation. Resolution follows only concrete, zero-argument local
aliases; it does not load providers or interpret general Erlang types. Source
member order is retained as the codec order, including through nested unions.
""".
%% Source type resolution used by records and concrete helper signatures.
-export([resolve/2, descriptor/2]).

-doc "Replaces a finite atom union or local alias with a self-contained descriptor annotation; leaves other types unchanged.".
-spec resolve(erl_parse:abstract_type(), [hls_source:form()]) -> term().
resolve(Type, Forms) ->
    case descriptor(Type, Forms) of
        {ok, Descriptor} -> {hls_enum_type, element(2, Type), Descriptor};
        none -> Type
    end.

-doc "Returns the codec descriptor for a finite atom union, or none for unsupported/non-enum types.".
-spec descriptor(term(), [hls_source:form()]) -> {ok, hls_type:descriptor()} | none.
descriptor({hls_enum_type, _, Descriptor}, _Forms) ->
    {ok, Descriptor};
descriptor({atom, _, Boolean}, _Forms) when Boolean =:= true; Boolean =:= false -> none;
descriptor(Type, Forms) ->
    case members(Type, Forms, []) of
        {ok, Members} ->
            case lists:any(fun(A) -> A =:= true orelse A =:= false end, Members) of
                true -> error({unsupported_hls_boolean_union, Type});
                false -> {ok, hls_enum:enum(unique(Members))}
            end;
        none ->
            none
    end.

%% A union has set semantics, but its first source occurrence fixes each code.
-spec unique([atom()]) -> [atom()].
unique(Atoms) ->
    lists:reverse(
        lists:foldl(
            fun(A, Acc) ->
                case lists:member(A, Acc) of
                    true -> Acc;
                    false -> [A | Acc]
                end
            end,
            [],
            Atoms
        )
    ).

%% General parameterized and remote aliases remain outside this concrete slice.
-spec members(term(), [hls_source:form()], [atom()]) -> {ok, [atom()]} | none.
members({ann_type, _, [_, Type]}, Forms, Stack) ->
    members(Type, Forms, Stack);
members({atom, _, Atom}, _Forms, _Stack) ->
    {ok, [Atom]};
members({type, _, union, Types}, Forms, Stack) ->
    Parts = [members(Type, Forms, Stack) || Type <- Types],
    case lists:member(none, Parts) of
        true -> none;
        false -> {ok, lists:append([Atoms || {ok, Atoms} <- Parts])}
    end;
members({user_type, _, Name, []}, Forms, Stack) ->
    case lists:member(Name, Stack) of
        true ->
            error({recursive_hls_atom_type, lists:reverse([Name | Stack])});
        false ->
            case [Body || {attribute, _, type, {N, Body, []}} <- Forms, N =:= Name] of
                [Body] -> members(Body, Forms, [Name | Stack]);
                _ -> none
            end
    end;
members(_, _Forms, _Stack) ->
    none.
