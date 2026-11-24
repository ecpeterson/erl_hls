-module(hls_implementation_source_build_tests).
-moduledoc "Implementation-plan projection through the public retained source-build façade. These are planning and packaging contract checks, not hardware qualification.".

-include_lib("eunit/include/eunit.hrl").

%% Empty and explicit schedules reach the retained network as local and shared completion policy.
-spec projected_local_and_shared_configuration_test_() -> term().
projected_local_and_shared_configuration_test_() ->
    {timeout, 60, fun projected_local_and_shared_configuration/0}.

%% Inspect only the checked configuration and placement retained by the public build plan.
-spec projected_local_and_shared_configuration() -> ok.
projected_local_and_shared_configuration() ->
    Config = configuration(),
    Topology = materialized_topology(Config),
    LocalPlan = implementation_plan(Topology, []),
    Local = hls_build:plan(request(Config, LocalPlan)),
    #{data := #{config := LocalConfig}} = hls_build:inspect(Local, configuration),
    #{data := #{whole := #{arithmetic := LocalArithmetic}}} =
        hls_build:inspect(Local, placement),
    ?assertEqual([], maps:get(arithmetic_groups, LocalConfig)),
    ?assertEqual([], LocalArithmetic),
    ?assertNot(maps:is_key(native_actors, LocalConfig)),

    SharedPlan = implementation_plan(Topology, [shared_schedule()]),
    Shared = hls_build:plan(request(Config, SharedPlan)),
    #{data := #{config := SharedConfig}} = hls_build:inspect(Shared, configuration),
    #{data := #{whole := #{arithmetic := SharedArithmetic}}} =
        hls_build:inspect(Shared, placement),
    ?assertEqual([[0, 1, 2]], maps:get(arithmetic_groups, SharedConfig)),
    ?assertMatch(
        [#{index := 0, members := [0, 1, 2], module := hls_protocol_arithmetic_fixture}],
        SharedArithmetic
    ),
    ?assertNot(maps:is_key(native_actors, SharedConfig)).

%% Planned requests reject both raw placement fields and every composition other than network.
-spec planned_request_rejection_test_() -> term().
planned_request_rejection_test_() ->
    {timeout, 30, fun planned_request_rejection/0}.

%% Rejection occurs at the public planning boundary before another placement authority is used.
-spec planned_request_rejection() -> ok.
planned_request_rejection() ->
    Config = configuration(),
    Topology = materialized_topology(Config),
    Plan = implementation_plan(Topology, []),
    lists:foreach(
        fun({Field, Value}) ->
            Diagnostic = diagnostic(fun() ->
                hls_build:plan(request(Config#{Field => Value}, Plan))
            end),
            ?assertMatch(
                #{
                    stage := configuration,
                    code := implementation_plan_placement_override,
                    context := #{fields := [Field]}
                },
                Diagnostic
            )
        end,
        [{native_actors, [0, 1]}, {arithmetic_groups, []}]
    ),
    Unsupported = diagnostic(fun() ->
        hls_build:plan((request(Config, Plan))#{kind := boundary})
    end),
    ?assertMatch(
        #{
            stage := configuration,
            code := unsupported_implementation_plan_kind,
            context := #{kind := boundary}
        },
        Unsupported
    ).

%% Written v2 bundles distinguish exact projected correlation from ordinary unplanned builds.
-spec projected_and_unplanned_provenance_test_() -> term().
projected_and_unplanned_provenance_test_() ->
    {timeout, 120, fun projected_and_unplanned_provenance/0}.

%% Compare the retained projection identity with both returned and serialized bundle provenance.
-spec projected_and_unplanned_provenance() -> ok.
projected_and_unplanned_provenance() ->
    Config = configuration(),
    Topology = materialized_topology(Config),
    ImplementationPlan = implementation_plan(Topology, [shared_schedule()]),
    Projection = hls_target_implementation_plan:source_protocol(
        ImplementationPlan, Topology, xc7
    ),
    Expected = #{
        kind => implementation_plan,
        logical_system_sha256 => hls_logical_topology:identity(Topology),
        implementation_plan_sha256 => hls_implementation_plan:identity(ImplementationPlan),
        target_projection_sha256 => hls_target_implementation_plan:identity(Projection)
    },
    ProjectedDirectory = fresh_directory("projected-source-build"),
    Projected = hls_build:plan(request(Config, ImplementationPlan)),
    ProjectedManifest = hls_build:write(Projected, ProjectedDirectory),
    ?assertEqual(2, maps:get(version, ProjectedManifest)),
    ?assertEqual(Expected, maps:get(provenance, ProjectedManifest)),
    ?assertEqual(Expected, disk_provenance(ProjectedDirectory)),
    {ok, [ProjectedConfig]} = file:consult(filename:join(ProjectedDirectory, "config.erl")),
    ?assertEqual([[0, 1, 2]], maps:get(arithmetic_groups, ProjectedConfig)),

    OrdinaryDirectory = fresh_directory("unplanned-source-build"),
    Ordinary = hls_build:plan(#{
        backend => source_protocol, kind => network, configuration => Config
    }),
    OrdinaryManifest = hls_build:write(Ordinary, OrdinaryDirectory),
    ?assertEqual(2, maps:get(version, OrdinaryManifest)),
    ?assertEqual(#{kind => unplanned}, maps:get(provenance, OrdinaryManifest)),
    ?assertEqual(#{kind => unplanned}, disk_provenance(OrdinaryDirectory)).

%% Prepare the trusted source to construct the upstream logical-plan fixture used by the request.
-spec materialized_topology(hls_source_config:network()) ->
    hls_logical_topology:materialized_plan().
materialized_topology(Config) ->
    Program = hls_protocol_transport:prepare(Config),
    maps:get(topology, hls_protocol_transport:bundle(Program)).

%% Bind the three exact fixture actors to one target with optional scalar-sharing schedules.
-spec implementation_plan(
    hls_logical_topology:materialized_plan(), [hls_implementation_plan:schedule()]
) -> hls_implementation_plan:plan().
implementation_plan(Topology, Schedules) ->
    Placement = maps:from_list([
        {Identity, xc7}
     || #{identity := Identity} <- hls_logical_topology:instances(Topology)
    ]),
    hls_implementation_plan:new(
        hls_logical_topology:identity(Topology),
        Placement,
        Schedules,
        #{},
        #{source_protocol => #{scalar_completion => true}},
        #{planner => <<"public source-build fixture">>, inputs => []}
    ).

%% One explicit schedule selects the existing three-member arithmetic fixture capability.
-spec shared_schedule() -> hls_implementation_plan:schedule().
shared_schedule() ->
    #{
        id => shared3,
        target => xc7,
        module => hls_protocol_arithmetic_fixture,
        members => [{actor, 0}, {actor, 1}, {actor, 2}]
    }.

%% Use the closed public request form rather than calling the backend owner directly.
-spec request(hls_source_config:network(), hls_implementation_plan:plan()) ->
    hls_build:request().
request(Config, ImplementationPlan) ->
    #{
        backend => source_protocol,
        kind => network,
        configuration => Config,
        implementation_plan => ImplementationPlan,
        target => xc7
    }.

