-module(xls_protocol_spacetime_dependencies_tests).
-moduledoc "Localized witnesses of selected XLS operand reconstruction; no compiler, simulator or native implementation is invoked.".
-include_lib("eunit/include/eunit.hrl").

%% Two data registers and a selector exercise exact bit projection and branch choice.
-spec fixture() -> {binary(), binary(), [xls_protocol_spacetime_dependencies:register()]}.
fixture() ->
    Ir = <<
        "  __state_0: bits[8] = state_read(state_element=__state_0, id=1)\n",
        "  __state_1: bits[8] = state_read(state_element=__state_1, id=2)\n",
        "  __state_2: bits[1] = state_read(state_element=__state_2, id=3)\n",
        "  lo: bits[4] = bit_slice(__state_0, start=0, width=4, id=4)\n",
        "  hi: bits[4] = bit_slice(__state_1, start=4, width=4, id=5)\n",
        "  joined: bits[8] = concat(hi, lo, id=6)\n",
        "  flipped: bits[8] = reverse(joined, id=7)\n",
        "  picked: bits[8] = sel(__state_2, cases=[joined, flipped], id=8)\n",
        "  true_value: bits[1] = literal(value=1, id=9)\n",
        "  update: () = next_value(state_element=__state_0, value=picked, predicate=true_value, id=10)\n"
    >>,
    Rtl = <<"  reg [7:0] ____state_0;\n  reg [7:0] ____state_1;\n  reg ____state_2;\n">>,
    Registers = [#{name => Name, width => W, data => <<"D">>, enable => <<"CE">>, rule => enabled_same_edge_register_write}
        || {Name,W} <- [{<<"____state_0">>,8},{<<"____state_1">>,8},{<<"____state_2">>,1}]],
    {Ir,Rtl,Registers}.

