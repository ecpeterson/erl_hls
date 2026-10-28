-module(xls_actor_observation_shared_tests).
-include_lib("eunit/include/eunit.hrl").


%% Checks partially scheduled ingress retains direct observation.
-spec partially_scheduled_ingress_retains_direct_observation_test() -> 'ok'.
partially_scheduled_ingress_retains_direct_observation_test() ->
    {Plan, Specs} = hls_actor_debug_dslx:fixture(mailbox),
    Partial = maps:with([producer], Specs),
    Text = iolist_to_binary(xls_fabric_topology_dslx:emit(Plan, (profile(rectangle))#{
        scheduler_groups => Partial, direct_actor_debug => true})),
    ?assertNotEqual(nomatch, binary:match(Text, <<"spawn IngressRouter0">>)),
    ?assertNotEqual(nomatch, binary:match(Text, <<"family_0_debug_out">>)),
    ?assertEqual(nomatch, binary:match(Text, <<"family_1_debug_out">>)).

%% Selects bounded storage and observation settings for the test deployment.
-spec profile('rectangle') -> map().
profile(Kind) ->
    #{name => case Kind of scalar -> debug_scalar; rectangle -> debug_rectangle end,
        channel_depth => 1, actor_egress_depth => burst}.
