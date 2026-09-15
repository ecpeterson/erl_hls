-module(xls_names_dslx).
-export([write/1]).

write(Stage) ->
    Grid = [0, 1, 2, 7, 16#7fffffff, 16#80000000, 16#fffffffe, 16#ffffffff],
    Cases = [{A, B, expected(A, B)} || A <- Grid, B <- Grid],
    {ok, Semantics} = file:read_file("test_data/hls_names_semantics.inc.x"),
    ok = file:write_file(filename:join(Stage, "names.x"), [
        xls_parse:to_xls("test/xls_names_fixture.erl", #{shared_service => aggregate_only}),
        Semantics, "#[test]\nfn beam_reduction_and_codecs() {\n",
        [io_lib:format("assert_eq(probe(u32:~B, u32:~B), bits[104]:~B);\n", [A, B, E])
            || {A, B, E} <- Cases], "}\n"]),
    ok = file:write_file(filename:join(Stage, "names_tb.sv"), testbench(Cases)),
    %% Type-check both actor service modes and the hls_gs callback codec calls.
    ok = file:write_file(filename:join(Stage, "ordinary.x"),
        xls_parse:to_xls("test/xls_names_fixture.erl")),
    ok = file:write_file(filename:join(Stage, "gs.x"), gs()),
    ok.

expected(A, B) ->
    {ok, 'Gathering', Data} = xls_names_fixture:init([]),
    {Data, [{open_reduction, 'SUM', Key, {count, 2}, {commutative_monoid, _}}]} =
        xls_names_fixture:'Gathering'(enter, 'Gathering', Data),
    {'Gathering', Data, {contribute, 'SUM', Key, Left}} =
        xls_names_fixture:'Gathering'(cast, {'Input_Value', Key, A}, Data),
    {'Gathering', Data, {contribute, 'SUM', Key, Right}} =
        xls_names_fixture:'Gathering'(cast, {'Input_Value', Key, B}, Data),
    Sum = xls_names_fixture:reduce('SUM', Left, Right),
    {'Complete', NextData, consume} = xls_names_fixture:'Gathering'(internal,
        {reduction_complete, 'SUM', Key, Sum}, Data),
    {NextData, [{cast, 'Result', Output}]} =
        xls_names_fixture:'Complete'(enter, 'Gathering', NextData),
    Value = binary:decode_unsigned(xls_names_fixture:pack(Output), little),
    (1 bsl 96) bor (Value bsl 64) bor (Value bsl 32) bor Value.

gs() ->
    {ok, Forms} = xls_parse:parse_file("test/xls_names_gs_fixture.erl"),
    [xls_parse:to_xls("test/xls_names_gs_fixture.erl"),
        "pub fn probe(value: u32) -> u32 {\n",
        "  let state_record = (Tag::SERVER_DATA, ServerData { Value: value });\n",
        "  let frame = axis::pack(Tag::GET_VALUE as u8, u32:0);\n",
        "  let (response, state) = match frame.header.op as Tag {\n",
        xls_gs_lower:callback_arms(Forms, 'Server_Data'), "};\n",
        "  replyvalue_from_bits(response.payload).Value\n}\n",
        "#[test]\nfn server_reply() {\n",
        [begin
            {reply, Reply, _} = xls_names_gs_fixture:handle_call({'Get_Value', 0}, {'Server_Data', V}),
            E = binary:decode_unsigned(xls_names_gs_fixture:pack(Reply), little),
            io_lib:format("assert_eq(probe(u32:~B), u32:~B);\n", [V, E])
        end || V <- [0, 17, 16#ffffffff]], "}\n"].

testbench(Cases) ->
    ["module names_tb;\nreg [31:0] a,b; wire [103:0] out;\n",
        "probe dut(.a(a), .b(b), .out(out));\ninitial begin\n",
        [io_lib:format("a=32'd~B; b=32'd~B; #1;\n"
            "if (out !== 104'd~B) $fatal(1, \"namespace probe mismatch: %h\", out);\n",
            [A, B, E]) || {A, B, E} <- Cases],
        io_lib:format("$display(\"PASS: ~B BEAM-derived mixed-case reduction/codec RTL cases\");\n",
            [length(Cases)]), "$finish; end\nendmodule\n"].
