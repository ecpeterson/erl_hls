%%%% xls_var_scope
%%%%
%%%% Mark branch expressions with the names their continuation can use.
%%%% This is a conservative use analysis: later matches count as uses too.
%%%% Definite binding is checked while lowering each arm. Unused arm-local
%%%% names need no joined value and may have different types in different arms.

-module(xls_var_scope).
-moduledoc false.
-export([annotate/1]).

-spec annotate([erl_parse:abstract_expression()]) -> [tuple()].
annotate(Expressions) -> sequence(Expressions, #{}).

sequence(Expressions, Live) ->
    {Rewritten, _} = lists:mapfoldr(fun(Expression, After) ->
        {expression(Expression, After), maps:merge(After, names(Expression))}
    end, Live, Expressions),
    Rewritten.

expression({'case', Line, Subject, Clauses}, Live) ->
    {xls_live, Line, Live, {'case', Line,
        expression(Subject, maps:merge(Live, names(Clauses))),
        [clause(Clause, Live) || Clause <- Clauses]}};
expression({'if', Line, Clauses}, Live) ->
    {xls_live, Line, Live, {'if', Line, [clause(Clause, Live) || Clause <- Clauses]}};
expression({op, Line, Op, Left, Right}, Live) when Op =:= 'andalso'; Op =:= 'orelse' ->
    {xls_live, Line, Live, {op, Line, Op,
        expression(Left, maps:merge(Live, names(Right))), expression(Right, Live)}};
expression({match, Line, Pattern, Value}, Live) ->
    {match, Line, Pattern, expression(Value, maps:merge(Live, names(Pattern)))};
expression(Tuple, Live) when is_tuple(Tuple) ->
    list_to_tuple(sequence(tuple_to_list(Tuple), Live));
expression(List, Live) when is_list(List) -> sequence(List, Live);
expression(Value, _Live) -> Value.

clause({clause, Line, Patterns, Guards, Body}, Live) ->
    {clause, Line, Patterns, Guards, sequence(Body, Live)}.

names({var, _, '_'}) -> #{};
names({var, _, Name}) -> #{Name => true};
names(Tuple) when is_tuple(Tuple) -> names(tuple_to_list(Tuple));
names(List) when is_list(List) ->
    lists:foldl(fun(Item, Acc) -> maps:merge(Acc, names(Item)) end, #{}, List);
names(_) -> #{}.
