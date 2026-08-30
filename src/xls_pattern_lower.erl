%%%% xls_pattern_lower
%%%%
%%%% Shared lowering for patterns in callback heads and expression clauses.
%%%% Subjects carry both the raw XLS value used for projections and the value
%%%% representation bound to a whole Erlang variable.

-module(xls_pattern_lower).
-moduledoc false.

-include("xls_parse.hrl").

-export([
    compile/3,
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

-spec compile(
    [erl_parse:af_pattern()],
    [argument()],
    xls_parse:clause_state()
) -> {xls_parse:clause_state(), [xls_parse:printable()]}.
compile(Patterns, Arguments, State)
        when length(Patterns) =:= length(Arguments) ->
    Context0 = #{state => State, bindings => #{}, conditions => []},
    Context1 = lists:foldl(
        fun({Pattern, Argument}, Context) ->
            compile_pattern(Pattern, Argument, Context)
        end,
        Context0,
        lists:zip(Patterns, Arguments)
    ),
    {
        maps:get(state, Context1),
        lists:reverse(maps:get(conditions, Context1))
    };
compile(Patterns, Arguments, _State) ->
    error({bad_xls_pattern_arity,
        pattern_line(Patterns), length(Patterns), length(Arguments)}).

compile_pattern({var, _Line, '_'}, _Subject, Context) ->
    Context;
compile_pattern({var, _Line, Name}, Subject, Context) ->
    bind_or_compare(Name, maps:get(value, Subject), Context);
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
        _ ->
            error({unsupported_nested_xls_record_pattern, Line, Name})
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
compile_pattern({integer, _Line, Integer}, Subject, Context) ->
    add_condition(
        [maps:get(raw, Subject), " == ", integer_to_list(Integer)],
        Context
    );
compile_pattern({atom, _Line, true}, Subject, Context) ->
    add_condition([maps:get(raw, Subject), " == bool:true"], Context);
compile_pattern({atom, _Line, false}, Subject, Context) ->
    add_condition([maps:get(raw, Subject), " == bool:false"], Context);
compile_pattern({atom, _Line, Atom}, Subject,
        Context = #{state := #clause_state{enum_atoms = EnumAtoms}}) ->
    Encoded = maps:get(
        Atom,
        EnumAtoms,
        string:uppercase(atom_to_list(Atom))
    ),
    add_condition([maps:get(raw, Subject), " == ", Encoded], Context);
compile_pattern(Pattern, _Subject, _Context) ->
    error({unsupported_xls_pattern, Pattern}).

bind_or_compare(Name, Value,
        Context = #{state := State, bindings := Bindings}) ->
    case maps:find(Name, Bindings) of
        {ok, Bound} ->
            add_condition([Bound, " == ", Value], Context);
        error ->
            case prebound_name(Name, State) of
                {ok, Bound} ->
                    add_condition([Bound, " == ", Value], Context);
                error ->
                    {EmittedName, State1} = xls_parse:uniquify(State, Name),
                    State2 = xls_parse:instr(State1, EmittedName, Value),
                    Context#{
                        state := State2,
                        bindings := Bindings#{Name => EmittedName}
                    }
            end
    end.

prebound_name(Name, #clause_state{named_counters = Counters}) ->
    Base = atom_to_list(Name),
    case maps:is_key(Base, Counters) of
        true -> {ok, Base ++ "_1"};
        false -> error
    end.

add_condition(Condition, Context = #{conditions := Conditions}) ->
    Context#{conditions := [Condition | Conditions]}.

pattern_line([Pattern | _]) when is_tuple(Pattern), tuple_size(Pattern) >= 2 ->
    element(2, Pattern);
pattern_line(_Patterns) ->
    undefined.
