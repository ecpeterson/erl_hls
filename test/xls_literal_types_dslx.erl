-module(xls_literal_types_dslx).
-moduledoc false.
-export([write/1]).

-doc "Writes BEAM-derived literal-context interpreter/RTL vectors and type-error witnesses.".
-spec write(file:filename()) -> ok.
write(Stage) ->
    {ok, Forms} = epp:parse_file("test/xls_literal_fixture.erl", [], []),
    Cases = [{Mode, X} || Mode <- lists:seq(0, 27), X <- [0, 1, 2, 7, 8, 127, 255]],
    Expected = [{M, X, expected(M, X)} || {M, X} <- Cases],
    ok = file:write_file(filename:join(Stage, "literal_context.x"), [
        program(Forms, "run", ["mode", "x"], "mode: u8, x: u8"),
        "#[test]\nfn matches_beam() {\n  let cases = [\n",
        [io_lib:format("    (u8:~p, u8:~p, u33:~p),\n", [M, X, V])
            || {M, X, V} <- Expected],
        "  ];\n  for ((mode, x, expected), ()): ((u8, u8, u33), ()) in cases {\n",
        "    assert_eq(run(mode, x), expected);\n  } (())\n}\n"]),
    ok = file:write_file(filename:join(Stage, "literal_context_tb.sv"), [
        "module literal_context_tb;\nreg [7:0] mode, x; wire [32:0] out;\n",
        "literal_context dut(.mode(mode), .x(x), .out(out));\ninitial begin\n",
        [io_lib:format("mode=8'd~p; x=8'd~p; #1; if(out !== 33'd~p) "
            "$fatal(1, \"literal context mode=~p x=~p: %h\", out);\n", [M, X, V, M, X])
            || {M, X, V} <- Expected],
        io_lib:format("$display(\"PASS: ~p literal-context RTL vectors\");\n", [length(Expected)]),
        "$finish; end\nendmodule\n"]),
    rejections(Stage).

%% Preserve signed results as two's-complement bits; bit 32 denotes failure.
-spec expected(byte(), byte()) -> non_neg_integer().
expected(Mode, X) ->
    try xls_literal_fixture:run(Mode, X) of Value -> Value band 16#ffffffff
    catch error:{badmatch, _} -> 1 bsl 32; error:function_clause -> 1 bsl 32 end.

%% The wrapper observes the helper value only when its selected path succeeds.
-spec program([hls_source:form()], string(), [string()], string()) -> iodata().
program(Forms0, Name, Args, Signature) ->
    {Forms, Helpers} = xls_helpers:prepare(Forms0, [{list_to_atom(Name), length(Args)}]),
    Data = xls_parse:state(Forms),
    Tags = [Data | xls_parse:find_tags(Forms)],
    [Clause] = xls_parse:find_function(Forms, list_to_atom(Name), length(Args)),
    #{body := Body, result := Value, failed := Failed} =
        xls_parse:clause_outcome(Clause, Args, Data, #{}),
    [xls_dslx_imports:emit([hls_failure, hls_integer, hls_bits],
            xls_dslx_imports:from_forms(Forms)),
        "enum Tag : u8 { ", lists:join(", ", [[xls_names:enum_member(Tag), " = ",
            integer_to_list(I)] || {I, Tag} <- lists:enumerate(Tags)]), " }\n",
        [[xls_parse:struct_from_record(Record), xls_parse:bitsfromstruct_from_record(Record)]
            || Record = {attribute, _, record, _} <- Forms],
        xls_helpers:emit(Helpers, Data, #{}),
        "pub fn ", Name, "(", Signature, ") -> u33 {\n",
        xls_parse:print([Body, "if ", Failed, " { u33:0x100000000 } else { (",
            Value, " as u32) as u33 }\n"]), "}\n"].

%% Constraints cannot silently narrow existing values, including bound literals.
-spec rejections(file:filename()) -> ok.
rejections(Stage) ->
    lists:foreach(fun({Kind, Source}) ->
        Header = ["-module(literal_rejection).", "-hls_data(cell).", "-hls_tags([])."],
        Forms = [form(S) || S <- Header ++ Source],
        ok = file:write_file(filename:join(Stage, Kind ++ ".x"),
            program(Forms, "root", ["x"], "x: u32"))
    end, [
        {"literal_conflicting_uses", ["root(_) -> A = 1, narrow(A), wide(A).",
            "-spec narrow(hls_nums:u8()) -> hls_nums:u8().", "narrow(X) -> X.",
            "-spec wide(hls_nums:u32()) -> hls_nums:u32().", "wide(X) -> X."]},
        {"literal_existing_value", ["root(X) -> narrow(X).",
            "-spec narrow(hls_nums:u8()) -> hls_nums:u8().", "narrow(X) -> X."]},
        {"literal_record_existing_value", [
            "-record(cell, {value = hls_type:zero() :: hls_nums:u8()}).",
            "root(X) -> Cell = #cell{value = X}, Cell#cell.value."]},
        {"literal_record_conflicting_uses", [
            "-record(cell, {small = hls_type:zero() :: hls_nums:u8(), large = hls_type:zero() :: hls_nums:u32()}).",
            "root(_) -> Value = 1, Cell = #cell{small = Value, large = Value}, Cell#cell.large."]}
    ]).

%% Parse synthetic declarations without depending on generated BEAM metadata.
-spec form(string()) -> hls_source:form().
form(Source) ->
    {ok, Tokens, _} = erl_scan:string(Source),
    {ok, Form} = erl_parse:parse_form(Tokens),
    Form.
