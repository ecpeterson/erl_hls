%%%% xls_case_lower
%%%%
%%%% Lowers expression-level Erlang case clauses.  The exact two-arm Boolean
%%%% form keeps its compact renderer; other supported cases become a
%%%% source-ordered chain whose selected arm carries both its value and any
%%%% body badmatch.

-module(xls_case_lower).
-moduledoc false.

-include("xls_parse.hrl").

-export([lower/4]).

-spec lower(
    erl_anno:location(),
    erl_parse:abstract_expression(),
    [erl_parse:af_clause(), ...],
    xls_parse:clause_state()
) -> xls_parse:clause_state().
lower(Line, Condition, Clauses, State) ->
    case boolean_only(Clauses) of
        true -> lower_boolean_case(Condition, Clauses, State);
        false -> lower_ordered_case(Line, Condition, Clauses, State)
    end.

%%%
%%% Exhaustive ordered case
%%%

lower_ordered_case(Line, Condition, Clauses0, State0) ->
    Clauses = [normalize_clause(Clause) || Clause <- Clauses0],
    Shape = case_shape(Clauses),
    ConditionState = xls_parse:statement_from_statement(
        Condition,
        State0#clause_state{reference = none}
    ),
    ok = validate_fallback(Line, Clauses, ConditionState),
    Subject = xls_parse:reference(ConditionState),
    Argument = case Shape of
        {record, Name} ->
            xls_pattern_lower:record_argument(
                Name,
                [Subject, ".1"],
                Subject
            );
        _ ->
            xls_pattern_lower:value_argument(Subject)
    end,
    BranchBase = ConditionState#clause_state{
        statements = [],
        reference = none
    },
    {Head, Result, BranchState} = lower_chain(
        Clauses,
        Argument,
        Subject,
        BranchBase
    ),
    MergedState = ConditionState#clause_state{
        anonymous_counter = BranchState#clause_state.anonymous_counter,
        match_counter = BranchState#clause_state.match_counter,
        reference = none
    },
    finish_case(
        MergedState,
        ["{\n", xls_parse_io:indent(
            xls_parse:print([Head, Result]),
            2
        ), "}"]
    ).

normalize_clause({clause, Line, [Pattern], Guards, Body})
        when Body =/= [] ->
    {Line, Pattern, Guards, Body};
normalize_clause(Clause) ->
    error({unsupported_xls_case_clause, Clause}).

validate_fallback(Line, Clauses, State) ->
    case lists:reverse(Clauses) of
        [{_FallbackLine, Pattern, [], _Body} | Reversed] ->
            case fallback_pattern(Pattern, State) of
                true -> validate_nonfinal_fallbacks(
                    lists:reverse(Reversed),
                    State
                );
                false -> error({missing_xls_case_fallback, Line})
            end;
        [{FallbackLine, Pattern, _Guards, _Body} | _] ->
            case fallback_pattern(Pattern, State) of
                true -> error({guarded_xls_case_fallback, FallbackLine});
                false -> error({missing_xls_case_fallback, Line})
            end;
        [] ->
            error({missing_xls_case_fallback, Line})
    end.

validate_nonfinal_fallbacks([], _State) ->
    ok;
validate_nonfinal_fallbacks([
    {Line, Pattern, [], _Body} | Rest
], State) ->
    case fallback_pattern(Pattern, State) of
        true -> error({nonfinal_xls_case_fallback, Line});
        false -> validate_nonfinal_fallbacks(Rest, State)
    end;
validate_nonfinal_fallbacks([_Clause | Rest], State) ->
    validate_nonfinal_fallbacks(Rest, State).

fallback_pattern({var, _Line, '_'}, _State) ->
    true;
fallback_pattern({var, _Line, Name}, State) ->
    not variable_is_bound(Name, State);
fallback_pattern({match, _Line, Left, Right}, State) ->
    fallback_pattern(Left, State) andalso fallback_pattern(Right, State);
fallback_pattern(_Pattern, _State) ->
    false.

