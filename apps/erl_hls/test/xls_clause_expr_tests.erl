-module(xls_clause_expr_tests).
-moduledoc "Clause expression structure, binding order and source comparison semantics.".
-include_lib("eunit/include/eunit.hrl").

%% Source operators share the target syntax tree without losing their operands.
-spec arithmetic_lowering_test_() -> [term()].
arithmetic_lowering_test_() ->
    [?_test(begin
        #{body := Body} = lower("A " ++ Source ++ " B"),
        ?assertEqual([{Target, "v_A_1", "v_B_1"}],
            [{Op, Left, Right} || {xls_dslx, binary, Op, Left, Right} <- nodes(Body)])
    end) || {Source, Target} <- [{"+", '+'}, {"-", '-'}, {"bxor", '^'}]].

%% Aliases keep bindings to earlier values instead of duplicating arithmetic.
-spec alias_binding_test() -> ok.
alias_binding_test() ->
    #{body := Body} = lower("T = A + B, Alias = T, Alias =:= A"),
    [{Sum, Addition}] = [{Name, Value} || {xls_dslx, bind, Name,
        Value = {xls_dslx, binary, '+', _, _}} <- Body],
    ?assertEqual(1, length([Node || Node = {xls_dslx, binary, '+', _, _} <- nodes(Body)])),
    ?assertEqual(Sum, binding("v_T_1", Body)),
    ?assertEqual("v_T_1", binding("v_Alias_1", Body)),
    ?assertEqual([["v_Alias_1", "v_A_1"]],
        [Args || {xls_dslx, call, "hls_integer::equal", Args} <- nodes(Body)]),
    ?assert(index(Addition, Body) < index(binding("v_T_1", Body), Body)),
    ?assertEqual(0, zero_comparisons(Body)).

%% Each selected arm owns its arithmetic; the outer comparison reads the joined binding.
-spec branch_boundary_test() -> ok.
branch_boundary_test() ->
    #{body := Body} = lower("T = case A =:= B of true -> A + B; false -> A - B end, T =:= A"),
    [{Then, Else}] = [{T, E} || {xls_dslx, choose, _, T, E} <- nodes(Body)],
    ?assertEqual(['+'], [Op || {xls_dslx, binary, Op, _, _} <- nodes(Then)]),
    ?assertEqual(['-'], [Op || {xls_dslx, binary, Op, _, _} <- nodes(Else)]),
    ?assertEqual([], [Node || {xls_dslx, bind, _, Node = {xls_dslx, binary, _, _, _}} <- Body]),
    ?assertEqual(["v_T_1", "v_A_1"], lists:last(
        [Args || {xls_dslx, call, "hls_integer::equal", Args} <- nodes(Body)])),
    ?assertEqual(0, zero_comparisons(Body)).

%% Division remains before its dependent addition and comparison, with the original divisor check.
-spec eager_evaluation_test() -> ok.
eager_evaluation_test() ->
    #{body := Body, failure := Failure, failed := Failed} = lower("T = (A div B) + A, T =:= A"),
    [Addition = {xls_dslx, binary, '+', Quotient, _}] =
        [Node || Node = {xls_dslx, binary, '+', _, _} <- nodes(Body)],
    Division = binding(Quotient, Body),
    ?assertEqual(["v_A_1", " / ", "v_B_1"], Division),
    [Comparison] = [Node || Node = {xls_dslx, call, "hls_integer::equal", _} <- nodes(Body)],
    ?assert(index(Division, Body) < index(Addition, Body)),
    ?assert(index(Addition, Body) < index(Comparison, Body)),
    ?assertMatch(["hls_failure::check(", "v_B_1", " == 0, ", _, ")"], Failure),
    ?assertEqual(<<"hls_failure::check(v_B_1 == 0, hls_failure::BADARITH)">>,
        iolist_to_binary(xls_clause_lower:print(Failure))),
    ?assertNotEqual("bool:false", Failed),
    ?assertEqual(0, zero_comparisons(Body)).

%% Mixed-width comparisons use numeric helpers and independently sized literals, including reversed and negated cases.
-spec integer_comparison_lowering_test() -> ok.
integer_comparison_lowering_test() ->
    #{body := Body} = lower("hls_nums:s8(), hls_nums:u32()",
        "{A < B, A < 128, -256 > A, A =/= 256}"),
    Nodes = nodes(Body),
    [["v_A_1", "v_B_1"], ["v_A_1", Positive], ["v_A_1", Negative]] =
        [Args || {xls_dslx, call, "hls_integer::less", Args} <- Nodes],
    ?assertEqual({xls_dslx, literal, "sN[9]", 128}, Positive),
    ?assertEqual({xls_dslx, literal, "sN[10]", -256}, Negative),
    ?assertMatch([{xls_dslx, unary, '!', {xls_dslx, call, "hls_integer::equal",
        ["v_A_1", {xls_dslx, literal, "sN[10]", 256}]}}],
        [Node || Node = {xls_dslx, unary, '!', _} <- Nodes]).

%% Default operands carry the ordinary fixed-width integer source evidence.
-spec lower(string()) -> xls_clause_lower:outcome().
lower(Body) -> lower("hls_nums:u32(), hls_nums:u32()", Body).

%% Parse the complete source before applying numeric classification and clause lowering.
-spec lower(string(), string()) -> xls_clause_lower:outcome().
lower(Types, Body) ->
    Forms = [parse("-spec f(" ++ Types ++ ") -> term()."), parse("f(A, B) -> " ++ Body ++ ".")],
    [_, {function, _, _, _, [Clause]}] = xls_comparison:prepare(Forms),
    xls_clause_lower:clause_outcome(Clause, ["a", "b"], state, #{}).

%% Parse complete forms so source binding behavior matches ordinary frontend input.
-spec parse(string()) -> hls_source:form().
parse(Source) ->
    {ok, Tokens, _} = erl_scan:string(Source),
    {ok, Form} = erl_parse:parse_form(Tokens),
    Form.

%% A source variable resolves to the value emitted in its one lexical binding.
-spec binding(string(), [xls_clause_lower:printable()]) -> xls_clause_lower:printable().
binding(Name, Body) ->
    [Value] = [Value || {xls_dslx, bind, Bound, Value} <- Body, Bound =:= Name],
    Value.

%% Inspect emitted order without depending on printer whitespace or temporary names.
-spec index(xls_clause_lower:printable(), [xls_clause_lower:printable()]) -> non_neg_integer().
index(Value, Body) ->
    [Index] = [Index || {Index, {xls_dslx, bind, _, Expr}} <- lists:enumerate(0, Body), Expr =:= Value],
    Index.

%% Traverse retained syntax while leaving text opaque.
-spec nodes(term()) -> [tuple()].
nodes(Node) when is_tuple(Node) -> [Node | nodes(tuple_to_list(Node))];
nodes(Values) when is_list(Values) -> lists:append([nodes(Value) || Value <- Values]);
nodes(_) -> [].

%% No comparison against zero may replace the original arithmetic dependency.
-spec zero_comparisons(term()) -> non_neg_integer().
zero_comparisons(Body) ->
    length([Args || {xls_dslx, call, Name, Args} <- nodes(Body),
        lists:member(Name, ["hls_integer::equal", "hls_integer::less", "hls_integer::less_equal"]),
        lists:any(fun is_zero/1, Args)]).

%% Static and independently typed zero literals both denote the same forbidden rewrite here.
-spec is_zero(xls_clause_lower:printable()) -> boolean().
is_zero({static, integer, 0}) -> true;
is_zero({xls_dslx, literal, _, 0}) -> true;
is_zero(_) -> false.
