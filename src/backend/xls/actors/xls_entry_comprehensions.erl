-module(xls_entry_comprehensions).
-moduledoc "Expands finite literal-list comprehensions in state-entry callbacks before interface and expression analysis. Generated effects retain ordinary source order and failure behavior; generator constants expose ports while fresh local names preserve comprehension scope. No source calls run during expansion.".

%% Normalize only the declared state-machine entry surface.
-export([forms/2, clause/1]).

%% Source names known to be bound, including unsafe names retained for later validation.
-type names() :: #{atom() => true}.
%% Fresh names avoid every spelling already present in the original clause.
-type state() :: #{next := non_neg_integer(), used := names()}.
%% Generator domains contain only compile-time scalar and tuple values.
-type literal() :: atom() | integer() | tuple().

-doc "Expands supported comprehensions only in enter clauses of the declared phase functions; other source forms remain unchanged.".
-spec forms([hls_source:form()], [atom()]) -> [hls_source:form()].
forms(Forms, Phases) ->
    [
        case Form of
            {function, Line, Name, 3, Clauses} ->
                case lists:member(Name, Phases) of
                    true -> {function, Line, Name, 3, [entry(C) || C <- Clauses]};
                    false -> Form
                end;
            _ ->
                Form
        end
     || Form <- Forms
    ].

%% Event discrimination precedes specialization; cast and internal callbacks are unaffected.
-spec entry(erl_parse:abstract_clause()) -> erl_parse:abstract_clause().
entry({clause, _, [{atom, _, enter}, _, _], _, _} = Clause) -> clause(Clause);
entry(Clause) -> Clause.

-doc "Expands one-generator comprehensions over at most 256 literal atoms, integers or tuples. Literal/variable/tuple patterns skip mismatches. Preserves generator shadowing and iteration-local bindings; rejects filters, dynamic domains and nested comprehensions/closures.".
-spec clause(erl_parse:abstract_clause()) -> erl_parse:abstract_clause().
clause(Clause = {clause, Line, Patterns, Guards, Body}) ->
    State0 = #{next => 0, used => variables(Clause)},
    {Expanded, _Bound, _State} = expressions(Body, variables(Patterns), State0),
    {clause, Line, Patterns, Guards, Expanded}.

%% Track surrounding bindings in source order without executing expressions.
-spec expressions([term()], names(), state()) -> {[term()], names(), state()}.
expressions([], Bound, State) ->
    {[], Bound, State};
expressions([First | Rest], Bound0, State0) ->
    {Expanded, Bound1, State1} = expression(First, Bound0, State0),
    {Tail, Bound, State} = expressions(Rest, Bound1, State1),
    {[Expanded | Tail], Bound, State}.

%% A comprehension has its own binding scope; its locals never enter the continuation.
-spec expression(term(), names(), state()) -> {term(), names(), state()}.
expression({lc, Line, Body, Qualifiers}, Bound, State0) ->
    {Expanded, State} = comprehension(Line, Body, Qualifiers, Bound, State0),
    {Expanded, Bound, State};
expression({match, Line, Pattern, Value}, Bound0, State0) ->
    {Expanded, Bound, State} = expression(Value, Bound0, State0),
    {{match, Line, Pattern, Expanded}, maps:merge(Bound, variables(Pattern)), State};
expression({'case', Line, Subject, Clauses}, Bound0, State0) ->
    {Value, Bound1, State1} = expression(Subject, Bound0, State0),
    {Arms, Bound, State} = branches(Clauses, Bound1, State1),
    {{'case', Line, Value, Arms}, Bound, State};
expression({'if', Line, Clauses}, Bound0, State0) ->
    {Arms, Bound, State} = branches(Clauses, Bound0, State0),
    {{'if', Line, Arms}, Bound, State};
expression({block, Line, Body}, Bound0, State0) ->
    {Expanded, Bound, State} = expressions(Body, Bound0, State0),
    {{block, Line, Expanded}, Bound, State};
expression({'fun', _, _} = Value, Bound, State) ->
    {Value, Bound, State};
expression({named_fun, _, _, _} = Value, Bound, State) ->
    {Value, Bound, State};
expression(Tuple, Bound0, State0) when is_tuple(Tuple) ->
    {Expanded, Bound, State} = expressions(tuple_to_list(Tuple), Bound0, State0),
    {list_to_tuple(Expanded), Bound, State};
expression(List, Bound, State) when is_list(List) -> expressions(List, Bound, State);
expression(Value, Bound, State) ->
    {Value, Bound, State}.

