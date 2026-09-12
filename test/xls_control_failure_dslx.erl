-module(xls_control_failure_dslx).
-export([write/1, oracle/3]).

oracle(Mode, X, Y) ->
    try xls_control_failure_fixture:evaluate(Mode, X, Y) of
        Value -> {0, Value}
    catch
        error:{badmatch, _} -> {2, 0};
        error:{case_clause, _} -> {4, 0};
        error:if_clause -> {5, 0}
    end.

write(Stage) ->
    Source = "test/xls_control_failure_fixture.erl",
    Generated = xls_parse:to_xls(Source),
    {ok, Semantics} = file:read_file("test_data/xls_control_failure_semantics.inc.x"),
    Cases = [{M, X, Y, oracle(M, X, Y)} || M <- lists:seq(0, 24),
        X <- [0, 1, 2, 16#ffffffff], Y <- [0, 1, 2]],
    ok = write(Stage, "control.x", [Generated, Semantics,
        [dslx_test(M, [C || C = {Mode, _, _, _} <- Cases, Mode =:= M])
            || M <- lists:seq(0, 24)]]),
    ok = write(Stage, "control_vectors.svh", [vector(C) || C <- Cases]),
    %% Both forms fail constant initialization, even for an unrelated top.
    {ok, Original} = file:read_file(Source),
    lists:foreach(fun({Name, Expression}) ->
        Path = filename:join(Stage, Name ++ ".erl"),
        ok = file:write_file(Path, binary:replace(Original,
            <<"case Value of 7 -> Value end">>, Expression)),
        ok = write(Stage, Name ++ ".x", xls_parse:to_xls(Path))
    end, [{"bad_case_init", <<"case Value of 0 -> Value end">>},
          {"bad_if_init", <<"if Value =:= 0 -> Value end">>}]).

dslx_test(Mode, Cases) ->
    [io_lib:format("\n#[test]\nfn beam_~p() {\n  let cases = [\n", [Mode]),
        [io_lib:format("    (u32:~p, u32:~p, bits[35]:~p),\n",
            [X, Y, (Code bsl 32) bor Value]) || {_, X, Y, {Code, Value}} <- Cases],
        io_lib:format("  ];\n  for (i, ()): (u32, ()) in u32:0..u32:~p {\n"
            "    let (x, y, expected) = cases[i];\n"
            "    assert_eq(control_probe(u32:~p, x, y), expected);\n  } (())\n}\n",
            [length(Cases), Mode])].

vector({M, X, Y, {Code, Value}}) ->
    io_lib:format("    probe(32'd~p, 32'd~p, 32'd~p, 3'd~p, 32'd~p);\n",
        [M, X, Y, Code, Value]).

write(Stage, Name, Data) -> file:write_file(filename:join(Stage, Name), Data).
