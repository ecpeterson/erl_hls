%%%% Source-only logical shapes used to prove bounded patterns total.
-module(xls_type_shape).
-moduledoc false.

-export([records/2]).
-export_type([shape/0]).

-type shape() :: unknown | {array, shape(), non_neg_integer()} |
    {record, atom(), #{atom() => shape()}}.

%% Deliberately independent of loaded modules and provider callbacks. Aliases
%% are source declarations, not proof of a provider's emitted hardware type;
%% consumers must retain and check the dimensions on which they rely in DSLX.
-spec records([erl_parse:abstract_form()], [atom()]) -> #{atom() => shape()}.
records(Forms, Names) ->
    Context = case xls_parse:find_optional_attribute(Forms, hls_source_context) of
        {ok, Captured} -> Captured;
        none -> hls_source:from_forms(Forms, [])
    end,
    Source = source(Forms, Context),
    {Records, _Cache} = lists:mapfoldl(fun(Name, Cache) ->
        {attribute, _, record, {Name, Fields}} = xls_parse:find_record(Forms, Name),
        {Shapes, Next} = lists:mapfoldl(fun({typed_record_field, Field, Type}, Acc) ->
            {Shape, Updated} = resolve(Type, #{}, Source, Acc, []),
            {{xls_parse:record_field_name(Field), shape(Shape)}, Updated}
        end, Cache, Fields),
        {{Name, {record, Name, maps:from_list(Shapes)}}, Next}
    end, #{}, lists:usort(Names)),
    maps:from_list(Records).

source(Forms, Context) ->
    #{directory := Directory, source_name := Filename} = Context,
    #{forms => Forms, context => Context,
        path => filename:absname(Filename, Directory)}.

resolve({var, _, Name}, Parameters, _Source, Cache, _Stack) ->
    {maps:get(Name, Parameters, unknown), Cache};
resolve({integer, _, Value}, _Parameters, _Source, Cache, _Stack) ->
    {Value, Cache};
resolve({remote_type, _, [{atom, _, Module}, {atom, _, Name}, Args]},
        Parameters, Source, Cache0, Stack) ->
    {Values, Cache1} = arguments(Args, Parameters, Source, Cache0, Stack),
    case {Module, Name, Values} of
        {hls_lists, list, [Element, Count]} when is_integer(Count), Count >= 0 ->
            {{array, shape(Element), Count}, Cache1};
        {hls_vec, vector, [Element, Count]} when is_integer(Count), Count > 0 ->
            {{array, shape(Element), Count}, Cache1};
        {Builtin, _, _} when Builtin =:= hls_lists; Builtin =:= hls_vec;
                Builtin =:= hls_nums; Builtin =:= hls_fixed ->
            {unknown, Cache1};
        _ ->
            case provider(Module, Source, Cache1) of
                {unknown, Cache2} -> {unknown, Cache2};
                {Provider, Cache2} -> alias(Name, Values, Provider, Cache2, Stack)
            end
    end;
resolve({user_type, _, Name, Args}, Parameters, Source, Cache0, Stack) ->
    {Values, Cache1} = arguments(Args, Parameters, Source, Cache0, Stack),
    alias(Name, Values, Source, Cache1, Stack);
resolve(_Type, _Parameters, _Source, Cache, _Stack) ->
    {unknown, Cache}.

arguments(Args, Parameters, Source, Cache, Stack) ->
    lists:mapfoldl(fun(Arg, Acc) ->
        resolve(Arg, Parameters, Source, Acc, Stack)
    end, Cache, Args).

alias(Name, Args, Source = #{path := Path, forms := Forms}, Cache, Stack) ->
    Key = {Path, Name, length(Args)},
    %% The key excludes arguments: expanding recursive aliases with growing
    %% arguments must terminate too. Recursive shapes remain conservative.
    case lists:member(Key, Stack) of
        true -> {unknown, Cache};
        false ->
            case [{Body, Vars} || {attribute, _, type, {N, Body, Vars}} <- Forms,
                    N =:= Name, length(Vars) =:= length(Args)] of
                [{Body, Vars}] ->
                    Parameters = maps:from_list(lists:zip(
                        [Variable || {var, _, Variable} <- Vars], Args)),
                    resolve(Body, Parameters, Source, Cache, [Key | Stack]);
                _ -> {unknown, Cache}
            end
    end.

provider(Module, #{path := Path, context := Context}, Cache) ->
    #{directory := Directory, includes := Includes} = Context,
    %% Source-relative discovery has the same answer in a clean tree and with
    %% old BEAMs on the code path. Explicit include directories can also make
    %% shared type sources visible. No recursive project scan or global cache.
    Candidates = [filename:join(Dir, atom_to_list(Module) ++ ".erl")
        || Dir <- [filename:dirname(Path) |
            [filename:absname(Include, Directory) || Include <- Includes]]],
    case lists:search(fun filelib:is_regular/1, Candidates) of
        false -> {unknown, Cache};
        {value, Filename} ->
            case maps:find(Filename, Cache) of
                {ok, Provider} -> {Provider, Cache};
                error ->
                    ProviderContext = (maps:remove(origins, Context))#{source_name := Filename},
                    Forms = hls_source:read(Filename, ProviderContext),
                    %% A file with another module name is not this alias.
                    Provider = case xls_parse:find_optional_attribute(Forms, module) of
                        {ok, Module} -> source(Forms, ProviderContext);
                        _ -> unknown
                    end,
                    {Provider, Cache#{Filename => Provider}}
            end
    end.

shape({array, _, _} = Shape) -> Shape;
shape(_) -> unknown.
