-module(hls_domain_endpoint_network_tests).
-moduledoc "Checks pin ownership across the mechanical local-role, management and carrier boundary. Real component semantics are exercised by their finite native/RTL witnesses; these small fixtures isolate composition errors.".
-include_lib("eunit/include/eunit.hrl").

%% Public streams remain independent; numeric endpoint pins are private and uniquely driven.
-spec composed_ports_test() -> ok.
composed_ports_test() ->
    {Role, Packets, Management} = fixture(),
    #{files := #{"endpoint_network_0.sv" := Source},
        result := #{inputs := Inputs, outputs := Outputs}} =
        hls_domain_endpoint_network:emit(Role, Packets, Management),
    ?assertEqual([{"reset",1},{"domain_0_application_word",32},{"carrier_fault",1},{"packet_rx",1024},
        {"endpoint_management_word",32}], Inputs),
    ?assertEqual([{"domain_0_application_ready",1},{"router_fault",1},
        {"endpoint_management_ready",1}], Outputs),
    Text = iolist_to_binary(Source),
    ?assertNotEqual(nomatch, binary:match(Text,
        <<".endpoint_1_observed_active(endpoint_1_active)">>)),
    ?assertNotEqual(nomatch, binary:match(Text,
        <<".endpoint_2_observed_active(endpoint_2_active)">>)),
    ?assertEqual(3, length(binary:matches(Text, <<".reset(reset)">>))),
    ?assertNotEqual(nomatch, binary:match(Text,
        <<"assign domain_0_fabric_fault = carrier_fault || router_fault;">>)),
    ?assertEqual(nomatch, binary:match(Text, <<"always">>)),
    ok.

%% Reject a mismatched endpoint set before its pins could accidentally alias another endpoint.
-spec identity_mismatch_test() -> ok.
identity_mismatch_test() ->
    {Role, Packets, Management} = fixture(),
    ?assertError({endpoint_network, packet_endpoints},
        hls_domain_endpoint_network:emit(Role,
            Packets#{routes := [#{id => 1, kind => rx}, #{id => 2, kind => tx}]}, Management)),
    ?assertError({endpoint_network, duplicate_endpoint},
        hls_domain_endpoint_network:emit(Role,
            Packets#{routes := [#{id => 1, kind => tx}, #{id => 1, kind => rx}]}, Management)),
    ok.

%% A missing driver, wrong observation width and duplicate external name each reject.
-spec invalid_wiring_test() -> ok.
invalid_wiring_test() ->
    {Role, Packets = #{outputs := Outputs}, Management = #{inputs := Inputs}} = fixture(),
    ?assertError({endpoint_network, endpoint_drivers},
        hls_domain_endpoint_network:emit(Role,
            Packets#{outputs := lists:keydelete("endpoint_2_data_valid", 1, Outputs)}, Management)),
    ?assertError({endpoint_network, {endpoint_observation,{"endpoint_1_active",2}}},
        hls_domain_endpoint_network:emit(Role, Packets, Management#{inputs :=
            lists:keyreplace("endpoint_1_observed_active", 1, Inputs,
                {"endpoint_1_observed_active",2})})),
    ?assertError({endpoint_network, duplicate_pin},
        hls_domain_endpoint_network:emit(Role, Packets,
            Management#{inputs := Inputs ++ [{"packet_rx",1024}]})),
    ok.

%% Two directions and both public endpoint_management_* and private endpoint_ID_* namespaces.
-spec fixture() -> {map(),map(),map()}.
fixture() ->
    Endpoints = [#{id => 1,kind => tx},#{id => 2,kind => rx}],
    Role = #{top_module => "role_0", domain_index => 0,endpoints => Endpoints,
        inputs => [{"reset",1},{"domain_0_application_word",32},{"domain_0_fabric_fault",1},
            {"endpoint_1_bind_request",1},{"endpoint_1_credit_valid",1},
            {"endpoint_2_bind_request",1},{"endpoint_2_data_valid",1}],
        outputs => [{"domain_0_application_ready",1},{"endpoint_1_tx_valid",1},
            {"endpoint_1_active",1},{"endpoint_2_ack_valid",1},{"endpoint_2_active",1}]},
    Packets = #{top_module => "packets_0",routes => Endpoints,
        inputs => [{"reset",1},{"carrier_fault",1},{"packet_rx",1024},{"endpoint_1_tx_valid",1},{"endpoint_2_ack_valid",1}],
        outputs => [{"router_fault",1},{"endpoint_1_credit_valid",1},{"endpoint_2_data_valid",1}]},
    Management = #{top_module => "management_0",interface => #{endpoints => Endpoints},
        inputs => [{"reset",1},{"endpoint_management_word",32},{"endpoint_1_observed_active",1},
            {"endpoint_2_observed_active",1}],
        outputs => [{"endpoint_management_ready",1},{"endpoint_1_bind_request",1},{"endpoint_2_bind_request",1}]},
    {Role,Packets,Management}.
