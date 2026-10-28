%%%% xls_callback_lower
%%%%
%%%% Lowers source-ordered Erlang callback clauses into one nested XLS
%%%% selection expression. Actor-specific lowerers perform the outer dispatch
%%%% by message tag (and phase); this module handles complete heads, guards,
%%%% and the distinction between clause fallthrough and a selected-body error.

-module(xls_callback_lower).
-moduledoc "Lowers source-ordered callback clauses after actor-specific grouping by phase or message tag. Pattern and guard lowerers distinguish clause fallthrough from selected-body failure; xls_clause_lower supplies the deferred value and failure computation consumed by actor and helper renderers.".

-include("xls_clause_lower.hrl").

%% Retain source order while actor lowerers form dispatch families.
-export([group_by/2]).
%% Lower a complete ordered callback family.
-export([lower/7]).

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

-doc "Lowers ordered callback selection to statements and a result, distinguishing clause fallthrough from selected-body failure.".
-spec lower(
    [erl_parse:abstract_clause(), ...],
    [xls_pattern_lower:argument()],
    atom(),
    fun((xls_clause_lower:printable()) -> xls_clause_lower:printable()),
    xls_clause_lower:printable(),
    fun((xls_clause_lower:printable()) -> xls_clause_lower:printable()),
    #{atom() => xls_clause_lower:printable()}
) -> {xls_clause_lower:printable(), xls_clause_lower:printable()}.
lower(
    Clauses0,
    Arguments,
    StateName,
    Postprocessor,
    NoClauseFailure,
    BodyFailure,
    EnumAtoms
) ->
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

%%%
%%% Ordered selection
%%%

%% Evaluate heads in source order and keep fallthrough distinct from selected-body failure.
-spec lower_chain(
    [erl_parse:abstract_clause()],
    [xls_pattern_lower:argument()],
    atom(),
    fun((xls_clause_lower:printable()) -> xls_clause_lower:printable()),
    xls_clause_lower:printable(),
    fun((xls_clause_lower:printable()) -> xls_clause_lower:printable()),
    #{atom() => xls_clause_lower:printable()}
) ->
    {xls_clause_lower:printable(), xls_clause_lower:printable()}.
lower_chain(
    [],
    _Arguments,
    _StateName,
    _Postprocessor,
    NoClauseFailure,
    _BodyFailure,
    _EnumAtoms
) ->
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
    {PatternState, Conditions} = xls_pattern_lower:lower(
        Patterns,
        Arguments,
        Initial
    ),
    Guard = xls_guard_lower:condition(Guards, Conditions, Line),
    GuardState = xls_clause_lower:statement_from_statement(
        Guard,
        PatternState#clause_state{reference = none}
    ),
    GuardReference = GuardState#clause_state.reference,
    HeadBody = lists:reverse(GuardState#clause_state.statements),

    BodyBase = GuardState#clause_state{statements = [], reference = none, failures = []},
    BodyState = lower_expressions(xls_var_scope:annotate(Body), BodyBase),
    BodyMismatch = xls_clause_lower:failure_expression(BodyState),
    Selected = [
        lists:reverse(BodyState#clause_state.statements),
        "if (",
        BodyMismatch,
        ") {\n",
        xls_dslx:indent(BodyFailure(xls_clause_lower:failure_code(BodyState)), 2),
        "} else {\n",
        xls_dslx:indent(Postprocessor(BodyState#clause_state.reference), 2),
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
    Result =
        case GuardReference of
            "bool:true" ->
                Selected;
            _ ->
                [
                    "if ",
                    GuardReference,
                    " {\n",
                    xls_dslx:indent(Selected, 2),
                    "} else {\n",
                    xls_dslx:indent([NextBody, NextResult], 2),
                    "}"
                ]
        end,
    {HeadBody, Result}.

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
    list_to_tuple([rename_variables(Element, Index) || Element <- tuple_to_list(Tuple)]);
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

%% Lower prepared expressions in order, replacing only the current value reference.
-spec lower_expressions([term()], xls_clause_lower:clause_state()) ->
    xls_clause_lower:clause_state().
lower_expressions(Expressions, State0) ->
    lists:foldl(
        fun(Expression, State) ->
            xls_clause_lower:statement_from_statement(
                Expression,
                State#clause_state{reference = none}
            )
        end,
        State0,
        Expressions
    ).
