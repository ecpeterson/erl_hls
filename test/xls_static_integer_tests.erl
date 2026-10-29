-module(xls_static_integer_tests).
-moduledoc "Checks compile-time integer evaluation before a hardware type boundary, without widening typed arithmetic or discarding selected failures.".
-include_lib("eunit/include/eunit.hrl").

%% Untyped Erlang integers retain mathematical values through nested operations.
-spec nested_static_arithmetic_test_() -> [term()].
nested_static_arithmetic_test_() ->
    [?_test(assert_static(Expression, Expected)) || {Expression, Expected} <- [
        {"1 - (2 + 3)", -4},
        {"(2 - 5) * (7 + 1)", -24},
        {"-23 div (2 + 3)", -4},
        {"-23 rem (2 + 3)", -3},
        {"((15 band 6) bor 8) bxor 3", 13},
        {"(1 - 9) bsr 2", -2},
        {"1 bsl (3 + 2)", 32},
        {"((1 bsl 65) - 1) bxor (1 bsl 65)", (1 bsl 66) - 1}
    ]].

%% Signs and complement apply to complete constant expressions, not only tokens.
-spec static_unary_operations_test_() -> [term()].
static_unary_operations_test_() ->
    [?_test(assert_static(Expression, Expected)) || {Expression, Expected} <- [
        {"+(2 - 7)", -5},
        {"-(2 - 7)", 5},
        {"bnot (1 bsl 8)", -257},
        {"-(-((1 bsl 9) + 3))", 515}
    ]].

%% A variable alias must not erase the source value's still-untyped status.
-spec static_bindings_test() -> ok.
static_bindings_test() ->
    assert_static("Bound = 1 - 257, Alias = Bound, -(Alias + 1)", 255).

%% Comparison literals keep an independent signed type after constant evaluation.
-spec comparison_of_folded_negative_test() -> ok.
comparison_of_folded_negative_test() ->
    #{body := Body, failure := Failure} = lower("Bound = 1 - 257, A > Bound"),
    ?assertEqual("hls_failure::NONE", Failure),
    ?assertMatch([{xls_dslx, literal, "sN[10]", -256}],
        [Left || {xls_dslx, call, "hls_integer::less", [Left, _]} <- syntax_nodes(Body)]).

%% Guard preparation must admit the same static sign/complement expressions.
-spec comparison_guards_test_() -> [term()].
comparison_guards_test_() ->
    [?_test(begin
        #{body := Body, failure := Failure} = lower_guard(Expression),
        ?assertEqual("hls_failure::NONE", Failure),
        ?assertMatch([{xls_dslx, literal, _, Expected}],
            [Right || {xls_dslx, call, "hls_integer::less", [_, Right]} <- syntax_nodes(Body)])
    end) || {Expression, Expected} <- [
        {"A < -(1 bsl 15)", -32768},
        {"A < +(1 - 257)", -256},
        {"A < bnot (1 bsl 8)", -257}
    ]].

%% The consuming wrap supplies the width only after the untyped result is known.
-spec wrapping_boundary_test() -> ok.
wrapping_boundary_test() ->
    #{body := Body, result := Result, failure := Failure} =
        lower("hls_nums:wrap(hls_nums:u8(), 1 - (1 bsl 9))"),
    ?assertEqual("hls_failure::NONE", Failure),
    ?assertEqual(<<"u8:1">>, rendered(definition(Result, Body))).

