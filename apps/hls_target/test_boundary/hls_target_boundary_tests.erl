-module(hls_target_boundary_tests).
-moduledoc "Exercises target policy and publication primitives without spacetime or the façade.".

-include_lib("eunit/include/eunit.hrl").

%% Prepared computation can acquire checked target schedule flags without an optimizer callback.
-spec target_only_policy_test() -> ok.
target_only_policy_test() ->
    #{version := 1, profile := Profile, codegen_flags := Flags} =
        hls_build_profile:experiment(#{
            schedule => #{pipeline_stages => 3, initiation_interval => 2},
            completion_storage => registers
        }),
    ?assertEqual(channel_scheduler, maps:get(backend, Profile)),
    ?assert(lists:member(<<"--pipeline_stages=3">>, Flags)),
    ?assertEqual(
        hls_generated_files:hash(<<"target fixture">>),
        hls_generated_files:hash([<<"target ">>, <<"fixture">>])
    ).
