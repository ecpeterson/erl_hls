-module(xls_binary_dslx).
-export([write/1]).

write(Stage) ->
    {ok, Forms0} = epp:parse_file("test/xls_binary_fixture.erl", [], []),
    Probes = xls_binary_fixture:probes(),
    {Forms, Helpers} = xls_helpers:prepare(Forms0, [{N, 2} || {N, _} <- Probes]),
    Grid = [{X, <<B:24>>} || X <- [-256, -1, 0, 1, 127, 255, 256, 65535],
        B <- [0, 1, 16#ffffff, 16#800080, 16#fffeff, 16#a50180, 16#a5ffff,
            16#010100, 16#abcdef, 16#abcabc, 16#414243, 16#7fff7f]],
    Expected = [{I, Name, [{Input, expected(Name, Input)} || Input <- Grid]}
        || {I, {Name, _}} <- lists:enumerate(0, Probes)],
    Text = [xls_dslx_imports:emit([hls_failure], xls_dslx_imports:from_forms(Forms)),
        xls_helpers:emit(Helpers, unused, #{}),
        [function(Name, Kind, Forms) || {Name, Kind} <- Probes],
        "pub fn probe(mode: u32, x: s32, raw: u24) -> bits[36] {\nmatch mode {\n",
        [["u32:", integer_to_list(I), " => probe_", atom_to_list(Name), "(x, (raw,)),\n"]
            || {I, Name, _} <- Expected], "_ => bits[36]:0\n}\n}\n",
        "pub fn wire_probe(raw: u24) -> bits[36] { probe_wire(s32:0, (raw,)) }\n",
        [test(Name, Cases) || {_, Name, Cases} <- Expected]],
    ok = file:write_file(filename:join(Stage, "binary.x"), Text),
    ok = file:write_file(filename:join(Stage, "binary_tb.sv"), testbench(Expected)),
    codecs(Stage).

function(Name, Kind, Forms) ->
    [Clause] = xls_parse:find_function(Forms, Name, 2),
    #{body := Body, result := Value, failure := Failure} =
        xls_parse:clause_outcome(Clause, ["x", "value"], unused, #{}),
    Result = case Kind of bits -> ["(", Value, ").0"]; integer -> Value end,
    ["fn probe_", atom_to_list(Name), "(x: s32, value: (u24,)) -> bits[36] {\n",
        xls_parse:print(Body), "let code = ", xls_parse:print(Failure), ";\n",
        "let value = if code != hls_failure::NONE { u32:0 } else { (",
        xls_parse:print(Result), ") as u32 };\n",
        "(hls_failure::kind(code) as u4) ++ value\n}\n"].

expected(Name, {X, Value}) ->
    try apply(xls_binary_fixture, Name, [X, Value]) of
        Result when is_bitstring(Result) ->
            Width = bit_size(Result), <<N:Width>> = Result, N;
        Result -> Result band 16#ffffffff
    catch
        error:function_clause -> 1 bsl 32;
        error:{badmatch, _} -> 2 bsl 32;
        error:{case_clause, _} -> 4 bsl 32;
        error:badarith -> 13 bsl 32;
        error:badarg -> 14 bsl 32
    end.

test(Name, Cases) ->
    ["#[test]\nfn check_", atom_to_list(Name), "() {\nlet cases = [\n",
        [io_lib:format("(s32:~p, u24:~p, bits[36]:~p),\n", [X,B,V])
            || {{X, <<B:24>>}, V} <- Cases],
        "];\nfor (i, ()): (u32, ()) in u32:0..u32:", integer_to_list(length(Cases)), " {\n",
        "let (x, b, expected) = cases[i];\nassert_eq(probe_", atom_to_list(Name),
        "(x, (b,)), expected);\n} (())\n}\n"].

testbench(Expected) ->
    ["module binary_tb;\nreg [31:0] mode, x; reg [23:0] raw; wire [35:0] out;\n",
        "probe dut(.mode(mode), .x(x), .raw(raw), .out(out));\ninitial begin\n",
        [[io_lib:format("mode=32'd~p; x=32'h~.16b; raw=24'h~.16b; #1;\n"
            "if (out !== 36'h~.16b) $fatal(1, \"~s x=~p raw=~p: got %h\", out);\n",
            [I, X band 16#ffffffff, B, V, Name, X, B])
            || {{X,<<B:24>>},V} <- Cases] || {I,Name,Cases} <- Expected],
        io_lib:format("$display(\"PASS: ~p bit-syntax RTL vectors\");\n$finish;\nend\nendmodule\n",
            [lists:sum([length(C) || {_,_,C} <- Expected])])].

%% Check both codec directions against BEAM independently; a pair of inverse
%% mistakes must not pass merely because encode(decode(x)) returns x.
codecs(Stage) ->
    Widths = [0, 1, 3, 7, 8, 9, 13, 16, 17, 23, 24, 31, 32, 33, 65, 127],
    Values = [0, 1, 16#ffffffffffffffffffffffffffffffff,
        16#123456789abcdef00102030405060708],
    Cases = [{I, Raw, begin
        <<Stream:W>> = <<Raw:W/little>>,
        Wire = hls_codec:unsigned(<<Raw:W>>),
        (Stream bsl 128) bor Wire
    end} || {I, W} <- lists:enumerate(0, Widths), Raw <- Values],
    Text = ["import hls_bits;\npub fn codec_probe(raw: bits[128], kind: u8) -> bits[256] {\nmatch kind {\n",
        [begin
            T = hls_bits:bits(W), Part = ["raw[0+:bits[", integer_to_list(W), "]]"] ,
            ["u8:", integer_to_list(I), " => {\nlet decoded = ", hls_type:dslx_from_bits(T, Part),
                ";\nlet encoded = ", hls_type:dslx_to_bits(T, ["(", Part, ",)"]),
                ";\n(decoded.0 as bits[128]) ++ (encoded as bits[128]) },\n"]
        end || {I,W} <- lists:enumerate(0, Widths)],
        "_ => bits[256]:0\n}\n}\n#[test]\nfn host_codec_directions() {\n",
        [io_lib:format("assert_eq(codec_probe(bits[128]:~p, u8:~p), bits[256]:~p);\n", [Raw, I, Expected])
            || {I, Raw, Expected} <- Cases], "}\n"],
    ok = file:write_file(filename:join(Stage, "binary_codecs.x"), Text),
    ok = file:write_file(filename:join(Stage, "binary_codecs_tb.sv"), [
        "module binary_codecs_tb;\nreg [127:0] raw; reg [7:0] kind; wire [255:0] out;\n",
        "codec_probe dut(.raw(raw), .kind(kind), .out(out));\ninitial begin\n",
        [io_lib:format("raw=128'h~.16b; kind=8'd~p; #1; if(out !== 256'h~.16b) $fatal(1,\"codec ~p got %h\",out);\n",
            [Raw, I, Expected, I]) || {I, Raw, Expected} <- Cases],
        "$display(\"PASS: 64 independent bitstring encode/decode RTL vectors\");$finish;\nend\nendmodule\n"]).
