-module(hls_domain_endpoint_role_tests).
-moduledoc "Mechanical endpoint-role wiring checks using small retained-interface fixtures. No source application, XLS tool, RTL simulation or board is executed; these checks establish pin composition only.".
-include_lib("eunit/include/eunit.hrl").

%% Four outgoing and four incoming crossings use only their owning domain's lifecycle.
-spec local_role_test() -> ok.
local_role_test() ->
    #{files := Files, result := #{inputs := Inputs, outputs := Outputs,
        endpoints := Endpoints, source := Source}} =
        hls_domain_endpoint_role:emit(domain(), crossings(), endpoints()),
    Text = iolist_to_binary(maps:get(Source, Files)),
    ?assertEqual(1, map_size(Files)),
    ?assertEqual(4, length([I || #{id := I, kind := tx} <- Endpoints])),
    ?assertEqual(4, length([I || #{id := I, kind := rx} <- Endpoints])),
    ?assert(lists:member({"domain_0_management_word", 32}, Inputs)),
    ?assert(lists:member({"domain_0_application_word", 32}, Inputs)),
    ?assert(lists:member({"domain_0_domain_reset", 1}, Inputs)),
    ?assert(lists:member({"domain_0_fabric_fault", 1}, Inputs)),
    ?assert(lists:member({"domain_0_transport_reset", 1}, Inputs)),
    ?assert(lists:member({"domain_0_inspect_address", 32}, Inputs)),
    ?assert(lists:member({"domain_0_app_inspect_value", 128}, Outputs)),
    ?assertNot(lists:keymember("domain_0_reset", 1, Inputs)),
    ?assertEqual([], [N || {N, _} <- Inputs, string:find(N, "remote_") =/= nomatch]),
    ?assertEqual(lists:sort(["domain_0_" ++ remote(Id, Suffix, output)
        || Id <- [8, 28, 37, 61], Suffix <- ["fault", "free"]]),
        lists:sort([N || {N, _} <- Outputs, string:find(N, "remote_") =/= nomatch])),
    ?assert(lists:member({"domain_0_app_remote_8_free", 1}, Outputs)),
    ?assert(lists:member({"domain_0_app_remote_28_free", 3}, Outputs)),
    includes(Text, "output wire domain_0_app_remote_8_fault"),
    includes(Text, "output wire [2:0] domain_0_app_remote_28_free"),
    includes(Text, ".app_remote_8_fault(domain_0_app_remote_8_fault)"),
    includes(Text, ".domain_reset(domain_0_domain_reset)"),
    includes(Text, ".fabric_fault(domain_0_fabric_fault)"),
    includes(Text, ".local_incarnation(domain_0_domain_current)"),
    includes(Text, ".local_ready((!reset && !domain_0_domain_reset && domain_0_domain_phase == 2'd2"),
    includes(Text, "domain_0_domain_current != 64'd0)"),
    includes(Text, ".source_frame(domain_0_app_remote_1_frame)"),
    includes(Text, ".source_ready(domain_0_remote_1_ready)"),
    includes(Text, ".destination_ready(domain_0_app_remote_8_ready)"),
    includes(Text, ".destination_frame(domain_0_remote_8_frame)"),
    includes(Text, ".receiver_active(endpoint_1_receiver_active)"),
    ?assert(lists:member({"endpoint_1_receiver_active", 1}, Inputs)),
    ?assert(lists:member({"endpoint_8_data_frame", 96}, Inputs)),
    ?assert(lists:member({"endpoint_1_tx_frame", 96}, Outputs)),
    ?assertNot(lists:keymember("endpoint_1_local_ready", 1, Inputs)),
    ?assertEqual(9, length(binary:matches(Text, <<".reset(reset)">>))),
    ?assertEqual(nomatch, binary:match(Text, <<"domain_1_">>)),
    ?assertEqual(nomatch, binary:match(Text, <<"always">>)),
    ?assertEqual(nomatch, binary:match(Text, <<"reg ">>)),
    ok.

%% Existing compiled module identities are configurable without rebuilding their logic.
-spec module_names_test() -> ok.
module_names_test() ->
    #{tx := Tx, rx := Rx} = endpoints(),
    #{files := #{"board_role.sv" := Bytes}, result := Result} =
        hls_domain_endpoint_role:emit(domain(), crossings(),
            #{tx => Tx#{top_module := "custom_tx"}, rx => Rx#{top_module := "custom_rx"}},
            #{top_module => "board_role", domain_module => "frozen_domain"}),
    Text = iolist_to_binary(Bytes),
    includes(Text, "module board_role(input wire clk,"),
    includes(Text, "frozen_domain local_domain(.clk(clk),"),
    includes(Text, "custom_tx endpoint_1(.clk(clk),"),
    includes(Text, "custom_rx endpoint_8(.clk(clk),"),
    ?assertMatch(#{domain_module := "frozen_domain", top_module := "board_role"}, Result),
    ?assertError({endpoint_role, {identifier, "bad;module"}},
        hls_domain_endpoint_role:emit(domain(), crossings(), endpoints(),
            #{top_module => "bad;module"})),
    ok.

%% Omitted/duplicate crossings, width skew and missing lifecycle authority reject locally.
-spec rejected_interfaces_test() -> ok.
rejected_interfaces_test() ->
    Domain = #{interface := Interface = #{outputs := Outputs}} = domain(),
    [First | Rest] = crossings(),
    ?assertError({endpoint_role, duplicate_crossing},
        hls_domain_endpoint_role:emit(Domain, [First, First | Rest], endpoints())),
    ?assertError({endpoint_role, crossing_inputs},
        hls_domain_endpoint_role:emit(Domain, Rest, endpoints())),
    WrongWidth = lists:keyreplace("app_remote_1_frame", 1, Outputs, {"app_remote_1_frame", 97}),
    ?assertError({endpoint_role, crossing_outputs},
        hls_domain_endpoint_role:emit(Domain#{interface := Interface#{outputs := WrongWidth}},
            crossings(), endpoints())),
    MissingCurrent = lists:keydelete("domain_current", 1, Outputs),
    ?assertError({endpoint_role, domain_lifecycle},
        hls_domain_endpoint_role:emit(Domain#{interface := Interface#{outputs := MissingCurrent}},
            crossings(), endpoints())),
    ?assertError({endpoint_role, crossing_diagnostics},
        hls_domain_endpoint_role:emit(Domain#{interface := Interface#{outputs :=
            Outputs ++ [{"app_remote_8_unknown", 1}]}}, crossings(), endpoints())),
    ?assertError({endpoint_role, crossing_diagnostics},
        hls_domain_endpoint_role:emit(Domain#{interface := Interface#{outputs :=
            Outputs ++ [{"app_remote_1_fault", 1}]}}, crossings(), endpoints())),
    #{tx := Tx} = endpoints(),
    ?assertError({endpoint_role, endpoint_direction},
        hls_domain_endpoint_role:emit(Domain, crossings(), (endpoints())#{tx := Tx#{direction := rx}})),
    ok.

%% A compact three-word frame keeps these source-only fixtures independent of Phi's dimensions.
-spec domain() -> hls_domain_endpoint_role:domain().
domain() ->
    Tx = [1, 17, 26, 50],
    Rx = [8, 28, 37, 61],
    #{index => 0, mode => stream, interface => #{
        inputs => [{"reset", 1}, {"domain_reset", 1}, {"fabric_fault", 1}, {"transport_reset", 1},
            {"management_word", 32}, {"application_word", 32}, {"inspect_address", 32}] ++
            [{remote(Id, "ready", input), 1} || Id <- Tx] ++
            lists:append([[{remote(Id, Suffix, input), Width}
                || {Suffix, Width} <- [{"valid", 1}, {"slot", 8}, {"frame", 96}]] || Id <- Rx]),
        outputs => [{"domain_phase", 2}, {"domain_current", 64}, {"app_inspect_value", 128}] ++
            [{remote(Id, "ready", output), 1} || Id <- Rx] ++
            [{remote(Id, "fault", output), 1} || Id <- Rx] ++
            [{remote(Id, "free", output), case Id of 8 -> 1; _ -> 3 end} || Id <- Rx] ++
            lists:append([[{remote(Id, Suffix, output), Width}
                || {Suffix, Width} <- [{"valid", 1}, {"slot", 8}, {"frame", 96}]] || Id <- Tx]),
        codecs => #{phase => hls_enum:enum([cold, starting, ready, failed])}}}.

%% Extra crossings on unrelated roles must not create peer wires or instances here.
-spec crossings() -> [#{index := non_neg_integer(), source_domain := non_neg_integer(),
    destination_domain := non_neg_integer()}].
crossings() ->
    [#{index => Id, source_domain => 0, destination_domain => 1} || Id <- [1, 17, 26, 50]] ++
        [#{index => Id, source_domain => 1, destination_domain => 0} || Id <- [8, 28, 37, 61]] ++
        [#{index => 90, source_domain => 2, destination_domain => 3}].

%% These reduced interfaces exercise local wiring and public passthrough without compiling kernels.
-spec endpoints() -> hls_domain_endpoint_role:endpoints().
endpoints() -> #{tx => endpoint(tx), rx => endpoint(rx)}.

%% Local lifecycle and ownership interfaces have the same names/widths as emitted endpoints.
-spec endpoint(tx | rx) -> hls_domain_endpoint_role:endpoint().
endpoint(Kind) ->
    Common = [{"reset", 1}, {"local_ready", 1}, {"local_incarnation", 64},
        {"bind_request", 1}, {"fence", 1}, {"namespace", 64}],
    {Inputs, Outputs} = case Kind of
        tx -> {Common ++ [{"source_valid", 1}, {"source_slot", 8}, {"source_frame", 96},
                    {"receiver_active", 1}, {"data_tx_ready", 1}, {"credit_valid", 1}],
                [{"source_ready", 1}, {"source_take", 1}, {"tx_valid", 1},
                    {"tx_frame", 96}, {"status", 4}]};
        rx -> {Common ++ [{"destination_ready", 1}, {"data_valid", 1},
                    {"data_frame", 96}, {"ack_tx_ready", 1}],
                [{"destination_valid", 1}, {"destination_slot", 8}, {"destination_frame", 96},
                    {"destination_take", 1}, {"ack_valid", 1}, {"status", 4}]}
    end,
    #{direction => Kind, inputs => Inputs, outputs => Outputs,
        top_module => "endpoint_" ++ atom_to_list(Kind), cold_reset_pin => "reset",
        local_ready_pin => "local_ready", local_incarnation_pin => "local_incarnation"}.

%% Fixture names preserve the actual source domain's crossing orientation.
-spec remote(non_neg_integer(), string(), input | output) -> string().
remote(Id, Suffix, input) -> "remote_" ++ integer_to_list(Id) ++ "_" ++ Suffix;
remote(Id, Suffix, output) -> "app_remote_" ++ integer_to_list(Id) ++ "_" ++ Suffix.

%% Check only interface-significant generated fragments rather than an entire formatting snapshot.
-spec includes(binary(), iodata()) -> ok.
includes(Text, Fragment) ->
    ?assertNotEqual(nomatch, binary:match(Text, iolist_to_binary(Fragment))),
    ok.
