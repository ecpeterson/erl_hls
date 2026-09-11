%%%% xls_statem_entry
%%%%
%%%% Normalizes bounded entry programs before expression lowering. Branches
%%%% retain their Erlang scope and evaluation order; each leaf describes one
%%%% possible ordered batch. No payload is lifted out of its selected branch.

-module(xls_statem_entry).
-moduledoc false.

-export([analyze/3, effects/1, max_effects/1, map_leaves/2]).

-type variant() :: #{id := non_neg_integer(), actions := [map()],
    reduction := none | map()}.
-type plan() :: #{clause := erl_parse:af_clause(), program := term(),
    variants := [variant(), ...], reduction := none | map()}.

-spec analyze(erl_parse:af_clause(), [atom()], [atom()]) -> plan().
analyze(Clause = {clause, Line, Patterns, Guards, Body}, Messages, Outputs) ->
    State0 = #{next_variable => 0, used => variables(Clause), variants => [],
        messages => Messages, outputs => Outputs},
    {Program, State} = body(Body, #{}, fun result/3, State0),
    Variants = lists:reverse(maps:get(variants, State)),
    #{clause => Clause, program => {clause, Line, Patterns, Guards, Program},
        variants => Variants, reduction => common_reduction(Variants)}.

%% Every continuation consumes a statically bounded list. Applying the same
%% continuation inside each arm preserves branch-local variables, including
%% those needed by a later list tail, without evaluating a branch twice.
result({tuple, Line, [Data, Actions]}, Bindings, State0) ->
    {DataVar, State1} = fresh(State0),
    {Program, State} = actions(Actions, Bindings,
        #{data => DataVar, reduction => none, reduction_value => {tuple, Line, []},
            actions => [], values => []}, fun finish/2, State1),
    {{block, Line, [{match, Line, DataVar, Data}, Program]}, State};
result(Expression, Bindings, State) ->
    branch(Expression, Bindings, fun result/3, State,
        bad_hls_statem_enter_result).

actions({nil, _Line}, _Bindings, Acc, Continue, State) ->
    Continue(Acc, State);
