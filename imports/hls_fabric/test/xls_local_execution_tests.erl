-module(xls_local_execution_tests).
-include_lib("eunit/include/eunit.hrl").

%% A caller cannot smuggle physical collection/service choices into the reference boundary.
-spec closed_artifact_test() -> ok.
closed_artifact_test() ->
    Spec = xls_parse:actor_artifact("test/hls_local_actor_fixture.erl", []),
    ?assertError({local_execution_requires_closed_artifact, [shared_service]},
        xls_shared_codegen:execution(Spec#{shared_service => aggregate_only})).

%% A retained reply needs additional ownership that this API deliberately does not supply.
-spec retained_reply_test() -> ok.
retained_reply_test() ->
    Spec = xls_parse:actor_artifact("test/hls_local_actor_fixture.erl", []),
    ?assertError(local_execution_retained_calls_unsupported,
        xls_shared_codegen:execution(Spec#{retained_calls => #{}})).

%% Slot selection must not silently decode constants from a different projection instance.
-spec projection_instance_test() -> ok.
projection_instance_test() ->
    Spec = xls_parse:actor_artifact("test/hls_local_actor_fixture.erl", []),
    ?assertError(local_execution_requires_instance_zero,
        xls_shared_codegen:execution(Spec#{state_projection => #{rows => [#{instance => 1}]}})).
