-module(hls_logical_model_tests).

-include_lib("eunit/include/eunit.hrl").

%% The historical logical-ID domain includes negative integers and recursive tuples.
-spec recursive_identity_domain_is_preserved_test() -> ok.
recursive_identity_domain_is_preserved_test() ->
    Valid = [actor, -9, 0, 12, {tile, -3, {plane, 2}}],
    ?assert(lists:all(fun hls_logical_identity:is_valid/1, Valid)),
    lists:foreach(fun(Id) -> ok = hls_logical_identity:validate(Id) end, Valid),
    ?assertNot(hls_logical_identity:is_valid({})),
    ?assertNot(hls_logical_identity:is_valid({tile, 1.5})),
    ?assertError({invalid_topology_id, {}}, hls_logical_identity:validate({})),
    ?assertError({invalid_topology_id, 1.5}, hls_logical_identity:validate({tile, 1.5})).

%% A process-free interface preserves output ABI order and answers topology queries.
-spec process_interface_is_source_independent_test() -> ok.
process_interface_is_source_independent_test() ->
    Interface = interface(),
    ?assertEqual(logical_fixture, hls_process_interface:module(Interface)),
    ?assertEqual(4, hls_process_interface:mailbox_capacity(Interface)),
    ?assertEqual([east, west], hls_process_interface:outputs(Interface)),
    ?assertEqual([message], hls_process_interface:dispatched_schemas(Interface)),
    ?assertEqual([message], hls_process_interface:output_schemas(Interface, east)),
    ?assertEqual([], hls_process_interface:output_schemas(Interface, west)),
    #{fields := [#{name := value, type := Type}]} =
        hls_process_interface:schema(Interface, message),
    ?assertEqual(hls_nums:u8(), Type).

%% Every schema field is an exact named descriptor rather than an unchecked compiler map.
-spec malformed_process_interface_fields_are_rejected_test() -> ok.
malformed_process_interface_fields_are_rejected_test() ->
    Base = interface_map(),
    ?assertError(
        {invalid_process_interface_field, message, arbitrary},
        hls_process_interface:new(Base#{schemas := [#{name => message, fields => [arbitrary]}]})
    ),
    ?assertError(
        {invalid_process_interface_type, bad},
        hls_process_interface:new(Base#{
            schemas := [#{name => message, fields => [#{name => value, type => bad}]}]
        })
    ),
    ?assertError(
        {duplicate_process_interface_values, {schema_fields, message}, [value, value]},
        hls_process_interface:new(Base#{
            schemas := [#{
                name => message,
                fields => [
                    #{name => value, type => hls_nums:u8()},
                    #{name => value, type => hls_nums:u8()}
                ]
            }]
        })
    ).

