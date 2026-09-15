-module(xls_control_failure_dslx).
-export([write/1, oracle/3]).

oracle(Mode, X, Y) ->
    try xls_control_failure_fixture:evaluate(Mode, X, Y) of
        Value -> {0, Value}
    catch
        error:{badmatch, _} -> {2, 0};
        error:{case_clause, _} -> {4, 0};
        error:if_clause -> {5, 0};
        error:badarith -> {13, 0};
        error:badarg -> {14, 0}
    end.

write(Stage) ->
    Source = "test/xls_control_failure_fixture.erl",
    Generated = xls_parse:to_xls(Source),
    {ok, Semantics} = file:read_file("test_data/xls_control_failure_semantics.inc.x"),
    Cases = [{M, X, Y, oracle(M, X, Y)} || M <- lists:seq(0, 58),
        X <- [0, 1, 2, 16#ffffffff], Y <- [0, 1, 2]],
    ok = write(Stage, "control.x", [Generated, Semantics,
        [dslx_test(M, [C || C = {Mode, _, _, _} <- Cases, Mode =:= M])
            || M <- lists:seq(0, 58)]]),
    ok = write(Stage, "control_vectors.svh", [vector(C) || C <- Cases]),
    %% Selected failures reject constant initialization, even for an unrelated top.
    {ok, Original} = file:read_file(Source),
    lists:foreach(fun({Name, Expression}) ->
        Path = filename:join(Stage, Name ++ ".erl"),
        ok = file:write_file(Path, binary:replace(Original,
            <<"case Value of 7 -> Value end">>, Expression)),
        ok = write(Stage, Name ++ ".x", xls_parse:to_xls(Path))
    end, [{"bad_div_init", <<"Value div 0">>},
          {"bad_rem_init", <<"Value rem 0">>},
          {"bad_case_init", <<"case Value of 0 -> Value end">>},
          {"bad_if_init", <<"if Value =:= 0 -> Value end">>},
          {"bad_nth_init", <<"hls_vec:nth(0, hls_lists:new(hls_nums:u32(), 3))">>},
          {"bad_set_init", <<"hls_vec:nth(1, hls_vec:set(4, hls_lists:new(hls_nums:u32(), 3), Value))">>},
          {"bad_slice_init", <<"hls_vec:nth(1, hls_lists:array_slice(hls_lists:list(hls_nums:u32(), 3), hls_lists:new(hls_nums:u32(), 3), 3, 2))">>}]).

dslx_test(Mode, Cases) ->
    [io_lib:format("\n#[test]\nfn beam_~p() {\n  let cases = [\n", [Mode]),
        [io_lib:format("    (u32:~p, u32:~p, bits[36]:~p),\n",
            [X, Y, (Code bsl 32) bor Value]) || {_, X, Y, {Code, Value}} <- Cases],
        io_lib:format("  ];\n  for (i, ()): (u32, ()) in u32:0..u32:~p {\n"
            "    let (x, y, expected) = cases[i];\n"
            "    assert_eq(control_probe(u32:~p, x, y), expected);\n  } (())\n}\n",
            [length(Cases), Mode])].

vector({M, X, Y, {Code, Value}}) ->
    io_lib:format("    probe(32'd~p, 32'd~p, 32'd~p, 4'd~p, 32'd~p);\n",
        [M, X, Y, Code, Value]).

write(Stage, Name, Data) -> file:write_file(filename:join(Stage, Name), Data).
