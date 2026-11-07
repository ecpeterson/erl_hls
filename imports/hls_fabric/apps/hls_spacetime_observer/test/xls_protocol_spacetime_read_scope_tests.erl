-module(xls_protocol_spacetime_read_scope_tests).
-include_lib("eunit/include/eunit.hrl").

%% Semantic snapshots and numerical expressions refer to the same Q but make different bit claims.
-spec snapshot_subset_is_not_inferred_test() -> ok.
snapshot_subset_is_not_inferred_test() ->
    #{bundle := #{events := Events}} = capture(),
    Snapshots = [E || E = #{operation := <<"operand_read">>} <- Events],
    ?assertEqual(2, length(Snapshots)),
    ?assertEqual(
        [<<"register/____state_0">>, <<"register/____state_1">>],
        lists:sort([maps:get(resource, maps:get(access, E)) || E <- Snapshots])
    ),
    lists:foreach(fun(#{access := Access}) ->
        ?assertNot(maps:is_key(read_mask, Access))
    end, [E || E = #{operation := Operation} <- Events,
               Operation =:= <<"operand_read">> orelse Operation =:= <<"operand_value">>]),
    Selected = [E || E = #{operation := <<"selected_operand_read">>} <- Events],
    ?assertEqual(2, length(Selected)),
    lists:foreach(fun(#{access := Access}) ->
        ?assertMatch(#{resource := <<"register/____state_1">>, read_mask := 15}, Access)
    end, Selected).

%% Two sampled edges exercise one complete publication and one admission; no RTL tool is needed.
-spec capture() -> xls_protocol_spacetime_capture:capture().
capture() ->
    Controls = [<<"accept">>, <<"reservation">>, <<"egress_blocked">>, <<"phase_boundary">>,
                <<"head_done">>, <<"take">>, <<"postpone">>, <<"publication_accept">>],
    Ordinary = [tap(N, W) || {N, W} <- [{<<"input_reset">>, 1}, {<<"p0_stage_done">>, 1},
        {<<"____state_0">>, 16}, {<<"____state_1">>, 16}, {<<"____state_2">>, 16},
        {<<"d0">>, 16}, {<<"d1">>, 16}, {<<"d2">>, 16},
        {<<"ce0">>, 1}, {<<"ce1">>, 1}, {<<"ce2">>, 1}]],
    Signals = Ordinary ++ [(tap(<<"control_", N/binary>>, 1))#{
        id := <<"actor/0/", N/binary>>} || N <- Controls],
    Registers = [#{name => N, width => 16, data => D, enable => CE,
        rule => enabled_same_edge_register_write} || {N, D, CE} <- [
        {<<"____state_0">>, <<"d0">>, <<"ce0">>},
        {<<"____state_1">>, <<"d1">>, <<"ce1">>},
        {<<"____state_2">>, <<"d2">>, <<"ce2">>}]],
    Ir = <<"  __state_0: bits[16] = state_read(state_element=__state_0, id=6)\n",
           "  __state_1: bits[16] = state_read(state_element=__state_1, id=1)\n",
           "  __state_2: bits[16] = state_read(state_element=__state_2, id=7)\n",
           "  low: bits[4] = bit_slice(__state_1, start=0, width=4, id=2)\n",
           "  extended: bits[16] = zero_ext(low, new_bit_count=16, id=3)\n",
           "  yes: bits[1] = literal(value=1, id=4)\n",
           "  next: () = next_value(state_element=__state_2, value=extended, predicate=yes, id=5)\n">>,
    Rtl = <<"  reg [15:0] ____state_0;\n  reg [15:0] ____state_1;\n",
            "  reg [15:0] ____state_2;\n">>,
    Plan = #{schema => 1, signals => Signals, registers => Registers, unsupported => [],
        actors => [#{actor => 0, inbox => #{<<"slots">> => [],
            <<"host">> => #{<<"offset">> => 0, <<"slots">> => 0},
            <<"startup">> => #{<<"offset">> => 0, <<"count">> => 1}}}],
        state => [#{tuple_path => P, signal => N, source_width => 16, physical_width => 16}
            || {P, N} <- [{[0, 1, 0, 0], <<"____state_0">>},
                          {[0, 1, 0, 5, 0], <<"____state_1">>}]],
        inputs => #{source_build => <<"fixture-source">>, rtl => <<"fixture-rtl">>},
        dependencies => xls_protocol_spacetime_dependencies:plan(Ir, Rtl, Registers)},
    Rows = [[0, 0, 1, 7, 26, 10, 7, 26, 10, 0, 0, 1] ++ C || C <-
        [[0, 0, 0, 0, 0, 0, 0, 0], [1, 1, 0, 0, 0, 0, 0, 1]]],
    Trace = #{signals => [#{id => <<"reset">>, width => 1, path => <<"public">>} | Signals],
        spans => [#{first => C, count => 1, values => V} || {C, V} <- lists:enumerate(0, Rows)],
        end_cycle => 2, complete => true, cause => <<"ok">>, records => 2},
    Build = #{source => <<"fixture-source">>, rtl => <<"fixture-rtl">>,
        observation => xls_protocol_spacetime:observation_digest(Plan)},
    xls_protocol_spacetime_capture:capture(Plan, Trace, Build).

%% Fixture taps supply exact declared IDs without pretending to observe native hardware.
-spec tap(binary(), pos_integer()) -> xls_protocol_spacetime:signal().
tap(Name, Width) -> #{id => <<"signal/", Name/binary>>, name => Name, width => Width,
    path => <<"test.", Name/binary>>, actor => null, meaning => <<"fixture">>,
    evidence => <<"Synthetic read-scope fixture">>}.