%% Logical normalization rejects missing, extra, mismatched, or malformed interface catalogs.
-spec exact_process_interface_catalog_is_required_test() -> ok.
exact_process_interface_catalog_is_required_test() ->
    Spec = topology_spec(),
    Interface = interface(),
    ?assertError(
        {process_interface_catalog, [logical_fixture], []},
        hls_logical_topology:normalize(Spec, #{})
    ),
    Extra = hls_process_interface:new((interface_map())#{module := extra_fixture}),
    ?assertError(
        {process_interface_catalog, [], [extra_fixture]},
        hls_logical_topology:normalize(
            Spec, #{logical_fixture => Interface, extra_fixture => Extra}
        )
    ),
    ?assertError(
        {process_interface_module_mismatch, wrong_key, logical_fixture},
        hls_logical_topology:normalize(Spec, #{wrong_key => Interface})
    ),
    ?assertError(
        {invalid_process_interface, invalid},
        hls_logical_topology:normalize(Spec, #{logical_fixture => invalid})
    ).

%% Compact normalization and bounded expansion share identity, routes, and lane authority.
-spec compact_and_materialized_topology_share_one_authority_test() -> ok.
compact_and_materialized_topology_share_one_authority_test() ->
    Spec = topology_spec(),
    ?assertEqual([logical_fixture], hls_logical_topology:interface_modules(Spec)),
    Compact = hls_logical_topology:normalize(Spec, #{logical_fixture => interface()}),
    Repeat = hls_logical_topology:normalize(Spec, #{logical_fixture => interface()}),
    ?assertEqual(
        #{logical_fixture => interface()},
        hls_logical_topology:interfaces(Compact)
    ),
    FamilyId = {tile, -3},
    InstanceId = {FamilyId, 0, 0},
    ?assertEqual(
        [
            #{
                source => {InstanceId, east},
                delivery => direct,
                recipients => [{external, sink}]
            },
            #{
                source => {InstanceId, west},
                delivery => direct,
                recipients => [{external, sink}]
            }
        ],
        hls_logical_topology:routes_for_instance(Compact, FamilyId, [0, 0])
    ),
    Materialized = hls_logical_topology:materialize(Compact, 3),
    ?assertEqual(
        hls_logical_topology:identity(Compact), hls_logical_topology:identity(Repeat)
    ),
    ?assertEqual(
        hls_logical_topology:identity(Compact), hls_logical_topology:identity(Materialized)
    ),
    ?assertEqual(
        hls_logical_topology:interfaces(Compact),
        hls_logical_topology:interfaces(Materialized)
    ),
    ?assertEqual(
        [
            {actor, -7},
            {family, FamilyId, [0, 0]},
            {family, FamilyId, [1, 0]}
        ],
        [Identity || #{identity := Identity} <- hls_logical_topology:instances(Compact)]
    ),
    ?assertEqual(
        hls_logical_topology:instances(Compact),
        hls_logical_topology:instances(Materialized)
    ),
    ?assertEqual([], maps:get(families, Materialized)),
    ?assertEqual([], maps:get(route_relations, Materialized)),
    ?assertEqual(3, length(maps:get(actors, Materialized))),
    ?assertEqual(
        hls_logical_topology:lanes(maps:get(routes, Materialized)),
        maps:get(lanes, Materialized)
    ),
    [#{targets := [#{recipients := IngressRecipients}]}] = maps:get(
        ingresses, Materialized
    ),
    ?assertEqual(
        [
            #{actor => {FamilyId, 0, 0}, at => [0, 0]},
            #{actor => {FamilyId, 1, 0}, at => [1, 0]}
        ],
        IngressRecipients
    ).

%% A normalized logical change receives another identity, while raw source has none.
-spec logical_topology_identity_tracks_normalized_changes_test() -> ok.
logical_topology_identity_tracks_normalized_changes_test() ->
    Spec = topology_spec(),
    FamilyId = {tile, -3},
    Changed = Spec#{
        families := #{FamilyId => #{module => logical_fixture, shape => [1, 1]}}
    },
    InterfaceCatalog = #{logical_fixture => interface()},
    Plan = hls_logical_topology:normalize(Spec, InterfaceCatalog),
    ChangedPlan = hls_logical_topology:normalize(Changed, InterfaceCatalog),
    ?assertNotEqual(
        hls_logical_topology:identity(Plan), hls_logical_topology:identity(ChangedPlan)
    ),
    ?assertError({invalid_normalized_topology, Spec}, hls_logical_topology:identity(Spec)).

%% One-dimensional, rectangular, and three-dimensional families retain Cartesian order and IDs.
-spec arbitrary_rank_family_materialization_test() -> ok.
arbitrary_rank_family_materialization_test() ->
    Cases = [
        {[3], [[0], [1], [2]]},
        {[2, 2], [[0, 0], [0, 1], [1, 0], [1, 1]]},
        {[2, 2, 2], [
            [0, 0, 0],
            [0, 0, 1],
            [0, 1, 0],
            [0, 1, 1],
            [1, 0, 0],
            [1, 0, 1],
            [1, 1, 0],
            [1, 1, 1]
        ]}
    ],
    lists:foreach(
        fun({Shape, Coordinates}) ->
            Compact = hls_logical_topology:normalize(
                ranked_topology_spec(Shape), #{logical_fixture => interface()}
            ),
            Materialized = hls_logical_topology:materialize(Compact, length(Coordinates)),
            Identities = [{family, ranked, Coordinate} || Coordinate <- Coordinates],
            RawIds = [list_to_tuple([ranked | Coordinate]) || Coordinate <- Coordinates],
            ?assertEqual(
                Identities,
                [Identity || #{identity := Identity} <- maps:get(instances, Materialized)]
            ),
            ?assertEqual(
                RawIds,
                [maps:get(id, Actor) || Actor <- maps:get(actors, Materialized)]
            ),
            ?assertEqual(
                lists:append([
                    [{RawId, east}, {RawId, west}]
                 || RawId <- RawIds
                ]),
                [Source || #{source := Source} <- maps:get(routes, Materialized)]
            )
        end,
        Cases
    ).

%% Rectangle ingress remains two-dimensional even when ordinary families have another rank.
-spec non_rectangular_rank_is_rejected_as_ingress_recipient_test() -> ok.
non_rectangular_rank_is_rejected_as_ingress_recipient_test() ->
    Spec = ranked_topology_spec([3]),
    WithIngress = Spec#{
        ingresses := [
            {commands, {rectangle, [3, 1]}, [
                {all, [message], [{family, ranked, {embed, [1, 1], [0, 0]}}]}
            ]}
        ]
    },
    ?assertError(
        {ingress_embedding, ranked, [3], [1, 1], [0, 0], [3, 1]},
        hls_logical_topology:normalize(WithIngress, #{logical_fixture => interface()})
    ).

%% Every materializing consumer shares the same finite actor allocation bound.
-spec materialization_actor_bound_test() -> ok.
materialization_actor_bound_test() ->
    Oversized = #{
        actors => [],
        families => [#{id => grid, shape => [(1 bsl 16) + 1, 1]}],
        routes => [],
        ingresses => []
    },
    ?assertException(
        error,
        {hls_diagnostic, #{stage := topology, code := actor_limit}},
        hls_logical_topology:materialize(Oversized, 1 bsl 16)
    ).

%% Build the minimal source-independent interface used by the core topology witness.
-spec interface() -> hls_process_interface:interface().
interface() ->
    hls_process_interface:new(interface_map()).

%% Return the unvalidated source-independent interface fixture for rejection tests.
-spec interface_map() -> map().
interface_map() ->
    #{
        version => 1,
        module => logical_fixture,
        mailbox_capacity => 4,
        outputs => [east, west],
        schemas => [#{
            name => message,
            fields => [#{name => value, type => hls_nums:u8()}]
        }],
        dispatched_schemas => [message],
        emitted_schemas => #{east => [message], west => []}
    }.

%% Build a compact topology with negative exact and nested family identities.
-spec topology_spec() -> hls_logical_topology:spec().
topology_spec() ->
    FamilyId = {tile, -3},
    #{
        version => 1,
        actors => #{-7 => logical_fixture},
        families => #{FamilyId => #{module => logical_fixture, shape => [2, 1]}},
        externals => [{sink, out, [message]}],
        ingresses => [
            {commands, {rectangle, [2, 1]}, [
                {all, [message], [{family, FamilyId, {embed, [1, 1], [0, 0]}}]}
            ]}
        ],
        routes => [
            {{-7, east}, [{external, sink}]},
            {{-7, west}, [{external, sink}]}
        ],
        route_relations => [
            {{FamilyId, east}, [{external, sink}]},
            {{FamilyId, west}, [{external, sink}]}
        ],
        startup => []
    }.

%% Build an ingress-free family witness whose routes are valid at every supported rank.
-spec ranked_topology_spec([pos_integer()]) -> hls_logical_topology:spec().
ranked_topology_spec(Shape) ->
    #{
        version => 1,
        actors => #{},
        families => #{ranked => #{module => logical_fixture, shape => Shape}},
        externals => [{sink, out, [message]}],
        ingresses => [],
        routes => [],
        route_relations => [
            {{ranked, east}, [{external, sink}]},
            {{ranked, west}, [{external, sink}]}
        ],
        startup => []
    }.
