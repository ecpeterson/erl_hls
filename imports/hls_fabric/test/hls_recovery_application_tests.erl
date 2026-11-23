-module(hls_recovery_application_tests).
-moduledoc "Native entry for the same supervised application used by the generated-domain witness. The source controller is reset-safe; the external resource owner and device effects are deliberately not reset.".
-include_lib("eunit/include/eunit.hrl").

%% Local and external-driver entries share the same setup and scenario.
-export([native/1]).

%% A single bounded integration combines ordinary supervision, remote PIDs and surviving effects.
-spec native_supervised_application_test_() -> term().
native_supervised_application_test_() ->
    {timeout, 45, fun() ->
        Stage = filename:join(["_build", "test", "recovery-application-" ++
            integer_to_list(erlang:unique_integer([positive, monotonic]))]),
        Result = native(Stage),
        ?assertMatch(#{restart_intensity := true, external_effects_survive := true,
            real_erts_peer := true, independent_domain := true}, Result)
    end}.

-doc "Creates two native deployments and surviving simulated devices, then runs the exact backend-neutral application; retains its public result and fresh counter files in Stage.".
-spec native(file:filename()) -> map().
native(Stage) ->
    ok = filelib:ensure_dir(filename:join(Stage, "counter")),
    {ok, DeviceA} = hls_recovery_device_model:start_link(),
    {ok, DeviceB} = hls_recovery_device_model:start_link(),
    unlink(DeviceA), unlink(DeviceB),
    {ok, BackendA} = hls_domain_erts:start_link(specification(DeviceA)),
    {ok, BackendB} = hls_domain_erts:start_link(specification(DeviceB)),
    unlink(BackendA), unlink(BackendB),
    OwnerA = owner(a, automatic, BackendA, filename:join(Stage, "a.incarnations")),
    OwnerB = owner(b, manual, BackendB, filename:join(Stage, "b.incarnations")),
    try
        Result = hls_recovery_application:run(OwnerA, OwnerB, DeviceA, DeviceB, #{}),
        ok = file:write_file(filename:join(Stage, "result.etf"), term_to_binary(Result), [exclusive]),
        ok = file:write_file(filename:join(Stage, "result.json"), json:encode(Result#{passed => true,
            deployment => native}), [exclusive]),
        Result
    after
        [stop(Pid) || Pid <- [OwnerA, OwnerB, BackendA, BackendB, DeviceA, DeviceB]]
    end.

%% Simulation explicitly permits fresh digital initialization; external state belongs to Device.
-spec specification(pid()) -> hls_domain_erts:specification().
specification(Device) ->
    #{actors => #{actuator => #{module => hls_recovery_actuator_fixture, mailbox_capacity => 4}},
        routes => #{actuator => #{effect => {external, Device}, reply => {external, Device}}},
        startup => #{}}.

%% Each deployment has its own persistent counter and independently owned backend session.
-spec owner(atom(), hls_domain:policy(), pid(), file:filename()) -> pid().
owner(Domain, Policy, Backend, Store) ->
    ok = hls_domain_ids:create(Store),
    {ok, Owner} = hls_domain:start_link(#{Domain => Policy},
        #{module => hls_domain_erts, endpoints => #{Domain => Backend}, incarnation_file => Store}),
    unlink(Owner),
    Owner.

%% Closing the test owner or device is explicit and occurs only after the shared scenario.
-spec stop(pid()) -> ok.
stop(Pid) -> catch gen_server:stop(Pid), ok.
