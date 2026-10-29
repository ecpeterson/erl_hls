-module(xls_static_integer).
-moduledoc "Evaluates untyped integer constants before literal typing and DSLX width inference. Expression lowerers share the restricted operator evaluator; helper preparation substitutes proven straight-line aliases without removing matches or evaluating providers. Typed values and unsupported scopes remain opaque.".

%% Evaluate the integer-only source subset and already lowered static operands.
-export([eval/1, operation/2]).
%% Normalize source clauses before propagating expected literal types.
-export([clauses/1]).

%% Only successful untyped integer computations establish a constant.
-type result() :: {ok, integer()} | error.
%% Unknown entries retain typed/runtime binding identity across later matches.
-type bindings() :: #{atom() => integer() | unknown}.

-doc "Evaluates integer/character literals and supported integer operators. Variables, calls, typed nodes and invalid arithmetic return error; VM resource exhaustion propagates.".
-spec eval(term()) -> result().
eval({integer, _, Value}) ->
    {ok, Value};
eval({char, _, Value}) ->
    {ok, Value};
eval({op, _, Op, Operand}) ->
    case eval(Operand) of
        {ok, Value} -> operation(Op, [Value]);
        error -> error
    end;
eval({op, _, Op, Left, Right}) ->
    case eval(Left) of
        {ok, A} ->
            case eval(Right) of
                {ok, B} -> operation(Op, [A, B]);
                error -> error
            end;
        error ->
            error
    end;
eval(_) ->
    error.

-doc "Applies only Erlang integer arithmetic, shifts and bitwise operators to integer operands. Unsupported arities/operators and badarith return error; no provider callbacks run.".
-spec operation(atom(), [integer()]) -> result().
operation(Op, [A]) when Op =:= '+'; Op =:= '-'; Op =:= 'bnot' ->
    calculate(Op, [A]);
operation(Op, [A, B]) when
    Op =:= '+';
    Op =:= '-';
    Op =:= '*';
    Op =:= 'div';
    Op =:= 'rem';
    Op =:= 'bsl';
    Op =:= 'bsr';
    Op =:= 'band';
    Op =:= 'bor';
    Op =:= 'bxor'
->
    calculate(Op, [A, B]);
operation(_, _) ->
    error.

%% Invalid arithmetic must reach the ordinary guard/body failure boundary.
-spec calculate(atom(), [integer()]) -> result().
calculate(Op, Values) ->
    try apply(erlang, Op, Values) of
        Integer -> {ok, Integer}
    catch
        error:badarith -> error
    end.

