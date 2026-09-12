%%%% xls_case_lower
%%%%
%%%% Lowers expression-level Erlang case clauses.  The exact two-arm Boolean
%%%% form keeps its compact renderer; other supported cases become a
%%%% source-ordered chain whose selected arm carries both its value and any
%%%% selected failure, plus the bindings needed after the join.

-module(xls_case_lower).
-moduledoc false.

-include("xls_parse.hrl").

-export([lower/4, lower_if/3]).

-spec lower(
    erl_anno:location(),
    erl_parse:abstract_expression(),
    [erl_parse:af_clause(), ...],
    xls_parse:clause_state()
) -> xls_parse:clause_state().
lower(Line, Condition, Clauses, State) ->
    case boolean_only(Clauses) of
        true -> lower_boolean_case(Line, Condition, Clauses, State);
        false -> lower_ordered_case(Line, Condition, Clauses, State, case_clause)
    end.

%%%
%%% Ordered selection
%%%

lower_ordered_case(Line, Condition, Clauses0, State0, FailureKind) ->
    Clauses = [normalize_clause(Clause) || Clause <- Clauses0],
    Shape = case_shape(Clauses),
    ConditionState = xls_parse:statement_from_statement(
        Condition,
        State0#clause_state{reference = none}
    ),
    ok = validate_nonfinal_fallbacks(lists:droplast(Clauses), ConditionState, FailureKind),
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
    BranchBase = branch_base(ConditionState),
    Branches = [lower_branch(Clause, Argument, Subject, BranchBase) || Clause <- Clauses],
    Failure = xls_failure_sites:at(FailureKind, Line),
    join(Line, ConditionState, Branches, fun(Exports) ->
        ["{\n", xls_parse_io:indent(
            xls_parse:print(render_chain(Branches, Exports, Failure)), 2), "}"]
    end).

normalize_clause({clause, Line, [Pattern], Guards, Body})
        when Body =/= [] ->
    {Line, Pattern, Guards, Body};
normalize_clause(Clause) ->
    error({unsupported_xls_case_clause, Clause}).

validate_nonfinal_fallbacks([], _State, _Kind) ->
    ok;
validate_nonfinal_fallbacks([
    {Line, Pattern, [], _Body} | Rest
], State, Kind) ->
    case fallback_pattern(Pattern, State) of
        true -> error({fallback_error(Kind), Line});
        false -> validate_nonfinal_fallbacks(Rest, State, Kind)
    end;
validate_nonfinal_fallbacks([_Clause | Rest], State, Kind) ->
    validate_nonfinal_fallbacks(Rest, State, Kind).

fallback_error(case_clause) -> nonfinal_xls_case_fallback;
fallback_error(if_clause) -> nonfinal_xls_if_fallback.

fallback_pattern({var, _Line, '_'}, _State) ->
    true;
fallback_pattern({var, Line, Name}, State) ->
    xls_parse:find_binding(Name, Line, State) =:= error;
fallback_pattern({match, _Line, Left, Right}, State) ->
    fallback_pattern(Left, State) andalso fallback_pattern(Right, State);
fallback_pattern(_Pattern, _State) ->
    false.

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

lower_branch({Line, Pattern, Guards, Body}, Argument, Subject, BranchBase) ->
    {PatternState, Conditions} = xls_pattern_lower:lower([Pattern], [Argument], BranchBase),
    Guard = xls_guard_lower:condition(Guards,
        record_tag_condition(Pattern, Subject) ++ Conditions, Line),
    GuardState = xls_parse:statement_from_statement(Guard, PatternState#clause_state{reference = none}),
    #{head => lists:reverse(GuardState#clause_state.statements),
        guard => xls_parse:reference(GuardState),
        state => lower_expressions(Body, branch_base(GuardState))}.

