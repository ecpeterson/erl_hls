-module(hls_direct_actor_debug_tests).
-include_lib("eunit/include/eunit.hrl").

projection_and_catalog_test() ->
    {Plan, Specs} = hls_actor_debug_dslx:fixture(direct_reduction),
    Options = #{direct_actor_debug => true},
    Artifacts = hls_actor_debug_dslx:artifacts(direct_reduction, Options),
    Projection = #{<<"banks">> := [], <<"direct">> := Direct} =
        xls_scheduler_debug:projection(Plan, Specs, Artifacts, Options),
    ?assertEqual(5, length(Direct)),
    ?assertEqual(ok, xls_scheduler_debug:validate(Plan, Specs, Projection)),
    Resources = [resource(B) || B <- Direct],
    Manifest = #{<<"actor_projection">> => Projection, <<"resources">> => Resources,
        <<"fingerprint">> => <<"direct-fixture">>},
    Session = #{manifest => Manifest, resources => list_to_tuple(Resources)},
    Catalog = hls_debug_catalog:hardware(Plan, Specs, [], Session),
    lists:foreach(fun(Id) ->
        {ok, Actor} = hls_debug_catalog:actor(Catalog, Id),
        ?assertEqual({placement, #{kind => direct}}, hls_debug:info(Actor, placement)),
        {capabilities, #{info := Items}} = hls_debug:info(Actor, capabilities),
        ?assertEqual([], [phase, enter_pending, failure, reduction, initialized, cycle] -- Items),
        ?assertNot(lists:member(message_queue_len, Items)),
        ?assertNot(lists:member(reserved, Items)),
        ?assertMatch({observation, #{kind := committed_state, mailbox := unavailable}},
            hls_debug:info(Actor, observation))
    end, hls_debug_catalog:actors(Catalog)),
    [First | Rest] = Direct,
    lists:foreach(fun(Bad) ->
        ?assertError(actor_projection_mismatch, xls_scheduler_debug:validate(Plan, Specs,
            Projection#{<<"direct">> := [Bad | Rest]}))
    end, [First#{<<"port">> := <<"unrelated_output">>},
        First#{<<"phases">> := [<<"wrong_phase">>]},
        First#{<<"index">> := 9}, First#{<<"width">> := 25},
        First#{<<"actors">> := maps:get(<<"actors">>, lists:last(Direct))}]),
    ?assertError(actor_projection_mismatch, xls_scheduler_debug:validate(Plan, Specs,
        Projection#{<<"direct">> := Rest})),
    [R | Rs] = Resources,
    BadManifest = Manifest#{<<"resources">> := [R#{<<"slot">> := 1} | Rs]},
    ?assertError(actor_resources_mismatch,
        hls_debug_catalog:hardware(Plan, Specs, [], Session#{manifest := BadManifest})).

resource(#{<<"index">> := Index, <<"actors">> := [Actor], <<"module">> := Module,
        <<"phases">> := Phases, <<"failures">> := Failures,
        <<"reduction">> := Reduction = #{<<"width">> := Width}}) ->
    Actor#{<<"id">> => Index, <<"kind">> => <<"actor">>, <<"bank">> => Index,
        <<"module">> => Module, <<"phases">> => Phases, <<"failures">> => Failures,
        <<"reduction">> => Reduction, <<"width">> => 56 + Width}.
