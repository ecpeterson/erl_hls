-module(xls_protocol_spacetime_physical_tests).
-moduledoc "Synthetic qualification regressions reject unsupported native membership and incomplete finite evidence.".
-include_lib("eunit/include/eunit.hrl").

%% Invented catalogue and finite summaries qualify orchestration, never native APIs.
-spec qualification_test() -> ok.
qualification_test() ->
    {Catalogue, Candidates, Witness, Resources} = fixture(),
    Qualified = xls_protocol_spacetime_physical:qualify(Catalogue, Candidates, Witness),
    #{probes := [#{bits := [#{varied := true}, #{varied := false}]}]} = Qualified,
    #{bindings := [#{disposition := ambiguous, cells := [<<"r0">>, <<"r1">>],
        bits := [#{status := supported}, #{status := supported}, #{status := unknown}]}]} =
        xls_protocol_spacetime_physical:claims(Resources, Qualified),
    ok.

%% Two source bits may use one qualified native output without double-counting its cell.
-spec shared_output_test() -> ok.
shared_output_test() ->
    {Catalogue, #{probes := [P]} = Candidates, #{cases := [C]} = Witness, Resources} = fixture(),
    [B0, _] = maps:get(bits, P),
    [R] = maps:get(rows, C),
    Repeated = Candidates#{probes := [P#{bits := [B0, B0#{bit := 1}]}]},
    BothVary = Witness#{cases := [C#{rows := [R#{observed_ones := 3, observed_zeroes := 3,
        expected_ones := 3, expected_zeroes := 3}]}]},
    Qualified = xls_protocol_spacetime_physical:qualify(Catalogue, Repeated, BothVary),
    #{bindings := [#{cells := [<<"r0">>]}]} =
        xls_protocol_spacetime_physical:claims(Resources, Qualified),
    ok.

%% Matching names cannot rescue mismatched input identities, incomplete coverage or native connectivity.
-spec rejection_test_() -> [term()].
rejection_test_() ->
    {Catalogue, #{identity := Identity, probes := [P]} = Candidates,
        #{cases := [C]} = Witness, _} = fixture(),
    [R] = maps:get(rows, C),
    [B0, B1] = maps:get(bits, P),
    Changes = [
        {identity_mismatch, Catalogue, Candidates, Witness#{identity := Identity#{probe := <<"other">>}}},
        {catalogue_identity_mismatch, Catalogue#{checkpoint := <<"other">>}, Candidates, Witness},
        {{invalid_horizon, <<"live">>}, Catalogue, Candidates,
            Witness#{cases := [C#{nonreset_cycles := 0}]}},
        {{incomplete_witness, <<"live">>}, Catalogue, Candidates,
            Witness#{cases := [C#{public_passed := false}]}},
        {{comparison_population, <<"live">>}, Catalogue, Candidates,
            Witness#{cases := [C#{rows := []}]}},
        {{failed_comparison, <<"q">>}, Catalogue, Candidates,
            Witness#{cases := [C#{rows := [R#{unknown_mask := 1}]}]}},
        {{unobserved_bits, <<"q">>}, Catalogue, Candidates,
            Witness#{cases := [C#{rows := [R#{observed_zeroes := 1}]}]}},
        {{population_mismatch, <<"q">>}, Catalogue, Candidates,
            Witness#{cases := [C#{rows := [R#{expected_ones := 3}]}]}},
        {{duplicate_bit, 0}, Catalogue, Candidates#{probes := [P#{bits := [B0, B0]}]}, Witness},
        {{parent_net_mismatch, <<"r0/Q">>, <<"n1">>}, Catalogue,
            Candidates#{probes := [P#{bits := [B0#{parent_net := <<"n1">>}, B1]}]}, Witness},
        {{unknown_parent_net, <<"guessed">>}, Catalogue,
            Candidates#{probes := [P#{bits := [B0#{parent_net := <<"guessed">>}, B1]}]}, Witness},
        {{unsupported_storage_output, <<"r0">>, <<"LUT1">>, <<"O">>}, Catalogue,
            Candidates#{probes := [P#{bits := [B0#{primitive := <<"LUT1">>, pin := <<"O">>}, B1]}]}, Witness}
    ],
    [?_assertError({spacetime_physical, Reason},
        xls_protocol_spacetime_physical:qualify(Cat, Can, Wit)) || {Reason, Cat, Can, Wit} <- Changes].

%% Small direct/aliased output connections include one exercised and one constant-only bit.
-spec fixture() -> {map(), map(), map(), [map()]}.
fixture() ->
    Build = #{source => <<"source">>, rtl => <<"rtl">>, observation => <<"observation">>},
    Identity = #{build => Build, checkpoint => <<"checkpoint">>, netlist => <<"netlist">>, probe => <<"probe">>},
    Cells = [#{id => Id, kind => <<"FDRE">>} || Id <- [<<"r0">>, <<"r1">>]],
    Nets = [#{id => Net, pins => [#{cell => Cell, pin => <<"Q">>, native => <<Cell/binary,"/Q">>, direction => output}]}
        || {Net, Cell} <- [{<<"n0">>, <<"r0">>}, {<<"n1">>, <<"r1">>}]],
    Catalogue = #{build => Build, checkpoint => <<"checkpoint">>, cells => Cells, nets => Nets,
        native => #{aliases => [#{id => <<"actual_parent[0]">>, net => <<"n0">>}] }},
    Bits = [#{bit => I, cell => Cell, pin => <<"Q">>, native_pin => <<Cell/binary,"/Q">>,
        primitive => <<"FDRE">>, parent_net => Parent}
        || {I, Cell, Parent} <- [{0, <<"r0">>, <<"actual_parent[0]">>}, {1, <<"r1">>, <<"n1">>}]],
    Candidates = #{identity => Identity, probes => [#{id => <<"q">>, resource => <<"word">>,
        generated => <<"core.q">>, width => 3, bits => Bits}]},
    Row = #{id => <<"q">>, width => 3, mask => 3, mismatch_samples => 0, unknown_samples => 0,
        mismatch_mask => 0, unknown_mask => 0, observed_ones => 1, observed_zeroes => 3,
        expected_ones => 1, expected_zeroes => 3},
    Witness = #{identity => Identity, cases => [#{id => <<"live">>, cycles => 9, nonreset_cycles => 7,
        complete => true, public_passed => true, rows => [Row]}]},
    {Catalogue, Candidates, Witness, [#{id => <<"word">>, kind => register, width => 3, depth => 1}]}.
