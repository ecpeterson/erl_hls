-module(xls_expr_ir_tests).
-moduledoc "Structured scalar lowering, binding identity and rendering regressions.".
-include_lib("eunit/include/eunit.hrl").

%% Arithmetic remains structured until the final rendering boundary.
-spec arithmetic_rendering_test() -> ok.
arithmetic_rendering_test() ->
    [begin
        Node = {xls_bits_binary, Op, "a", "b"},
        ?assertEqual(Text, iolist_to_binary(xls_parse:print(Node)))
    end || {Op, Text} <- [{'+', <<"a + b">>}, {'-', <<"a - b">>}, {'bxor', <<"a ^ b">>}]],
    ok.

%% Aliases resolve by binding identity; arbitrary snippets remain opaque.
-spec alias_and_opaque_test() -> ok.
alias_and_opaque_test() ->
    Node = {xls_bits_binary, '+', "a", "b"},
    D0 = xls_expr_ir:remember("sum", Node, #{}),
    D1 = xls_expr_ir:remember("alias", "sum", D0),
    D2 = xls_expr_ir:remember("second_alias", "alias", D1),
    ?assertEqual("sum", xls_expr_ir:resolve("second_alias", D2)),
    ?assertEqual(Node, xls_expr_ir:definition("second_alias", D2)),
    ?assertEqual(opaque, xls_expr_ir:definition("sum", #{})),
    Text = xls_expr_ir:remember("text", "a + b", D2),
    ?assertEqual(opaque, xls_expr_ir:definition("text", Text)),
    Rebound = xls_expr_ir:remember("sum", "sum", D2),
    ?assertEqual(opaque, xls_expr_ir:definition("sum", Rebound)),
    ok.

%% Ordinary lowering retains the comparison's arithmetic dependency for XLS to optimize.
-spec ordinary_lowering_test() -> ok.
ordinary_lowering_test() ->
    #{body := Body} = lower("T = A + B, Alias = T, {T, Alias =:= A}"),
    ?assertEqual(1, count_nodes(xls_bits_binary, Body)),
    ?assertEqual(1, count_nodes(xls_integer_comparison, Body)),
    ?assertEqual(0, zero_comparisons(Body)),
    Rendered = iolist_to_binary(xls_parse:print(Body)),
    ?assertNotEqual(nomatch, binary:match(Rendered, <<" + ">>)),
    ?assertNotEqual(nomatch, binary:match(Rendered, <<"hls_integer::equal(">>)),
    ok.

%% The existing branch renderer leaves joined values opaque to the enclosing clause.
-spec branch_boundary_test() -> ok.
branch_boundary_test() ->
    #{body := Body} = lower("T = case A =:= B of true -> A + B; false -> A - B end, T =:= A"),
    ?assertEqual(0, count_nodes(xls_bits_binary, Body)),
    Text = iolist_to_binary(xls_parse:print(Body)),
    ?assertNotEqual(nomatch, binary:match(Text, <<" + ">>)),
    ?assertNotEqual(nomatch, binary:match(Text, <<" - ">>)),
    ?assertEqual(0, zero_comparisons(Body)),
    ok.

%% The representation preserves eager division and its failure check before the comparison.
-spec eager_evaluation_test() -> ok.
eager_evaluation_test() ->
    #{body := Body, failed := Failed} = lower("T = (A div B) + A, T =:= A"),
    ?assertEqual(1, count_nodes(xls_bits_binary, Body)),
    ?assertEqual(0, zero_comparisons(Body)),
    Text = iolist_to_binary(xls_parse:print([Body, Failed])),
    ?assertNotEqual(nomatch, binary:match(Text, <<" / ">>)),
    ?assertNotEqual(nomatch, binary:match(Text, <<"hls_failure::">>)),
    ok.

%% Use the ordinary integer-classification and clause-lowering path.
-spec lower(string()) -> map().
lower(Body) ->
    Forms = [parse("-spec f(hls_nums:u32(), hls_nums:u32()) -> term()."),
        parse("f(A, B) -> " ++ Body ++ ".")],
    [_, {function, _, _, _, [Clause]}] = xls_comparison:prepare(Forms),
    xls_parse:clause_outcome(Clause, ["a", "b"], state, #{}).

%% Parse complete forms so source binding behavior matches ordinary frontend input.
-spec parse(string()) -> hls_source:form().
parse(Source) ->
    {ok, Tokens, _} = erl_scan:string(Source),
    {ok, Form} = erl_parse:parse_form(Tokens),
    Form.

%% Count operation nodes before rendering without inspecting emitted text.
-spec count_nodes(atom(), term()) -> non_neg_integer().
count_nodes(Kind, Node) when is_tuple(Node), element(1, Node) =:= Kind -> 1;
count_nodes(Kind, Node) when is_tuple(Node) -> count_nodes(Kind, tuple_to_list(Node));
count_nodes(Kind, List) when is_list(List) -> lists:sum([count_nodes(Kind, V) || V <- List]);
count_nodes(_, _) -> 0.

%% A zero comparison here would indicate an unexpected frontend algebraic rewrite.
-spec zero_comparisons(term()) -> non_neg_integer().
zero_comparisons({xls_integer_comparison, _, _, {static, integer, 0}}) -> 1;
zero_comparisons(Node) when is_tuple(Node) -> zero_comparisons(tuple_to_list(Node));
zero_comparisons(List) when is_list(List) -> lists:sum([zero_comparisons(V) || V <- List]);
zero_comparisons(_) -> 0.
