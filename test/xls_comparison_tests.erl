-module(xls_comparison_tests).
-moduledoc "Checks numeric evidence, scope joins and nonnumeric equality preservation.".
-include_lib("eunit/include/eunit.hrl").

%% A concrete helper signature covers both mixed operands and literal bounds.
-spec signature_and_literal_test() -> ok.
signature_and_literal_test() ->
    Prepared = prepare(["-spec f(hls_nums:s8(), hls_nums:u32()) -> {boolean(), boolean(), boolean(), boolean(), boolean()}.",
        "f(A, B) -> {A < B, A =:= B, A < 128, -256 > A, A =/= 256}."]),
    ?assertEqual(5, count(Prepared)).

%% Record patterns and field selections work without a concrete callback spec.
-spec field_and_binding_test() -> ok.
field_and_binding_test() ->
    Prepared = prepare(["-record(r, {a :: hls_nums:s8(), b :: hls_nums:u32()}).",
        "f(R = #r{a = A}) -> B = R#r.b, {X, Y} = {A, B}, X >= Y."]),
    ?assertEqual(1, count(Prepared)).

%% Only facts common to all branches may flow out of a join.
-spec branch_facts_test() -> ok.
branch_facts_test() ->
    Prepared = prepare(["f(Flag) -> "
        "case Flag of true -> X = 1; false -> X = 2 end, "
        "Y = case Flag of true -> 3; false -> 4 end, X < Y." ]),
    ?assertEqual(1, count(Prepared)),
    Mixed = prepare(["f(Flag) -> X = case Flag of true -> 1; false -> false end, X =:= 1."]),
    ?assertEqual(0, count(Mixed)).

%% Structural/atom equality cannot be sent to a bit-vector comparison helper.
-spec structural_equality_test() -> ok.
structural_equality_test() ->
    Forms = ["-spec f(boolean(), boolean()) -> {boolean(), boolean(), boolean()}.",
        "f(A, B) -> {A =:= B, {A, B} =:= {B, A}, A =:= true}."],
    ?assertEqual(0, count(prepare(Forms))),
    ?assertEqual(0, count(prepare(["f(A, B) -> opaque:result(A) =:= opaque:result(B)."]))).

%% DSLX bool is u1, but Erlang true is not the integer 1. Do not let the
%% shared bit representation silently authorize a cross-kind comparison.
-spec integer_boolean_mismatch_test() -> ok.
integer_boolean_mismatch_test() ->
    lists:foreach(fun(Op) ->
        lists:foreach(fun({A, B}) ->
            ?assertException(error, {unsupported_xls_comparison, _, _, _, _},
                prepare(["-spec f(hls_nums:uN(1), boolean()) -> boolean().",
                    "f(X, Y) -> " ++ A ++ " " ++ Op ++ " " ++ B ++ "."]))
        end, [{"X", "Y"}, {"Y", "X"}])
    end, ["<", "=<", ">", ">=", "=:=", "=/="]).

%% Integer bit segments have independent widths even without a tuple signature.
-spec binary_pattern_test() -> ok.
binary_pattern_test() ->
    ?assertEqual(2, count(prepare([
        "f(<<A:3/signed, B:5>>) -> {A < B, A =:= B}."]))),
    ?assertEqual(0, count(prepare([
        "f(<<A:3/bitstring, B:5/bitstring>>) -> A =:= B."]))).

%% A helper's declared result and an explicit integer wrap carry the same fact.
-spec helper_and_provider_test() -> ok.
helper_and_provider_test() ->
    Prepared = prepare(["-spec value(hls_nums:u8()) -> hls_nums:u8().", "value(X) -> X.",
        "f(A) -> value(A) < hls_nums:wrap(hls_nums:u32(), 256)."]),
    ?assertEqual(1, count(Prepared)).

%% Private comparison nodes remain valid inside the existing guard grammar.
-spec guard_test() -> ok.
guard_test() ->
    [_, {function, _, _, _, [{clause, _, _, Guards, _} | _]}] = prepare([
        "-spec f(hls_nums:s8(), hls_nums:u32()) -> boolean().",
        "f(A, B) when A < B, A < 128 -> true; f(_, _) -> false."]),
    _ = xls_guard_lower:predicate(Guards, 1),
    ?assertEqual(2, count(Guards)).

%% Parse source declarations before applying the production preparation pass.
-spec prepare([string()]) -> [hls_source:form()].
prepare(Sources) ->
    xls_comparison:prepare([begin
        {ok, Tokens, _} = erl_scan:string(Source),
        {ok, Form} = erl_parse:parse_form(Tokens), Form
    end || Source <- Sources]).

%% Count annotations, including nested comparison operands.
-spec count(term()) -> non_neg_integer().
count({xls_integer_compare, _, _, A, B}) -> 1 + count(A) + count(B);
count(Tuple) when is_tuple(Tuple) -> count(tuple_to_list(Tuple));
count(List) when is_list(List) -> lists:sum([count(X) || X <- List]);
count(_) -> 0.
