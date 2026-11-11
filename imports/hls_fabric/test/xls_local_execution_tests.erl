-module(xls_local_execution_tests).
-include_lib("eunit/include/eunit.hrl").

%% A caller cannot smuggle physical collection/service choices into the reference boundary.
-spec closed_artifact_test() -> ok.
closed_artifact_test() ->
    Spec = xls_parse:actor_artifact("test/hls_local_actor_fixture.erl", []),
    ?assertError({local_execution_requires_closed_artifact, [shared_service]},
        xls_activation_codegen:emit(Spec#{shared_service => aggregate_only})).

%% The reference owner reuses the same bounded caller book as the scheduler owner.
-spec retained_reply_test() -> ok.
retained_reply_test() ->
    Spec = xls_parse:actor_artifact("test/hls_protocol_call_fixture.erl", []),
    Local = xls_emitted:bytes(xls_activation_codegen:artifact(Spec)),
    ?assertNotEqual(nomatch, binary:match(Local, <<"type ReplyBook = hls_reply::Book<REPLY_CAPACITY>">>)),
    ?assertNotEqual(nomatch, binary:match(Local, <<"hls_reply::admit(machine.replies, frame)">>)),
    ?assertEqual(nomatch, binary:match(Local, <<"pub proc SharedExecutor">>)).

%% Slot selection must not silently decode constants from a different projection instance.
-spec projection_instance_test() -> ok.
projection_instance_test() ->
    Spec = xls_parse:actor_artifact("test/hls_local_actor_fixture.erl", []),
    ?assertError(local_execution_requires_instance_zero,
        xls_activation_codegen:emit(Spec#{state_projection => #{rows => [#{instance => 1}]}})).

%% The same source failures survive both owners; local activation emits no scheduler storage or process.
-spec activation_owner_boundary_test() -> ok.
activation_owner_boundary_test() ->
    Spec = #{failure_locations := Locations} =
        xls_parse:actor_artifact("test/hls_local_actor_fixture.erl", []),
    Activation = xls_activation_codegen:artifact(Spec),
    Scheduler = xls_scheduler_codegen:artifact(Spec#{shared_service => ordinary}),
    Sites = xls_emitted:sites(Activation, Locations),
    ?assertNotEqual([], Sites),
    ?assertEqual(Sites, xls_emitted:sites(Scheduler, Locations)),
    Local = xls_emitted:bytes(Activation),
    Ram = xls_emitted:bytes(Scheduler),
    ?assertNotEqual(nomatch, binary:match(Local, <<"pub fn local_step_at(">>)),
    ?assertNotEqual(nomatch, binary:match(Local, <<"pub fn shared_execute(">>)),
    lists:foreach(fun(Token) ->
        ?assertEqual(nomatch, binary:match(Local, Token)),
        ?assertNotEqual(nomatch, binary:match(Ram, Token))
    end, [<<"pub type MachineRamReadReq">>, <<"struct SharedDispatchTicket">>,
        <<"struct SharedState<">>, <<"const PUBLICATION_CAPACITY">>,
        <<"pub proc SharedExecutor">>, <<"fn machine_read(">>, <<"import bram;">>,
        <<"import scheduler;">>]).
