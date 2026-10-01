%%%% Preserve signature- and field-directed literal types before expression flattening.
-module(xls_literal_types).
-moduledoc false.

-export([clauses/3, format/1]).
-export_type([type/0]).

-doc "A concrete helper type, retaining tuple structure for literal context.".
-type type() :: {dslx, iodata()} | {provider, hls_type:descriptor()} | {tuple, [type()]}.
%% Source declarations are resolved only for fields constructed by hardware code.
-type records() :: #{atom() => #{atom() => erl_parse:abstract_type()}}.
%% No context means XLS must infer the expression's type from other uses.
-type expected() :: unknown | type() | {tuple, [expected()]}.
%% Requirements on single-assignment source variables from their consumers.
-type requirements() :: #{atom() => expected()}.

-doc "Prints a concrete helper type as DSLX.".
-spec format(type()) -> iodata().
format({dslx, Text}) -> Text;
format({provider, Type}) -> hls_type:print_type(Type);
format({tuple, Fields}) -> ["(", [[format(T), ", "] || T <- Fields], ")"].

-doc "Annotates integer literals from helper signatures and record fields through bindings, tuples and branches; does not cast existing values.".
-spec clauses([erl_parse:abstract_clause()], expected(), [hls_source:form()]) ->
    [erl_parse:abstract_clause()].
