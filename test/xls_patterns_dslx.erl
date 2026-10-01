-module(xls_patterns_dslx).
-export([write/1]).

write(Stage) ->
    {ok, Forms0} = epp:parse_file("test/xls_patterns_fixture.erl", [], []),
    Names = xls_patterns_fixture:probes(),
    {Forms, Helpers} = xls_helpers:prepare(Forms0, [{N, 2} || N <- Names]),
    Grid = [{X, [A, B, C]} || X <- [-2, 0, 1, 3], A <- [-1, 0, 2],
        B <- [-1, 0, 2], C <- [-1, 0, 2]],
    Expected = [{I, Name, [{Input, expected(Name, Input)} || Input <- Grid]}
        || {I, Name} <- lists:enumerate(0, Names)],
    Text = ["enum Tag : u8 { CELL = 1 }\n",
        xls_dslx_imports:emit([hls_failure, hls_bits], xls_dslx_imports:from_forms(Forms)),
        [[xls_parse:struct_from_record(R), xls_parse:bitsfromstruct_from_record(R)]
            || R = {attribute, _, record, _} <- Forms],
        xls_helpers:emit(Helpers, cell, #{}),
        [function(Name, Forms) || Name <- Names],
        "pub fn probe(mode: u32, x: s32, a: s32, b: s32, c: s32) -> bits[36] {\n",
        "match mode {\n", [["u32:", integer_to_list(I), " => probe_", atom_to_list(Name),
            "(x, [a, b, c]),\n"] || {I, Name, _} <- Expected],
        "_ => bits[36]:0\n}\n}\n",
        [test(Name, Cases) || {_, Name, Cases} <- Expected]],
    ok = file:write_file(filename:join(Stage, "patterns.x"), Text),
    ok = file:write_file(filename:join(Stage, "patterns_tb.sv"), testbench(Expected)),
    ok = file:write_file(filename:join(Stage, "list_reduction.x"),
        xls_parse:to_xls("test_data/hls_list_reduction_fixture.erl")),
    write_rejections(Stage).

function(Name, Forms) ->
    [Clause] = xls_parse:find_function(Forms, Name, 2),
    #{body := Body, result := Value, failure := Failure} =
        xls_parse:clause_outcome(Clause, ["x", "values"], cell, #{}),
    ["fn probe_", atom_to_list(Name), "(x: s32, values: s32[3]) -> bits[36] {\n",
        xls_parse:print(Body), "let code = ", xls_parse:print(Failure), ";\n",
        "let value = if code != hls_failure::NONE { s32:0 } else { ",
        xls_parse:print(Value), " };\n",
        "(hls_failure::kind(code) as u4) ++ (value as u32)\n}\n"].

expected(Name, {X, Values}) ->
    try apply(xls_patterns_fixture, Name, [X, Values]) of
        Value -> Value band 16#ffffffff
    catch
        error:function_clause -> 1 bsl 32;
        error:{badmatch, _} -> 2 bsl 32;
        error:{case_clause, _} -> 4 bsl 32;
        error:badarith -> 13 bsl 32
    end.

test(Name, Cases) ->
    ["#[test]\nfn check_", atom_to_list(Name), "() {\nlet cases = [\n",
        [io_lib:format("(s32:~p, s32:~p, s32:~p, s32:~p, bits[36]:~p),\n", [X,A,B,C,V])
            || {{X, [A,B,C]}, V} <- Cases],
        "];\nfor (i, ()): (u32, ()) in u32:0..u32:", integer_to_list(length(Cases)), " {\n",
        "let (x, a, b, c, expected) = cases[i];\nassert_eq(probe_", atom_to_list(Name),
        "(x, [a,b,c]), expected);\n} (())\n}\n"].

testbench(Expected) ->
    ["module patterns_tb;\nreg [31:0] mode, x, a, b, c; wire [35:0] out;\n",
        "probe dut(.mode(mode), .x(x), .a(a), .b(b), .c(c), .out(out));\ninitial begin\n",
        [[io_lib:format("mode=32'd~p; x=32'h~.16b; a=32'h~.16b; b=32'h~.16b; c=32'h~.16b; #1;\n"
            "if (out !== 36'h~.16b) $fatal(1, \"~s x=~p values=~w: got %h\", out);\n",
            [I, X band 16#ffffffff, A band 16#ffffffff, B band 16#ffffffff,
             C band 16#ffffffff, V, Name, X, [A,B,C]])
            || {{X,[A,B,C]},V} <- Cases] || {I,Name,Cases} <- Expected],
        io_lib:format("$display(\"PASS: ~p bounded-pattern RTL vectors\");\n$finish;\nend\nendmodule\n",
            [lists:sum([length(C) || {_,_,C} <- Expected])])].

write_rejections(Stage) ->
    lists:foreach(fun({Name, Cut}) ->
        ok = file:write_file(filename:join(Stage, Name ++ ".x"),
            io_lib:format("import hls_patterns;\npub fn probe(values: u32[3]) -> u32 {\n"
                "let tail = hls_patterns::tail<u32:~p>(values); tail[u32:0]\n}\n", [Cut]))
    end, [{"empty_tail", 3}, {"overlong_tail", 4}]).
