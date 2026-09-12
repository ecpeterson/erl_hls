-module(xls_entry_outcome_dslx).
-export([write/1]).

phases() ->
    [prefix, data, condition, message, precomputed, skipped, shared_values, empty, noncase, nonif, nonsegment, nonguarded, nonunused].

%% The expected final data and ordered emissions come from the compiled BEAM
%% callback. A raised badmatch yields no entry result and no action list.
oracle(Phase, Value) ->
    try xls_entry_outcome_fixture:Phase(enter, Phase, {cell, Value}) of
        {{cell, Next}, Actions} ->
            Effects = [{Port, Payload} || {cast, Port, {value, Payload}} <- Actions],
            {false, Next, Effects}
    catch
        error:{badmatch, _} -> {true, Value, []};
        error:{case_clause, _} -> {true, Value, []};
        error:if_clause -> {true, Value, []}
    end.

write(Stage) ->
    {ok, Semantics} = file:read_file("test_data/xls_entry_outcome_semantics.inc.x"),
    Generated = xls_parse:to_xls("test/xls_entry_outcome_fixture.erl"),
    Cases = [{Shared, PhaseIndex, Phase, Value, Ready}
        || Shared <- [false, true],
           {PhaseIndex, Phase} <- lists:enumerate(0, phases()),
           Value <- [0, 1, 2, 3],
           Ready <- [16#ffff, 16#aaa0, 0]],
    ok = file:write_file(filename:join(Stage, "xls_entry_outcome.x"),
        [Generated, Semantics, dslx_tests(Cases)]),
    ok = file:write_file(filename:join(Stage, "xls_entry_outcome_tb.sv"),
        testbench(Cases)),
    {ok, ReductionTests} = file:read_file(
        "test_data/xls_entry_reduction_semantics.inc.x"),
    lists:foreach(fun({Mode, Name}) ->
        X = xls_parse:to_xls("test/xls_entry_reduction_fixture.erl",
            #{shared_service => Mode}),
        ok = file:write_file(filename:join(Stage, Name), [X, ReductionTests])
    end, [{ordinary, "xls_entry_reduction.x"},
        {aggregate_only, "xls_entry_reduction_aggregate.x"}]).

expected(Phase, Value, Ready) ->
    {Failed, Next, Effects} = oracle(Phase, Value),
    %% Account only for externally accepted frames. The direct actor retires
    %% one output per ready cycle; the shared actor commits
    %% its complete batch in one activation when space is reserved.
    {Pending, Data, Accepted} = case {Failed, Effects, Ready} of
        {true, _, _} -> {false, Value, []};
        {false, [], _} -> {false, Next, []};
        {false, _, 0} -> {true, Value, []};
        _ -> {false, Next, Effects}
    end,
    Ports = [port(Port) || {Port, _} <- Accepted],
    Values = [Payload || {_, Payload} <- Accepted],
    <<(bit(Failed)):1, (bit(Pending)):1, Data:32, (length(Accepted)):8,
        (pad_bytes(Ports))/binary, (pad_values(Values))/binary>>.

bit(false) -> 0;
bit(true) -> 1.
port(first) -> 0;
port(second) -> 1;
port(third) -> 2.
pad_bytes(Values) -> list_to_binary(Values ++ lists:duplicate(3 - length(Values), 0)).
pad_values(Values) -> << <<V:32>> || V <- Values ++ lists:duplicate(3 - length(Values), 0) >>.

hex(Bits) ->
    Width = bit_size(Bits),
    <<Value:Width>> = Bits,
    integer_to_list(Value, 16).

dslx_tests(Cases) ->
    [["\n#[test]\nfn ", atom_to_list(Phase), "_", integer_to_list(Value),
        "_", atom_to_list(Shared), "_", integer_to_list(Ready), "() {\n",
        io_lib:format("  assert_eq(entry_probe(~p, u8:~p, u32:~p, u16:~p),\n",
            [Shared, PhaseIndex, Value, Ready]),
        "    bits[162]:0x", hex(expected(Phase, Value, Ready)), ");\n}\n"]
        || {Shared, PhaseIndex, Phase, Value, Ready} <- Cases].

testbench(Cases) ->
    ["module xls_entry_outcome_tb;\n",
        "  reg shared; reg [7:0] phase; reg [31:0] value; reg [15:0] ready;\n",
        "  wire [161:0] observed;\n",
        "  entry_probe dut(.shared(shared), .phase(phase), .value(value),\n",
        "    .ready(ready), .out(observed));\n",
        "  initial begin\n",
        [[io_lib:format("    shared = 1'b~p; phase = 8'd~p; value = 32'd~p; ready = 16'd~p; #1;\n",
                [bit(Shared), PhaseIndex, Value, Ready]),
            "    if (observed !== 162'h", hex(expected(Phase, Value, Ready)), ")\n",
            io_lib:format("      $fatal(1, \"~p ~p ~p ready=~p: %h\", observed);\n",
                [Shared, Phase, Value, Ready])]
            || {Shared, PhaseIndex, Phase, Value, Ready} <- Cases],
        io_lib:format("    $display(\"PASS: ~p entry outcome RTL vectors\");\n", [length(Cases)]),
        "    $finish;\n  end\nendmodule\n"].
