-module(hls_domain_board_host_tests).
-moduledoc "Finite platform attachment predicates; no device, transport, compiler backend or board is opened.".
-include_lib("eunit/include/eunit.hrl").

%% Platform sources stay outside generic runtime src_dirs and are loaded only for this selected fixture.
-spec cold_boundary_test_() -> term().
cold_boundary_test_() -> {setup, fun load_host/0, fun unload_host/1, fun cold_boundary/0}.

%% Compile the exact platform module in memory, without introducing a runtime compiler dependency.
-spec load_host() -> ok.
load_host() ->
    Source = "platforms/xc7/application/hls_domain_board_host.erl",
    {ok, hls_domain_board_host, Beam, []} = compile:file(Source,
        [binary, debug_info, warnings_as_errors, return_errors, return_warnings]),
    {module, hls_domain_board_host} = code:load_binary(hls_domain_board_host, Source, Beam), ok.

%% No host process is created by this predicate-only fixture.
-spec unload_host(ok) -> ok.
unload_host(ok) -> _ = code:delete(hls_domain_board_host), _ = code:purge(hls_domain_board_host), ok.

%% Neither a host session nor a reset current-incarnation field can erase retained health evidence.
-spec cold_boundary() -> ok.
cold_boundary() ->
    Phase = {hls_type, hls_enum, enum, [[ready, unbound, closing, isolated, initializing, failed, stopped]]},
    Width = hls_type:width(Phase), <<Unbound:Width>> = hls_type:pack(unbound, Phase),
    Health = #{phase_code => Unbound, domain_attached => false, endpoint_attached => false, domain_wire_fault => false,
        endpoint_wire_fault => false, router_fault => false, carrier_fault => 0, carrier_armed => true},
    Cold = #{kind => board, abi => 1, role => 1, status => ok, domain_session => 0,
        endpoint_session => 0, incarnation => 0, health => Health},
    ?assert(hls_domain_board_host:cold_status(0, Cold, Phase)),
    ?assertNot(hls_domain_board_host:cold_status(1, Cold, Phase)),
    [?assertNot(hls_domain_board_host:cold_status(0, Cold#{Key := 1}, Phase)) ||
        Key <- [domain_session, endpoint_session, incarnation]],
    [?assertNot(hls_domain_board_host:cold_status(0, Cold#{health := Health#{Key := true}}, Phase)) ||
        Key <- [domain_attached, endpoint_attached, domain_wire_fault, endpoint_wire_fault, router_fault]],
    ?assertNot(hls_domain_board_host:cold_status(0, Cold#{health := Health#{carrier_fault := 64}}, Phase)),
    ?assertNot(hls_domain_board_host:cold_status(0, Cold#{health := Health#{phase_code := Unbound bxor 1}}, Phase)),
    ok.