%% The last arm supplies the XLS value type even when it does not match.
%% Its value/bindings are then unobservable: the selection failure takes
%% precedence over any body failure and consumers discard the whole outcome.
render_chain([#{head := Head, guard := "bool:true", state := State}], Exports, _Kind) ->
    [Head, selected(State, Exports)];
render_chain([#{head := Head, guard := Guard, state := State}], Exports, Code) ->
    Failure = ["if ", Guard, " { ", xls_parse:failure_code(State),
        " } else { ", Code, " }"],
    [Head, selected(State, Exports, Failure)];
render_chain([#{head := Head, guard := Guard, state := State} | Rest], Exports, Kind) ->
    [Head, "if ", Guard, " {\n",
        xls_parse_io:indent(xls_parse:print(selected(State, Exports)), 2),
        "} else {\n",
        xls_parse_io:indent(xls_parse:print(render_chain(Rest, Exports, Kind)), 2), "}"].

%% Guard-only clauses share case's ordering, branch joins, and failure carrier.
-spec lower_if(erl_anno:location(), [erl_parse:af_clause(), ...],
    xls_parse:clause_state()) -> xls_parse:clause_state().
lower_if(Line, Clauses, State) ->
    Normalized = [if_clause(Clause) || Clause <- Clauses],
    lower_ordered_case(Line, "()", Normalized, State, if_clause).

if_clause({clause, Line, [], Guards, Body}) when Body =/= [] ->
    Predicate = xls_guard_lower:predicate(Guards, Line),
    %% An unguarded wildcard avoids carrying a redundant final true test.
    Normalized = case Predicate of {atom, _, true} -> []; _ -> [[Predicate]] end,
    {clause, Line, [{var, Line, '_'}], Normalized, Body};
if_clause(Clause) -> error({unsupported_xls_if_clause, Clause}).

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

branch_base(State) ->
    State#clause_state{statements = [], reference = none, failures = []}.

%% Every arm returns the expression value, its own failure kind, and the
%% same ordered set of new bindings. Pre-existing names retain their original
%% value; matching them inside an arm contributes only to that arm's failure.
join(Line, Base = #clause_state{bindings = Bound, unsafe_bindings = Unsafe}, Branches, Render) ->
    States = [State || #{state := State} <- Branches],
    BindingSets = [S#clause_state.bindings || S <- States],
    Common = lists:foldl(fun(Bindings, Acc) -> maps:intersect(Acc, Bindings) end,
        hd(BindingSets), tl(BindingSets)),
    Exports = lists:sort(maps:keys(maps:intersect(Base#clause_state.live_bindings,
        maps:without(maps:keys(Bound), Common)))),
    AllNames = lists:usort(lists:append([maps:keys(S#clause_state.bindings) ++
        maps:keys(S#clause_state.unsafe_bindings) || S <- States])),
    Partial = AllNames -- maps:keys(Common),
    Merged = Base#clause_state{
        anonymous_counter = lists:max([S#clause_state.anonymous_counter || S <- States]),
        unsafe_bindings = maps:merge(maps:from_list([{Name, Line} || Name <- Partial]), Unsafe)},
    Outcome = xls_parse:instr(Merged, Render(Exports)),
    Result = xls_parse:reference(Outcome),
    Joined = lists:foldl(fun({Index, Name}, Acc) ->
        xls_parse:bind(Name, Line, [Result, ".2.", integer_to_list(Index)], Acc)
    end, Outcome, lists:enumerate(0, Exports)),
    xls_parse:outcome_value(xls_parse:reference(Joined, Result)).

selected(State, Exports) ->
    selected(State, Exports, xls_parse:failure_code(State)).

selected(State = #clause_state{bindings = Bindings}, Exports, Failure) ->
    [lists:reverse(State#clause_state.statements),
        "(", xls_parse:reference(State), ", ", Failure,
        case Exports of
            [] -> [];
            _ -> [", (", [[maps:get(Name, Bindings), ", "] || Name <- Exports], ")"]
        end, ")"].

%%%
%%% Exact Boolean case
%%%

boolean_only(Clauses) ->
    length(Clauses) >= 2 andalso lists:all(
        fun
            ({clause, _Line, [{atom, _PatternLine, Atom}], [], Body})
                    when (Atom =:= true orelse Atom =:= false), Body =/= [] ->
                true;
            (_Clause) ->
                false
        end,
        Clauses
    ).

lower_boolean_case(Line, Condition, Clauses, State0) ->
    {TrueBody, FalseBody} = boolean_case_bodies(Clauses),
    ConditionState = xls_parse:statement_from_statement(Condition, State0#clause_state{reference = none}),
    BranchBase = branch_base(ConditionState),
    TrueState = lower_expressions(TrueBody, BranchBase),
    FalseState = lower_expressions(FalseBody, BranchBase),
    join(Line, ConditionState, [#{state => TrueState}, #{state => FalseState}], fun(Exports) ->
        ["if ", xls_parse:reference(ConditionState), " {\n",
            xls_parse_io:indent(xls_parse:print(selected(TrueState, Exports)), 2),
            "} else {\n",
            xls_parse_io:indent(xls_parse:print(selected(FalseState, Exports)), 2), "}"]
    end).

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
