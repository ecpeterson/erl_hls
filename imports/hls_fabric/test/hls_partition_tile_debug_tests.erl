-module(hls_partition_tile_debug_tests).
-include_lib("eunit/include/eunit.hrl").

%% A logical label must never silently change which RAM slot a public query addresses.
-spec logical_catalog_test() -> ok.
logical_catalog_test() ->
    {Plan, Specs, Manifest} = fixture(),
    Session = #{manifest => Manifest},
    Binding = hls_partition_tile_debug:prepare(Plan, Specs, maps:get(<<"actor_projection">>, Manifest)),
    Retained = binary_to_term(term_to_binary(Binding)),
    Catalog = hls_shared_observation:bind(Retained, Session),
    ?assertEqual(Catalog, hls_partition_tile_debug:catalog(Plan, Specs, Session)),
    lists:foreach(fun(I) ->
        Id = {actor, {family, cells, [7, I]}},
        ?assertMatch({ok, {actor, #{identity := Id, scope := #{id := Id}, placement := #{slot := I}},
            {actor_snapshot, Session, I}}}, hls_debug_catalog:actor(Catalog, Id))
    end, [0, 1]),
    ?assertEqual(2, length(hls_debug_catalog:actors(Catalog))),
    P = #{<<"banks">> := [B]} = maps:get(<<"actor_projection">>, Manifest),
    [A | Rest] = maps:get(<<"actors">>, B),
    Bad = Manifest#{<<"actor_projection">> := P#{<<"banks">> := [B#{<<"actors">> :=
        [A#{<<"name">> := <<"misleading actor">>} | Rest]}]}},
    ?assertException(error, _, hls_shared_observation:bind(Retained, Session#{manifest := Bad})),
    [First | Others] = maps:get(actors, Plan),
    ?assertException(error, _, hls_partition_tile_debug:prepare(
        Plan#{actors := [First#{logical_identity := unrelated} | Others]}, Specs, P)),
    [Resource | Resources] = maps:get(<<"resources">>, Manifest),
    WrongSlot = Manifest#{<<"resources">> := [Resource#{<<"slot">> := 1} | Resources]},
    ?assertException(error, _, hls_shared_observation:bind(Retained, Session#{manifest := WrongSlot})),
    ok.

%% Use the public projection builder and its resource contract without requiring RTL compilation.
-spec fixture() -> {map(), map(), map()}.
fixture() ->
    Actors = [#{id => I, index => I, logical_identity => {family, cells, [7, I]},
        module => hls_partition_fixture, mailbox_capacity => 2, outputs => [left, right, report]}
        || I <- [0, 1]],
    Plan = #{actors => Actors, families => []},
    Specs = #{cells => #{members => [{actor, 0}, {actor, 1}],
        state_storage => block_ram, mailbox_storage => block_ram}},
    Physical = xls_scheduler_debug:projection(Plan, Specs, #{hls_partition_fixture => xls_emitted:new([], <<>>)}, #{mailbox_debug => true}),
    Projection = hls_partition_tile:projection(#{tile => true, schedulers => [#{index => 0,
        actors => [#{identity => {family, cells, [7, I]}, slot => I} || I <- [0, 1]]}]}, Physical),
    [#{<<"actors">> := Bound, <<"module">> := Module, <<"phases">> := Phases,
        <<"failures">> := Failures}] = maps:get(<<"banks">>, Projection),
    Resources = [A#{<<"id">> => I, <<"kind">> => <<"actor">>, <<"bank">> => 0,
        <<"module">> => Module, <<"phases">> => Phases, <<"failures">> => Failures,
        <<"width">> => 56, <<"mailbox_capacity">> => 2, <<"mailbox_kind">> => <<"shared">>}
        || A = #{<<"slot">> := I} <- Bound],
    {Plan, Specs, #{<<"actor_projection">> => Projection, <<"resources">> => Resources,
        <<"fingerprint">> => <<"fixture">>}}.
