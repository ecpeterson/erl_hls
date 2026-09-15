-module(xls_type_shape_dslx).
-export([write/1]).

write(Stage) ->
    xls_type_shape_fixture:with_source(fun(Actor, Provider, _Header) ->
        ok = xls_type_shape_fixture:load(Provider, []),
        ok = xls_type_shape_fixture:load(Actor, []),
        {ok, Semantics} = file:read_file("test_data/hls_type_shape_semantics.inc.x"),
        Grid = [0, 1, 16#7fffffff, 16#ffffffff],
        Cases = [{[A, B, C, D], expected(A, B, C, D)}
            || A <- Grid, B <- Grid, C <- Grid, D <- Grid],
        Generated = xls_parse:to_xls(Actor, #{shared_service => aggregate_only}),
        ok = file:write_file(filename:join(Stage, "shape.x"),
            [Generated, Semantics, tests(Cases)]),
        ok = file:write_file(filename:join(Stage, "shape_tb.sv"), testbench(Cases)),
        %% The source still declares two elements, but the loaded provider
        %% emits one. Type-dependent routing must fail before RTL generation.
        ok = xls_type_shape_fixture:load(Provider, [{d, 'WIRE_COUNT', 1}]),
        ok = file:write_file(filename:join(Stage, "shape_mismatch.x"),
            xls_parse:to_xls(Actor, #{shared_service => aggregate_only}))
    end).

expected(A, B, C, D) ->
    Cell = {cell, 0, [0, 0]},
    {gathering, Cell, {contribute, sum, 17, Left}} =
        hls_shape_reduction_fixture:gathering(cast, {value, 17, [A, B]}, Cell),
    {gathering, Cell, {contribute, sum, 17, Right}} =
        hls_shape_reduction_fixture:gathering(cast, {value, 17, [C, D]}, Cell),
    {sum, Sum} = hls_shape_reduction_fixture:reduce(sum, Left, Right),
    Word = Sum band 16#ffffffff,
    (1 bsl 64) bor (Word bsl 32) bor Word.

tests(Cases) ->
    ["#[test]\nfn beam_contributions_and_aggregate_agree() {\n",
        [io_lib:format("assert_eq(probe(u32:~B, u32:~B, u32:~B, u32:~B), bits[72]:~B);\n",
            Args ++ [Expected]) || {Args, Expected} <- Cases], "}\n"].

testbench(Cases) ->
    ["module shape_tb;\nreg [31:0] a,b,c,d; wire [71:0] out;\n",
        "probe dut(.a(a), .b(b), .c(c), .d(d), .out(out));\ninitial begin\n",
        [io_lib:format("a=32'd~B; b=32'd~B; c=32'd~B; d=32'd~B; #1;\n"
            "if (out !== 72'd~B) $fatal(1, \"shape reduction mismatch: %h\", out);\n",
            Args ++ [Expected]) || {Args, Expected} <- Cases],
        io_lib:format("$display(\"PASS: ~B BEAM-derived ordinary/aggregate RTL cases\");\n",
            [length(Cases)]), "$finish; end\nendmodule\n"].
