%%%% xls_callback_lower
%%%%
%%%% Lowers source-ordered Erlang callback clauses into one nested XLS
%%%% selection expression. Actor-specific lowerers perform the outer dispatch
%%%% by message tag (and phase); this module handles complete heads, guards,
%%%% and the distinction between clause fallthrough and a selected-body error.

-module(xls_callback_lower).
-moduledoc false.

-include("xls_parse.hrl").

-export([
    group_by/2,
    lower/7,
    record_argument/3,
    record_pattern_name/1,
    value_argument/1
]).

%% `raw` is the struct or primitive used for field access and comparisons.
%% `value` is the tagged representation expected by the existing expression
%% lowerer when a whole callback argument is bound to an Erlang variable.
-type argument() :: #{
    raw := xls_parse:printable(),
    value := xls_parse:printable(),
    record => atom()
}.
-spec record_argument(atom(), xls_parse:printable(),
    xls_parse:printable()) -> argument().
record_argument(Name, Raw, Value) ->
    #{record => Name, raw => Raw, value => Value}.

-spec value_argument(xls_parse:printable()) -> argument().
value_argument(Value) ->
    #{raw => Value, value => Value}.

-spec group_by([term()], fun((term()) -> term())) ->
    [{term(), [term(), ...]}].
group_by(Items, KeyFun) ->
    lists:foldl(
        fun(Item, Groups) ->
            add_to_group(KeyFun(Item), Item, Groups)
        end,
        [],
        Items
    ).

-spec lower(
    [erl_parse:af_clause(), ...],
    [argument()],
    atom(),
    fun((xls_parse:printable()) -> xls_parse:printable()),
    xls_parse:printable(),
    xls_parse:printable(),
    #{atom() => xls_parse:printable()}
) -> {xls_parse:printable(), xls_parse:printable()}.
lower(Clauses0, Arguments, StateName, Postprocessor,
        NoClauseFailure, BodyFailure, EnumAtoms) ->
    Clauses = [
        rename_clause_variables(Clause, Index)
        || {Index, Clause} <- lists:enumerate(1, Clauses0)
    ],
    lower_chain(
        Clauses,
        Arguments,
        StateName,
        Postprocessor,
        NoClauseFailure,
        BodyFailure,
        EnumAtoms
    ).

-spec record_pattern_name(erl_parse:af_pattern()) -> atom().
record_pattern_name({record, _Line, Name, _Fields}) ->
    Name;
record_pattern_name({match, _Line, {var, _VarLine, _Name}, Pattern}) ->
    record_pattern_name(Pattern);
record_pattern_name({match, _Line, Pattern, {var, _VarLine, _Name}}) ->
    record_pattern_name(Pattern);
record_pattern_name(Pattern) ->
    error({unsupported_xls_callback_record_pattern, Pattern}).

%%%
%%% Ordered selection
%%%

lower_chain([], _Arguments, _StateName, _Postprocessor,
        NoClauseFailure, _BodyFailure, _EnumAtoms) ->
    {[], NoClauseFailure};
