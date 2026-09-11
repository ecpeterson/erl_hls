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
    {Program, State} = body(Body, bound_names(Patterns, #{}), fun result/3, State0),
    Variants = lists:reverse(maps:get(variants, State)),
    #{clause => Clause, program => {clause, Line, Patterns, Guards, Program},
        variants => Variants, reduction => common_reduction(Variants)}.

%% Every continuation consumes a statically bounded list. Applying the same
%% continuation inside each arm preserves branch-local variables, including
%% those needed by a later list tail, without evaluating a branch twice.
result({tuple, Line, [Data, Actions]}, Bindings, State0) ->
    {DataVar, State1} = fresh(State0),
    {Program, State} = segment(Actions, Bindings, fun(Items, NextState) ->
        Acc = lists:foldl(fun append_action/2,
            #{data => DataVar, reduction => none, reduction_value => {tuple, Line, []},
                actions => [], values => []}, Items),
        finish(Acc, NextState)
    end, State1),
    {{block, Line, [{match, Line, DataVar, Data}, Program]}, State};
result(Expression, Bindings, State) ->
    branch(Expression, Bindings, fun result/3, State,
        bad_hls_statem_enter_result).

%% Capture payloads when a list is constructed, even if a later branch omits
%% it. Named segments contain descriptors and references to evaluated values;
%% using a segment never re-evaluates its original expressions.
segment({nil, _Line}, _Bindings, Continue, State) ->
    Continue([], State);
segment({cons, Line, Head, Tail}, Bindings, Continue, State0) ->
    {Descriptor, Value} = action(Head, Bindings, State0),
    {Variable, State1} = fresh(State0),
    {Rest, State} = segment(Tail, Bindings, fun(Items, NextState) ->
        Continue([{Descriptor, Variable} | Items], NextState)
    end, State1),
    {{block, Line, [{match, Line, Variable, Value}, Rest]}, State};
segment({op, _Line, '++', Left, Right}, Bindings, Continue, State) ->
    segment(Left, Bindings, fun(LeftItems, NextState) ->
        segment(Right, Bindings, fun(RightItems, LastState) ->
            Continue(LeftItems ++ RightItems, LastState)
        end, NextState)
    end, State);
segment({var, _, Name} = Expression, Bindings, Continue, State) ->
    case maps:find(Name, Bindings) of
        {ok, {segment, Items}} -> Continue(Items, State);
        _ -> error({nonliteral_hls_statem_actions, element(2, Expression), Expression})
    end;
segment(Expression, Bindings, Continue, State) ->
    branch(Expression, Bindings, fun(Arm, ArmBindings, ArmState) ->
        segment(Arm, ArmBindings, Continue, ArmState)
    end, State, nonliteral_hls_statem_actions).

action({tuple, Line, [{atom, _, open_reduction} | _]} = Open,
        _Bindings, _State) ->
    {Reduction, []} = xls_statem_reduction_lower:split_entry_actions(
        {cons, Line, Open, {nil, Line}}, Line),
    #{key_expression := Key, identity_expression := Identity} = Reduction,
    TypedKey = {call, Line,
        {remote, Line, {atom, Line, hls_type}, {atom, Line, as}},
        [{call, Line, {remote, Line, {atom, Line, hls_nums},
            {atom, Line, u32}}, []}, Key]},
    {{reduction, Line, Reduction}, {tuple, Line, [TypedKey, Identity]}};