clauses(Clauses, Result, Forms) ->
    Records = maps:from_list([{Name, maps:from_list([
        {xls_parse:record_field_name(Field), Type}
        || {typed_record_field, Field, Type} <- Fields])}
        || {attribute, _, record, {Name, Fields}} <- Forms]),
    [Clause || Source <- Clauses, {Clause, _} <- [clause(Source, Result, #{}, Records)]].

%% Each clause has its own scope; guards cannot export new bindings.
-spec clause(erl_parse:abstract_clause(), expected(), requirements(), records()) ->
    {erl_parse:abstract_clause(), requirements()}.
clause({clause, Line, Patterns, Guards, Body}, Result, After, Records) ->
    {Typed, Before} = sequence(Body, Result, After, Records),
    {{clause, Line, Patterns, Guards, Typed}, Before}.

%% Visit consumers before definitions, preserving source evaluation order.
-spec sequence([erl_parse:abstract_expr()], expected(), requirements(), records()) ->
    {[erl_parse:abstract_expr()], requirements()}.
sequence(Expressions, Result, After, Records) ->
    {Typed, {_, Before}} = lists:mapfoldr(fun(Expression, {Expected, Needs}) ->
        {Next, Previous} = expression(Expression, Expected, Needs, Records),
        {Next, {unknown, Previous}}
    end, {Result, After}, Expressions),
    {Typed, Before}.

%% Requirements guide literals only. XLS still checks every use of a value,
%% including incompatible signatures; no truncation or sign conversion occurs.
-spec expression(erl_parse:abstract_expr(), expected(), requirements(), records()) ->
    {erl_parse:abstract_expr(), requirements()}.
expression({xls_expected, _, Type, Value}, _Expected, Needs, Records) ->
    expression(Value, Type, Needs, Records);
expression({var, _, Name} = Variable, Type, Needs, _Records) when Name =/= '_', Type =/= unknown ->
    {Variable, Needs#{Name => merge_type(Type, maps:get(Name, Needs, unknown))}};
expression({integer, Line, Value}, Type, Needs, _Records) when Type =/= unknown ->
    {literal(Line, Value, Type), Needs};
expression({char, Line, Value}, Type, Needs, _Records) when Type =/= unknown ->
    {literal(Line, Value, Type), Needs};
expression({op, Line, Sign, {integer, _, Value}}, Type, Needs, _Records)
        when Type =/= unknown, (Sign =:= '+' orelse Sign =:= '-') ->
    Signed = case Sign of '+' -> Value; '-' -> -Value end,
    {literal(Line, Signed, Type), Needs};
expression({match, Line, Pattern, Value}, Expected, Needs, Records) ->
    Type = pattern_type(Pattern, Expected, Needs),
    {Typed, Before} = expression(Value, Type, Needs, Records),
    {{match, Line, Pattern, Typed}, Before};
expression({tuple, Line, Values}, {tuple, Types}, Needs, Records) when length(Values) =:= length(Types) ->
    {Typed, Before} = arguments(Values, Types, Needs, Records),
    {{tuple, Line, Typed}, Before};
expression({record, Line, Name, Fields}, _Expected, Needs, Records) ->
    {Typed, Before} = fields(Name, Fields, Needs, Records),
    {{record, Line, Name, Typed}, Before};
expression({record, Line, Base, Name, Fields}, _Expected, Needs, Records) ->
    {Typed, FieldNeeds} = fields(Name, Fields, Needs, Records),
    {Input, Before} = expression(Base, unknown, FieldNeeds, Records),
    {{record, Line, Input, Name, Typed}, Before};
expression({block, Line, Body}, Expected, Needs, Records) ->
    {Typed, Before} = sequence(Body, Expected, Needs, Records),
    {{block, Line, Typed}, Before};
expression({'case', Line, Subject, Clauses}, Expected, Needs, Records) ->
    {Typed, BranchNeeds} = branches(Clauses, Expected, Needs, Records),
    {Input, Before} = expression(Subject, unknown, BranchNeeds, Records),
    {{'case', Line, Input, Typed}, Before};
expression({'if', Line, Clauses}, Expected, Needs, Records) ->
    {Typed, Before} = branches(Clauses, Expected, Needs, Records),
    {{'if', Line, Typed}, Before};
expression({op, Line, Op, Left, Right}, Expected, Needs, Records) ->
    Types = case Op of
        '+' -> [Expected, Expected]; '-' -> [Expected, Expected];
        '*' -> [Expected, Expected]; 'div' -> [Expected, Expected];
        'rem' -> [Expected, Expected]; 'band' -> [Expected, Expected];
        'bor' -> [Expected, Expected]; 'bxor' -> [Expected, Expected];
        'bsl' -> [Expected, unknown]; 'bsr' -> [Expected, unknown];
        _ -> [unknown, unknown]
    end,
    {Typed, Before} = arguments([Left, Right], Types, Needs, Records),
    [A, B] = Typed,
    {{op, Line, Op, A, B}, Before};
expression({op, Line, Op, Value}, Expected, Needs, Records) when Op =:= '+'; Op =:= '-'; Op =:= 'bnot' ->
    {Typed, Before} = expression(Value, Expected, Needs, Records),
    {{op, Line, Op, Typed}, Before};
expression(Tuple, _Expected, Needs, Records) when is_tuple(Tuple) ->
    {Typed, Before} = untyped(tuple_to_list(Tuple), Needs, Records),
    {list_to_tuple(Typed), Before};
expression(List, _Expected, Needs, Records) when is_list(List) -> untyped(List, Needs, Records);
expression(Value, _Expected, Needs, _Records) -> {Value, Needs}.

%% DSLX accepts some out-of-range signed literals as bit patterns. A helper
%% or field contract requires the same value: wrapping must remain explicit.
-spec literal(erl_anno:location(), integer(), expected()) -> erl_parse:abstract_expr().
literal(Line, Value, {provider, Type} = Context) ->
    try hls_type:pack_exact(Value, Type) of
        _Packed -> {xls_typed_integer, Line, format(Context), Value}
    catch error:Reason -> error({xls_literal_type, Line, Value, Type, Reason})
    end;
literal(Line, Value, _Type) -> {integer, Line, Value}.

%% A later use constrains an initializer, including selected tuple fields;
%% unconstrained siblings keep their own inference rules.
-spec pattern_type(erl_parse:abstract_expr(), expected(), requirements()) -> expected().
pattern_type({var, _, Name}, Expected, Needs) ->
    merge_type(maps:get(Name, Needs, unknown), Expected);
pattern_type({match, _, Left, Right}, Expected, Needs) ->
    pattern_type(Left, pattern_type(Right, Expected, Needs), Needs);
pattern_type({tuple, _, Fields}, Expected, Needs) ->
    Defaults = case Expected of
        {tuple, Defaults0} when length(Defaults0) =:= length(Fields) -> Defaults0;
        _ -> lists:duplicate(length(Fields), unknown)
    end,
    Types = [pattern_type(Pattern, Default, Needs)
        || {Pattern, Default} <- lists:zip(Fields, Defaults)],
    {tuple, Types};
pattern_type(_, Expected, _) -> Expected.

%% Branch-local requirements do not flow into sibling branches. Requirements
%% on outer bindings meet before the subject; conflicting uses remain errors.
-spec branches([erl_parse:abstract_clause()], expected(), requirements(), records()) ->
    {[erl_parse:abstract_clause()], requirements()}.
branches(Clauses, Expected, Needs, Records) ->
    Results = [clause(Clause, Expected, Needs, Records) || Clause <- Clauses],
    {[Typed || {Typed, _} <- Results],
        lists:foldl(fun({_, Before}, Acc) ->
            maps:merge_with(fun(_Name, A, B) -> merge_type(B, A) end, Acc, Before)
        end, Needs, Results)}.

%% Arguments retain left-to-right evaluation; only the analysis runs backward.
-spec arguments([erl_parse:abstract_expr()], [expected()], requirements(), records()) ->
    {[erl_parse:abstract_expr()], requirements()}.
arguments(Values, Types, Needs, Records) ->
    lists:mapfoldr(fun({Value, Type}, Acc) -> expression(Value, Type, Acc, Records) end,
        Needs, lists:zip(Values, Types)).

%% Traverse other syntax for explicitly typed helper calls without assuming
%% provider argument types, comparison widths, or static type parameters.
-spec untyped([erl_parse:abstract_expr()], requirements(), records()) ->
    {[erl_parse:abstract_expr()], requirements()}.
untyped(Values, Needs, Records) -> arguments(Values, lists:duplicate(length(Values), unknown), Needs, Records).

%% Record syntax identifies the declaration even when the whole record has no
%% expected type. Pattern fields are deliberately excluded by clause/match.
-spec fields(atom(), [erl_parse:abstract_expr()], requirements(), records()) ->
    {[erl_parse:abstract_expr()], requirements()}.
fields(Name, Fields, Needs, Records) ->
    Types = maps:get(Name, Records),
    lists:mapfoldr(fun({record_field, Line, Field = {atom, _, Slot}, Value}, Acc) ->
        Type = {provider, hls_type:descriptor(maps:get(Slot, Types))},
        {Typed, Before} = expression(Value, Type, Acc, Records),
        {{record_field, Line, Field, Typed}, Before}
    end, Needs, Fields).

%% Separate consumers can constrain disjoint tuple fields. For incompatible
%% concrete types, retain one requirement and let XLS reject the other use.
-spec merge_type(expected(), expected()) -> expected().
merge_type(unknown, Type) -> Type;
merge_type({tuple, Left}, {tuple, Right}) when length(Left) =:= length(Right) ->
    {tuple, [merge_type(A, B) || {A, B} <- lists:zip(Left, Right)]};
merge_type(Type, _Other) -> Type.