%% Prepare a fresh immutable plan and observed pre-edge values for each test.
-spec setup(non_neg_integer()) -> {xls_protocol_spacetime_dependencies:plan(), xls_protocol_spacetime_dependencies:sample()}.
setup(Selector) ->
    {Ir,Rtl,Registers}=fixture(), P=xls_protocol_spacetime_dependencies:plan(Ir,Rtl,Registers),
    {P,xls_protocol_spacetime_dependencies:sample(P,#{<<"____state_0">>=>16#AB,<<"____state_1">>=>16#C4,<<"____state_2">>=>Selector})}.

%% Dynamic selection retains only the selected branch's requested data bits and selector control.
-spec selected_slice_test() -> ok.
selected_slice_test() ->
    {P,S0}=setup(0), R0=xls_protocol_spacetime_dependencies:read(P,<<"picked">>,16#0F,S0),
    ?assertEqual(16#CB,maps:get(value,R0)),
    ?assertEqual(#{<<"____state_0">>=>16#0F},maps:get(data_masks,R0)),
    ?assertEqual(#{<<"____state_2">>=>1},maps:get(control_masks,R0)),
    {P,S1}=setup(1), R1=xls_protocol_spacetime_dependencies:read(P,<<"picked">>,16#0F,S1),
    ?assertEqual(16#D3,maps:get(value,R1)),
    ?assertEqual(#{<<"____state_1">>=>16#F0},maps:get(data_masks,R1)).

%% An enabled write uses its selected next_value and both source ranges without equality matching.
-spec write_sources_test() -> ok.
write_sources_test() ->
    {P,S}=setup(0), R=xls_protocol_spacetime_dependencies:write(P,<<"____state_0">>,S),
    ?assertEqual([<<"update">>],maps:get(selected,R)),
    ?assertEqual(#{<<"____state_0">>=>15,<<"____state_1">>=>240},maps:get(data_masks,R)),
    ?assertEqual([],maps:get(unknown,R)).

%% Unsupported operations in an unselected branch do not poison known selected data.
-spec opaque_branch_test() -> ok.
opaque_branch_test() ->
    {Ir,Rtl,Registers}=fixture(),
    Extra= <<"  opaque: bits[8] = unsupported(joined, id=11)\n  choose: bits[8] = sel(__state_2, cases=[joined, opaque], id=12)\n">>,
    P=xls_protocol_spacetime_dependencies:plan(<<Ir/binary,Extra/binary>>,Rtl,Registers),
    S0=xls_protocol_spacetime_dependencies:sample(P,#{<<"____state_0">>=>1,<<"____state_1">>=>2,<<"____state_2">>=>0}),
    ?assertEqual([],maps:get(unknown,xls_protocol_spacetime_dependencies:read(P,<<"choose">>,255,S0))),
    S1=xls_protocol_spacetime_dependencies:sample(P,#{<<"____state_0">>=>1,<<"____state_1">>=>2,<<"____state_2">>=>1}),
    ?assertEqual([reason({unsupported_node,<<"opaque">>,<<"unsupported">>})],maps:get(unknown,xls_protocol_spacetime_dependencies:read(P,<<"choose">>,255,S1))).

%% Missing selector values stop branch attribution instead of including every alternative.
-spec missing_selector_test() -> ok.
missing_selector_test() ->
    {Ir,Rtl,Registers}=fixture(),P=xls_protocol_spacetime_dependencies:plan(Ir,Rtl,Registers),
    S=xls_protocol_spacetime_dependencies:sample(P,#{<<"____state_0">>=>1,<<"____state_1">>=>2}),
    R=xls_protocol_spacetime_dependencies:read(P,<<"picked">>,255,S),
    ?assertEqual(unknown,maps:get(value,R)),?assertEqual(#{},maps:get(data_masks,R)),
    ?assert(lists:member(reason({unknown_selector,<<"picked">>,<<"__state_2">>}),maps:get(unknown,R))).

%% Direct received tuple slices are checked structurally and remain external-input roots.
-spec input_binding_test() -> ok.
input_binding_test() ->
    Ir= <<"  token: token = after_all(id=1)\n  received: (token, (bits[1], bits[3])) = receive(token, channel=_commands, id=2)\n  input: (bits[1], bits[3]) = tuple_index(received, index=1, id=3)\n  input_flag: bits[1] = tuple_index(input, index=0, id=4)\n  input_data: bits[3] = tuple_index(input, index=1, id=5)\n">>,
    Rtl= <<"  wire input_flag;\n  wire [2:0] input_data;\n  assign input_flag = _commands[3:3];\n  assign input_data = _commands[2:0];\n">>,
    P=xls_protocol_spacetime_dependencies:plan(Ir,Rtl,[]),
    ?assertEqual(2,length(xls_protocol_spacetime_dependencies:signals(P))),
    S=xls_protocol_spacetime_dependencies:sample(P,#{<<"input_flag">>=>1,<<"input_data">>=>5}),
    R=xls_protocol_spacetime_dependencies:read(P,<<"input_data">>,7,S),
    ?assertEqual(5,maps:get(value,R)),?assertEqual([reason({external_input,<<"input_data">>,7,data})],maps:get(unknown,R)),
    Bad=binary:replace(Rtl,<<"_commands[2:0]">>,<<"_commands[3:1]">>),
    ?assertEqual(1,length(xls_protocol_spacetime_dependencies:signals(xls_protocol_spacetime_dependencies:plan(Ir,Bad,[])))).

%% Conflicting next_value guards do not invent write priority absent from the XLS contract.
-spec overlapping_updates_test() -> ok.
overlapping_updates_test() ->
    {Ir,Rtl,Registers}=fixture(),Extra= <<"  second: () = next_value(state_element=__state_0, value=joined, predicate=true_value, id=11)\n">>,
    P=xls_protocol_spacetime_dependencies:plan(<<Ir/binary,Extra/binary>>,Rtl,Registers),
    S=xls_protocol_spacetime_dependencies:sample(P,#{<<"____state_0">>=>1,<<"____state_1">>=>2,<<"____state_2">>=>0}),
    R=xls_protocol_spacetime_dependencies:write(P,<<"____state_0">>,S),
    ?assertEqual(unknown,maps:get(value,R)),?assertEqual(#{},maps:get(data_masks,R)).

%% Arithmetic carries require lower source bits, whereas sign extension uses the sign bit alone.
-spec arithmetic_masks_test() -> ok.
arithmetic_masks_test() ->
    {Ir,Rtl,Registers}=fixture(), Extra= <<"  sum: bits[8] = add(__state_0, __state_1, id=11)\n  extended: bits[16] = sign_ext(__state_0, new_bit_count=16, id=12)\n">>,
    P=xls_protocol_spacetime_dependencies:plan(<<Ir/binary,Extra/binary>>,Rtl,Registers),
    S=xls_protocol_spacetime_dependencies:sample(P,#{<<"____state_0">>=>128,<<"____state_1">>=>1,<<"____state_2">>=>0}),
    R=xls_protocol_spacetime_dependencies:read(P,<<"sum">>,8,S),
    ?assertEqual(#{<<"____state_0">>=>15,<<"____state_1">>=>15},maps:get(data_masks,R)),
    ?assertEqual(#{<<"____state_0">>=>128},maps:get(data_masks,xls_protocol_spacetime_dependencies:read(P,<<"extended">>,16#FF00,S))).

%% Planning and observed values reject widths or identities that could silently misbind data.
-spec rejection_test() -> ok.
rejection_test() ->
    {Ir,Rtl,Registers}=fixture(), P=xls_protocol_spacetime_dependencies:plan(Ir,Rtl,Registers),
    ?assertError({spacetime_dependency_value,<<"____state_0">>,8,256},xls_protocol_spacetime_dependencies:sample(P,#{<<"____state_0">>=>256})),
    ?assertError({badmatch,true},xls_protocol_spacetime_dependencies:plan(<<Ir/binary,"  __state_0: bits[8] = literal(value=0, id=99)\n">>,Rtl,Registers)),
    ?assertError({badmatch,false},xls_protocol_spacetime_dependencies:plan(<<"  wide: bits[4097] = literal(value=0, id=1)\n">>,<<>>,[])).

%% Binary diagnostics can be carried unchanged by the observer's JSON evidence envelope.
-spec reason(term()) -> binary().
reason(Term) -> iolist_to_binary(io_lib:format("~tp", [Term])).

%% A coalesced startup flag still selects writes through its exact proc recurrence.
-spec equivalent_state_test() -> ok.
equivalent_state_test() ->
    {Ir, Rtl, Registers} = equivalent_fixture(<<"0">>, <<"value=one">>, false),
    P = xls_protocol_spacetime_dependencies:plan(Ir, Rtl, Registers),
    B = maps:get(<<"folded">>, maps:get(bindings, P)),
    ?assertEqual(<<"__state_0">>, maps:get(equivalent_state, B)),
    ?assertEqual(<<"____state_0">>, maps:get(signal, B)),
    S = xls_protocol_spacetime_dependencies:sample(P, #{<<"____state_0">> => 1, <<"__result">> => 0}),
    R = xls_protocol_spacetime_dependencies:write(P, <<"__result">>, S),
    ?assertEqual(42, maps:get(value, R)),
    ?assertEqual(#{<<"____state_0">> => 1}, maps:get(control_masks, R)),
    ?assertEqual([], maps:get(unknown, R)),
    %% Alias nodes must not make the original register's update binding ambiguous.
    ?assertEqual(1, maps:get(value, xls_protocol_spacetime_dependencies:write(P, <<"____state_0">>, S))).

%% Initial values, update expression and guard are semantic, not cosmetic matches.
-spec unequal_recurrence_test() -> ok.
unequal_recurrence_test() ->
    lists:foreach(fun({Initial, Update}) ->
        {Ir, Rtl, Registers} = equivalent_fixture(Initial, Update, false),
        P = xls_protocol_spacetime_dependencies:plan(Ir, Rtl, Registers),
        ?assertNot(maps:is_key(<<"folded">>, maps:get(bindings, P)))
    end, [{<<"1">>, <<"value=one">>}, {<<"0">>, <<"value=zero">>},
          {<<"0">>, <<"value=one, predicate=one">>}]).

%% No unique observed representative means no native identity is chosen.
-spec ambiguous_recurrence_test() -> ok.
ambiguous_recurrence_test() ->
    {Ir, Rtl, Registers} = equivalent_fixture(<<"0">>, <<"value=one">>, true),
    WithThird = binary:replace(Ir, <<"result: bits[8], init={0, 0, 0}">>,
        <<"result: bits[8], folded_again: bits[1], init={0, 0, 0, 0}">>),
    Third = <<WithThird/binary,
        "  folded_again: bits[1] = state_read(state_element=folded_again, id=20)\n",
        "  third: () = next_value(state_element=folded_again, value=one, id=21)\n">>,
    P = xls_protocol_spacetime_dependencies:plan(Third, Rtl, Registers),
    ?assertNot(maps:is_key(equivalent_state, maps:get(<<"folded">>, maps:get(bindings, P)))),
    ?assertNot(maps:is_key(<<"folded_again">>, maps:get(bindings, P))),
    %% Remove both direct flag representatives while retaining the data register.
    P0 = xls_protocol_spacetime_dependencies:plan(Ir, <<"  reg [7:0] __result;\n">>,
        [R || R = #{name := N} <- Registers, N =:= <<"__result">>]),
    ?assertNot(maps:is_key(<<"folded">>, maps:get(bindings, P0))).

%% Channel parameters and source positions are outside the scalar state initializer.
-spec equivalent_proc_header_test() -> ok.
equivalent_proc_header_test() ->
    {Ir, Rtl, Registers} = equivalent_fixture(<<"0">>, <<"value=one">>, false),
    Header = binary:replace(Ir, <<"top proc sample(__state_0: bits[1],">>,
        <<"top proc sample<commands: (bits[1], bits[8]) in>(__state_0: bits[1] pos=[(1,2,3)],">>),
    P = xls_protocol_spacetime_dependencies:plan(Header, Rtl, Registers),
    ?assertEqual(<<"__state_0">>, maps:get(equivalent_state, maps:get(<<"folded">>, maps:get(bindings, P)))).

%% Multiple procs, aggregate/malformed initial values and conflicting updates
%% cannot establish the common transition and unique-update argument.
-spec unsupported_recurrence_test() -> ok.
unsupported_recurrence_test() ->
    {Ir, Rtl, Registers} = equivalent_fixture(<<"0">>, <<"value=one">>, false),
    Variants = [
        <<Ir/binary, "proc other(s: bits[1], init={0}) {\n}\n">>,
        binary:replace(Ir, <<"init={0, 0, 0}">>, <<"init={0, (0, 0), 0}">>),
        binary:replace(Ir, <<"init={0, 0, 0}">>, <<"init={0, 2, 0}">>),
        binary:replace(Ir, <<"init={0, 0, 0}">>, <<"init={0, _, 0}">>),
        binary:replace(Ir, <<"init={0, 0, 0}">>, <<"init={0, 0x_, 0}">>),
        <<Ir/binary, "  extra: () = next_value(state_element=folded, value=one, predicate=one, id=20)\n">>
    ],
    lists:foreach(fun(Bad) ->
        P = xls_protocol_spacetime_dependencies:plan(Bad, Rtl, Registers),
        ?assertNot(maps:is_key(<<"folded">>, maps:get(bindings, P)))
    end, Variants).

%% Different source widths cannot share the representative's sampled bits.
-spec equivalent_width_test() -> ok.
equivalent_width_test() ->
    {Ir, Rtl, Registers} = equivalent_fixture(<<"0">>, <<"value=one">>, false),
    Wide = binary:replace(Ir, <<"folded: bits[1]">>, <<"folded: bits[2]">>, [global]),
    P = xls_protocol_spacetime_dependencies:plan(Wide, Rtl, Registers),
    ?assertNot(maps:is_key(<<"folded">>, maps:get(bindings, P))).

%% The selected predicate refers to an IR state whose RTL copy was coalesced.
-spec equivalent_fixture(binary(), binary(), boolean()) ->
    {binary(), binary(), [xls_protocol_spacetime_dependencies:register()]}.
equivalent_fixture(Initial, Update, BothObserved) ->
    Ir = iolist_to_binary([
        "top proc sample(__state_0: bits[1], folded: bits[1], result: bits[8], init={0, ", Initial, ", 0}) {\n",
        "  __state_0: bits[1] = state_read(state_element=__state_0, id=1)\n",
        "  folded: bits[1] = state_read(state_element=folded, id=2)\n",
        "  result: bits[8] = state_read(state_element=result, id=3)\n",
        "  one: bits[1] = literal(value=1, id=4)\n",
        "  zero: bits[1] = literal(value=0, id=5)\n",
        "  answer: bits[8] = literal(value=42, id=6)\n",
        "  a: () = next_value(state_element=__state_0, value=one, id=7)\n",
        "  b: () = next_value(state_element=folded, ", Update, ", id=8)\n",
        "  c: () = next_value(state_element=result, value=answer, predicate=folded, id=9)\n}\n"
    ]),
    Names = [{<<"____state_0">>, 1}, {<<"__result">>, 8}] ++
        case BothObserved of true -> [{<<"__folded">>, 1}]; false -> [] end,
    Rtl = iolist_to_binary([["  reg ", case W of 1 -> []; _ -> ["[", integer_to_list(W-1), ":0] "] end,
        N, ";\n"] || {N, W} <- Names]),
    Registers = [#{name => N, width => W, data => <<"D">>, enable => <<"CE">>,
        rule => enabled_same_edge_register_write} || {N, W} <- Names],
    {Ir, Rtl, Registers}.

%% Priority selection chooses the lowest asserted lane; one-hot selection combines all asserted lanes.
-spec multi_selector_test() -> ok.
multi_selector_test() ->
    {Ir,Rtl,Registers}=fixture(),
    Extra = <<
      "  select_bits: bits[2] = bit_slice(__state_0, start=0, width=2, id=11)\n",
      "  priority: bits[8] = priority_sel(select_bits, cases=[__state_0, __state_1], default=joined, id=12)\n",
      "  multi: bits[8] = one_hot_sel(select_bits, cases=[__state_0, __state_1], id=13)\n"
    >>,
    P=xls_protocol_spacetime_dependencies:plan(<<Ir/binary,Extra/binary>>,Rtl,Registers),
    S=xls_protocol_spacetime_dependencies:sample(P,#{<<"____state_0">>=>3,<<"____state_1">>=>16#C4,<<"____state_2">>=>0}),
    Priority=xls_protocol_spacetime_dependencies:read(P,<<"priority">>,255,S),
    ?assertEqual(3,maps:get(value,Priority)),
    ?assertEqual(#{<<"____state_0">>=>255},maps:get(data_masks,Priority)),
    ?assertEqual(#{<<"____state_0">>=>3},maps:get(control_masks,Priority)),
    Multi=xls_protocol_spacetime_dependencies:read(P,<<"multi">>,255,S),
    ?assertEqual(16#C7,maps:get(value,Multi)),
    ?assertEqual(#{<<"____state_0">>=>255,<<"____state_1">>=>255},maps:get(data_masks,Multi)),
    Zero=xls_protocol_spacetime_dependencies:sample(P,#{<<"____state_0">>=>0,<<"____state_1">>=>16#C4,<<"____state_2">>=>0}),
    ?assertEqual(16#C0,maps:get(value,xls_protocol_spacetime_dependencies:read(P,<<"priority">>,255,Zero))),
    Empty=xls_protocol_spacetime_dependencies:read(P,<<"multi">>,255,Zero),
    ?assertEqual(0,maps:get(value,Empty)),?assertEqual(#{},maps:get(data_masks,Empty)).

%% Signed scalar arithmetic follows XLS truncation/extension; unsupported signed shifts remain opaque.
-spec signed_values_test() -> ok.
signed_values_test() ->
    {Ir,Rtl,Registers}=fixture(),
    Extra = <<
      "  extended: bits[16] = sign_ext(__state_0, new_bit_count=16, id=11)\n",
      "  product: bits[16] = smul(__state_0, __state_1, id=12)\n",
      "  narrow_product: bits[4] = smul(__state_0, __state_1, id=13)\n",
      "  less: bits[1] = slt(__state_0, __state_1, id=14)\n",
      "  shifted: bits[8] = shra(__state_0, __state_1, id=15)\n"
    >>,
    P=xls_protocol_spacetime_dependencies:plan(<<Ir/binary,Extra/binary>>,Rtl,Registers),
    S=xls_protocol_spacetime_dependencies:sample(P,#{<<"____state_0">>=>254,<<"____state_1">>=>3,<<"____state_2">>=>0}),
    ?assertEqual(65534,maps:get(value,xls_protocol_spacetime_dependencies:read(P,<<"extended">>,65535,S))),
    ?assertEqual(65530,maps:get(value,xls_protocol_spacetime_dependencies:read(P,<<"product">>,65535,S))),
    ?assertEqual(10,maps:get(value,xls_protocol_spacetime_dependencies:read(P,<<"narrow_product">>,15,S))),
    ?assertEqual(1,maps:get(value,xls_protocol_spacetime_dependencies:read(P,<<"less">>,1,S))),
    Shift=xls_protocol_spacetime_dependencies:read(P,<<"shifted">>,255,S),
    ?assertEqual(unknown,maps:get(value,Shift)),
    ?assertEqual([reason({unsupported_node,<<"shifted">>,<<"shra">>})],maps:get(unknown,Shift)).

%% The zero sentinel and priority direction agree with XLS's one_hot interpreter contract.
-spec one_hot_values_test() -> ok.
one_hot_values_test() ->
    {Ir,Rtl,Registers}=fixture(),
    Extra = <<
      "  lsb: bits[9] = one_hot(__state_0, lsb_prio=true, id=11)\n",
      "  msb: bits[9] = one_hot(__state_0, lsb_prio=false, id=12)\n"
    >>,
    P=xls_protocol_spacetime_dependencies:plan(<<Ir/binary,Extra/binary>>,Rtl,Registers),
    S=xls_protocol_spacetime_dependencies:sample(P,#{<<"____state_0">>=>16#90,<<"____state_1">>=>0,<<"____state_2">>=>0}),
    ?assertEqual(16#10,maps:get(value,xls_protocol_spacetime_dependencies:read(P,<<"lsb">>,511,S))),
    ?assertEqual(16#80,maps:get(value,xls_protocol_spacetime_dependencies:read(P,<<"msb">>,511,S))),
    Zero=xls_protocol_spacetime_dependencies:sample(P,#{<<"____state_0">>=>0,<<"____state_1">>=>0,<<"____state_2">>=>0}),
    ?assertEqual(256,maps:get(value,xls_protocol_spacetime_dependencies:read(P,<<"lsb">>,511,Zero))),
    ?assertEqual(256,maps:get(value,xls_protocol_spacetime_dependencies:read(P,<<"msb">>,511,Zero))).

%% Literal-array indexing clamps out-of-range indices to the last entry, as XLS does.
-spec literal_table_test() -> ok.
literal_table_test() ->
    {Ir,Rtl,Registers}=fixture(),
    Extra = <<
      "  table: bits[4][3] = literal(value=[1, 7, 12], id=11)\n",
      "  lookup: bits[4] = array_index(table, indices=[__state_0], id=12)\n",
      "  unknown_lookup: bits[4] = array_index(unobserved_array, indices=[__state_0], id=13)\n"
    >>,
    P=xls_protocol_spacetime_dependencies:plan(<<Ir/binary,Extra/binary>>,Rtl,Registers),
    S=xls_protocol_spacetime_dependencies:sample(P,#{<<"____state_0">>=>1,<<"____state_1">>=>0,<<"____state_2">>=>0}),
    Lookup=xls_protocol_spacetime_dependencies:read(P,<<"lookup">>,15,S),
    ?assertEqual(7,maps:get(value,Lookup)),
    ?assertEqual(#{},maps:get(data_masks,Lookup)),
    ?assertEqual(#{<<"____state_0">>=>255},maps:get(control_masks,Lookup)),
    ?assertEqual([],maps:get(unknown,Lookup)),
    OutOfRange=xls_protocol_spacetime_dependencies:sample(P,#{<<"____state_0">>=>255,<<"____state_1">>=>0,<<"____state_2">>=>0}),
    ?assertEqual(12,maps:get(value,xls_protocol_spacetime_dependencies:read(P,<<"lookup">>,15,OutOfRange))),
    Unknown=xls_protocol_spacetime_dependencies:read(P,<<"unknown_lookup">>,15,S),
    ?assertEqual(unknown,maps:get(value,Unknown)),
    ?assertEqual([reason({unsupported_node,<<"unknown_lookup">>,<<"array_index">>})],maps:get(unknown,Unknown)),
    Missing=xls_protocol_spacetime_dependencies:sample(P,#{}),
    ?assertEqual(unknown,maps:get(value,xls_protocol_spacetime_dependencies:read(P,<<"lookup">>,15,Missing))).

%% Table budgets and literal widths are checked before building potentially large indexed tuples.
-spec literal_table_rejection_test() -> ok.
literal_table_rejection_test() ->
    ?assertError({badmatch,false},xls_protocol_spacetime_dependencies:plan(<<"  table: bits[1][65537] = literal(value=[], id=1)\n">>,<<>>,[])),
    ?assertError({badmatch,false},xls_protocol_spacetime_dependencies:plan(<<"  table: bits[4096][257] = literal(value=[], id=1)\n">>,<<>>,[])),
    ?assertError({badmatch,false},xls_protocol_spacetime_dependencies:plan(<<"  table: bits[1][1] = literal(value=[2], id=1)\n">>,<<>>,[])),
    ?assertError({badmatch,false},xls_protocol_spacetime_dependencies:plan(<<"  table: bits[1][2] = literal(value=[1], id=1)\n">>,<<>>,[])).


%% A widened product cannot extend operand masks beyond a narrower slice's declared boundary.
-spec widened_multiply_slice_test() -> ok.
widened_multiply_slice_test() ->
    Ir = <<
      "  __state_0: bits[16] = state_read(state_element=__state_0, id=1)\n",
      "  low: bits[8] = bit_slice(__state_0, start=0, width=8, id=2)\n",
      "  product: bits[16] = umul(low, low, id=3)\n"
    >>,
    Rtl = <<"  reg [15:0] ____state_0;\n">>,
    P = xls_protocol_spacetime_dependencies:plan(Ir, Rtl, [#{name => <<"____state_0">>, width => 16}]),
    S = xls_protocol_spacetime_dependencies:sample(P, #{<<"____state_0">> => 16#CDAB}),
    R = xls_protocol_spacetime_dependencies:read(P, <<"product">>, 16#FFFF, S),
    ?assertEqual(16#AB * 16#AB, maps:get(value, R)),
    ?assertEqual(#{<<"____state_0">> => 16#FF}, maps:get(data_masks, R)),
    Top = xls_protocol_spacetime_dependencies:read(P, <<"product">>, 16#8000, S),
    ?assertEqual(#{<<"____state_0">> => 16#FF}, maps:get(data_masks, Top)).

%% Overlapping uses of one scalar contribute all newly requested bits without leaking across targets.
-spec overlapping_masks_test() -> ok.
overlapping_masks_test() ->
    {Ir,Rtl,Registers}=fixture(),
    Extra = <<
      "  shared: bits[8] = reverse(__state_0, id=11)\n",
      "  lower: bits[6] = bit_slice(shared, start=0, width=6, id=12)\n",
      "  upper: bits[6] = bit_slice(shared, start=2, width=6, id=13)\n",
      "  combined: bits[12] = concat(lower, upper, id=14)\n"
    >>,
    P=xls_protocol_spacetime_dependencies:plan(<<Ir/binary,Extra/binary>>,Rtl,Registers),
    S=xls_protocol_spacetime_dependencies:sample(P,#{<<"____state_0">>=>16#AB,<<"____state_1">>=>0,<<"____state_2">>=>0}),
    Combined=xls_protocol_spacetime_dependencies:read(P,<<"combined">>,16#FFF,S),
    ?assertEqual(#{<<"____state_0">>=>16#FF},maps:get(data_masks,Combined)),
    Lower=xls_protocol_spacetime_dependencies:read(P,<<"lower">>,16#3F,S),
    Upper=xls_protocol_spacetime_dependencies:read(P,<<"upper">>,16#3F,S),
    ?assertEqual(#{<<"____state_0">>=>16#FC},maps:get(data_masks,Lower)),
    ?assertEqual(#{<<"____state_0">>=>16#3F},maps:get(data_masks,Upper)).
