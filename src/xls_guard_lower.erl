%%%% xls_guard_lower
%%%%
%%%% Shared lowering for the side-effect-free Erlang guard subset accepted in
%%%% callback clause heads and `if` expressions.

-module(xls_guard_lower).
-moduledoc false.

-export([predicate/2]).

-spec predicate([[erl_parse:abstract_expression()]], erl_anno:location()) ->
    erl_parse:abstract_expression().
predicate([Expressions], _Line) when Expressions =/= [] ->
    ok = lists:foreach(
        fun(Expression) ->
            validate_predicate(Expression)
        end,
        Expressions
    ),
    rewrite_short_circuit(sequence(Expressions));
predicate(Guards, Line) ->
    error({unsupported_xls_guard_sequences, Line, Guards}).

validate_predicate({atom, _Line, Atom})
        when Atom =:= true; Atom =:= false ->
    ok;
validate_predicate({op, _Line, 'not', Operand}) ->
    validate_predicate(Operand);
validate_predicate({op, _Line, Operator, Left, Right})
        when Operator =:= 'andalso'; Operator =:= 'orelse' ->
    ok = validate_predicate(Left),
    validate_predicate(Right);
validate_predicate({op, Line, Operator, Left, Right}) ->
    case lists:member(Operator, comparison_operators()) of
        true ->
            ok = validate_value(Left),
            validate_value(Right);
        false ->
            unsupported_guard(Line, {non_boolean_predicate, Operator})
    end;
validate_predicate(Expression) ->
    unsupported_guard(expression_line(Expression), non_boolean_predicate).

validate_value({var, _Line, _Name}) ->
    ok;
validate_value({integer, _Line, _Integer}) ->
    ok;
validate_value({atom, _Line, Atom})
        when Atom =:= true; Atom =:= false ->
    ok;
validate_value({record_field, _Line, Object, _Record, _Field}) ->
    validate_value(Object);
validate_value({op, _Line, 'not', Operand}) ->
    validate_predicate(Operand);
validate_value({op, _Line, 'bnot', Operand}) ->
    validate_value(Operand);
validate_value({op, _Line, Operator, Left, Right})
        when Operator =:= 'andalso'; Operator =:= 'orelse' ->
    ok = validate_predicate(Left),
    validate_predicate(Right);
validate_value({op, Line, Operator, Left, Right}) ->
    case lists:member(Operator, comparison_operators()) orelse
            lists:member(Operator, arithmetic_operators()) of
        true ->
            ok = validate_value(Left),
            validate_value(Right);
        false ->
            unsupported_guard(Line, {unsupported_operator, Operator})
    end;
validate_value(Expression) ->
    unsupported_guard(expression_line(Expression), unsupported_expression).

sequence([Expression]) ->
    Expression;
sequence([Expression | Rest]) ->
    {op, expression_line(Expression), 'andalso',
        Expression, sequence(Rest)}.

rewrite_short_circuit({op, Line, 'andalso', Left, Right}) ->
    {'case', Line, rewrite_short_circuit(Left), [
        {clause, Line, [{atom, Line, true}], [], [
            rewrite_short_circuit(Right)
        ]},
        {clause, Line, [{atom, Line, false}], [], [
            {atom, Line, false}
        ]}
    ]};
rewrite_short_circuit({op, Line, 'orelse', Left, Right}) ->
    {'case', Line, rewrite_short_circuit(Left), [
        {clause, Line, [{atom, Line, true}], [], [
            {atom, Line, true}
        ]},
        {clause, Line, [{atom, Line, false}], [], [
            rewrite_short_circuit(Right)
        ]}
    ]};
rewrite_short_circuit(Tuple) when is_tuple(Tuple) ->
    list_to_tuple([
        rewrite_short_circuit(Element) || Element <- tuple_to_list(Tuple)
    ]);
rewrite_short_circuit(List) when is_list(List) ->
    [rewrite_short_circuit(Element) || Element <- List];
rewrite_short_circuit(Term) ->
    Term.

unsupported_guard(Line, Reason) ->
    error({unsupported_xls_guard, Line, Reason}).

expression_line(Expression)
        when is_tuple(Expression), tuple_size(Expression) >= 2 ->
    element(2, Expression);
expression_line(_Expression) ->
    undefined.

comparison_operators() ->
    ['<', '=<', '>', '>=', '=:=', '=/='].

arithmetic_operators() ->
    ['+', '-', '*', 'band', 'bor', 'bxor', 'bsl', 'bsr'].