actions({cons, Line, Head, Tail}, Bindings, Acc0, Continue, State0) ->
    {Value, Acc1} = action(Head, Bindings, Acc0, State0),
    {Variable, State1} = fresh(State0),
    Acc = case maps:get(kind, Acc1) of
        reduction -> maps:remove(kind, Acc1#{reduction_value => Variable});
        cast -> maps:remove(kind, Acc1#{values => maps:get(values, Acc1) ++ [Variable]})
    end,
    {Rest, State} = actions(Tail, Bindings, Acc, Continue, State1),
    {{block, Line, [{match, Line, Variable, Value}, Rest]}, State};
actions({op, _Line, '++', Left, Right}, Bindings, Acc, Continue, State) ->
    actions(Left, Bindings, Acc, fun(NextAcc, NextState) ->
        actions(Right, Bindings, NextAcc, Continue, NextState)
    end, State);
actions(Expression, Bindings, Acc, Continue, State) ->
    branch(Expression, Bindings, fun(Arm, ArmBindings, ArmState) ->
        actions(Arm, ArmBindings, Acc, Continue, ArmState)
    end, State, nonliteral_hls_statem_actions).

action({tuple, Line, [{atom, _, open_reduction} | _]} = Open,
        _Bindings, #{reduction := none, actions := []} = Acc, _State) ->
    {Reduction, []} = xls_statem_reduction_lower:split_entry_actions(
        {cons, Line, Open, {nil, Line}}, Line),
    #{key_expression := Key, identity_expression := Identity} = Reduction,
    TypedKey = {call, Line,
        {remote, Line, {atom, Line, hls_type}, {atom, Line, as}},
        [{call, Line, {remote, Line, {atom, Line, hls_nums},
            {atom, Line, u32}}, []}, Key]},
    {{tuple, Line, [TypedKey, Identity]},
        Acc#{kind => reduction, reduction => Reduction}};
action({tuple, Line, [{atom, _, open_reduction} | _]}, _Bindings, _Acc, _State) ->
    error({hls_statem_open_reduction_must_be_first, Line});
action({tuple, Line, [{atom, _, cast}, {atom, _, Port}, Message]},
        Bindings, Acc, State) ->
    cast(Port, Message, {atom, Line, true}, false, Line, Bindings, Acc, State);
action({tuple, Line, [{atom, _, cast_if}, Condition, {atom, _, Port}, Message]},
        Bindings, Acc, State) ->
    cast(Port, Message, Condition, true, Line, Bindings, Acc, State);
action(Action, _Bindings, _Acc, _State) ->
    error({bad_hls_statem_entry_action, element(2, Action), Action}).

cast(Port, Message, Condition, Conditional, Line, Bindings,
        #{actions := Actions} = Acc, #{messages := Messages, outputs := Outputs}) ->
    declared(entry_output, Port, Outputs),
    Tag = message_tag(Message, Bindings),
    declared(entry_message, Tag, Messages),
    case lists:any(fun(#{port := P}) -> P =:= Port end, Actions) of
        true -> error({duplicate_hls_statem_declaration, entry_output,
            [maps:get(port, A) || A <- Actions] ++ [Port]});
        false -> ok
    end,
    Effect = #{port => Port, tag => Tag, conditional => Conditional},
    {{tuple, Line, [Condition, Message]}, Acc#{kind => cast, actions => Actions ++ [Effect]}}.

finish(#{data := Data, reduction := Reduction, reduction_value := ReductionValue,
        actions := Actions, values := Values}, #{variants := Variants} = State) ->
    Id = length(Variants),
    case Id < 256 of
        true -> ok;
        false -> error({too_many_hls_statem_entry_variants, 256})
    end,
    Variant = #{id => Id, actions => Actions, reduction => Reduction},
    {{entry_leaf, 0, Id, {tuple, 0, [Data, ReductionValue, {tuple, 0, Values}]}},
        State#{variants => [Variant | Variants]}}.

branch({'case', Line, Subject, Clauses}, Bindings, Continue, State0, _Error) ->
    {Arms, State} = clauses(Clauses, Bindings, Continue, State0),
    {{'case', Line, Subject, Arms}, State};
branch({'if', Line, Clauses}, Bindings, Continue, State0, _Error) ->
    {Arms, State} = clauses(Clauses, Bindings, Continue, State0),
    {{'if', Line, Arms}, State};
branch({block, Line, Body}, Bindings, Continue, State0, _Error) ->
    {Program, State} = body(Body, Bindings, Continue, State0),
    {{block, Line, Program}, State};
branch(Expression, _Bindings, _Continue, _State, Error) ->
    error({Error, element(2, Expression), Expression}).

clauses(Clauses, Bindings, Continue, State) ->
    lists:mapfoldl(fun({clause, Line, Patterns, Guards, Body}, Acc) ->
        {Program, Next} = body(Body, Bindings, Continue, Acc),
        {{clause, Line, Patterns, Guards, Program}, Next}
    end, State, Clauses).

body(Body, Bindings, Continue, State0) ->
    {Prefix, [Last]} = lists:split(length(Body) - 1, Body),
    Local = lists:foldl(fun record_binding/2, Bindings, Prefix),
    {Result, State} = Continue(Last, Local, State0),
    {Prefix ++ [Result], State}.

record_binding({match, _, {var, _, Name}, Expression}, Bindings) ->
    case record_tag(Expression, Bindings) of
        unknown -> Bindings;
        Tag -> Bindings#{Name => Tag}
    end;
record_binding(_Expression, Bindings) -> Bindings.

record_tag({record, _, Tag, _}, _Bindings) -> Tag;
record_tag({record, _, _, Tag, _}, _Bindings) -> Tag;
record_tag({var, _, Name}, Bindings) -> maps:get(Name, Bindings, unknown);
record_tag(_Expression, _Bindings) -> unknown.

message_tag(Message, Bindings) ->
    case record_tag(Message, Bindings) of
        unknown -> error({unsupported_hls_statem_action_message, Message});
        Tag -> Tag
    end.

%% A phase has one reduction site. It may open only on selected paths, but
%% every opening must describe that same site. Keys remain subject to the
%% reduction lowerer's existing data-relative expression checks.
common_reduction(Variants) ->
    Opens = [Open || #{reduction := Open} <- Variants, Open =/= none],
    case Opens of
        [] -> none;
        [First | Rest] ->
            Key = reduction_key(First),
            case lists:all(fun(Open) -> reduction_key(Open) =:= Key end, Rest) of
                true -> First#{opens_conditionally => length(Opens) =/= length(Variants)};
                false -> error(inconsistent_hls_statem_entry_reductions)
            end
    end.

reduction_key(#{name := Name, population := Population, accumulator := Accumulator,
        key_expression := Key, identity_expression := Identity}) ->
    {Name, Population, Accumulator, erl_parse:map_anno(fun(_) -> 0 end, Key),
        erl_parse:map_anno(fun(_) -> 0 end, Identity)}.

%% Interface effects are a conservative union by ordered position. A shared
%% unconditional prefix remains provable even if the tail branches; mutually
%% exclusive alternatives do not inflate the maximum batch capacity.
-spec effects(plan()) -> [map()].
effects(#{variants := Variants}) ->
    Occurrences = lists:append([[{Order, Action}
        || {Order, Action} <- lists:enumerate(0, Actions)]
        || #{actions := Actions} <- Variants]),
    Keys = lists:usort([{Order, Port, Tag}
        || {Order, #{port := Port, tag := Tag}} <- Occurrences]),
    [begin
        Matches = [Conditional || {O, #{port := P, tag := T,
            conditional := Conditional}} <- Occurrences,
            {O, P, T} =:= {Order, Port, Tag}],
        Effect = #{order => Order, port => Port, schema => Tag},
        case length(Matches) =:= length(Variants) andalso
                not lists:member(true, Matches) of
            true -> Effect;
            false -> Effect#{conditional => true}
        end
    end || {Order, Port, Tag} <- Keys].

-spec max_effects(plan()) -> non_neg_integer().
max_effects(#{variants := Variants}) ->
    lists:max([length(Actions) || #{actions := Actions} <- Variants]).

-spec map_leaves(term(), fun((non_neg_integer(), term()) -> term())) -> term().
map_leaves({entry_leaf, _Line, Id, Value}, Fun) -> Fun(Id, Value);
map_leaves(Tuple, Fun) when is_tuple(Tuple) ->
    list_to_tuple([map_leaves(E, Fun) || E <- tuple_to_list(Tuple)]);
map_leaves(List, Fun) when is_list(List) -> [map_leaves(E, Fun) || E <- List];
map_leaves(Value, _Fun) -> Value.

fresh(#{next_variable := Index, used := Used} = State) ->
    Name = list_to_atom("Xls_entry_" ++ integer_to_list(Index)),
    Next = State#{next_variable => Index + 1},
    case maps:is_key(Name, Used) of
        true -> fresh(Next);
        false -> {{var, 0, Name}, Next}
    end.

variables({var, _, Name}) -> #{Name => true};
variables(Tuple) when is_tuple(Tuple) -> variables(tuple_to_list(Tuple));
variables(List) when is_list(List) ->
    lists:foldl(fun(E, Acc) -> maps:merge(Acc, variables(E)) end, #{}, List);
variables(_Other) -> #{}.

declared(Kind, Value, Values) ->
    case lists:member(Value, Values) of
        true -> ok;
        false -> error({undeclared_hls_statem_name, Kind, Value, Values})
    end.