%% A constant zero divisor becomes a selected failure, never invalid target arithmetic.
-spec static_zero_divisor_test_() -> [term()].
static_zero_divisor_test_() ->
    [?_test(begin
        #{body := Body, failure := Failure} = lower(Expression),
        ?assertMatch([#{kind := badarith, file := <<"static_integer_fixture.erl">>, line := 1}],
            failure_origins(Failure)),
        assert_no_division(Body)
    end) || Expression <- ["1 div (2 - 2)", "7 rem (3 - 3)"]].

%% Discarding a failed value cannot discard the callback's earlier failure.
-spec unused_static_failure_test_() -> [term()].
unused_static_failure_test_() ->
    [?_test(begin
        #{body := Body, result := Result, failure := Failure} = lower(Expression),
        ?assertEqual({static, integer, 7}, Result),
        ?assertMatch([#{kind := badarith}], failure_origins(Failure)),
        assert_no_division(Body)
    end) || Expression <- ["1 div 0, 7", "1 rem 0, 7"]].

%% A guard consumes its own arithmetic failure as false without failing the body.
-spec static_guard_failure_test_() -> [term()].
static_guard_failure_test_() ->
    [?_test(begin
        #{body := Body, failure := Failure, failed := Failed} = lower_guard(Expression),
        ?assertEqual("hls_failure::NONE", Failure),
        ?assertEqual("bool:false", Failed),
        ?assertMatch([#{kind := badarith}], failure_origins(Body)),
        assert_no_division(Body)
    end) || Expression <- ["(1 div 0) < A", "(1 rem 0) < A"]].

%% Repeated source bindings still check equality when both values are static.
-spec repeated_static_binding_failure_test() -> ok.
repeated_static_binding_failure_test() ->
    #{failure := Failure} = lower("Bound = 2 - 3, Bound = 0 - 2, 7"),
    ?assertMatch([#{kind := match_failure}], failure_origins(Failure)).

%% Matching a retained 255 against signed eight-bit -1 compares numbers, not their bits.
-spec retained_static_rematch_uses_sized_equality_test_() -> [term()].
retained_static_rematch_uses_sized_equality_test_() ->
    [?_test(begin
        Outcome = lower_after_prepass(Expression),
        #{result := Result, failure := Failure} = Outcome,
        ?assertEqual({static, integer, 7}, Result),
        ?assertMatch([#{kind := match_failure}], failure_origins(Failure)),
        assert_sized_equality(Outcome, Side, 255)
    end) || {Expression, Side} <- [
        {"Bound = 255, Bound = hls_type:as(hls_nums:s8(), -1), 7", 1},
        {"Bound = hls_type:as(hls_nums:s8(), -1), Bound = 255, 7", 2}
    ]].

%% A bound variable used as a case pattern has the same independent integer width.
-spec retained_static_case_pattern_uses_sized_equality_test() -> ok.
retained_static_case_pattern_uses_sized_equality_test() ->
    Outcome = lower_after_prepass(
        "Bound = 255, case hls_type:as(hls_nums:s8(), -1) of Bound -> 1; _ -> 0 end"),
    assert_sized_equality(Outcome, 1, 255).

%% Find the semantic comparison, allowing a retained expression to be referenced more than once.
-spec assert_sized_equality(xls_clause_lower:outcome(), 1 | 2, integer()) -> ok.
assert_sized_equality(#{body := Body, failure := Failure}, Side, Value) ->
    [Arguments] = lists:usort([Args ||
        {xls_dslx, call, "hls_bits::same_integer", Args} <- syntax_nodes([Body, Failure])]),
    ?assertEqual({xls_dslx, literal, "sN[9]", Value}, lists:nth(Side, Arguments)).

%% Explicitly typed operands stay at their chosen width, even when both are constants.
-spec typed_arithmetic_is_not_folded_test() -> ok.
typed_arithmetic_is_not_folded_test() ->
    #{body := Body, result := Result} = lower(
        "hls_type:as(hls_nums:u8(), 0) - hls_type:as(hls_nums:u8(), 1)"),
    ?assertNotMatch({static, integer, _}, Result),
    ?assertEqual(['-'], [Op || {xls_dslx, binary, Op, _, _} <- syntax_nodes(Body)]),
    ?assertEqual(["u8", "u8"], [Type ||
        {xls_dslx, bind, _, ["(", _, " as ", Type, ")"]} <- Body]),
    ?assertEqual([], [Type || {xls_dslx, literal, Type, _} <- syntax_nodes(Body)]).

%% Dynamic arithmetic retains its operands; the new constant path supplies no cast.
-spec dynamic_arithmetic_is_not_widened_test() -> ok.
dynamic_arithmetic_is_not_widened_test() ->
    #{body := Body, result := Result} = lower("A - B"),
    ?assertNotMatch({static, integer, _}, Result),
    ?assertEqual([{xls_dslx, binary, '-', "v_A_1", "v_B_1"}],
        [Node || Node = {xls_dslx, binary, _, _, _} <- syntax_nodes(Body)]),
    ?assertEqual([], [Type || {xls_dslx, literal, Type, _} <- syntax_nodes(Body)]).

%% Sibling branches learn independent constants, and a join retains its dynamic binding.
-spec branch_constants_do_not_escape_test_() -> [term()].
branch_constants_do_not_escape_test_() ->
    [?_test(begin
        [Selection, {var, _, 'Local'}] = normalized_body(SelectionSource ++ ", Local"),
        Clauses = element(tuple_size(Selection), Selection),
        [{clause, _, _, _, [_, {integer, _, 3}]},
         {clause, _, _, _, [_, {op, _, '+', {var, _, 'Local'}, {integer, _, 1}}]}] = Clauses
    end) || SelectionSource <- [
        "case A of 0 -> Local = 2, Local + 1; _ -> Local = B, Local + 1 end",
        "if A =:= 0 -> Local = 2, Local + 1; true -> Local = B, Local + 1 end"
    ]].

%% Values established before a selection remain available in both arms and afterward.
-spec outer_aliases_reach_branches_test_() -> [term()].
outer_aliases_reach_branches_test_() ->
    [?_test(begin
        [_, Selection, {integer, _, 10}] = normalized_body(
            "Outer = 10, " ++ SelectionSource ++ ", Outer"),
        Clauses = element(tuple_size(Selection), Selection),
        ?assertMatch([{clause, _, _, _, [{integer, _, 11}]},
                      {clause, _, _, _, [{integer, _, 8}]}], Clauses),
        ?assertEqual([], [Name || {var, _, Name = 'Outer'} <- syntax_nodes(Selection)])
    end) || SelectionSource <- [
        "case A of 0 -> Outer + 1; _ -> Outer - 2 end",
        "if A < Outer -> Outer + 1; true -> Outer - 2 end"
    ]].

%% Provider results establish typed values even when their input is a constant.
-spec typed_provider_aliases_remain_dynamic_test_() -> [term()].
typed_provider_aliases_remain_dynamic_test_() ->
    [?_test(begin
        [Binding, {match, _, {var, _, 'Alias'}, {var, _, 'N'}},
         {op, _, '+', {var, _, 'Alias'}, {integer, _, 1}}] = normalized_body(
            "N = " ++ Provider ++ ", Alias = N, Alias + 1"),
        ?assertMatch({match, _, {var, _, 'N'}, {call, _, _, _}}, Binding)
    end) || Provider <- [
        "hls_type:as(hls_nums:u8(), 255)",
        "hls_nums:wrap(hls_nums:u8(), 255)"
    ]].

%% A match checks an existing argument; it cannot replace its declared hardware type.
-spec typed_argument_rematch_is_not_static_test() -> ok.
typed_argument_rematch_is_not_static_test() ->
    {clause, _, _, _, [_, Result]} = normalized_function("f(X) -> X = 255, X + 1."),
    ?assertMatch({op, _, '+', {var, _, 'X'}, {integer, _, 1}}, Result).

%% Branch-pattern bindings are equally unknown until their selected runtime value is read.
-spec typed_branch_pattern_rematch_is_not_static_test() -> ok.
typed_branch_pattern_rematch_is_not_static_test() ->
    [{'case', _, _, [{clause, _, _, _, [_, Result]}]}] = normalized_body(
        "case A of X -> X = 255, X + 1 end"),
    ?assertMatch({op, _, '+', {var, _, 'X'}, {integer, _, 1}}, Result).

%% Rechecking a typed provider value does not grant permission to widen later arithmetic.
-spec typed_provider_rematch_is_not_static_test_() -> [term()].
typed_provider_rematch_is_not_static_test_() ->
    [?_test(begin
        [_, _, Result] = normalized_body("X = " ++ Provider ++ ", X = 255, X + 1"),
        ?assertMatch({op, _, '+', {var, _, 'X'}, {integer, _, 1}}, Result)
    end) || Provider <- [
        "hls_type:as(hls_nums:u8(), 255)",
        "hls_nums:wrap(hls_nums:u8(), 255)"
    ]].

%% A value joined from typed arms stays dynamic after a matching constant check.
-spec joined_typed_rematch_is_not_static_test_() -> [term()].
joined_typed_rematch_is_not_static_test_() ->
    [?_test(begin
        Expression = Selection ++ ", X = 255, X + 1",
        ?assertMatch({op, _, '+', {var, _, 'X'}, {integer, _, 1}},
            lists:last(normalized_body(Expression))),
        #{body := Body, result := Result} = lower_after_prepass(Expression),
        ?assertNotMatch({static, integer, _}, Result),
        ?assertEqual(['+'], [Op || {xls_dslx, binary, Op, _, _} <- syntax_nodes(Body)])
    end) || Selection <- [
        "case A of 0 -> X = hls_type:as(hls_nums:u8(), 255); _ -> X = B end",
        "if A =:= 0 -> X = hls_type:as(hls_nums:u8(), 255); true -> X = B end"
    ]].

%% A later match cannot repair a binding absent from one selected case arm.
-spec partially_bound_rematch_stays_unsafe_test() -> ok.
partially_bound_rematch_stays_unsafe_test() ->
    Expression = "case A of 0 -> X = B; _ -> 0 end, X = 255, X + 1",
    ?assertMatch({op, _, '+', {var, _, 'X'}, {integer, _, 1}},
        lists:last(normalized_body(Expression))),
    ?assertException(error, {unsafe_xls_variable, _, 'X', _},
        lower_after_prepass(Expression)).

%% A conditional Boolean operand also leaves its new binding unsafe outside that operand.
-spec short_circuit_bound_rematch_stays_unsafe_test_() -> [term()].
short_circuit_bound_rematch_stays_unsafe_test_() ->
    [?_test(begin
        Expression = "(A =:= 0) " ++ Operator ++ " ((X = B) =:= 0), X = 255, X + 1",
        ?assertMatch({op, _, '+', {var, _, 'X'}, {integer, _, 1}},
            lists:last(normalized_body(Expression))),
        ?assertException(error, {unsafe_xls_variable, _, 'X', _},
            lower_after_prepass(Expression))
    end) || Operator <- ["andalso", "orelse"]].

%% Invalid arithmetic remains executable syntax and cannot become a constant alias.
-spec failed_alias_preserves_failure_test_() -> [term()].
failed_alias_preserves_failure_test_() ->
    [?_test(begin
        Expression = "N = 1 " ++ Operator ++ " (2 - 2), Alias = N, Alias + 1",
        [Binding, {match, _, {var, _, 'Alias'}, {var, _, 'N'}},
         {op, _, '+', {var, _, 'Alias'}, {integer, _, 1}}] = normalized_body(Expression),
        ?assertMatch({match, _, {var, _, 'N'},
            {op, _, Op, {integer, _, 1}, {integer, _, 0}}}, Binding),
        #{body := Body, failure := Failure} = lower_after_prepass(Expression),
        ?assertMatch([#{kind := badarith}], failure_origins(Failure)),
        assert_no_division(Body)
    end) || {Operator, Op} <- [{"div", 'div'}, {"rem", 'rem'}]].

%% The prepass must retain source order when an alias failure competes with a failed match.
-spec first_failure_order_after_prepass_test_() -> [term()].
first_failure_order_after_prepass_test_() ->
    [?_test(begin
        #{body := Body, failure := Failure} = lower_after_prepass(Expression),
        ?assertMatch(["hls_failure::first_all([", _, "])"], Failure),
        ?assertEqual(Expected, [Kind || #{kind := Kind} <- failure_origins(Failure)]),
        assert_no_division(Body)
    end) || {Expression, Expected} <- [
        {"N = 1 div 0, 1 = 2, N", [badarith, match_failure]},
        {"1 = 2, N = 1 rem 0, N", [match_failure, badarith]}
    ]].

%% Untaken Boolean operands retain their failure inside the short-circuit expression.
-spec short_circuit_failure_after_prepass_test_() -> [term()].
short_circuit_failure_after_prepass_test_() ->
    [?_test(begin
        [Expression] = normalized_body(Source),
        ?assertMatch({op, _, Operator, {atom, _, Left},
            {op, _, '=:=', {op, _, Arithmetic, _, _}, _}}, Expression),
        ?assertEqual(lower(Source), lower_after_prepass(Source))
    end) || {Source, Operator, Left, Arithmetic} <- [
        {"false andalso (1 div 0 =:= 0)", 'andalso', false, 'div'},
        {"true orelse (1 rem 0 =:= 0)", 'orelse', true, 'rem'}
    ]].

%% Inspect the prepass directly before expected-type propagation or target lowering.
-spec normalized_body(string()) -> [erl_parse:abstract_expr()].
normalized_body(Expression) ->
    {clause, _, _, _, Body} = normalized_function("f(A, B) -> " ++ Expression ++ "."),
    Body.

%% Each parsed function supplies its own argument and branch binding scopes.
-spec normalized_function(string()) -> erl_parse:abstract_clause().
normalized_function(Source) ->
    {function, _, f, _, Clauses} = parse(Source),
    [Clause] = xls_static_integer:clauses(Clauses),
    Clause.

%% Retain ordinary failure annotation and lowering after the source normalization step.
-spec lower_after_prepass(string()) -> xls_clause_lower:outcome().
lower_after_prepass(Expression) ->
    [Clause] = xls_static_integer:clauses([prepare("f(A, B) -> " ++ Expression ++ ".")]),
    xls_clause_lower:clause_outcome(Clause, ["a", "b"], unused, #{}).

%% Assert mathematical evaluation without depending on emitted temporary bindings.
-spec assert_static(string(), integer()) -> ok.
assert_static(Expression, Expected) ->
    #{result := Result, failure := Failure} = lower(Expression),
    ?assertEqual({static, integer, Expected}, Result),
    ?assertEqual("hls_failure::NONE", Failure).

%% Parse ordinary typed source, then use the same comparison and origin preparation as lowering.
-spec lower(string()) -> xls_clause_lower:outcome().
lower(Expression) ->
    Clause = prepare("f(A, B) -> " ++ Expression ++ "."),
    xls_clause_lower:clause_outcome(Clause, ["a", "b"], unused, #{}).

%% Lower the prepared guard predicate as a value while retaining its exception boundary.
-spec lower_guard(string()) -> xls_clause_lower:outcome().
lower_guard(Expression) ->
    {clause, Line, Arguments, Guards, _} = prepare(
        "f(A, B) when " ++ Expression ++ " -> true."),
    Predicate = xls_guard_lower:predicate(Guards, Line),
    xls_clause_lower:clause_outcome({clause, Line, Arguments, [], [Predicate]},
        ["a", "b"], unused, #{}).

%% Synthetic file metadata makes failure references inspectable without creating fixture files.
-spec prepare(string()) -> erl_parse:abstract_clause().
prepare(Function) ->
    Forms = [{attribute, 1, file, {"static_integer_fixture.erl", 1}},
        parse("-spec f(hls_nums:u8(), hls_nums:u8()) -> term()."), parse(Function)],
    {Annotated, _Locations} = xls_failure_sites:prepare(xls_comparison:prepare(Forms)),
    [{function, _, f, 2, [Clause]}] = [F || F = {function, _, _, _, _} <- Annotated],
    Clause.

%% Erlang parsing supplies the same operator nesting that an actor source would use.
-spec parse(string()) -> hls_source:form().
parse(Source) ->
    {ok, Tokens, _} = erl_scan:string(Source),
    {ok, Form} = erl_parse:parse_form(Tokens),
    Form.

%% Resolve the final emitted binding only when a provider made the value nonstatic.
-spec definition(xls_clause_lower:printable(), [xls_clause_lower:printable()]) ->
    xls_clause_lower:printable().
definition(Result, Body) ->
    case [Value || {xls_dslx, bind, Name, Value} <- Body, Name =:= Result] of
        [Value] -> Value;
        [] -> Result
    end.

%% Traverse retained syntax; text remains opaque to semantic assertions.
-spec syntax_nodes(term()) -> [tuple()].
syntax_nodes(Value) when is_tuple(Value) -> [Value | syntax_nodes(tuple_to_list(Value))];
syntax_nodes(Values) when is_list(Values) -> lists:append([syntax_nodes(Value) || Value <- Values]);
syntax_nodes(_) -> [].

%% Inspect structured source failures without depending on final site numbers or printer symbols.
-spec failure_origins(term()) -> [xls_failure_sites:origin()].
failure_origins(Value) ->
    [Origin || {xls_dslx, failure_ref, Origin} <- syntax_nodes(Value)].

%% Static bad arithmetic must not leave a divide-by-zero operation in generated DSLX.
-spec assert_no_division(xls_clause_lower:printable()) -> ok.
assert_no_division(Body) ->
    Text = rendered(Body),
    ?assertEqual(nomatch, binary:match(Text, <<" / ">>)),
    ?assertEqual(nomatch, binary:match(Text, <<"hls_integer::remainder(">>)).

%% Render one local value for the two target-syntax boundary checks only.
-spec rendered(xls_clause_lower:printable()) -> binary().
rendered(Value) -> iolist_to_binary(xls_clause_lower:print(Value)).
