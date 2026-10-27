-module(xls_init).
-moduledoc false.

-export([clause/2, lower/4, emit/3]).
-export_type([lowered/0]).

-doc "Initialization retains its selected failure references until module allocation.".
-type lowered() :: #{line := non_neg_integer(), body := xls_dslx:value(),
    result := xls_dslx:value(), failed := xls_dslx:value()}.

-doc "Returns the sole init([]) clause; rejects guards, other heads and multiple initializers.".
-spec clause([hls_source:form()], hls_gs | hls_statem) ->
    erl_parse:abstract_clause().

%% Hardware has one compile-time initializer. Per-instance configuration is
%% supplied separately by topology startup messages, before normal input traffic.
clause(Forms, Behaviour) ->
    case hls_source:find_function(Forms, init, 1) of
        [Clause = {clause, _Line, [{nil, _}], [], _Body}] -> Clause;
        [{clause, Line, Patterns, Guards, _Body}] ->
            error({unsupported_hls_init_head, Behaviour, Line, Patterns, Guards});
        Clauses ->
            error({unsupported_hls_init_clauses, Behaviour, length(Clauses)})
    end.

-doc "Lowers initialization to its source line, statements, postprocessed value and failure expression.".
-spec lower(erl_parse:abstract_clause(), atom(),
    fun((xls_clause_lower:printable()) -> xls_clause_lower:printable()), map()) -> lowered().
lower(Clause = {clause, Line, _, _, _}, DataName, Postprocess, EnumAtoms) ->
    #{body := Body, result := Result, failed := Failed} =
        xls_clause_lower:clause_outcome(Clause, [], DataName, EnumAtoms),
    #{
        line => erl_anno:line(Line),
        body => Body,
        result => Postprocess(Result),
        failed => Failed
    }.

-doc "Emits an initializer that rejects failed matches during DSLX conversion.".
%% Evaluate the outcome as a constant even if the caller runs after proc init().
-spec emit(string(), string(), lowered()) -> xls_dslx:value().
emit(Name, Type, #{line := Line, body := Body, result := Result,
        failed := Failed}) ->
    Constant = string:uppercase(Name),
    [
        "fn ", Name, "_outcome() -> (bool, ", Type, ") {  // L",
        integer_to_list(Line), "\n",
        xls_dslx:indent(Body, 2),
        xls_dslx:indent(["(", Failed, ", ", Result, ")"], 2),
        "}\n",
        "const ", Constant, " = ", Name, "_outcome();\n",
        "const_assert!(!", Constant, ".0);\n\n",
        "fn ", Name, "() -> ", Type, " { ", Constant, ".1 }\n\n"
    ].
