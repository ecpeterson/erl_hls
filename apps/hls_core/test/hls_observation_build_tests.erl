-module(hls_observation_build_tests).

-include_lib("eunit/include/eunit.hrl").

%% Construction preserves the established three-key wire map.
-spec construction_test() -> ok.
construction_test() ->
    Build = hls_observation_build:new(<<"source">>, <<"rtl">>, <<"observation">>),
    ?assertEqual(
        #{source => <<"source">>, rtl => <<"rtl">>, observation => <<"observation">>},
        Build
    ),
    ?assertEqual(ok, hls_observation_build:validate(Build)).

%% Core correlation components remain opaque nonempty bytes rather than textual digests.
-spec opaque_component_test() -> ok.
opaque_component_test() ->
    Build = hls_observation_build:new(<<0>>, <<255>>, <<0, 255>>),
    ?assertEqual(ok, hls_observation_build:validate(Build)),
    ?assertEqual(ok, hls_observation_build:validate_component(<<255>>)).

%% Missing, extra, empty, and nonbinary components fail at the shared boundary.
-spec validation_rejection_test() -> ok.
validation_rejection_test() ->
    ?assertEqual(
        {error, {invalid_component, rtl, <<>>}},
        hls_observation_build:validate(#{
            source => <<"source">>, rtl => <<>>, observation => <<"observation">>
        })
    ),
    ?assertEqual(
        {error, invalid_shape},
        hls_observation_build:validate(#{source => <<"source">>, rtl => <<"rtl">>})
    ),
    ?assertEqual(
        {error, invalid_shape},
        hls_observation_build:validate((build())#{extra => <<"not-on-the-wire">>})
    ),
    ?assertError(
        {observation_build, {invalid_component, observation, not_a_binary}},
        hls_observation_build:new(<<"source">>, <<"rtl">>, not_a_binary)
    ).

%% Exact matching identifies the first missing or different component.
-spec exact_match_test() -> ok.
exact_match_test() ->
    Build = build(),
    ?assertEqual(ok, hls_observation_build:match(Build, Build)),
    ?assertEqual(
        {error, {component_mismatch, rtl, <<"rtl">>, {ok, <<"other">>}}},
        hls_observation_build:match(Build, Build#{rtl := <<"other">>})
    ),
    ?assertEqual(
        {error, {component_mismatch, rtl, <<"rtl">>, {ok, <<"other-rtl">>}}},
        hls_observation_build:match(
            Build, Build#{source := <<"other-source">>, rtl := <<"other-rtl">>}
        )
    ),
    ?assertEqual(
        {error, {component_mismatch, observation, <<"observation">>, error}},
        hls_observation_build:match(Build, maps:remove(observation, Build))
    ),
    ?assertEqual(
        {error, {invalid_actual, invalid_shape}},
        hls_observation_build:match(Build, Build#{extra => true})
    ).

%% Return one valid correlation fixture.
-spec build() -> hls_observation_build:build().
build() ->
    #{source => <<"source">>, rtl => <<"rtl">>, observation => <<"observation">>}.