lower_chain(
    [{clause, Line, Patterns, Guards, Body} | Rest],
    Arguments,
    StateName,
    Postprocessor,
    NoClauseFailure,
    BodyFailure,
    EnumAtoms
) ->
    Initial = #clause_state{
        state_name = StateName,
        enum_atoms = EnumAtoms
    },
    Context0 = #{state => Initial, bindings => #{}, conditions => []},
    Context1 = compile_patterns(Patterns, Arguments, Context0, Line),
    Conditions = lists:reverse(maps:get(conditions, Context1)),
    {GuardState, GuardReference} = lower_guard(
        Guards,
        maps:get(state, Context1),
        Conditions,
        Line
    ),
    HeadBody = lists:reverse(GuardState#clause_state.statements),

    BodyBase = GuardState#clause_state{statements = [], reference = none},
    BodyState = lower_expressions(Body, BodyBase),
    BodyMismatch = xls_parse:mismatch_expression(
        BodyState#clause_state.named_counters,
        GuardState#clause_state.named_counters
    ),
    Selected = [
        lists:reverse(BodyState#clause_state.statements),
        "if (", BodyMismatch, ") {\n",
        xls_parse_io:indent(xls_parse:print(BodyFailure), 2),
        "} else {\n",
        xls_parse_io:indent(xls_parse:print(
            Postprocessor(BodyState#clause_state.reference)
        ), 2),
        "}"
    ],
    {NextBody, NextResult} = lower_chain(
        Rest,
        Arguments,
        StateName,
        Postprocessor,
        NoClauseFailure,
        BodyFailure,
        EnumAtoms
    ),
    Result = [
        "if ", GuardReference, " {\n",
        xls_parse_io:indent(xls_parse:print(Selected), 2),
        "} else {\n",
        xls_parse_io:indent(xls_parse:print([NextBody, NextResult]), 2),
        "}"
    ],
    {HeadBody, Result}.

%%%
%%% Clause heads
%%%

compile_patterns(Patterns, Arguments, Context, _Line)
        when length(Patterns) =:= length(Arguments) ->
    lists:foldl(
        fun({Pattern, Argument}, Acc) ->
            compile_pattern(Pattern, Argument, Acc)
        end,
        Context,
        lists:zip(Patterns, Arguments)
    );
compile_patterns(Patterns, Arguments, _Context, Line) ->
    error({bad_xls_callback_arity, Line, length(Patterns), length(Arguments)}).

compile_pattern({var, _Line, '_'}, _Subject, Context) ->
    Context;
compile_pattern({var, _Line, Name}, Subject, Context) ->
    bind_or_compare(Name, maps:get(value, Subject), Context);
compile_pattern({match, _Line, Left, Right}, Subject, Context0) ->
    Context1 = compile_pattern(Left, Subject, Context0),
    compile_pattern(Right, Subject, Context1);
compile_pattern({record, Line, Name, Fields}, Subject, Context0) ->
    case Subject of
        #{record := Name} ->
            lists:foldl(
                fun({record_field, _FieldLine,
                        {atom, _AtomLine, Field}, Pattern}, Context) ->
                    Raw = [maps:get(raw, Subject), ".", atom_to_list(Field)],
                    compile_pattern(
                        Pattern,
                        #{raw => Raw, value => Raw},
                        Context
                    );
                   (Field, _Context) ->
                    error({unsupported_xls_callback_record_field, Line, Field})
                end,
                Context0,
                Fields
            );
        #{record := Actual} ->
            error({xls_callback_record_type_mismatch, Line, Name, Actual});
        _ ->
            error({unsupported_nested_xls_record_pattern, Line, Name})
    end;
compile_pattern({tuple, _Line, Patterns}, Subject, Context0) ->
    lists:foldl(
        fun({Index, Pattern}, Context) ->
            Raw = [maps:get(raw, Subject), ".", integer_to_list(Index)],
            compile_pattern(Pattern, #{raw => Raw, value => Raw}, Context)
        end,
        Context0,
        lists:enumerate(0, Patterns)
    );
compile_pattern({integer, _Line, Integer}, Subject, Context) ->
    add_condition(
        [maps:get(raw, Subject), " == ", integer_to_list(Integer)],
        Context
    );
compile_pattern({atom, _Line, true}, Subject, Context) ->
    add_condition([maps:get(raw, Subject), " == bool:true"], Context);
compile_pattern({atom, _Line, false}, Subject, Context) ->
    add_condition([maps:get(raw, Subject), " == bool:false"], Context);
compile_pattern(Pattern, _Subject, _Context) ->
    error({unsupported_xls_callback_pattern, Pattern}).

bind_or_compare(Name, Value, Context = #{bindings := Bindings}) ->
    case maps:find(Name, Bindings) of
        {ok, Bound} ->
            add_condition([Bound, " == ", Value], Context);
        error ->
            State0 = maps:get(state, Context),
            {EmittedName, State1} = xls_parse:uniquify(State0, Name),
            State2 = xls_parse:instr(State1, EmittedName, Value),
            Context#{
                state := State2,
                bindings := Bindings#{Name => EmittedName}
            }
    end.

add_condition(Condition, Context = #{conditions := Conditions}) ->
    Context#{conditions := [Condition | Conditions]}.

%%%
%%% Guards
%%%

lower_guard([], State, Conditions, _Line) ->
    {State, conjunction(Conditions)};
lower_guard([Expressions], State0, Conditions, Line)
        when Expressions =/= [] ->
    ok = lists:foreach(
        fun(Expression) ->
            validate_guard_predicate(Expression)
        end,
        Expressions
    ),
    Predicate = rewrite_short_circuit(guard_sequence(Expressions)),
    Guard = case Conditions of
        [] -> Predicate;
        _ -> lazy_conjunction(Line, conjunction(Conditions), Predicate)
    end,
    State1 = xls_parse:statement_from_statement(
        Guard,
        State0#clause_state{reference = none}
    ),
    {State1, State1#clause_state.reference};
lower_guard(Guards, _State, _Conditions, Line) ->
    error({unsupported_xls_guard_sequences, Line, Guards}).

validate_guard_predicate({atom, _Line, Atom})
        when Atom =:= true; Atom =:= false ->
    ok;
validate_guard_predicate({op, _Line, 'not', Operand}) ->
    validate_guard_predicate(Operand);
validate_guard_predicate({op, _Line, Operator, Left, Right})
        when Operator =:= 'andalso'; Operator =:= 'orelse' ->
    ok = validate_guard_predicate(Left),
    validate_guard_predicate(Right);
validate_guard_predicate({op, Line, Operator, Left, Right}) ->
    case lists:member(Operator, comparison_operators()) of
        true ->
            ok = validate_guard_value(Left),
            validate_guard_value(Right);
        false ->
            unsupported_guard(Line, {non_boolean_predicate, Operator})
    end;
validate_guard_predicate(Expression) ->
    unsupported_guard(guard_line(Expression), non_boolean_predicate).

validate_guard_value({var, _Line, _Name}) ->
    ok;
validate_guard_value({integer, _Line, _Integer}) ->
    ok;
validate_guard_value({atom, _Line, Atom})
        when Atom =:= true; Atom =:= false ->
    ok;
validate_guard_value({record_field, _Line, Object, _Record, _Field}) ->
    validate_guard_value(Object);
validate_guard_value({op, _Line, 'not', Operand}) ->
    validate_guard_predicate(Operand);
validate_guard_value({op, _Line, 'bnot', Operand}) ->
    validate_guard_value(Operand);
validate_guard_value({op, _Line, Operator, Left, Right})
        when Operator =:= 'andalso'; Operator =:= 'orelse' ->
    ok = validate_guard_predicate(Left),
    validate_guard_predicate(Right);
validate_guard_value({op, Line, Operator, Left, Right}) ->
    case lists:member(Operator, comparison_operators()) orelse
            lists:member(Operator, arithmetic_operators()) of
        true ->
            ok = validate_guard_value(Left),
            validate_guard_value(Right);
        false ->
            unsupported_guard(Line, {unsupported_operator, Operator})
    end;
validate_guard_value(Expression) ->
    unsupported_guard(guard_line(Expression), unsupported_expression).

guard_sequence([Expression]) ->
    Expression;
guard_sequence([Expression | Rest]) ->
    {op, guard_line(Expression), 'andalso',
        Expression, guard_sequence(Rest)}.

lazy_conjunction(Line, Left, Right) ->
    {'case', Line, Left, [
        {clause, Line, [{atom, Line, true}], [], [Right]},
        {clause, Line, [{atom, Line, false}], [], [
            {atom, Line, false}
        ]}
    ]}.

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

guard_line(Expression) when is_tuple(Expression), tuple_size(Expression) >= 2 ->
    element(2, Expression);
guard_line(_Expression) ->
    undefined.

comparison_operators() ->
    ['<', '=<', '>', '>=', '=:=', '=/='].

arithmetic_operators() ->
    ['+', '-', '*', 'band', 'bor', 'bxor', 'bsl', 'bsr'].

%%%
%%% AST and output utilities
%%%

rename_clause_variables(Clause, Index) ->
    rename_variables(Clause, Index).

rename_variables({var, Line, '_'}, _Index) ->
    {var, Line, '_'};
rename_variables({var, Line, Name}, Index) ->
    Prefix = "Xls_clause_" ++ integer_to_list(Index) ++ "_",
    {var, Line, list_to_atom(Prefix ++ atom_to_list(Name))};
rename_variables(Tuple, Index) when is_tuple(Tuple) ->
    list_to_tuple([
        rename_variables(Element, Index) || Element <- tuple_to_list(Tuple)
    ]);
rename_variables(List, Index) when is_list(List) ->
    [rename_variables(Element, Index) || Element <- List];
rename_variables(Term, _Index) ->
    Term.

add_to_group(Key, Item, []) ->
    [{Key, [Item]}];
add_to_group(Key, Item, [{Key, Items} | Rest]) ->
    [{Key, Items ++ [Item]} | Rest];
add_to_group(Key, Item, [Group | Rest]) ->
    [Group | add_to_group(Key, Item, Rest)].

lower_expressions(Expressions, State0) ->
    lists:foldl(
        fun(Expression, State) ->
            xls_parse:statement_from_statement(
                Expression,
                State#clause_state{reference = none}
            )
        end,
        State0,
        Expressions
    ).

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
