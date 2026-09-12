-module(xls_var_scope_tests).
-include_lib("eunit/include/eunit.hrl").

unsafe_variables_are_rejected_test_() ->
    [?_assertException(error, {unsafe_xls_variable, _, 'Value', _}, lower(Source))
        || Source <- [
            "f(X) -> case X of true -> Value = X; false -> X end, Value.",
            "f(X) -> case X of true -> Value = X; false -> X end, Value = X.",
            "f(X) -> case X of true -> Value = X; false -> X end, case X of Value -> X; _ -> X end.",
            "f(X) -> if X =:= true -> Value = X; true -> X end, Value.",
            "f(X) -> X andalso (Value = X), Value.",
            "f(X) -> X orelse (Value = X), Value.",
            "f(X) -> case X of true -> case X of true -> Value = X; false -> X end; false -> Value = X end, Value."
        ]].

unbound_variable_has_source_diagnostic_test() ->
    ?assertError({unbound_xls_variable, 2, 'Missing'}, lower("f(X) ->\n Missing." )).

unsafe_diagnostic_identifies_join_test() ->
    ?assertError({unsafe_xls_variable, 5, 'Value', 2}, lower(
        "f(X) ->\ncase X of\ntrue -> Value = X;\nfalse -> X end,\nValue." )).

exports_only_names_used_after_join_test() ->
    Xls = lower("f(X) -> case X of true -> Kept = X, Local = X; "
        "false -> Local = X, Kept = X end, Kept."),
    ?assertEqual(3, length(binary:matches(Xls, <<"let Kept_1">>))),
    ?assertEqual(2, length(binary:matches(Xls, <<"let Local_1">>))).

later_match_is_a_use_test() ->
    Xls = lower("f(X) -> case X of true -> Value = X; false -> Value = X end, Value = X."),
    ?assertNotEqual(nomatch, binary:match(Xls, <<"Value_1 != Value_2">>)).

%% A case can occur inside an expression, not just at the top of a body.
expression_continuations_export_bindings_test_() ->
    [?_assertEqual(3, length(binary:matches(lower(Source), <<"let Value_1">>)))
        || Source <- [
            "f(X) -> {case X of true -> Value = X; false -> Value = X end, X}, Value.",
            "f(X) -> (case X of true -> Value = X; false -> Value = X end) =:= X, Value.",
            "f(X) -> Value = case X of true -> Value = X; false -> Value = X end."
        ]].

lower(Source) ->
    {ok, Tokens, _} = erl_scan:string(Source),
    {ok, {function, _, _, _, [Clause]}} = erl_parse:parse_form(Tokens),
    #{body := Body, result := Value, failed := Failed} =
        xls_parse:clause_outcome(Clause, ["x"], cell, #{}),
    iolist_to_binary(xls_parse:print([Body, "(", Value, ", ", Failed, ")"])).