variable_is_bound(Name, #clause_state{named_counters = Counters}) ->
    maps:get(atom_to_list(Name), Counters, 0) > 0.

case_shape(Clauses) ->
    lists:foldl(
        fun({_Line, Pattern, _Guards, _Body}, Shape) ->
            merge_shape(Shape, pattern_shape(Pattern))
        end,
        any,
        Clauses
    ).

pattern_shape({var, _Line, _Name}) ->
    any;
pattern_shape({match, Line, Left, Right}) ->
    merge_shape(pattern_shape(Left), pattern_shape(Right), Line);
pattern_shape({integer, _Line, _Integer}) ->
    scalar;
pattern_shape({atom, _Line, _Atom}) ->
    scalar;
pattern_shape({tuple, _Line, Patterns}) ->
    {tuple, length(Patterns)};
pattern_shape({record, _Line, Name, _Fields}) ->
    {record, Name};
pattern_shape(Pattern) ->
    error({unsupported_xls_case_pattern, Pattern}).

merge_shape(any, Shape) ->
    Shape;
merge_shape(Shape, any) ->
    Shape;
merge_shape(Shape, Shape) ->
    Shape;
merge_shape(Left, Right) ->
    error({incompatible_xls_case_pattern_shapes, Left, Right}).

merge_shape(any, Shape, _Line) ->
    Shape;
merge_shape(Shape, any, _Line) ->
    Shape;
merge_shape(Shape, Shape, _Line) ->
    Shape;
merge_shape(Left, Right, Line) ->
    error({incompatible_xls_case_pattern_shapes, Line, Left, Right}).

lower_chain([
    {Line, Pattern, Guards, Body} | Rest
], Argument, Subject, BranchBase) ->
    {PatternState, PatternConditions0} = xls_pattern_lower:compile(
        [Pattern],
        [Argument],
        BranchBase
    ),
    PatternConditions = record_tag_condition(Pattern, Subject) ++
        PatternConditions0,
    Guard = xls_guard_lower:condition(Guards, PatternConditions, Line),
    GuardState = xls_parse:statement_from_statement(
        Guard,
        PatternState#clause_state{reference = none}
    ),
    Head = lists:reverse(GuardState#clause_state.statements),
    BodyBase = GuardState#clause_state{statements = [], reference = none},
    BodyState = lower_expressions(Body, BodyBase),
    Selected = [
        lists:reverse(BodyState#clause_state.statements),
        "(", xls_parse:reference(BodyState), ", ",
        xls_parse:mismatch_expression(
            BodyState#clause_state.named_counters,
            GuardState#clause_state.named_counters
        ), ")"
    ],
    case Rest of
        [] ->
            {Head, Selected, merge_states(
                BranchBase,
                [GuardState, BodyState]
            )};
        _ ->
            {NextHead, NextResult, NextState} = lower_chain(
                Rest,
                Argument,
                Subject,
                BranchBase
            ),
            Result = [
                "if ", xls_parse:reference(GuardState), " {\n",
                xls_parse_io:indent(xls_parse:print(Selected), 2),
                "} else {\n",
                xls_parse_io:indent(
                    xls_parse:print([NextHead, NextResult]),
                    2
                ),
                "}"
            ],
            {Head, Result, merge_states(
                BranchBase,
                [GuardState, BodyState, NextState]
            )}
    end.

record_tag_condition(Pattern, Subject) ->
    case top_record_name(Pattern) of
        none -> [];
        {ok, Name} -> [[
            Subject,
            ".0 == Tag::",
            string:uppercase(atom_to_list(Name))
        ]]
    end.

top_record_name({record, _Line, Name, _Fields}) ->
    {ok, Name};
top_record_name({match, _Line, {var, _VarLine, _Name}, Pattern}) ->
    top_record_name(Pattern);
top_record_name({match, _Line, Pattern, {var, _VarLine, _Name}}) ->
    top_record_name(Pattern);
top_record_name(_Pattern) ->
    none.

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

merge_states(Base, States) ->
    Base#clause_state{
        anonymous_counter = lists:max([
            State#clause_state.anonymous_counter || State <- [Base | States]
        ]),
        match_counter = lists:max([
            State#clause_state.match_counter || State <- [Base | States]
        ])
    }.

finish_case(State0, Expression) ->
    CaseState = xls_parse:instr(State0, Expression),
    CaseReference = xls_parse:reference(CaseState),
    MatchCounter = CaseState#clause_state.match_counter + 1,
    MatchBase = "case_match_" ++ integer_to_list(MatchCounter),
    CounterState = CaseState#clause_state{match_counter = MatchCounter},
    {ExpectedName, ExpectedState} = xls_parse:uniquify(
        CounterState,
        MatchBase
    ),
    {ActualName, ActualState} = xls_parse:uniquify(
        ExpectedState,
        MatchBase
    ),
    ActualState#clause_state{
        reference = [CaseReference, ".0"],
        statements = [
            ["let ", ActualName, " = ", CaseReference, ".1;\n"],
            ["let ", ExpectedName, " = bool:false;\n"]
            | ActualState#clause_state.statements
        ]
    }.

%%%
%%% Exact Boolean case
%%%

boolean_only(Clauses) ->
    Clauses =/= [] andalso lists:all(
        fun
            ({clause, _Line, [{atom, _PatternLine, Atom}], [], Body})
                    when (Atom =:= true orelse Atom =:= false), Body =/= [] ->
                true;
            (_Clause) ->
                false
        end,
        Clauses
    ).

lower_boolean_case(Condition, Clauses, State0) ->
    {TrueBody, FalseBody} = boolean_case_bodies(Clauses),
    ConditionState = xls_parse:statement_from_statement(
        Condition,
        State0#clause_state{reference = none}
    ),
    BranchBase = ConditionState#clause_state{
        statements = [],
        reference = none
    },
    TrueState = lower_expressions(TrueBody, BranchBase),
    FalseState = lower_expressions(FalseBody, BranchBase),
    AnonymousCounter = erlang:max(
        TrueState#clause_state.anonymous_counter,
        FalseState#clause_state.anonymous_counter
    ),
    CaseMatchCounter = erlang:max(
        TrueState#clause_state.match_counter,
        FalseState#clause_state.match_counter
    ) + 1,
    BaseCounters = BranchBase#clause_state.named_counters,
    MergedState = ConditionState#clause_state{
        anonymous_counter = AnonymousCounter,
        match_counter = CaseMatchCounter,
        reference = none
    },
    CaseState = xls_parse:instr(MergedState, [
        "if ", xls_parse:reference(ConditionState), " {\n",
        xls_parse_io:indent(xls_parse:print(
            lists:reverse(TrueState#clause_state.statements)
        ), 2),
        "  (", xls_parse:reference(TrueState), ", ",
        xls_parse:mismatch_expression(
            TrueState#clause_state.named_counters,
            BaseCounters
        ), ")\n",
        "} else {\n",
        xls_parse_io:indent(xls_parse:print(
            lists:reverse(FalseState#clause_state.statements)
        ), 2),
        "  (", xls_parse:reference(FalseState), ", ",
        xls_parse:mismatch_expression(
            FalseState#clause_state.named_counters,
            BaseCounters
        ), ")\n",
        "}"
    ]),
    CaseReference = xls_parse:reference(CaseState),
    MatchBase = "case_match_" ++ integer_to_list(CaseMatchCounter),
    {ExpectedName, ExpectedState} = xls_parse:uniquify(CaseState, MatchBase),
    {ActualName, ActualState} = xls_parse:uniquify(
        ExpectedState,
        MatchBase
    ),
    ActualState#clause_state{
        reference = [CaseReference, ".0"],
        statements = [
            ["let ", ActualName, " = ", CaseReference, ".1;\n"],
            ["let ", ExpectedName, " = bool:false;\n"]
            | ActualState#clause_state.statements
        ]
    }.

boolean_case_bodies(Clauses) ->
    case lists:foldl(
        fun
            ({clause, _Line, [{atom, _PatternLine, true}], [], Body},
                    {none, False}) ->
                {Body, False};
            ({clause, Line, [{atom, _PatternLine, true}], [], _Body},
                    {_True, _False}) ->
                error({duplicate_xls_boolean_case_branch, Line, true});
            ({clause, _Line, [{atom, _PatternLine, false}], [], Body},
                    {True, none}) ->
                {True, Body};
            ({clause, Line, [{atom, _PatternLine, false}], [], _Body},
                    {_True, _False}) ->
                error({duplicate_xls_boolean_case_branch, Line, false});
            (Clause, _Bodies) ->
                error({unsupported_xls_case_clause, Clause})
        end,
        {none, none},
        Clauses
    ) of
        {none, _} -> error({missing_xls_boolean_case_branch, true});
        {_, none} -> error({missing_xls_boolean_case_branch, false});
        Bodies -> Bodies
    end.
