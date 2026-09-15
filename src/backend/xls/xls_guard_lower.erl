%%%% xls_guard_lower
%%%%
%%%% Shared lowering for the side-effect-free Erlang guard subset accepted in
%%%% callback clause heads, `case` clauses, and `if` expressions.

-module(xls_guard_lower).
-moduledoc false.

-export([condition/3, predicate/2]).

-spec condition(
    [[erl_parse:abstract_expression()]],
    [xls_parse:printable()],
    erl_anno:location()
) -> term().
condition([], Conditions, _Line) ->
    conjunction(Conditions);
condition(Guards, [], Line) ->
    predicate(Guards, Line);
condition(Guards, Conditions, Line) ->
    {op, Line, 'andalso', conjunction(Conditions), predicate(Guards, Line)}.

-spec predicate([[erl_parse:abstract_expression()]], erl_anno:location()) ->
    term().
predicate(Guards = [_ | _], Line) ->
    alternatives([guard_sequence(Expressions, Line) || Expressions <- Guards]);
predicate(Guards, Line) ->
    error({unsupported_xls_guard_sequences, Line, Guards}).

guard_sequence(Expressions = [_ | _], Line) ->
    ok = lists:foreach(fun validate_predicate/1, Expressions),
    Predicate = sequence(Expressions),
    case can_fail(Predicate) of
        true -> {xls_guard, Line, Predicate};
        false -> Predicate
    end;
guard_sequence(Expressions, Line) ->
    error({unsupported_xls_guard_sequences, Line, Expressions}).

%% All other accepted guard operations are total on their XLS operand types.
%% Keep their existing compact output, without an unnecessary failure carrier.
can_fail({op, _, Op, _, _}) when Op =:= 'div'; Op =:= 'rem' -> true;
can_fail(Tuple) when is_tuple(Tuple) -> lists:any(fun can_fail/1, tuple_to_list(Tuple));
can_fail(_) -> false.

alternatives([Only]) -> Only;
alternatives([First | Rest]) ->
    {op, expression_line(First), 'orelse', First, alternatives(Rest)}.

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
validate_value({op, _Line, Sign, {integer, _, _}}) when Sign =:= '-'; Sign =:= '+' ->
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

conjunction([]) ->
    "bool:true";
conjunction([Only]) ->
    Only;
conjunction(Expressions) ->
    ["(", join_with(" && ", Expressions), ")"].

join_with(_Separator, []) ->
    [];
join_with(Separator, [First | Rest]) ->
    [First | [[Separator, Item] || Item <- Rest]].

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
    ['+', '-', '*', 'div', 'rem', 'band', 'bor', 'bxor', 'bsl', 'bsr'].