%% Siblings inherit the same outer scope. Potentially unsafe exported names remain names,
%% so later ordinary lowering still diagnoses their use rather than treating them as fresh.
-spec branches([erl_parse:abstract_clause()], names(), state()) ->
    {[erl_parse:abstract_clause()], names(), state()}.
branches(Clauses, Outer, State0) ->
    {Expanded, {Bound, State}} = lists:mapfoldl(
        fun({clause, Line, Patterns, Guards, Body}, {Seen, Acc}) ->
            {Result, After, Next} = expressions(Body, maps:merge(Outer, variables(Patterns)), Acc),
            {{clause, Line, Patterns, Guards, Result}, {maps:merge(Seen, After), Next}}
        end,
        {Outer, State0},
        Clauses
    ),
    {Expanded, Bound, State}.

%% A literal domain has no runtime evaluation to move or suppress.
-spec comprehension(erl_anno:anno(), term(), [term()], names(), state()) -> {term(), state()}.
comprehension(Line, Body, [{generate, _, Pattern, Domain}], Outer, State0) ->
    validate_pattern(Pattern, Line),
    validate_body(Body, Line),
    Values = domain(Domain, Line, 0),
    {Items, State} = lists:mapfoldl(
        fun(Value, Acc) ->
            case match(Pattern, Value, #{}) of
                nomatch ->
                    {[], Acc};
                {ok, Constants} ->
                    {Names, Next} = rename_locals(Body, Outer, Constants, Acc),
                    {[substitute(Body, Constants, Names)], Next}
            end
        end,
        State0,
        Values
    ),
    {
        lists:foldr(
            fun(Value, Tail) -> {cons, Line, Value, Tail} end,
            {nil, Line},
            lists:append(Items)
        ),
        State
    };
comprehension(Line, _Body, Qualifiers, _Outer, _State) ->
    error({unsupported_static_entry_comprehension, Line, {qualifiers, Qualifiers}}).

%% Check the bound before materializing cloned bodies; improper and computed domains reject.
-spec domain(term(), erl_anno:anno(), non_neg_integer()) -> [literal()].
domain({nil, _}, _Line, _Count) ->
    [];
domain({cons, _, _Head, _Tail}, Line, 256) ->
    error({static_entry_comprehension_limit, Line, 256});
domain({cons, _, Head, Tail}, Line, Count) ->
    case literal(Head) of
        {ok, Value} -> [Value | domain(Tail, Line, Count + 1)];
        error -> error({unsupported_static_entry_comprehension, Line, {domain_element, Head}})
    end;
domain(Domain, Line, _Count) ->
    error({unsupported_static_entry_comprehension, Line, {domain, Domain}}).

%% Erlang represents a signed literal with a unary operator; no arithmetic calls are evaluated.
-spec literal(term()) -> {ok, literal()} | error.
literal({Kind, _, Value}) when Kind =:= atom; Kind =:= integer; Kind =:= char -> {ok, Value};
literal({op, _, '-', {integer, _, Value}}) ->
    {ok, -Value};
literal({op, _, '+', {integer, _, Value}}) ->
    {ok, Value};
literal({tuple, _, Fields}) ->
    case literal_fields(Fields) of
        {ok, Values} -> {ok, list_to_tuple(Values)};
        error -> error
    end;
literal(_) ->
    error.

%% Preserve tuple element order and reject the entire literal on an unsupported field.
-spec literal_fields([term()]) -> {ok, [literal()]} | error.
literal_fields([]) ->
    {ok, []};
literal_fields([Field | Rest]) ->
    case {literal(Field), literal_fields(Rest)} of
        {{ok, Value}, {ok, Values}} -> {ok, [Value | Values]};
        _ -> error
    end.

%% Validate even an empty generator so unsupported patterns do not depend on domain contents.
-spec validate_pattern(term(), erl_anno:anno()) -> ok.
validate_pattern({var, _, _}, _Line) ->
    ok;
validate_pattern({tuple, _, Fields}, Line) ->
    lists:foreach(fun(Field) -> validate_pattern(Field, Line) end, Fields);
validate_pattern(Pattern, Line) ->
    case literal(Pattern) of
        {ok, _} -> ok;
        error -> error({unsupported_static_entry_comprehension, Line, {pattern, Pattern}})
    end.

%% These constructs introduce additional scopes or dynamic iteration; their ordinary lowering
%% remains unsupported rather than being mistaken for a textual substitution opportunity.
-spec validate_body(term(), erl_anno:anno()) -> ok.
validate_body(Tuple, Line) when is_tuple(Tuple) ->
    case element(1, Tuple) of
        Kind when
            Kind =:= lc;
            Kind =:= bc;
            Kind =:= mc;
            Kind =:= 'fun';
            Kind =:= named_fun;
            Kind =:= 'receive';
            Kind =:= 'try';
            Kind =:= 'maybe'
        ->
            error({unsupported_static_entry_comprehension, Line, {body_scope, Kind}});
        _ ->
            lists:foreach(fun(Value) -> validate_body(Value, Line) end, tuple_to_list(Tuple))
    end;
validate_body(List, Line) when is_list(List) ->
    lists:foreach(fun(Value) -> validate_body(Value, Line) end, List);
validate_body(_Value, _Line) ->
    ok.

%% Generator patterns bind afresh, including names shadowing the surrounding callback.
-spec match(term(), literal(), #{atom() => literal()}) -> {ok, #{atom() => literal()}} | nomatch.
match({var, _, '_'}, _Value, Bound) ->
    {ok, Bound};
match({var, _, Name}, Value, Bound) ->
    case maps:find(Name, Bound) of
        {ok, Value} -> {ok, Bound};
        {ok, _Other} -> nomatch;
        error -> {ok, Bound#{Name => Value}}
    end;
match({tuple, _, Fields}, Value, Bound) when
    is_tuple(Value), length(Fields) =:= tuple_size(Value)
->
    match_fields(Fields, tuple_to_list(Value), Bound);
match(Pattern, Value, Bound) ->
    case literal(Pattern) of
        {ok, Value} -> {ok, Bound};
        _ -> nomatch
    end.

%% Repeated variables in one pattern constrain later fields rather than rebinding them.
-spec match_fields([term()], [literal()], #{atom() => literal()}) ->
    {ok, #{atom() => literal()}} | nomatch.
match_fields([], [], Bound) ->
    {ok, Bound};
match_fields([Pattern | Patterns], [Value | Values], Bound) ->
    case match(Pattern, Value, Bound) of
        {ok, Next} -> match_fields(Patterns, Values, Next);
        nomatch -> nomatch
    end.

%% Local bindings have one spelling per iteration; free variables retain the outer identity.
-spec rename_locals(term(), names(), #{atom() => literal()}, state()) ->
    {#{atom() => atom()}, state()}.
rename_locals(Body, Outer, Constants, State0) ->
    Locals = lists:sort(
        maps:keys(maps:without(['_' | maps:keys(Outer) ++ maps:keys(Constants)], variables(Body)))
    ),
    lists:foldl(
        fun(Name, {Renamed, Acc}) ->
            {Fresh, Next} = fresh(Acc),
            {Renamed#{Name => Fresh}, Next}
        end,
        {#{}, State0},
        Locals
    ).

%% Constants replace only their own generator binding; patterns retain ordinary matching semantics.
-spec substitute(term(), #{atom() => literal()}, #{atom() => atom()}) -> term().
substitute({var, Line, Name} = Variable, Constants, Names) ->
    case maps:find(Name, Constants) of
        {ok, Value} ->
            erl_parse:abstract(Value, Line);
        error ->
            case maps:find(Name, Names) of
                {ok, Renamed} -> {var, Line, Renamed};
                error -> Variable
            end
    end;
substitute(Tuple, Constants, Names) when is_tuple(Tuple) ->
    list_to_tuple([substitute(Value, Constants, Names) || Value <- tuple_to_list(Tuple)]);
substitute(List, Constants, Names) when is_list(List) ->
    [substitute(Value, Constants, Names) || Value <- List];
substitute(Value, _Constants, _Names) ->
    Value.

%% Fresh compiler names never collide with source or a preceding iteration.
-spec fresh(state()) -> {atom(), state()}.
fresh(State = #{next := Index, used := Used}) ->
    Name = list_to_atom("HlsEntryComprehension" ++ integer_to_list(Index)),
    Next = State#{next := Index + 1},
    case is_map_key(Name, Used) of
        true -> fresh(Next);
        false -> {Name, Next#{used := Used#{Name => true}}}
    end.

%% Collect lexical spellings without interpreting expressions or records.
-spec variables(term()) -> names().
variables({var, _, Name}) ->
    #{Name => true};
variables(Tuple) when is_tuple(Tuple) -> variables(tuple_to_list(Tuple));
variables(List) when is_list(List) ->
    lists:foldl(fun(Value, Names) -> maps:merge(Names, variables(Value)) end, #{}, List);
variables(_) ->
    #{}.
