%%%% Carry callback result constructors through local bindings. Tuples keep
%%%% their source annotation and references to fields evaluated at construction;
%%%% returning an alias never evaluates those fields again. Structural choices
%%%% receive the continuation in each arm, before callback-specific lowering.

-module(xls_callback_result).
-moduledoc false.

-export([map/2, results/1]).

-spec map(erl_parse:af_clause(), fun((term()) -> term())) -> erl_parse:af_clause().
map(Clause, Leaf) ->
    {Program, _Results} = normalize(Clause, Leaf),
    Program.

-spec results(erl_parse:af_clause()) -> [term()].
results(Clause) ->
    {_Program, Results} = normalize(Clause, fun(Value) -> Value end),
    Results.

normalize(Clause = {clause, Line, Patterns, Guards, Body}, Leaf) ->
    State0 = #{next => 0, used => variables(Clause), needed => needed(Body), results => []},
    Continue = fun(Value, _Bindings, State = #{results := Results}) ->
        case length(Results) < 256 of
            true -> {Leaf(Value), State#{results => [Value | Results]}};
            false -> error({too_many_callback_result_paths, 256})
        end
    end,
    Bindings = maps:map(fun(_, _) -> ordinary end, variables(Patterns)),
    {Program, #{results := Results}} = body(Body, Bindings, Continue, State0),
    {{clause, Line, Patterns, Guards, Program}, lists:reverse(Results)}.

body([Last], Bindings, Continue, State) ->
    {Result, Next} = choice(Last, Bindings, Continue, State),
    {[Result], Next};
body([{match, Line, {tuple, _, _} = Pattern, Expression} = First | Rest],
        Bindings, Continue, State = #{needed := Needed}) ->
    case maps:size(maps:with(maps:keys(variables(Pattern)), Needed)) > 0
            andalso structural(Expression, Bindings)
            andalso fresh_pattern(Pattern, bound_after(Expression, Bindings)) of
        true ->
            {Program, Next} = capture(Expression, Bindings, fun(Value, Evaluated, Acc) ->
                {Matches, Local} = bind_product(Pattern, Value, Evaluated),
                {Tail, LastState} = body(Rest, Local, Continue, Acc),
                {{block, Line, Matches ++ Tail}, LastState}
            end, State),
            {[Program], Next};
        false -> ordinary(First, Rest, Bindings, Continue, State)
    end;
body([{match, Line, {var, _, Name}, Expression} = First | Rest],
        Bindings, Continue, State = #{needed := Needed})
        when Name =:= '_'; not is_map_key(Name, Bindings) ->
    case (Name =:= '_' orelse is_map_key(Name, Needed)
            orelse uses_constructor(Expression, Bindings))
            andalso structural(Expression, Bindings) of
        true ->
            {Program, Next} = capture(Expression, Bindings, fun(Value, Evaluated, Acc) ->
                Local = case Name of
                    '_' -> Evaluated;
                    _ -> Evaluated#{Name => Value}
                end,
                {Tail, LastState} = body(Rest, Local, Continue, Acc),
                {{block, Line, Tail}, LastState}
            end, State),
            {[Program], Next};
        false -> ordinary(First, Rest, Bindings, Continue, State)
    end;
body([First | Rest], Bindings, Continue, State) ->
    ordinary(First, Rest, Bindings, Continue, State).

ordinary(First, Rest, Bindings, Continue, State0) ->
    Expression = expand(First, Bindings),
    {Tail, State} = body(Rest, bound_after(First, Bindings), Continue, State0),
    {[Expression | Tail], State}.

%% Decompose only fresh product patterns, after every RHS field has evaluated.
%% Keep ordinary aliases as real bindings so later matches still check equality;
%% control atoms and nested products remain visible to callback analysis.
bind_product({var, _, '_'}, _Value, Bindings) -> {[], Bindings};
bind_product({var, _, Name}, {atom, _, Atom} = Value, Bindings)
        when Atom =/= true, Atom =/= false ->
    {[], Bindings#{Name => Value}};
bind_product({var, _, Name}, {tuple, _, _} = Value, Bindings) ->
    {[], Bindings#{Name => Value}};
bind_product({var, Line, Name} = Pattern, Value, Bindings) ->
    {[{match, Line, Pattern, Value}], Bindings#{Name => ordinary}};
bind_product({tuple, _, Patterns}, {tuple, _, Values}, Bindings)
        when length(Patterns) =:= length(Values) ->
    {Matches, Local} = lists:mapfoldl(fun({Pattern, Value}, Acc) ->
        bind_product(Pattern, Value, Acc)
    end, Bindings, lists:zip(Patterns, Values)),
    {lists:append(Matches), Local};
bind_product(Pattern, _Value, _Bindings) ->
    error({unsupported_callback_result_binding, Pattern}).

fresh_pattern(Pattern, Bindings) ->
    case fresh_names(Pattern, Bindings) of
        false -> false;
        _Names -> true
    end.

fresh_names({var, _, '_'}, Names) -> Names;
fresh_names({var, _, Name}, Names) when not is_map_key(Name, Names) ->
    Names#{Name => ordinary};
fresh_names({tuple, _, Patterns}, Names) ->
    lists:foldl(fun
        (_, false) -> false;
        (Pattern, Acc) -> fresh_names(Pattern, Acc)
    end, Names, Patterns);
fresh_names(_, _Names) -> false.

%% Follow result fields/aliases backwards, leaving unrelated product-valued
%% computations (including refutable matches) to ordinary expression lowering.
needed(Body) ->
    lists:foldr(fun
        ({match, _, Pattern, Expression}, Names) ->
            case maps:size(maps:with(maps:keys(variables(Pattern)), Names)) of
                0 -> Names;
                _ -> maps:merge(Names, result_variables(Expression))
            end;
        (_, Names) -> Names
    end, result_variables(lists:last(Body)), lists:droplast(Body)).

result_variables({var, _, _} = Variable) -> variables(Variable);
result_variables({tuple, _, Fields}) -> merge_results(Fields);
result_variables({'case', _, _, Clauses}) -> result_arms(Clauses);
result_variables({'if', _, Clauses}) -> result_arms(Clauses);
result_variables({block, _, Body}) -> needed(Body);
result_variables(_) -> #{}.

result_arms(Clauses) ->
    lists:foldl(fun({clause, _, _, _, Body}, Acc) -> maps:merge(Acc, needed(Body)) end,
        #{}, Clauses).

merge_results(Expressions) ->
    lists:foldl(fun(Expression, Acc) -> maps:merge(Acc, result_variables(Expression)) end,
        #{}, Expressions).

uses_constructor(Expression, Bindings) ->
    lists:any(fun(Name) -> maps:get(Name, Bindings, ordinary) =/= ordinary end,
        maps:keys(variables(Expression))).

%% Only structurally known bindings need continuation expansion. Ordinary
%% arithmetic/record choices still join through the expression lowerer.
structural({tuple, _, _}, _Bindings) -> true;
structural({atom, _, Atom}, _Bindings) -> Atom =/= true andalso Atom =/= false;
structural({var, _, Name}, Bindings) -> maps:get(Name, Bindings, ordinary) =/= ordinary;
structural({'case', _, _, Clauses}, Bindings) -> structural_arms(Clauses, Bindings);
structural({'if', _, Clauses}, Bindings) -> structural_arms(Clauses, Bindings);
structural({block, _, Body}, Bindings) -> structural_body(Body, Bindings);
structural(_, _) -> false.

structural_arms(Clauses, Bindings) ->
    lists:any(fun({clause, _, _, _, Body}) -> structural_body(Body, Bindings) end,
        Clauses).

structural_body([Last], Bindings) -> structural(Last, Bindings);
structural_body([{match, _, {var, _, Name}, Expression} | Rest], Bindings) ->
    Local = case structural(Expression, Bindings) of
        true -> Bindings#{Name => Expression};
        false -> Bindings
    end,
    structural_body(Rest, Local);
structural_body([_ | Rest], Bindings) -> structural_body(Rest, Bindings).

choice({'case', Line, Subject, Clauses}, Bindings, Continue, State0) ->
    {Arms, State} = clauses(Clauses, Bindings, Continue, State0),
    {{'case', Line, expand(Subject, Bindings), Arms}, State};
choice({'if', Line, Clauses}, Bindings, Continue, State0) ->
    {Arms, State} = clauses(Clauses, Bindings, Continue, State0),
    {{'if', Line, Arms}, State};
choice({block, Line, Body}, Bindings, Continue, State0) ->
    {Program, State} = body(Body, Bindings, Continue, State0),
    {{block, Line, Program}, State};
choice(Expression, Bindings, Continue, State) ->
    Continue(expand(Expression, Bindings), Bindings, State).

clauses(Clauses, Bindings, Continue, State) ->
    lists:mapfoldl(fun({clause, Line, Patterns, Guards, Body}, Acc) ->
        reject_rebinding(Patterns, Bindings),
        Local = maps:merge(maps:map(fun(_, _) -> ordinary end, variables(Patterns)),
            Bindings),
        {Program, Next} = body(Body, Local, Continue, Acc),
        {{clause, Line, Patterns, expand(Guards, Bindings), Program}, Next}
    end, State, Clauses).

capture(Expression, Bindings, Continue, State) ->
    choice(Expression, Bindings, fun(Value, Local, Acc) ->
        capture_value(Value, fun(Captured, Next) ->
            Continue(Captured, bound_after(Value, Local), Next)
        end, Acc)
    end, State).

capture_value({tuple, Line, Fields}, Continue, State) ->
    capture_fields(Fields, fun(Values, Next) ->
        Continue({tuple, Line, Values}, Next)
    end, State);
capture_value({atom, _, _} = Value, Continue, State) -> Continue(Value, State);
capture_value({var, _, _} = Value, Continue, State) -> Continue(Value, State);
capture_value(Expression, Continue, State0) ->
    {Variable, State1} = fresh(State0),
    {Rest, State} = Continue(Variable, State1),
    {{block, 0, [{match, 0, Variable, Expression}, Rest]}, State}.

capture_fields([], Continue, State) -> Continue([], State);
capture_fields([Field | Fields], Continue, State) ->
    capture_value(Field, fun(Value, Next) ->
        capture_fields(Fields, fun(Values, Last) ->
            Continue([Value | Values], Last)
        end, Next)
    end, State).

%% Ordinary uses can reconstruct products from captured references. Binding
%% patterns must remain fresh: matching an erased structural variable would
%% otherwise lose the original equality check (and action lists have no XLS
%% equality representation). Ordinary expression bindings are unaffected.
expand({var, _, Name} = Variable, Bindings) ->
    case maps:get(Name, Bindings, ordinary) of
        ordinary -> Variable;
        Value -> Value
    end;
expand({match, Line, Pattern, Expression}, Bindings) ->
    reject_rebinding(Pattern, Bindings),
    {match, Line, Pattern, expand(Expression, Bindings)};
expand({clause, Line, Patterns, Guards, Body}, Bindings) ->
    reject_rebinding(Patterns, Bindings),
    {clause, Line, Patterns, expand(Guards, Bindings), expand(Body, Bindings)};
expand(Tuple, Bindings) when is_tuple(Tuple) ->
    list_to_tuple([expand(Item, Bindings) || Item <- tuple_to_list(Tuple)]);
expand(List, Bindings) when is_list(List) -> [expand(Item, Bindings) || Item <- List];
expand(Value, _Bindings) -> Value.

reject_rebinding(Pattern, Bindings) ->
    case lists:any(fun(Name) -> maps:get(Name, Bindings, ordinary) =/= ordinary end,
            maps:keys(variables(Pattern))) of
        false -> ok;
        true -> error({unsupported_callback_result_binding, Pattern})
    end.

bound_after({match, _, Pattern, Expression}, Bindings) ->
    maps:merge(maps:map(fun(_, _) -> ordinary end, variables(Pattern)),
        bound_after(Expression, Bindings));
bound_after({clause, _, Patterns, _Guards, Body}, Bindings) ->
    maps:merge(maps:map(fun(_, _) -> ordinary end, variables(Patterns)),
        bound_after(Body, Bindings));
bound_after(Tuple, Bindings) when is_tuple(Tuple) ->
    bound_after(tuple_to_list(Tuple), Bindings);
bound_after(List, Bindings) when is_list(List) ->
    lists:foldl(fun bound_after/2, Bindings, List);
bound_after(_, Bindings) -> Bindings.

fresh(State = #{next := N, used := Used}) ->
    Name = list_to_atom("Xls_result_" ++ integer_to_list(N)),
    Next = State#{next => N + 1},
    case is_map_key(Name, Used) of
        true -> fresh(Next);
        false -> {{var, 0, Name}, Next#{used => Used#{Name => true}}}
    end.

variables({var, _, Name}) -> #{Name => true};
variables(Tuple) when is_tuple(Tuple) -> variables(tuple_to_list(Tuple));
variables(List) when is_list(List) ->
    lists:foldl(fun(Item, Acc) -> maps:merge(Acc, variables(Item)) end, #{}, List);
variables(_) -> #{}.
