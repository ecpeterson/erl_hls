-module(xls_callback_result_tests).
-include_lib("eunit/include/eunit.hrl").

aliases_preserve_evaluation_and_values_test() ->
    equivalent("Result = {ok, stamp(first, 1), {stamp(second, 2), stamp(third, 3)}}, "
        "Alias = Result, stamp(between, 0), Alias"),
    equivalent("Xls_result_0 = stamp(first, 1), "
        "Result = {ok, Xls_result_0, stamp(second, 2)}, Result"),
    equivalent("Phase = boot, Alias = Phase, Result = {ok, Alias, stamp(data, 1)}, Result").

selected_choices_keep_local_bindings_and_failures_test() ->
    lists:foreach(fun(Select) ->
        equivalent("Result = case stamp(choice, " ++ atom_to_list(Select) ++ ") of "
            "true -> X = stamp(local, 1), Local = {ok, boot, X}, Local; "
            "false -> true = stamp(failure, false), {ok, boot, 2} end, "
            "stamp(after_choice, 3), Alias = Result, Alias"),
        equivalent("Result = if " ++ atom_to_list(Select) ++ " -> "
            "{ok, boot, stamp(data, 1)} end, stamp(after_choice, 2), Result"),
        equivalent("Result = {ok, boot, stamp(data, 1)}, "
            "case stamp(choice, " ++ atom_to_list(Select) ++ ") of "
            "true -> Result; false -> {ok, boot, 2} end")
    end, [true, false]).

unrelated_refutable_products_are_preserved_test() ->
    lists:foreach(fun(Value) ->
        equivalent("Pair = {stamp(first, 1), stamp(second, 2)}, "
            "Pair = {stamp(third, 1), stamp(fourth, " ++ integer_to_list(Value) ++ ")}, "
            "Result = {ok, boot, stamp(data, 0)}, Result")
    end, [2, 3]).

pattern_bound_variables_keep_their_equality_checks_test() ->
    equivalent("Result = case stamp(subject, {ok, 1}) of "
        "{ok, Data} -> Data = {stamp(first, 2), stamp(second, 3)}, "
        "{ok, boot, Data} end, Result"),
    equivalent("case stamp(subject, {ok, 1}) of {ok, Data} -> Data end, "
        "Data = {stamp(first, 2), stamp(second, 3)}, "
        "Result = {ok, boot, Data}, Result").

bindings_inside_a_captured_value_remain_bound_test() ->
    equivalent("Result = {ok, boot, Data = stamp(first, 1)}, "
        "Data = {stamp(second, 2), stamp(third, 3)}, "
        "Final = {ok, boot, Data}, case true of true -> Result; false -> Final end"),
    equivalent("Result = case true of true -> Data = 1, {ok, boot, Data}; "
        "false -> Data = 2, {ok, boot, Data} end, "
        "Data = {stamp(first, 2), stamp(second, 3)}, {ok, boot, Data}"),
    equivalent("Result = case true of "
        "true -> Phase = boot, {ok, Phase, 1}; "
        "false -> Phase = active, {ok, Phase, 2} end, "
        "stamp(phase, Phase), Result").

constructor_origins_survive_aliases_test() ->
    Clause = clause("Result = case true of\n"
        "true -> Local = {boot, 1, fail}, Local;\n"
        "false -> {repeat_phase, 2, consume}\n"
        "end,\nAlias = Result,\nAlias"),
    Results = xls_callback_result:results(Clause),
    ?assertMatch([{tuple, 2, _}, {tuple, 3, _}], Results).

fresh_products_capture_fields_before_destructuring_test() ->
    equivalent("{Phase, {Data, _}} = case stamp(choice, true) of "
        "true -> {repeat_phase, {stamp(first, 1), stamp(second, 2)}}; "
        "false -> {active, {0, 0}} end, stamp(after_choice, Data), "
        "{Phase, Data, consume}"),
    equivalent("Result = {boot, stamp(data, 1)}, "
        "{Phase, Data} = Result, Data = stamp(match, 2), {Phase, Data, consume}"),
    equivalent("{Phase, Data} = {boot, Phase = stamp(match, active)}, "
        "{Phase, Data, consume}").

structural_rebinding_is_rejected_test() ->
    ?assertException(error, {unsupported_callback_result_binding, _},
        normalize(clause("Result = {ok, boot, 1}, Result = {ok, boot, 2}, Result"))).

structural_expansion_is_bounded_test() ->
    Bindings = ["R" ++ integer_to_list(N) ++ " = case true of "
        "true -> {ok, boot, 1}; false -> {ok, boot, 2} end, "
        || N <- lists:seq(1, 9)],
    Result = "{" ++ lists:flatten(lists:join(",", ["R" ++ integer_to_list(N)
        || N <- lists:seq(1, 9)])) ++ "}",
    ?assertError({too_many_callback_result_paths, 256},
        normalize(clause(lists:flatten(Bindings) ++ Result))).

%% Execute both source and normalized Erlang, independently of XLS's optimizer.
%% Observable stamps expose duplication, reordering, and dropped eager work;
%% the exception and prefix of stamps must agree as well as successful values.
equivalent(Body) ->
    Original = clause(Body),
    ?assertEqual(evaluate(Original), evaluate(normalize(Original))).

normalize(Clause) -> xls_callback_result:map(Clause, fun(Value) -> Value end).

clause(Body) ->
    {ok, Tokens, _} = erl_scan:string("callback() -> " ++ Body ++ "."),
    {ok, {function, _, callback, 0, [Clause]}} = erl_parse:parse_form(Tokens),
    Clause.

evaluate({clause, _, [], [], Body}) ->
    put(callback_evaluations, []),
    try
        Outcome = try erl_eval:exprs(Body, erl_eval:new_bindings(), {value,
            fun(stamp, [Name, Value]) ->
                put(callback_evaluations, [Name | get(callback_evaluations)]),
                Value
            end}) of
            {value, Value, _} -> {ok, Value}
        catch error:Reason -> {error, Reason}
        end,
        {Outcome, lists:reverse(get(callback_evaluations))}
    after
        erase(callback_evaluations)
    end.
