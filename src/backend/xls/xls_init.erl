-module(xls_init).
-moduledoc false.

-export([clause/2, lower/4, emit/3]).
-export_type([lowered/0]).

-type lowered() :: #{line := non_neg_integer(), body := iodata(),
    result := iodata(), failed := iodata()}.

-spec clause([erl_parse:abstract_form()], hls_gs | hls_statem) ->
    erl_parse:af_clause().

%% Hardware has one compile-time initializer. Per-instance configuration is
%% supplied separately by topology startup messages, before normal input traffic.
clause(Forms, Behaviour) ->
    case xls_parse:find_function(Forms, init, 1) of
        [Clause = {clause, _Line, [{nil, _}], [], _Body}] -> Clause;
        [{clause, Line, Patterns, Guards, _Body}] ->
            error({unsupported_hls_init_head, Behaviour, Line, Patterns, Guards});
        Clauses ->
            error({unsupported_hls_init_clauses, Behaviour, length(Clauses)})
    end.

-spec lower(erl_parse:af_clause(), atom(),
    fun((xls_parse:printable()) -> xls_parse:printable()), map()) -> lowered().
lower(Clause = {clause, Line, _, _, _}, DataName, Postprocess, EnumAtoms) ->
    #{body := Body, result := Result, failed := Failed} =
        xls_parse:clause_outcome(Clause, [], DataName, EnumAtoms),
    #{
        line => Line,
        body => xls_parse:print(Body),
        result => xls_parse:print(Postprocess(Result)),
        failed => xls_parse:print(Failed)
    }.

%% Force evaluation even when only SharedService is instantiated: its RAM
%% population calls the initializer from next(), rather than proc init().
%% A failed match must reject conversion, never become a zero live machine.
-spec emit(string(), string(), lowered()) -> iolist().
emit(Name, Type, #{line := Line, body := Body, result := Result,
        failed := Failed}) ->
    Constant = string:uppercase(Name),
    [
        "// Source init/1, line ", integer_to_list(Line), ".\n",
        "fn ", Name, "_outcome() -> (bool, ", Type, ") {\n",
        xls_parse_io:indent(Body, 2),
        xls_parse_io:indent(["(", Failed, ", ", Result, ")"], 2),
        "}\n",
        "const ", Constant, " = ", Name, "_outcome();\n",
        "const_assert!(!", Constant, ".0);\n\n",
        "fn ", Name, "() -> ", Type, " { ", Constant, ".1 }\n\n"
    ].
