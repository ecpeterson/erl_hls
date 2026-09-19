%%%% Preserve signature-directed literal types before expression flattening.
-module(xls_literal_types).
-moduledoc false.

-export([clauses/2, format/1]).
-export_type([type/0]).

-doc "A concrete helper type, retaining tuple structure for literal context.".
-type type() :: {dslx, iodata()} | {provider, hls_type:descriptor()} | {tuple, [type()]}.
%% No context means XLS must infer the expression's type from other uses.
-type expected() :: unknown | type().
%% Requirements on single-assignment source variables from their consumers.
-type requirements() :: #{atom() => type()}.

-doc "Prints a concrete helper type as DSLX.".
-spec format(type()) -> iodata().
format({dslx, Text}) -> Text;
format({provider, Type}) -> hls_type:print_type(Type);
format({tuple, Fields}) -> ["(", [[format(T), ", "] || T <- Fields], ")"].

-doc "Annotates integer literals from helper signatures through bindings, tuples and branches; does not cast existing values.".
-spec clauses([erl_parse:abstract_clause()], expected()) -> [erl_parse:abstract_clause()].
clauses(Clauses, Result) ->
    [Clause || Source <- Clauses, {Clause, _} <- [clause(Source, Result, #{})]].

%% Each clause has its own scope; guards cannot export new bindings.
-spec clause(erl_parse:abstract_clause(), expected(), requirements()) ->
    {erl_parse:abstract_clause(), requirements()}.
clause({clause, Line, Patterns, Guards, Body}, Result, After) ->
    {Typed, Before} = sequence(Body, Result, After),
    {{clause, Line, Patterns, Guards, Typed}, Before}.

%% Visit consumers before definitions, preserving source evaluation order.
-spec sequence([erl_parse:abstract_expr()], expected(), requirements()) ->
    {[erl_parse:abstract_expr()], requirements()}.
sequence(Expressions, Result, After) ->
    {Typed, {_, Before}} = lists:mapfoldr(fun(Expression, {Expected, Needs}) ->
        {Next, Previous} = expression(Expression, Expected, Needs),
        {Next, {unknown, Previous}}
    end, {Result, After}, Expressions),
    {Typed, Before}.

%% Requirements guide literals only. XLS still checks every use of a value,
%% including incompatible signatures; no truncation or sign conversion occurs.
-spec expression(erl_parse:abstract_expr(), expected(), requirements()) ->
    {erl_parse:abstract_expr(), requirements()}.
expression({xls_expected, _, Type, Value}, _Expected, Needs) ->
    expression(Value, Type, Needs);
expression({var, _, Name} = Variable, Type, Needs) when Name =/= '_', Type =/= unknown ->
    {Variable, Needs#{Name => Type}};
expression({integer, Line, Value}, Type, Needs) when Type =/= unknown ->
    {literal(Line, Value, Type), Needs};
expression({char, Line, Value}, Type, Needs) when Type =/= unknown ->
    {literal(Line, Value, Type), Needs};
expression({op, Line, Sign, {integer, _, Value}}, Type, Needs)
        when Type =/= unknown, (Sign =:= '+' orelse Sign =:= '-') ->
    Signed = case Sign of '+' -> Value; '-' -> -Value end,
    {literal(Line, Signed, Type), Needs};
expression({match, Line, Pattern, Value}, Expected, Needs) ->
    Type = pattern_type(Pattern, Expected, Needs),
    {Typed, Before} = expression(Value, Type, Needs),
    {{match, Line, Pattern, Typed}, Before};
expression({tuple, Line, Values}, {tuple, Types}, Needs) when length(Values) =:= length(Types) ->
    {Typed, Before} = arguments(Values, Types, Needs),
    {{tuple, Line, Typed}, Before};
expression({block, Line, Body}, Expected, Needs) ->
    {Typed, Before} = sequence(Body, Expected, Needs),
    {{block, Line, Typed}, Before};
expression({'case', Line, Subject, Clauses}, Expected, Needs) ->
    {Typed, BranchNeeds} = branches(Clauses, Expected, Needs),
    {Input, Before} = expression(Subject, unknown, BranchNeeds),
    {{'case', Line, Input, Typed}, Before};
expression({'if', Line, Clauses}, Expected, Needs) ->
    {Typed, Before} = branches(Clauses, Expected, Needs),
    {{'if', Line, Typed}, Before};
expression({op, Line, Op, Left, Right}, Expected, Needs) ->
    Types = case Op of
        '+' -> [Expected, Expected]; '-' -> [Expected, Expected];
        '*' -> [Expected, Expected]; 'div' -> [Expected, Expected];
        'rem' -> [Expected, Expected]; 'band' -> [Expected, Expected];
        'bor' -> [Expected, Expected]; 'bxor' -> [Expected, Expected];
        'bsl' -> [Expected, unknown]; 'bsr' -> [Expected, unknown];
        _ -> [unknown, unknown]
    end,
    {Typed, Before} = arguments([Left, Right], Types, Needs),
    [A, B] = Typed,
    {{op, Line, Op, A, B}, Before};
expression({op, Line, Op, Value}, Expected, Needs) when Op =:= '+'; Op =:= '-'; Op =:= 'bnot' ->
    {Typed, Before} = expression(Value, Expected, Needs),
    {{op, Line, Op, Typed}, Before};
expression(Tuple, _Expected, Needs) when is_tuple(Tuple) ->
    {Typed, Before} = untyped(tuple_to_list(Tuple), Needs),
    {list_to_tuple(Typed), Before};
expression(List, _Expected, Needs) when is_list(List) -> untyped(List, Needs);
expression(Value, _Expected, Needs) -> {Value, Needs}.

%% DSLX accepts some out-of-range signed literals as bit patterns. A helper
%% contract instead requires the same value: wrapping must remain explicit.
-spec literal(erl_anno:location(), integer(), type()) -> erl_parse:abstract_expr().
literal(Line, Value, {provider, Type} = Context) ->
    try hls_type:pack_exact(Value, Type) of
        _Packed -> {xls_typed_integer, Line, format(Context), Value}
    catch error:Reason -> error({xls_literal_type, Line, Value, Type, Reason})
    end;
literal(Line, Value, _Type) -> {integer, Line, Value}.

%% A variable's later use constrains its initializer. Whole tuple patterns
%% propagate context only when every field has a known type.
-spec pattern_type(erl_parse:abstract_expr(), expected(), requirements()) -> expected().
pattern_type({var, _, Name}, Expected, Needs) -> maps:get(Name, Needs, Expected);
pattern_type({match, _, Left, Right}, Expected, Needs) ->
    pattern_type(Left, pattern_type(Right, Expected, Needs), Needs);
pattern_type({tuple, _, Fields}, Expected, Needs) ->
    Defaults = case Expected of
        {tuple, Defaults0} when length(Defaults0) =:= length(Fields) -> Defaults0;
        _ -> lists:duplicate(length(Fields), unknown)
    end,
    Types = [pattern_type(Pattern, Default, Needs)
        || {Pattern, Default} <- lists:zip(Fields, Defaults)],
    case lists:member(unknown, Types) of true -> Expected; false -> {tuple, Types} end;
pattern_type(_, Expected, _) -> Expected.

%% Branch-local requirements do not flow into sibling branches. Requirements
%% on outer bindings meet before the subject; conflicting uses remain errors.
-spec branches([erl_parse:abstract_clause()], expected(), requirements()) ->
    {[erl_parse:abstract_clause()], requirements()}.
branches(Clauses, Expected, Needs) ->
    Results = [clause(Clause, Expected, Needs) || Clause <- Clauses],
    {[Typed || {Typed, _} <- Results],
        lists:foldl(fun({_, Before}, Acc) -> maps:merge(Acc, Before) end, Needs, Results)}.

%% Arguments retain left-to-right evaluation; only the analysis runs backward.
-spec arguments([erl_parse:abstract_expr()], [expected()], requirements()) ->
    {[erl_parse:abstract_expr()], requirements()}.
arguments(Values, Types, Needs) ->
    lists:mapfoldr(fun({Value, Type}, Acc) -> expression(Value, Type, Acc) end,
        Needs, lists:zip(Values, Types)).

%% Traverse other syntax for explicitly typed helper calls without assuming
%% provider argument types, comparison widths, or static type parameters.
-spec untyped([erl_parse:abstract_expr()], requirements()) ->
    {[erl_parse:abstract_expr()], requirements()}.
untyped(Values, Needs) -> arguments(Values, lists:duplicate(length(Values), unknown), Needs).
