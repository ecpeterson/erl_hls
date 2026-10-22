-module(xls_local_execution_validation).
-moduledoc "Emits finite source-variation and projected-state witnesses through the ordinary activation API.".
-export([prepare/2]).

-doc "Writes fresh DSLX fixtures for source arithmetic, guards, phase renaming and two-slot projection, plus reduction/gather lowering inputs from the supplied compiler source root. These exercise the source artifact and existing executor, with no scheduler or external transport.".
-spec prepare(file:filename(), file:filename()) -> ok.
prepare(Stage, CompilerRoot) ->
    ok = file:make_dir(Stage),
    {ok, Source} = file:read_file("test/hls_local_actor_fixture.erl"),
    lists:foreach(fun({Name, Body, Value, Failure}) -> variant(Stage, Name, Body, Value, Failure) end,
        [{"base", Source, 8, false},
         {"arithmetic", binary:replace(Source, <<"C#counter.value + Added">>, <<"C#counter.value bxor Added">>), 6, false},
         {"guard", binary:replace(Source, <<"Added =< 7">>, <<"Added =< 3">>), 3, true},
         {"phase", binary:replace(Source, <<"ready">>, <<"collecting">>, [global]), 8, false}]),
    ok = projection(Stage),
    Dependency = filename:join(CompilerRoot, "test_data"),
    lists:foreach(fun({Name, File}) ->
        Spec = xls_parse:actor_artifact(filename:join(Dependency, File), []),
        ok = file:write_file(filename:join(Stage, Name ++ ".x"), xls_shared_codegen:execution(Spec), [exclusive])
    end, [{"reduction", "hls_statem_reduction_lower_fixture.erl"}, {"gather", "xls_statem_gather_fixture.erl"}]).

%% Each variant changes source before parsing; no generated program is rewritten.
-spec variant(file:filename(), string(), binary(), non_neg_integer(), boolean()) -> ok.
variant(Stage, Name, Source, Expected, Failure) ->
    File = filename:join(Stage, Name ++ ".erl"),
    ok = file:write_file(File, Source, [exclusive]),
    Spec = xls_parse:actor_artifact(File, []),
    {ok, Template} = file:read_file("test/local_actor_semantics.x.in"),
    Checks = binary:replace(binary:replace(Template, <<"@@SECOND@@">>, integer_to_binary(Expected), [global]),
        <<"@@FAIL@@">>, atom_to_binary(Failure), [global]),
    file:write_file(filename:join(Stage, Name ++ ".x"), [xls_shared_codegen:execution(Spec), Checks], [exclusive]).

%% The projection comes from actual startup/source analysis and is checked against the parsed source.
-spec projection(file:filename()) -> ok.
projection(Stage) ->
    Plan = hls_topology:normalize(#{version => 1,
        actors => #{a => hls_projection_fixture, b => hls_projection_fixture},
        families => #{}, externals => [], route_relations => [], ingresses => [],
        routes => [{{a, out}, [{actor, a}]}, {{b, out}, [{actor, b}]}],
        startup => [{a, [{configure, 4567, -731}]}, {b, [{configure, 1234, 513}]}]}),
    Groups = #{workers => #{members => [{actor, a}, {actor, b}],
        state_storage => registers, mailbox_storage => registers, specialize_state => true}},
    #{groups := [#{state_projection := Projection}]} = hls_scheduler_plan:normalize(Plan, Groups),
    [Context] = proplists:get_value(hls_source_context, hls_projection_fixture:module_info(attributes)),
    File = "test/hls_projection_fixture.erl",
    Spec = xls_parse:actor_artifact(File, Context),
    ok = xls_state_projection:validate(Spec, Projection, hls_source:read(File, Context)),
    {ok, Checks} = file:read_file("test/local_projection_semantics.x.in"),
    file:write_file(filename:join(Stage, "projected.x"),
        [xls_shared_codegen:execution(Spec#{state_projection => Projection}), Checks], [exclusive]).
