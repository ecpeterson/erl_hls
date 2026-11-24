-module(xls_protocol_spacetime_ancestry_tests).
-include_lib("eunit/include/eunit.hrl").

%% Simultaneous reciprocal writes both consume old Q; source equality does not select versions.
-spec same_edge_reads_test() -> ok.
same_edge_reads_test() ->
    Capture = capture([[0,0,1,1,2,2,1,1,1], [0,0,1,2,1,1,2,1,1]]),
    #{bundle := #{events := Events, versions := Versions}, ancestry := Counts} = Capture,
    ?assertMatch(#{writes := 4, values_checked := 4, refined := 4, reads := 4}, Counts),
    Index = maps:from_list([{maps:get(id,V),V} || V <- Versions]),
    EventIndex = maps:from_list([{maps:get(id,E),E} || E <- Events]),
    Reads = [E || E = #{operation := <<"selected_operand_read">>} <- Events],
    lists:foreach(fun(#{cycle := C, access := #{version := V, read_mask := Mask}}) ->
        ?assertEqual((1 bsl 16)-1,Mask),
        case maps:get(producer,maps:get(V,Index)) of
            root -> ?assertEqual(0,C);
            Producer -> ?assertEqual(C-1,maps:get(cycle,maps:get(Producer,EventIndex)))
        end
    end,Reads).

%% Fresh reset roots cannot accidentally resolve to a pre-reset write of equal bits.
-spec reset_reads_test() -> ok.
reset_reads_test() ->
    #{bundle := #{events := Events, versions := Versions}, ancestry := Counts} = capture([
        [0,0,1,7,7,7,7,1,1], [1,1,1,7,7,0,0,0,0], [0,0,1,7,7,7,7,1,1]
    ]),
    ?assertMatch(#{writes := 4, values_checked := 4, reads := 4}, Counts),
    Index = maps:from_list([{maps:get(id,V),V} || V <- Versions]),
    lists:foreach(fun(#{incarnation := Inc, access := #{version := V}}) ->
        ?assertMatch(#{producer := root, incarnation := Inc}, maps:get(V,Index))
    end,[E || E = #{operation := <<"selected_operand_read">>} <- Events]).

%% A last-clock D mismatch rejects even without the next-Q check available to the base observer.
-spec wrong_expression_value_test() -> ok.
wrong_expression_value_test() ->
    ?assertException(error, {spacetime_expression_value,_,<<"____state_0">>,2,9},
        capture([[0,0,1,1,2,9,1,1,1]])).

%% An exact scalar swap needs no application, native timing or simulator invocation.
-spec capture([[non_neg_integer()]]) -> xls_protocol_spacetime_capture:capture().
capture(Rows) ->
    Ir = <<"  __state_0: bits[16] = state_read(state_element=__state_0, id=1)\n",
           "  __state_1: bits[16] = state_read(state_element=__state_1, id=2)\n",
           "  yes: bits[1] = literal(value=1, id=3)\n",
           "  swap0: () = next_value(state_element=__state_0, value=__state_1, predicate=yes, id=4)\n",
           "  swap1: () = next_value(state_element=__state_1, value=__state_0, predicate=yes, id=5)\n">>,
    Rtl = <<"  reg [15:0] ____state_0;\n  reg [15:0] ____state_1;\n">>,
    Registers = [#{name => N, width => 16, data => D, enable => CE,
                  rule => enabled_same_edge_register_write}
                 || {N,D,CE} <- [{<<"____state_0">>,<<"d0">>,<<"ce0">>},
                                 {<<"____state_1">>,<<"d1">>,<<"ce1">>}]],
    Signals = [tap(N,W) || {N,W} <- [{<<"input_reset">>,1},{<<"p0_stage_done">>,1},
        {<<"____state_0">>,16},{<<"____state_1">>,16},{<<"d0">>,16},{<<"d1">>,16},
        {<<"ce0">>,1},{<<"ce1">>,1}]],
    Plan = #{schema => 1, actors => [], unsupported => [], state => [], registers => Registers,
        signals => Signals, inputs => #{source_build => <<"fixture-source">>,rtl => <<"fixture-rtl">>,
            implementation => <<"fixture-implementation">>},
        dependencies => xls_protocol_spacetime_dependencies:plan(Ir,Rtl,Registers)},
    Trace = #{signals => [#{id => <<"reset">>,width => 1,path => <<"public">>}|Signals],
        spans => [#{first => C,count => 1,values => V} || {C,V} <- lists:enumerate(0,Rows)],
        end_cycle => length(Rows),complete => true,cause => <<"ok">>,records => length(Rows)},
    Build = #{source => <<"fixture-source">>,rtl => <<"fixture-rtl">>,
              observation => xls_protocol_spacetime:observation_digest(Plan),
              implementation => <<"fixture-implementation">>},
    xls_protocol_spacetime_capture:capture(Plan,Trace,Build).

%% Fixture paths are deliberately distinct from qualified generated RTL paths.
-spec tap(binary(),pos_integer()) -> xls_protocol_spacetime:signal().
tap(Name,Width) -> #{id => <<"signal/",Name/binary>>,name => Name,width => Width,
    path => <<"test.",Name/binary>>,actor => null,meaning => <<"fixture">>,evidence => <<"Synthetic scalar fixture">>}.