-doc "Folds successful untyped integer expressions and substitutes proven aliases in source order. Preserves patterns, matches, annotations and failing operators. Branches inherit outer constants but export only unknown binding identities; unsupported scopes are left untouched.".
-spec clauses([erl_parse:abstract_clause()]) -> [erl_parse:abstract_clause()].
clauses(Clauses) ->
    [clause(Clause, #{}) || Clause <- Clauses].

%% Guard alternatives read the same outer environment and cannot export bindings.
-spec clause(erl_parse:abstract_clause(), bindings()) -> erl_parse:abstract_clause().
clause(Clause, Bindings) ->
    element(1, clause_bindings(Clause, Bindings)).

%% Retain bound names separately from the constants usable inside this arm.
-spec clause_bindings(erl_parse:abstract_clause(), bindings()) ->
    {erl_parse:abstract_clause(), bindings()}.
clause_bindings({clause, Line, Patterns, Guards, Body}, Outer) ->
    Bindings = pattern_bindings(Patterns, Outer),
    Conditions = [element(1, expressions(Sequence, Bindings)) || Sequence <- Guards],
    {Normalized, After} = expressions(Body, Bindings),
    {{clause, Line, Patterns, Conditions, Normalized}, After}.

%% Evaluate every expression before making its aliases available to the next.
-spec expressions([term()], bindings()) -> {[term()], bindings()}.
expressions(Expressions, Bindings) ->
    lists:mapfoldl(fun expression/2, Bindings, Expressions).

%% Only value positions are traversed. In particular, patterns and closures do
%% not share the substitution rules of an ordinary evaluated expression.
-spec expression(term(), bindings()) -> {term(), bindings()}.
expression({var, Line, Name} = Variable, Bindings) ->
    case maps:find(Name, Bindings) of
        {ok, unknown} -> {Variable, Bindings};
        {ok, Integer} -> {{integer, Line, Integer}, Bindings};
        error -> {Variable, Bindings}
    end;
expression({match, Line, Pattern, Value}, Bindings) ->
    {Normalized, After} = expression(Value, Bindings),
    {{match, Line, Pattern, Normalized}, bind(Pattern, Normalized, After)};
expression({op, Line, Op, Operand}, Bindings) ->
    {Value, After} = expression(Operand, Bindings),
    {fold({op, Line, Op, Value}), After};
expression({op, Line, Op, Left, Right}, Bindings) when Op =:= 'andalso'; Op =:= 'orelse' ->
    {A, AfterLeft} = expression(Left, Bindings),
    {B, AfterRight} = expression(Right, AfterLeft),
    {{op, Line, Op, A, B}, unknown_bindings(AfterRight, AfterLeft)};
expression({op, Line, Op, Left, Right}, Bindings) ->
    {[A, B], After} = expressions([Left, Right], Bindings),
    {fold({op, Line, Op, A, B}), After};
expression({xls_integer_compare, Line, Op, Left, Right}, Bindings) ->
    {[A, B], After} = expressions([Left, Right], Bindings),
    {{xls_integer_compare, Line, Op, A, B}, After};
expression({block, Line, Body}, Bindings) ->
    {Normalized, After} = expressions(Body, Bindings),
    {{block, Line, Normalized}, After};
expression({'case', Line, Subject, Clauses}, Bindings) ->
    {Value, AfterSubject} = expression(Subject, Bindings),
    {Normalized, After} = branches(Clauses, AfterSubject),
    {{'case', Line, Value, Normalized}, After};
expression({'if', Line, Clauses}, Bindings) ->
    {Normalized, After} = branches(Clauses, Bindings),
    {{'if', Line, Normalized}, After};
expression({call, Line, Target, Args}, Bindings) ->
    {Normalized, After} = expressions(Args, Bindings),
    {{call, Line, Target, Normalized}, After};
expression({xls_helper_call, Line, Name, Args}, Bindings) ->
    {Normalized, After} = expressions(Args, Bindings),
    {{xls_helper_call, Line, Name, Normalized}, After};
expression({xls_expected, Line, Type, Value}, Bindings) ->
    {Normalized, After} = expression(Value, Bindings),
    {{xls_expected, Line, Type, Normalized}, After};
expression({xls_bit_size, Line, Name, Value}, Bindings) ->
    {Normalized, After} = expression(Value, Bindings),
    {{xls_bit_size, Line, Name, Normalized}, After};
expression({tuple, Line, Values}, Bindings) ->
    {Normalized, After} = expressions(Values, Bindings),
    {{tuple, Line, Normalized}, After};
expression({cons, Line, Head, Tail}, Bindings) ->
    {[A, B], After} = expressions([Head, Tail], Bindings),
    {{cons, Line, A, B}, After};
expression({record, Line, Name, Fields}, Bindings) ->
    {Normalized, After} = fields(Fields, Bindings),
    {{record, Line, Name, Normalized}, After};
expression({record, Line, Base, Name, Fields}, Bindings) ->
    {Value, AfterBase} = expression(Base, Bindings),
    {Normalized, After} = fields(Fields, AfterBase),
    {{record, Line, Value, Name, Normalized}, After};
expression({record_field, Line, Base, Name, Field}, Bindings) ->
    {Value, After} = expression(Base, Bindings),
    {{record_field, Line, Value, Name, Field}, After};
expression({bin, Line, Elements}, Bindings) ->
    {Normalized, After} = lists:mapfoldl(fun segment/2, Bindings, Elements),
    {{bin, Line, Normalized}, After};
expression(Expression, Bindings) ->
    {Expression, Bindings}.

%% Repeated variables retain their original value and type. Even a successful
%% match against a constant cannot turn a typed binding into an untyped one.
-spec bind(term(), term(), bindings()) -> bindings().
bind({var, _, Name}, Value, Bindings) when Name =/= '_' ->
    case {maps:is_key(Name, Bindings), eval(Value)} of
        {false, {ok, Integer}} -> Bindings#{Name => Integer};
        {false, error} -> Bindings#{Name => unknown};
        {true, _} -> Bindings
    end;
bind(Pattern, _, Bindings) ->
    pattern_bindings(Pattern, Bindings).

%% Fresh pattern variables have a source type or projection that must survive
%% later matches. Existing outer bindings are matches, never shadowed aliases.
-spec pattern_bindings(term(), bindings()) -> bindings().
pattern_bindings({var, _, Name}, Bindings) when Name =/= '_' ->
    case maps:is_key(Name, Bindings) of
        true -> Bindings;
        false -> Bindings#{Name => unknown}
    end;
pattern_bindings(Pattern, Bindings) when is_tuple(Pattern) ->
    pattern_bindings(tuple_to_list(Pattern), Bindings);
pattern_bindings(Patterns, Bindings) when is_list(Patterns) ->
    lists:foldl(fun pattern_bindings/2, Bindings, Patterns);
pattern_bindings(_, Bindings) ->
    Bindings.

%% Arms never share new aliases. Their bound names remain unknown after the
%% join, so a later match cannot promote a typed or unsafe name to a constant.
-spec branches([erl_parse:abstract_clause()], bindings()) ->
    {[erl_parse:abstract_clause()], bindings()}.
branches(Clauses, Bindings) ->
    Results = [clause_bindings(Clause, Bindings) || Clause <- Clauses],
    After = lists:foldl(
        fun({_, BranchBindings}, Acc) -> unknown_bindings(BranchBindings, Acc) end,
        Bindings,
        Results
    ),
    {[Clause || {Clause, _} <- Results], After}.

%% Binding identity crosses conditional execution; new constant knowledge does
%% not. The unchanged source still owns definite-binding and failure checks.
-spec unknown_bindings(bindings(), bindings()) -> bindings().
unknown_bindings(Inner, Outer) ->
    maps:fold(
        fun(Name, _, Acc) ->
            case maps:is_key(Name, Acc) of
                true -> Acc;
                false -> Acc#{Name => unknown}
            end
        end,
        Outer,
        Inner
    ).

%% Retain the operator annotation so source-position provenance remains valid.
-spec fold(tuple()) -> tuple().
fold(Expression) ->
    case eval(Expression) of
        {ok, Integer} -> {integer, element(2, Expression), Integer};
        error -> Expression
    end.

%% Record field names are syntax, while assigned values evaluate in source order.
-spec fields([term()], bindings()) -> {[term()], bindings()}.
fields(Fields, Bindings) ->
    lists:mapfoldl(
        fun({record_field, Line, Name, Value}, Before) ->
            {Normalized, After} = expression(Value, Before),
            {{record_field, Line, Name, Normalized}, After}
        end,
        Bindings,
        Fields
    ).

%% Values and sizes keep their evaluation order; segment type flags are opaque.
-spec segment(term(), bindings()) -> {term(), bindings()}.
segment({bin_element, Line, Value, Size, Types}, Bindings) ->
    {[Normalized, Width], After} = expressions([Value, Size], Bindings),
    {{bin_element, Line, Normalized, Width, Types}, After}.
