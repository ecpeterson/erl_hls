-module(xls_failure_sites_shared_tests).
-include_lib("eunit/include/eunit.hrl").


%% Checks specializations use their own artifact codebook.
-spec specializations_use_their_own_artifact_codebook_test() -> 'ok'.
specializations_use_their_own_artifact_codebook_test() ->
    File = "apps/hls_fabric/test/hls_reduction_failure_fixture.erl",
    {ok, Forms} = hls_source:parse_file(File),
    {_, Locations} = xls_failure_sites:prepare(Forms),
    lists:foreach(fun(Mode) ->
        Artifact = xls_scheduler_actor:to_artifact(File, #{shared_service => Mode}),
        ?assertMatch([_ | _], xls_emitted:sites(Artifact, Locations))
    end, [ordinary, aggregate_only]).


%% Projection consumes the sealed module, so altered bytes cannot retain an old source codebook.
-spec projection_rejects_changed_artifact_test() -> ok.
projection_rejects_changed_artifact_test() ->
    {Plan, Specs} = hls_actor_debug_dslx:fixture(small),
    Artifacts = #{hls_actor_debug_fixture := Artifact} = hls_actor_debug_dslx:artifacts(small),
    Projection = xls_scheduler_debug:projection(Plan, Specs, Artifacts),
    ?assertEqual(ok, xls_scheduler_debug:validate(Plan, Specs, Projection)),
    %% Simulate a corrupted retained term outside the trusted emitted-artifact API.
    Saved = binary_to_term(term_to_binary(Artifact)),
    Edited = Saved#{dslx := <<"// stale module replacement\n">>},
    ?assertError(emitted_module_mismatch,
        xls_scheduler_debug:projection(Plan, Specs, Artifacts#{hls_actor_debug_fixture := Edited})).