%% Reuse the maintained three-actor scalar-completion source and constructor.
-spec configuration() -> hls_source_config:network().
configuration() ->
    #{
        sources => [{"apps/hls_fabric/test/hls_protocol_arithmetic_fixture.erl", []}],
        topology => {hls_protocol_arithmetic_fixture, topology, [3]},
        actor_limit => 3
    }.

%% Read back only the version-2 provenance object from the portable JSON record.
-spec disk_provenance(file:filename()) -> hls_artifact_bundle:provenance().
disk_provenance(Directory) ->
    {ok, Bytes} = file:read_file(filename:join(Directory, "source-build.json")),
    case json:decode(Bytes) of
        #{<<"provenance">> := #{<<"kind">> := <<"unplanned">>}} ->
            #{kind => unplanned};
        #{
            <<"provenance">> := #{
                <<"kind">> := <<"implementation_plan">>,
                <<"logical_system_sha256">> := LogicalSystem,
                <<"implementation_plan_sha256">> := ImplementationPlan,
                <<"target_projection_sha256">> := Projection
            }
        } ->
            #{
                kind => implementation_plan,
                logical_system_sha256 => LogicalSystem,
                implementation_plan_sha256 => ImplementationPlan,
                target_projection_sha256 => Projection
            }
    end.

%% Catch only the expected structured public diagnostic.
-spec diagnostic(fun(() -> term())) -> map().
diagnostic(Fun) ->
    try Fun() of
        _ -> error(expected_build_diagnostic)
    catch
        error:{hls_diagnostic, Diagnostic} -> Diagnostic
    end.

%% Allocate a unique absent path; packaging itself must enforce freshness.
-spec fresh_directory(string()) -> file:filename().
fresh_directory(Prefix) ->
    filename:join(
        "_build",
        Prefix ++ "-" ++ integer_to_list(erlang:system_time(nanosecond)) ++ "-" ++
            integer_to_list(erlang:unique_integer([positive, monotonic]))
    ).
