-module(xls_helpers_dslx).
-export([write/1]).

write(Stage) ->
    {ok, Forms0} = epp:parse_file("test/xls_helpers_fixture.erl", [], []),
    {Forms, Helpers} = xls_helpers:prepare(Forms0, [{factored, 3}, {inline, 3}]),
    Declarations = ["enum Tag : u8 { CELL = 0, REPORT = 1 }\n",
        xls_dslx_imports:emit([], xls_dslx_imports:from_forms(Forms)),
        [[xls_parse:struct_from_record(Record),
            xls_parse:bitsfromstruct_from_record(Record)]
            || Record = {attribute, _, record, _} <- Forms]],
    Cases = [{M, X, Y} || M <- lists:seq(0, 29),
        X <- [0, 1, 2, 3, 7, 8, 15, 1000], Y <- [0, 1, 2, 3, 7, 8, 15, 1000]],
    Expected = [{Case, expected(Case)} || Case <- Cases],
    ok = file:write_file(filename:join(Stage, "helpers.x"), [Declarations,
        xls_helpers:emit(Helpers, cell, #{}),
        [function(Name, Forms) || Name <- [factored, inline]],
        "#[test]\nfn matches_beam() {\n",
        [io_lib:format("  assert_eq(~s(u8:~p, u32:~p, u32:~p), bits[33]:~p);\n",
            [Name, M, X, Y, Value]) || {{M, X, Y}, Value} <- Expected,
            Name <- ["factored", "inline"]], "}\n"]),
    ok = file:write_file(filename:join(Stage, "helpers_tb.sv"), testbench(Expected)),
    write_rejections(Stage, Forms0).

function(Name, Forms) ->
    [Clause] = xls_parse:find_function(Forms, Name, 3),
    #{body := Body, result := Value, failed := Failed} =
        xls_parse:clause_outcome(Clause, ["mode", "x", "y"], cell, #{}),
    ["pub fn ", atom_to_list(Name), "(mode: u8, x: u32, y: u32) -> bits[33] {\n",
        xls_parse:print([Body, "if ", Failed, " { bits[33]:0x100000000 } else {\n",
            "  ", Value, " as bits[33]\n}\n"]), "}\n"].

expected(Arguments = {M, X, Y}) ->
    Factored = oracle(factored, [M, X, Y]),
    case oracle(inline, [M, X, Y]) of
        Factored -> Factored;
        Other -> error({helper_oracle_disagreement, Arguments, Factored, Other})
    end.

oracle(Name, Arguments) ->
    try apply(xls_helpers_fixture, Name, Arguments)
    catch error:{badmatch, _} -> 16#100000000
    end.

testbench(Cases) ->
    ["module helpers_tb;\n  reg [7:0] mode; reg [31:0] x, y;\n",
        "  wire [32:0] factored_out, inline_out;\n",
        "  factored a(.mode(mode), .x(x), .y(y), .out(factored_out));\n",
        "  inline b(.mode(mode), .x(x), .y(y), .out(inline_out));\n",
        "  initial begin\n",
        [io_lib:format("    mode=8'd~p; x=32'd~p; y=32'd~p; #1;\n"
            "    if (factored_out !== 33'd~p || inline_out !== 33'd~p)\n"
            "      $fatal(1, \"mode=~p x=~p y=~p: %h %h\", factored_out, inline_out);\n",
            [M, X, Y, Expected, Expected, M, X, Y])
            || {{M, X, Y}, Expected} <- Cases],
        io_lib:format("    $display(\"PASS: ~p factored/inline RTL vectors\");\n",
            [length(Cases)]), "    $finish;\n  end\nendmodule\n"].

write_rejections(Stage, Base) ->
    Header = [F || F = {attribute, _, Kind, _} <- Base,
        lists:member(Kind, [module, hls_data, hls_tags])],
    lists:foreach(fun({Kind, Sources}) ->
        Forms0 = Header ++ [form(Source) || Source <- Sources],
        {Forms, Helpers} = xls_helpers:prepare(Forms0, [{root, 1}]),
        [Clause] = xls_parse:find_function(Forms, root, 1),
        #{body := Body, result := Value, failed := Failed} =
            xls_parse:clause_outcome(Clause, ["x"], cell, #{}),
        ok = file:write_file(filename:join(Stage, Kind ++ ".x"), [
            xls_helpers:emit(Helpers, cell, #{}),
            "pub fn root(x: u32) -> (u32, bool) {\n",
            xls_parse:print([Body, "(", Value, ", ", Failed, ")\n"]), "}\n"])
    end, [
        {"wrong_argument", ["root(X) -> narrow(X).",
            "-spec narrow(hls_nums:u8()) -> hls_nums:u32().",
            "narrow(X) -> hls_type:as(hls_nums:u32(), X)."]},
        {"wrong_join", ["root(X) -> case X =:= 0 of "
            "true -> Joined = hls_nums:wrap(hls_nums:u16(), X), X; "
            "false -> Joined = X, X end, Joined."]},
        {"wrong_result", ["root(X) -> narrow(X).",
            "-spec narrow(hls_nums:u32()) -> hls_nums:u8().", "narrow(X) -> X."]}
    ]).

form(Source) ->
    {ok, Tokens, _} = erl_scan:string(Source),
    {ok, Form} = erl_parse:parse_form(Tokens),
    Form.