action({tuple, _Line, [{atom, _, cast}, {atom, _, Port}, Message]},
        Bindings, #{messages := Messages, outputs := Outputs}) ->
    declared(entry_output, Port, Outputs),
    Tag = message_tag(Message, Bindings),
    declared(entry_message, Tag, Messages),
    {#{port => Port, tag => Tag}, Message};
action(Action, _Bindings, _State) ->
    error({bad_hls_statem_entry_action, element(2, Action), Action}).

append_action({{reduction, _Line, Reduction}, Value},
        #{reduction := none, actions := []} = Acc) ->
    Acc#{reduction => Reduction, reduction_value => Value};
append_action({{reduction, Line, _Reduction}, _Value}, _Acc) ->
    error({hls_statem_open_reduction_must_be_first, Line});
append_action({#{port := Port} = Effect, Value},
        #{actions := Actions, values := Values} = Acc) ->
    case lists:any(fun(#{port := P}) -> P =:= Port end, Actions) of
        true -> error({duplicate_hls_statem_declaration, entry_output,
            [maps:get(port, A) || A <- Actions] ++ [Port]});
        false -> ok
    end,
    Acc#{actions => Actions ++ [Effect], values => Values ++ [Value]}.

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
        {Program, Next} = body(Body, bound_names(Patterns, Bindings), Continue, Acc),
        {{clause, Line, Patterns, Guards, Program}, Next}
    end, State, Clauses).

body([Last], Bindings, Continue, State0) ->
    {Result, State} = Continue(Last, Bindings, State0),
    {[Result], State};
body([{match, _, Pattern, Expression} = First | Rest], Bindings, Continue, State0) ->
    case contains_segment(Expression, Bindings) of
        true ->
            validate_binding_pattern(Pattern, Bindings),
            {Program, State} = bind(Pattern, Expression, Bindings,
                fun(Local, NextState) ->
                    {Tail, LastState} = body(Rest, Local, Continue, NextState),
                    {{block, 0, Tail}, LastState}
                end, State0),
            {[Program], State};
        false -> ordinary_body(First, Rest, Bindings, Continue, State0)
    end;
body([First | Rest], Bindings, Continue, State) ->
    ordinary_body(First, Rest, Bindings, Continue, State).

ordinary_body(First, Rest, Bindings, Continue, State0) ->
    {Tail, State} = body(Rest, record_binding(First, Bindings), Continue, State0),
    {[First | Tail], State}.

%% Bind bounded segments, including tuple destructuring alongside ordinary
%% values. Push the continuation into choices instead of requiring XLS to
%% join differently sized lists. Each tuple field still evaluates in order.
bind(Pattern, {'case', _, _, _} = Expression, Bindings, Continue, State) ->
    bind_branch(Pattern, Expression, Bindings, Continue, State);
bind(Pattern, {'if', _, _} = Expression, Bindings, Continue, State) ->
    bind_branch(Pattern, Expression, Bindings, Continue, State);
bind(Pattern, {block, _, _} = Expression, Bindings, Continue, State) ->
    bind_branch(Pattern, Expression, Bindings, Continue, State);
bind({tuple, _, Patterns}, {tuple, _, Expressions}, Bindings, Continue, State)
        when length(Patterns) =:= length(Expressions) ->
    bind_fields(lists:zip(Patterns, Expressions), Bindings, Continue, State);
bind(Pattern, Expression, Bindings, Continue, State0) ->
    case contains_segment(Expression, Bindings) of
        true ->
            segment(Expression, Bindings, fun(Items, NextState) ->
                case Pattern of
                    {var, _, '_'} -> Continue(Bindings, NextState);
                    {var, _, Name} when not is_map_key(Name, Bindings) ->
                        Continue(Bindings#{Name => {segment, Items}}, NextState);
                    _ -> error({unsupported_hls_statem_action_binding, Pattern})
                end
            end, State0);
        false ->
            Match = {match, 0, Pattern, Expression},
            {Rest, State} = Continue(record_binding(Match, Bindings), State0),
            {{block, 0, [Match, Rest]}, State}
    end.

bind_branch(Pattern, Expression, Bindings, Continue, State) ->
    branch(Expression, Bindings, fun(Arm, Local, NextState) ->
        bind(Pattern, Arm, Local, Continue, NextState)
    end, State, unsupported_hls_statem_action_binding).

bind_fields([], Bindings, Continue, State) -> Continue(Bindings, State);
bind_fields([{Pattern, Expression} | Rest], Bindings, Continue, State) ->
    bind(Pattern, Expression, Bindings, fun(Local, NextState) ->
        bind_fields(Rest, Local, Continue, NextState)
    end, State).

%% Refutable tuple patterns would have to match after all fields evaluate.
%% Segment bindings accept only fresh variables/tuples, so decomposing the
%% binding cannot introduce an earlier failure or treat list equality as aliasing.
validate_binding_pattern(Pattern, Bindings) ->
    binding_names(Pattern, Bindings),
    ok.

binding_names({var, _, '_'}, Bindings) -> Bindings;
binding_names({var, _, Name}, Bindings) when not is_map_key(Name, Bindings) ->
    Bindings#{Name => ordinary};
binding_names({tuple, _, Patterns}, Bindings) ->
    lists:foldl(fun binding_names/2, Bindings, Patterns);
binding_names(Pattern, _Bindings) ->
    error({unsupported_hls_statem_action_binding, Pattern}).

bound_names(Pattern, Bindings) ->
    maps:merge(maps:map(fun(_Name, _Used) -> ordinary end, variables(Pattern)), Bindings).

contains_segment({nil, _}, _Bindings) -> true;
contains_segment({cons, _, {tuple, _, [{atom, _, Kind} | _]}, _}, _Bindings)
        when Kind =:= cast; Kind =:= open_reduction -> true;
contains_segment({op, _, '++', Left, Right}, Bindings) ->
    contains_segment(Left, Bindings) orelse contains_segment(Right, Bindings);
contains_segment({tuple, _, Fields}, Bindings) ->
    lists:any(fun(Field) -> contains_segment(Field, Bindings) end, Fields);
contains_segment({var, _, Name}, Bindings) ->
    case maps:find(Name, Bindings) of
        {ok, {segment, _}} -> true;
        _ -> false
    end;
contains_segment({'case', _, _, Clauses}, Bindings) ->
    contains_segment_arms(Clauses, Bindings);
contains_segment({'if', _, Clauses}, Bindings) ->
    contains_segment_arms(Clauses, Bindings);
contains_segment({block, _, Body}, Bindings) ->
    lists:any(fun(Expression) -> contains_segment(Expression, Bindings) end, Body);
contains_segment({match, _, _Pattern, Expression}, Bindings) ->
    contains_segment(Expression, Bindings);
contains_segment(_Expression, _Bindings) -> false.

contains_segment_arms(Clauses, Bindings) ->
    lists:any(fun({clause, _, _, _, Body}) ->
        contains_segment({block, 0, Body}, Bindings)
    end, Clauses).

record_binding({match, _, {var, _, Name}, Expression}, Bindings) ->
    case record_tag(Expression, Bindings) of
        unknown -> Bindings#{Name => ordinary};
        Tag -> Bindings#{Name => {record, Tag}}
    end;
record_binding({match, _, Pattern, _Expression}, Bindings) ->
    bound_names(Pattern, Bindings);
record_binding(_Expression, Bindings) -> Bindings.

record_tag({record, _, Tag, _}, _Bindings) -> Tag;
record_tag({record, _, _, Tag, _}, _Bindings) -> Tag;
record_tag({var, _, Name}, Bindings) ->
    case maps:find(Name, Bindings) of
        {ok, {record, Tag}} -> Tag;
        _ -> unknown
    end;
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
        Matches = [ok || {O, #{port := P, tag := T}} <- Occurrences,
            {O, P, T} =:= {Order, Port, Tag}],
        Effect = #{order => Order, port => Port, schema => Tag},
        case length(Matches) =:= length(Variants) of
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
