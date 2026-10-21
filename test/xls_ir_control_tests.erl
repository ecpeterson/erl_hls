-module(xls_ir_control_tests).
-moduledoc "Structural cancellation, binding and ordinary-lowering regressions; finite circuits are checked separately through DSLX and XLS.".
-include_lib("eunit/include/eunit.hrl").

%% Both comparison orders and commutative operand orders preserve the remaining operand.
-spec cancellation_test() -> ok.
cancellation_test() ->
    [begin
        D = xls_expr_ir:remember("sum", {xls_bits_binary, Op, A, B}, #{}),
        Compare = {xls_integer_comparison, Eq, L, R},
        ?assertEqual({xls_integer_comparison, Eq, "b", {static, integer, 0}},
            xls_ir_control:simplify(Compare, D))
    end || Op <- ['+', 'bxor'], {A, B} <- [{"a", "b"}, {"b", "a"}],
        Eq <- ['=:=', '=/='], {L, R} <- [{"sum", "a"}, {"a", "sum"}]],
    D = xls_expr_ir:remember("difference", {xls_bits_binary, '-', "a", "b"}, #{}),
    ?assertEqual({xls_integer_comparison, '=:=', "b", {static, integer, 0}},
        xls_ir_control:simplify({xls_integer_comparison, '=:=', "difference", "a"}, D)),
    Reversed = {xls_integer_comparison, '=:=', "difference", "b"},
    ?assertEqual(Reversed, xls_ir_control:simplify(Reversed, D)),
    ok.

%% Alias identities carry provenance, but arbitrary text and unrelated equalities do not.
-spec alias_and_opaque_test() -> ok.
alias_and_opaque_test() ->
    D0 = xls_expr_ir:remember("a", "input", #{}),
    D1 = xls_expr_ir:remember("alias_a", "a", D0),
    D2 = xls_expr_ir:remember("sum", {xls_bits_binary, '+', "alias_a", "b"}, D1),
    D3 = xls_expr_ir:remember("alias_sum", "sum", D2),
    Compare = {xls_integer_comparison, '=:=', "alias_sum", "a"},
    ?assertEqual({xls_integer_comparison, '=:=', "b", {static, integer, 0}},
        xls_ir_control:simplify(Compare, D3)),
    ?assertEqual(Compare, xls_ir_control:simplify(Compare, #{})),
    Text = xls_expr_ir:remember("alias_sum", "a + b", D0),
    ?assertEqual(Compare, xls_ir_control:simplify(Compare, Text)),
    Less = {xls_integer_comparison, '<', "sum", "a"},
    ?assertEqual(Less, xls_ir_control:simplify(Less, D3)),
    ok.

%% Actual lowering automatically emits the zero comparison while retaining the full arithmetic use.
-spec ordinary_lowering_test() -> ok.
ordinary_lowering_test() ->
    #{body := Body} = lower("T = A + B, Alias = T, {T, Alias =:= A}"),
    ?assertEqual(1, count_nodes(xls_bits_binary, Body)),
    ?assertEqual(1, zero_comparisons(Body)),
    Rendered = iolist_to_binary(xls_parse:print(Body)),
    ?assertNotEqual(nomatch, binary:match(Rendered, <<" + ">>)),
    ?assertNotEqual(nomatch, binary:match(Rendered, <<"hls_integer::equal(">>)),
    ok.

%% Branch-local operation identities must not be reused for a joined value or opaque helper call.
-spec branch_boundary_test() -> ok.
branch_boundary_test() ->
    #{body := Body} = lower("T = case A =:= B of true -> A + B; false -> A - B end, T =:= A"),
    ?assertEqual(0, zero_comparisons(Body)),
    ok.

%% Failure-producing work remains present even if the comparison no longer depends on its value.
-spec eager_evaluation_test() -> ok.
eager_evaluation_test() ->
    #{body := Body, failed := Failed} = lower("T = (A div B) + A, T =:= A"),
    ?assertEqual(1, zero_comparisons(Body)),
    Text = iolist_to_binary(xls_parse:print([Body, Failed])),
    ?assertNotEqual(nomatch, binary:match(Text, <<" / ">>)),
    ?assertNotEqual(nomatch, binary:match(Text, <<"hls_failure::">>)),
    ok.

%% Use the existing integer-classification and clause-lowering path, not a standalone rewrite entry point.
-spec lower(string()) -> map().
lower(Body) ->
    Forms = [parse("-spec f(hls_nums:u32(), hls_nums:u32()) -> term()."),
        parse("f(A, B) -> " ++ Body ++ ".")],
    [_, {function, _, _, _, [Clause]}] = xls_comparison:prepare(Forms),
    xls_parse:clause_outcome(Clause, ["a", "b"], state, #{}).

%% Parse complete forms to keep source binding behavior identical to ordinary frontend input.
-spec parse(string()) -> hls_source:form().
parse(Source) ->
    {ok, Tokens, _} = erl_scan:string(Source),
    {ok, Form} = erl_parse:parse_form(Tokens),
    Form.

%% Count retained operation nodes before rendering, without inspecting emitted text.
-spec count_nodes(atom(), term()) -> non_neg_integer().
count_nodes(Kind, Node) when is_tuple(Node), element(1, Node) =:= Kind -> 1;
count_nodes(Kind, Node) when is_tuple(Node) -> count_nodes(Kind, tuple_to_list(Node));
count_nodes(Kind, List) when is_list(List) -> lists:sum([count_nodes(Kind, V) || V <- List]);
count_nodes(_, _) -> 0.

%% The rewritten predicate must consume zero directly at the structured IR boundary.
-spec zero_comparisons(term()) -> non_neg_integer().
zero_comparisons({xls_integer_comparison, _, _, {static, integer, 0}}) -> 1;
zero_comparisons(Node) when is_tuple(Node) -> zero_comparisons(tuple_to_list(Node));
zero_comparisons(List) when is_list(List) -> lists:sum([zero_comparisons(V) || V <- List]);
zero_comparisons(_) -> 0.
