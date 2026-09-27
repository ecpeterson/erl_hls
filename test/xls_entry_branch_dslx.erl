-module(xls_entry_branch_dslx).
-export([write/1]).

phases() ->
    [choice, nested, tail, appended, selected_failure, prefix_failure,
        bound, bound_tail, bound_tuple, discarded].

%% The expected final data and ordered emissions come from the compiled BEAM
%% callback. A raised badmatch yields no entry result and no action list.
oracle(Phase, Value) ->
    try xls_entry_branch_fixture:Phase(enter, Phase, {cell, Value}) of
        {{cell, Next}, Actions} ->
            Effects = [{Port, Message} || {cast, Port, Message} <- Actions],
            {false, Next, Effects}
    catch
        error:{badmatch, _} -> {true, Value, []}
    end.

-doc "Writes generated DSLX and the matching oracle or wrapper files into the test stage.".
-spec write(atom() | binary() | [atom() | [any()] | char()]) -> 'ok'.
write(Stage) ->
    {ok, Semantics} = file:read_file("test_data/xls_entry_branch_semantics.inc.x"),
    Generated = xls_parse:to_xls("test/xls_entry_branch_fixture.erl"),
    Cases = [{PhaseIndex, Phase, Value, Ready}
        || {PhaseIndex, Phase} <- lists:enumerate(0, phases()),
           Value <- lists:seq(0, 7),
           Ready <- [16#ffff, 16#aaa0, 0, 1, 3]],
    ok = file:write_file(filename:join(Stage, "xls_entry_branch.x"),
        [Generated, Semantics, dslx_tests(Cases)]),
    ok = file:write_file(filename:join(Stage, "xls_entry_branch_tb.sv"),
        testbench(Cases)).

%% Runs the BEAM oracle and packs its observable result for hardware comparison.
-spec expected(atom(),integer(),0 | 1 | 3 | 43680 | 65535) -> <<_:42,_:_*8>>.
expected(Phase, Value, Ready) ->
    {Failed, Next, Effects} = oracle(Phase, Value),
    Slots = length([Bit || Bit <- lists:seq(0, 15), Ready band (1 bsl Bit) =/= 0]),
    Accepted = lists:sublist(Effects, Slots),
    Pending = not Failed andalso length(Accepted) < length(Effects),
    Data = case Failed orelse Pending of true -> Value; false -> Next end,
    observation(Failed, Pending, Data, Accepted).

observation(Failed, Pending, Data, Accepted) ->
    Ports = [port(Port) || {Port, _} <- Accepted],
    Encoded = [wire(Message) || {_, Message} <- Accepted],
    Tags = [Tag || {Tag, _, _} <- Encoded],
    Lengths = [Length || {_, Length, _} <- Encoded],
    Values = [ValueBits || {_, _, ValueBits} <- Encoded],
    <<(bit(Failed)):1, (bit(Pending)):1, Data:32, (length(Accepted)):8,
        (pad_bytes(Ports))/binary, (pad_bytes(Tags))/binary,
        (pad_bytes(Lengths))/binary, (pad_values(Values))/binary>>.

bit(false) -> 0;
bit(true) -> 1.
port(first) -> 0;
port(second) -> 1;
port(third) -> 2.
pad_bytes(Values) -> list_to_binary(Values ++ lists:duplicate(3 - length(Values), 0)).
pad_values(Values) -> << <<V:64>> || V <- Values ++ lists:duplicate(3 - length(Values), 0) >>.

wire({small, Value}) -> {3, 1, Value};
wire({wide, Value, Check}) -> {4, 2, Value bor (Check bsl 32)}.

hex(Bits) ->
    Width = bit_size(Bits),
    <<Value:Width>> = Bits,
    integer_to_list(Value, 16).

%% Renders assertions against the BEAM-derived entry outcomes.
-spec dslx_tests([{integer(),atom(),integer(),0 | 1 | 3 | 43680 | 65535}]) -> [[[any()],...]].
dslx_tests(Cases) ->
    [["\n#[test]\nfn ", atom_to_list(Phase), "_", integer_to_list(Value),
        "_", integer_to_list(Ready), "() {\n",
        io_lib:format("  assert_eq(entry_probe( u8:~p, u32:~p, u16:~p),\n",
            [PhaseIndex, Value, Ready]),
        "    bits[306]:0x", hex(expected(Phase, Value, Ready)), ");\n}\n"]
        || {PhaseIndex, Phase, Value, Ready} <- Cases].

%% Renders the RTL scoreboard for the supplied expected outcomes.
-spec testbench([{integer(),atom(),integer(),0 | 1 | 3 | 43680 | 65535}]) -> [[[any()] | char()],...].
testbench(Cases) ->
    Vectors = lists:append([cycle_vectors(Case) || Case <- Cases]),
    ["module xls_entry_branch_tb;\n",
        "  reg pending, failed, ready; reg [7:0] phase, index; reg [31:0] value;\n",
        "  wire [313:0] observed;\n",
        "  entry_cycle_probe dut(.phase(phase), .value(value),\n",
        "    .pending(pending), .failed(failed), .index(index), .ready(ready), .out(observed));\n",
        "  initial begin\n",
        [cycle_vector(Vector) || Vector <- Vectors],
        io_lib:format("    $display(\"PASS: ~p branching entry RTL transitions (~p traces)\");\n",
            [length(Vectors), length(Cases)]),
        "    $finish;\n  end\nendmodule\n"].

%% Builds cycle inputs and expectations, including output backpressure.
-spec cycle_vectors({integer(),atom(),integer(),0 | 1 | 3 | 43680 | 65535}) -> [{integer(),term(),boolean(),<<_:8,_:_*1>>}].
cycle_vectors({PhaseIndex, Phase, Value, Ready}) ->
    Outcome = oracle(Phase, Value),
    {Vectors, _} = lists:mapfoldl(fun(Cycle, State) ->
        IsReady = Ready band (1 bsl Cycle) =/= 0,
        {Next, Emitted} = step(State, IsReady, Outcome),
        {Failed, Pending, Index, Data} = Next,
        Expected = <<Index:8, (observation(Failed, Pending, Data, Emitted))/bitstring>>,
        {{PhaseIndex, State, IsReady, Expected}, Next}
    end, {false, true, 0, Value}, lists:seq(0, 15)),
    Vectors.

%% Advances the CPU-derived reference state for one accepted operation.
-spec step(term(),boolean(),{'false',term(),[{term(),term()}]} | {'true',integer(),[]}) -> {term(),[{term(),term()}]}.
step( {Failed, Pending, _, _} = State, _Ready, _Outcome)
        when Failed; not Pending -> {State, []};
step( {_Failed, _Pending, Index, Data}, _Ready, {true, _, _}) ->
    {{true, false, Index, Data}, []};
step( _State, _Ready, {false, Next, []}) ->
    {{false, false, 0, Next}, []};
step( State, false, _Outcome) -> {State, []};
step( {false, true, Index, Data}, true, {false, Next, Effects}) ->
    State = case Index + 1 =:= length(Effects) of
        true -> {false, false, 0, Next};
        false -> {false, true, Index + 1, Data}
    end,
    {State, [lists:nth(Index + 1, Effects)]}.

%% Encodes one reference transition for the RTL testbench.
-spec cycle_vector({term(),{'false',boolean(),term(),term()} | {'true',boolean(),term(),term()},boolean(),bitstring()}) -> [[[any()] | char()],...].
cycle_vector({Phase, {Failed, Pending, Index, Data}, Ready, Expected}) ->
    [io_lib:format("    phase = 8'd~p; value = 32'd~p; pending = 1'b~p; failed = 1'b~p; index = 8'd~p; ready = 1'b~p; #1;\n",
        [Phase, Data, bit(Pending), bit(Failed), Index, bit(Ready)]),
        "    if (observed !== 314'h", hex(Expected), ")\n",
        io_lib:format("      $fatal(1, \"phase=~p value=~p pending=~p failed=~p index=~p ready=~p: %h\", observed);\n",
            [Phase, Data, Pending, Failed, Index, Ready])].
