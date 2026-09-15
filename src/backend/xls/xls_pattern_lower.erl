%%%% xls_pattern_lower
%%%%
%%%% Shared lowering for patterns in callback heads and expression clauses.
%%%% Subjects carry both the raw XLS value used for projections and the value
%%%% representation bound to a whole Erlang variable.

-module(xls_pattern_lower).
-moduledoc false.

-include("xls_parse.hrl").

-export([
    lower/3,
    match/3,
    record_argument/3,
    record_pattern_name/1,
    value_argument/1
]).
-export_type([argument/0]).

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

-spec record_pattern_name(erl_parse:af_pattern()) -> atom().
record_pattern_name({record, _Line, Name, _Fields}) ->
    Name;
record_pattern_name({match, _Line, {var, _VarLine, _Name}, Pattern}) ->
    record_pattern_name(Pattern);
record_pattern_name({match, _Line, Pattern, {var, _VarLine, _Name}}) ->
    record_pattern_name(Pattern);
record_pattern_name(Pattern) ->
    error({unsupported_xls_record_pattern, Pattern}).

-spec lower(
    [erl_parse:af_pattern()],
    [argument()],
    xls_parse:clause_state()
) -> {xls_parse:clause_state(), [xls_parse:printable()]}.
lower(Patterns, Arguments, State)
        when length(Patterns) =:= length(Arguments) ->
    Context0 = #{state => State, conditions => []},
    Context1 = lists:foldl(
        fun({Pattern, Argument}, Context) ->
            compile_pattern(Pattern, Argument, Context)
        end,
        Context0,
        lists:zip(Patterns, Arguments)
    ),
    {
        maps:get(state, Context1),
        [Condition || {_Line, Condition} <- lists:reverse(maps:get(conditions, Context1))]
    };
lower(Patterns, Arguments, _State) ->
    error({bad_xls_pattern_arity,
        pattern_line(Patterns), length(Patterns), length(Arguments)}).

%% Assignments use the same projections and equality predicates as clause
%% heads, but a mismatch contributes a failure instead of selecting another arm.
-spec match(erl_parse:af_pattern(), xls_parse:printable(),
    xls_parse:clause_state()) -> xls_parse:clause_state().
match(Pattern, Value, State) ->
    #{state := Bound, conditions := Conditions} = compile_pattern(Pattern,
        value_argument(Value), #{state => State, conditions => []}),
    Checked = lists:foldl(fun({Line, Condition}, Acc) ->
        xls_parse:add_match_failure(["!(", Condition, ")"], Line, Acc)
    end, Bound, lists:reverse(Conditions)),
    xls_parse:reference(Checked, Value).

compile_pattern({var, _Line, '_'}, _Subject, Context) ->
    Context;
compile_pattern({var, Line, Name}, Subject, Context) ->
    bind_or_compare(Name, Line, maps:get(value, Subject), Context);
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
                    error({unsupported_xls_record_pattern_field, Line, Field})
                end,
                Context0,
                Fields
            );
        #{record := Actual} ->
            error({xls_record_pattern_type_mismatch, Line, Name, Actual});
        #{value := Value} ->
            %% Expression values retain the tag alongside the record struct.
            Tagged = add_condition([Value, ".0 == Tag::",
                xls_names:enum_member(Name)], Line, Context0),
            compile_pattern({record, Line, Name, Fields},
                record_argument(Name, [Value, ".1"], Value), Tagged)
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
compile_pattern({integer, Line, Integer}, Subject, Context) ->
    add_condition(
        [maps:get(raw, Subject), " == ", integer_to_list(Integer)],
        Line, Context
    );
compile_pattern({atom, Line, true}, Subject, Context) ->
    add_condition([maps:get(raw, Subject), " == bool:true"], Line, Context);
compile_pattern({atom, Line, false}, Subject, Context) ->
    add_condition([maps:get(raw, Subject), " == bool:false"], Line, Context);
compile_pattern({atom, Line, Atom}, Subject,
        Context = #{state := #clause_state{enum_atoms = EnumAtoms}}) ->
    Encoded = maps:get(
        Atom,
        EnumAtoms,
        xls_names:enum_member(Atom)
    ),
    add_condition([maps:get(raw, Subject), " == ", Encoded], Line, Context);
compile_pattern({op, Line, '-', {integer, _, Integer}}, Subject, Context) ->
    compile_pattern({integer, Line, -Integer}, Subject, Context);
compile_pattern({op, Line, '+', {integer, _, Integer}}, Subject, Context) ->
    compile_pattern({integer, Line, Integer}, Subject, Context);
compile_pattern(Pattern = {cons, Line, _, _}, Subject, Context) ->
    compile_list(Pattern, Line, Subject, 0, Context);
compile_pattern({nil, Line}, #{raw := Raw}, Context) ->
    add_condition(["array_size(", Raw, ") == u32:0"], Line, Context);
compile_pattern(Pattern, _Subject, _Context) ->
    error({unsupported_xls_pattern, Pattern}).

%% A short array still needs well-typed projections in the unselected body.
%% Length predicates prevent these placeholder values from matching.
compile_list({cons, _, Head, Tail}, Line, Subject = #{raw := Raw}, Offset, Context) ->
    Element = [Raw, "[u32:", integer_to_list(Offset), " % array_size(", Raw, ")]"],
    Next = compile_pattern(Head, value_argument(Element), Context),
    compile_list(Tail, Line, Subject, Offset + 1, Next);
compile_list({nil, _}, Line, #{raw := Raw}, Offset, Context) ->
    add_condition(["array_size(", Raw, ") == u32:", integer_to_list(Offset)], Line, Context);
compile_list({var, _, '_'}, Line, #{raw := Raw}, Offset, Context) ->
    add_condition(["array_size(", Raw, ") >= u32:", integer_to_list(Offset)], Line, Context);
compile_list(Pattern = {var, _, _}, Line, #{raw := Raw}, Offset, Context) ->
    Next = add_condition(["array_size(", Raw, ") >= u32:", integer_to_list(Offset)], Line, Context),
    Tail = ["hls_patterns::tail<u32:", integer_to_list(Offset), ">(", Raw, ")"],
    compile_pattern(Pattern, value_argument(Tail), Next);
compile_list({match, _, Left, Right}, Line, Subject, Offset, Context) ->
    Next = compile_list(Left, Line, Subject, Offset, Context),
    compile_list(Right, Line, Subject, Offset, Next);
compile_list(Pattern, _Line, _Subject, _Offset, _Context) ->
    error({unsupported_xls_list_tail_pattern, Pattern}).

bind_or_compare(Name, Line, Value, Context = #{state := State}) ->
    case xls_parse:find_binding(Name, Line, State) of
        {ok, Bound} -> add_condition([Bound, " == ", Value], Line, Context);
        error -> Context#{state := xls_parse:bind(Name, Line, Value, State)}
    end.

add_condition(Condition, Line, Context = #{conditions := Conditions}) ->
    Context#{conditions := [{Line, Condition} | Conditions]}.

pattern_line([Pattern | _]) when is_tuple(Pattern), tuple_size(Pattern) >= 2 ->
    element(2, Pattern);
pattern_line(_Patterns) ->
    undefined.
