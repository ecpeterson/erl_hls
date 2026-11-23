-module(hls_build_diagnostics_tests).
-moduledoc "Source-build diagnostics and read-only plan inspection. These tests exercise small compiler inputs and actual renderer traces, not hardware behavior.".
-include_lib("eunit/include/eunit.hrl").

%% Missing structure is diagnosed before source preparation, including its selected build kind.
-spec missing_configuration_test() -> ok.
missing_configuration_test() ->
    {Diagnostic, Calls} = trace_calls(fun() ->
        diagnostic(fun() -> hls_source_build:plan(network, #{}) end)
    end, source_targets() ++ renderer_targets()),
    ?assertMatch(#{code := missing_config_field, context := #{kind := network, field := [sources]}}, Diagnostic),
    assert_readable(Diagnostic),
    ?assertEqual(#{}, Calls).

%% Malformed scalars, nested roles and unknown keys report their exact config path before compilation.
-spec invalid_configuration_test() -> ok.
invalid_configuration_test() ->
    Deployment = deployment(),
    #{devices := Devices, limits := Limits} = Deployment,
    North = maps:get(north, Devices),
    Cases = [{network, (base())#{actor_limit := 0}, invalid_config_field, [actor_limit], #{}},
        {network, (base())#{topology := {some_module, topology, invalid}}, invalid_config_field, [topology], #{}},
        {network, (base())#{sources := [{"bad.erl", invalid}]}, invalid_config_field, [sources, 0], #{}},
        {network, (base())#{surprise => true}, unknown_config_fields, [], #{value => [surprise]}},
        {deployment, Deployment#{devices := Devices#{north := invalid}}, invalid_config_field,
            [devices, north], #{role => north}},
        {deployment, Deployment#{devices := Devices#{north := maps:remove(service, North)}},
            missing_config_field, [devices, north, service], #{role => north}},
        {deployment, Deployment#{devices := Devices#{north := North#{host := 0}}},
            invalid_config_field, [devices, north, host], #{role => north}},
        {deployment, Deployment#{devices := Devices#{north := North#{extra => true}}},
            unknown_config_fields, [devices, north], #{role => north, value => [extra]}},
        {deployment, Deployment#{limits := invalid}, invalid_config_field, [limits], #{}},
        {deployment, Deployment#{limits := Limits#{events := 1}}, invalid_config_field, [limits, events], #{}},
        {deployment, Deployment#{limits := Limits#{extra => 7}}, unknown_config_fields, [limits], #{value => [extra]}}],
    {ok, Calls} = trace_calls(fun() ->
        lists:foreach(fun({Kind, Config, Code, Path, Extra}) ->
            Diagnostic = diagnostic(fun() -> hls_source_build:plan(Kind, Config) end),
            #{stage := configuration, code := Code, context := Context = #{kind := Kind, field := Path}} = Diagnostic,
            ?assertEqual(Extra, maps:with(maps:keys(Extra), Context)),
            assert_readable(Diagnostic)
        end, Cases),
        ?assertMatch(#{code := invalid_config_field, context := #{field := []}},
            diagnostic(fun() -> hls_source_config:validate(network, invalid) end)),
        ok
    end, source_targets() ++ renderer_targets()),
    ?assertEqual(#{}, Calls).

%% Filenames are flat Unicode text rather than iodata, arbitrary terms or invalid UTF-8 bytes.
-spec filename_configuration_test() -> ok.
filename_configuration_test() ->
    Invalid = [[bad_atom], [[97]], [97 | tail], <<255>>],
    {ok, Calls} = trace_calls(fun() ->
        lists:foreach(fun(File) ->
            lists:foreach(fun({Config, Path}) ->
                ?assertMatch(#{code := invalid_config_field, context := #{field := Path}},
                    diagnostic(fun() -> hls_source_build:plan(network, Config) end))
            end, [{(base())#{sources := [{File, []}]}, [sources, 0]},
                {(base())#{dslx_path => [File]}, [dslx_path, 0]}])
        end, Invalid),
        Unicode = [16#3bb, $., $e, $r, $l],
        lists:foreach(fun(File) ->
            Config = (base())#{sources := [{File, []}], dslx_path => [File]},
            ?assertEqual(Config, hls_source_config:validate(network, Config))
        end, [Unicode, unicode:characters_to_binary(Unicode)]),
        ok
    end, source_targets() ++ renderer_targets()),
    ?assertEqual(#{}, Calls).

%% Improper list tails must reject at the public boundary before traversal or apply/3.
-spec improper_configuration_test() -> ok.
improper_configuration_test() ->
    Cases = [{sources, [{"actor.erl", []} | bad_tail], [sources]},
        {sources, [{"actor.erl", [debug_info | bad_tail]}], [sources, 0]},
        {topology, {some_module, topology, [argument | bad_tail]}, [topology]},
        {dslx_path, ["directory" | bad_tail], [dslx_path]},
        {native_actors, [left | bad_tail], [native_actors]},
        {arithmetic_groups, [[left, right] | bad_tail], [arithmetic_groups]},
        {arithmetic_groups, [[left | bad_tail]], [arithmetic_groups, 0]}],
    {ok, Calls} = trace_calls(fun() ->
        lists:foreach(fun({Key, Value, Path}) ->
            ?assertMatch(#{code := invalid_config_field, context := #{field := Path}},
                diagnostic(fun() -> hls_source_build:plan(network, (base())#{Key => Value}) end))
        end, Cases)
    end, source_targets() ++ renderer_targets()),
    ?assertEqual(#{}, Calls).

%% Syntax, missing files and invalid contents retain the absolute config filename and selected kind.
-spec config_file_context_test() -> ok.
config_file_context_test() ->
    Directory = fresh_directory("diagnostic-config"),
    Syntax = filename:join(Directory, "syntax.erl"),
    Empty = filename:join(Directory, "empty.erl"),
    Missing = filename:join(Directory, "absent.erl"),
    ok = filelib:ensure_dir(Syntax),
    ok = file:write_file(Syntax, <<"%% Line one is valid.\n#{sources => }.\n">>),
    ok = file:write_file(Empty, <<"#{}.\n">>),
    {ok, Calls} = trace_calls(fun() ->
        lists:foreach(fun({File, Code}) ->
            D = diagnostic(fun() -> hls_source_build:plan(network, File) end),
            ?assertMatch(#{stage := configuration, code := Code,
                context := #{kind := network}}, D),
            ?assertEqual(unicode:characters_to_binary(filename:absname(File)), maps:get(config_file, maps:get(context, D))),
            case Code of
                config_syntax -> ?assertEqual(2, maps:get(line, maps:get(context, D)));
                missing_config_field -> ?assertEqual([sources], maps:get(field, maps:get(context, D)));
                config_read -> ok
            end,
            assert_readable(D)
        end, [{Syntax, config_syntax}, {Missing, config_read}, {Empty, missing_config_field}]),
        ok
    end, source_targets() ++ renderer_targets()),
    ?assertEqual(#{}, Calls).

%% Ordinary source syntax is a diagnostic, while a trusted topology constructor bug remains an error.
-spec source_failure_test_() -> term().
source_failure_test_() -> {timeout, 30, fun source_failure/0}.

%% The failing source has no parse transform; the topology error follows valid small-source loading.
-spec source_failure() -> ok.
source_failure() ->
    Source = filename:join(fresh_directory("diagnostic-source"), "diagnostic_broken.erl"),
    ok = filelib:ensure_dir(Source),
    ok = file:write_file(Source, <<"-module(diagnostic_broken).\nbroken( -> ok.\n">>),
    SourceText = unicode:characters_to_binary(Source),
    Config = (base())#{sources := [{Source, []}]},
    {ok, Calls} = trace_calls(fun() ->
        D = diagnostic(fun() -> hls_source_build:plan(network, Config) end),
        ?assertMatch(#{stage := source, code := source_compile_failed,
            context := #{source := SourceText, errors := [#{location := _, message := _} | _]}}, D),
        assert_readable(D),
        ?assertError(function_clause, hls_source_build:plan(network,
            (base())#{topology := {hls_protocol_network_fixture, unsupported, [internal_marker]}})),
        ok
    end, renderer_targets()),
    ?assertEqual(#{}, Calls).

%% Nested diagnostic context is scoped and must not rewrite unrelated programming failures.
-spec diagnostic_context_test() -> ok.
diagnostic_context_test() ->
    Tagged = diagnostic(fun() -> hls_diagnostic:with_context(#{role => north}, fun() ->
        hls_diagnostic:with_context(#{actor => left}, fun() ->
            hls_diagnostic:raise(composition, unsupported_fixture, <<"Fixture capability is unavailable">>, #{port => early})
        end)
    end) end),
    ?assertMatch(#{stage := composition, code := unsupported_fixture,
        context := #{role := north, actor := left, port := early}}, Tagged),
    assert_readable(Tagged),
    ?assertEqual(kept, hls_diagnostic:with_context(#{role => south}, fun() -> kept end)),
    ?assertError({unexpected_internal, marker}, hls_diagnostic:with_context(#{actor => broken},
        fun() -> error({unexpected_internal, marker}) end)),
    ?assertThrow(unexpected_throw, hls_diagnostic:with_context(#{actor => broken},
        fun() -> throw(unexpected_throw) end)),
    ?assertExit(unexpected_exit, hls_diagnostic:with_context(#{actor => broken},
        fun() -> exit(unexpected_exit) end)),
    Clean = diagnostic(fun() -> hls_diagnostic:raise(configuration, standalone_fixture,
        <<"No inherited diagnostic context">>, #{field => [sources]}) end),
    ?assertEqual(#{field => [sources]}, maps:get(context, Clean)).

%% Overlapping roles and unsupported BEAM routes retain their source identities in readable failures.
-spec composition_diagnostics_test_() -> term().
composition_diagnostics_test_() -> {timeout, 45, fun composition_diagnostics/0}.

%% All three inputs otherwise use the same small source-correct framed network.
-spec composition_diagnostics() -> ok.
composition_diagnostics() ->
    Overlap = (base())#{devices => #{
        north => #{native_actors => [left, sink], host => 2, service => 29},
        south => #{native_actors => [right, sink], host => 3, service => 31}},
        limits => #{crossings => 8, commands => 8, events => 8}},
    Multicast = (base())#{native_actors => [left, sink], host => 2, service => 29},
    HostLink = (base())#{sources := sources() ++ [{"apps/hls_fabric/test/hls_protocol_composition_fixture.erl", []}],
        topology := {hls_protocol_composition_fixture, beam_to_beam, []},
        native_actors => [left], host => 2, service => 29},
    {{Ownership, Fanout, Route}, Calls} = trace_calls(fun() ->
        {diagnostic(fun() -> hls_source_build:plan(deployment, Overlap) end),
         diagnostic(fun() -> hls_source_build:plan(mixed, Multicast) end),
         diagnostic(fun() -> hls_source_build:plan(mixed, HostLink) end)}
    end, renderer_targets()),
    ?assertMatch(#{stage := deployment, code := duplicate_actor_owner,
        context := #{actor := sink, roles := [north, south]}}, Ownership),
    ?assertMatch(#{stage := mixed, code := unsupported_host_fanout,
        context := #{actor := right, module := hls_protocol_network_fixture,
            port := _, recipients := [_, _]}}, Fanout),
    ?assertMatch(#{stage := mixed, code := unsupported_host_route,
        context := #{actor := right, module := hls_protocol_network_fixture,
            destination := {actor, sink}, capability := beam_to_beam}}, Route),
    lists:foreach(fun assert_readable/1, [Ownership, Fanout, Route]),
    ?assertEqual(#{}, Calls).

%% Every inspection stage must reuse planning facts without rendering hardware or writing a bundle.
-spec inspection_test_() -> term().
inspection_test_() -> {timeout, 45, fun inspection/0}.

%% Each inspection view reuses the same source snapshot and exposes only planning facts.
-spec inspection() -> ok.
inspection() ->
    Config = base(),
    {Plan, PlanningCalls} = trace_calls(fun() -> hls_source_build:plan(network, Config) end,
        renderer_targets()),
    ?assertEqual(#{}, PlanningCalls),
    {Inspections, Calls} = trace_calls(fun() ->
        [{Stage, hls_source_build:inspect(Plan, Stage)}
            || Stage <- [summary, configuration, source, topology, placement, composition, schedule]]
    end, renderer_targets() ++ source_targets()),
    ?assertEqual(#{}, Calls),
    lists:foreach(fun({Stage, View}) ->
        ?assertMatch(#{version := 1, kind := network, stage := Stage, data := _}, View)
    end, Inspections),
    #{data := #{config := Config, compiler := Compiler, fabric := Fabric,
        working_directory := Directory}} = proplists:get_value(configuration, Inspections),
    ?assert(filelib:is_dir(Compiler)), ?assert(filelib:is_dir(Fabric)),
    ?assert(filelib:is_dir(Directory)),
    ?assertMatch(#{data := #{kind := network, build := #{actors := 3,
        native_indices := [0, 1, 2]}, transport_transitions := #{whole := #{}},
        network_phases := #{observe := #{actors := [0, 1, 2]}}}},
        proplists:get_value(composition, Inspections)),
    #{data := Schedule} = proplists:get_value(schedule, Inspections),
    ?assertMatch([#{top := _, codegen_flags := [_ | _]} | _], Schedule).

%% Every builder's inspected schedule must be the exact schedule written into its eventual bundle.
-spec all_kind_schedule_test_() -> term().
all_kind_schedule_test_() ->
    [{atom_to_list(Kind), {timeout, 60, fun() -> inspect_and_write(Kind) end}}
        || Kind <- [transport, network, boundary, application, bridge, mixed, deployment]].

%% Emission is the positive trace control; retained stage inspection may neither render nor recompile.
-spec inspect_and_write(hls_source_build:kind()) -> ok.
inspect_and_write(Kind) ->
    {Plan, PlanningCalls} = trace_calls(fun() -> hls_source_build:plan(Kind, configuration(Kind)) end,
        renderer_targets()),
    ?assertEqual(#{}, PlanningCalls),
    {Views, InspectionCalls} = trace_calls(fun() ->
        maps:from_list([{Stage, hls_source_build:inspect(Plan, Stage)}
            || Stage <- [source, topology, placement, composition, schedule]])
    end, renderer_targets() ++ source_targets()),
    ?assertEqual(#{}, InspectionCalls),
    assert_public_report(Views),
    #{data := SourceRoles} = maps:get(source, Views),
    #{data := Topologies} = maps:get(topology, Views),
    #{data := Placements} = maps:get(placement, Views),
    #{data := #{transport_transitions := Transitions}} = maps:get(composition, Views),
    Roles = case Kind of deployment -> [north, south]; _ -> [whole] end,
    ?assertEqual(Roles, lists:sort(maps:keys(Transitions))),
    ?assert(lists:all(fun is_map/1, maps:values(Transitions))),
    ?assertEqual(Roles, lists:sort(maps:keys(SourceRoles))),
    ?assertEqual(Roles, lists:sort(maps:keys(Topologies))),
    ?assertEqual(Roles, lists:sort(maps:keys(Placements))),
    lists:foreach(fun(Role) ->
        #{modules := Modules, inventory := _} = maps:get(Role, SourceRoles),
        ?assert(map_size(Modules) > 0),
        maps:foreach(fun(_, Module) ->
            ?assertMatch(#{version := 1, source_plan := _, machine_layout := _, output_ports := _}, Module),
            ?assertNot(maps:is_key(program, Module)),
            ?assertNot(maps:is_key(emitted, Module)),
            ?assertNot(maps:is_key(dslx_sha256, Module))
        end, Modules),
        ?assertMatch(#{actors := [_ | _], routes := [_ | _]}, maps:get(Role, Topologies)),
        ?assertNot(maps:is_key(bundle, maps:get(Role, Placements)))
    end, Roles),
    #{data := Schedule} = maps:get(schedule, Views),
    Directory = fresh_directory("diagnostic-bundle-" ++ atom_to_list(Kind)),
    {Manifest, WriteCalls} = trace_calls(fun() -> hls_source_build:write(Plan, Directory) end,
        renderer_targets() ++ source_targets()),
    ?assertEqual(#{}, maps:with(source_targets(), WriteCalls)),
    lists:foreach(fun(Target) -> ?assert(maps:get(Target, WriteCalls, 0) > 0) end,
        [{xls_activation_codegen, artifact, 1}, {xls_local_owner, ports, 2}, {xls_template, render, 2}]),
    ?assertEqual(Schedule, maps:get(units, Manifest)),
    {ok, Bytes} = file:read_file(filename:join(Directory, "source-build.json")),
    Disk = json:decode(Bytes),
    ?assertEqual(json:decode(iolist_to_binary(json:encode(Schedule))), maps:get(<<"units">>, Disk)).

%% Keep opaque compiler programs and live VM handles out of every public inspection tree.
-spec assert_public_report(term()) -> ok.
assert_public_report(Value) when is_map(Value) ->
    ?assertNot(maps:is_key(program, Value)),
    maps:foreach(fun(Key, Entry) -> assert_public_report(Key), assert_public_report(Entry) end, Value);
assert_public_report(Value) when is_list(Value) -> lists:foreach(fun assert_public_report/1, Value);
assert_public_report(Value) when is_tuple(Value) ->
    ?assertNot(tuple_size(Value) > 0 andalso element(1, Value) =:= program),
    lists:foreach(fun assert_public_report/1, tuple_to_list(Value));
assert_public_report(Value) ->
    ?assertNot(is_reference(Value) orelse is_pid(Value) orelse is_port(Value) orelse is_function(Value)).

%% Reuse one tiny feedback graph across kinds, with only each kind's required ownership fields.
-spec configuration(hls_source_build:kind()) -> hls_source_config:config().
configuration(transport) -> maps:remove(control, base());
configuration(Kind) when Kind =:= network; Kind =:= boundary -> base();
configuration(application) -> (base())#{device => board, host => 2};
configuration(bridge) -> (base())#{native_actors => [left, sink], host => 2, service => 29};
configuration(mixed) -> (base())#{sources := sources() ++ [{"apps/hls_fabric/test/hls_protocol_composition_fixture.erl", []}],
    topology := {hls_protocol_composition_fixture, beam_to_beam, []},
    native_actors => [left, right], host => 2, service => 29};
configuration(deployment) -> deployment().

%% Complete disjoint role coverage keeps the same global actor indices and source snapshot.
-spec deployment() -> hls_source_config:deployment().
deployment() -> (base())#{devices => #{
    north => #{native_actors => [left, sink], host => 2, service => 29},
    south => #{native_actors => [right], host => 3, service => 31}},
    limits => #{crossings => 8, commands => 8, events => 8}}.

%% CLI selection errors reject before opening the config or preparing any actor source.
-spec cli_selection_test() -> ok.
cli_selection_test() ->
    {Diagnostics, Calls} = trace_calls(fun() ->
        [diagnostic(fun() -> hls_fabric_cli:run(["plan", "--kind", "network",
            "--config", "unread-config.erl", Option, "unsupported"]) end)
            || Option <- ["--stage", "--format"]]
    end, source_targets() ++ renderer_targets()),
    ?assertMatch([#{code := unknown_inspection_stage, context := #{value := <<"unsupported">>}},
        #{code := unknown_output_format, context := #{value := <<"unsupported">>}}], Diagnostics),
    ?assertEqual(#{}, Calls).

%% The CLI exposes machine-readable planning without requiring an output path.
-spec cli_json_test_() -> term().
cli_json_test_() -> {timeout, 30, fun cli_json/0}.

%% Capture only stdout and verify that the temporary terms file remains the sole output.
-spec cli_json() -> ok.
cli_json() ->
    Directory = fresh_directory("diagnostic-plan"),
    ConfigFile = filename:join(Directory, "input.erl"),
    ok = filelib:ensure_dir(ConfigFile),
    ok = file:write_file(ConfigFile, io_lib:format("~tp.~n", [base()])),
    {{ok, Printed}, Calls} = trace_calls(fun() -> capture_io(fun() ->
        hls_fabric_cli:run(["plan", "--kind", "network", "--config", ConfigFile,
            "--stage", "configuration", "--format", "json"])
    end) end, renderer_targets()),
    Json = json:decode(Printed),
    ?assertMatch(#{<<"version">> := 1, <<"kind">> := <<"network">>,
        <<"stage">> := <<"configuration">>, <<"data">> := #{<<"config">> := #{
            <<"topology">> := #{<<"$tuple">> := [<<"hls_protocol_network_fixture">>, <<"framed">>, []]}}}}, Json),
    {ok, Files} = file:list_dir(Directory),
    ?assertEqual(["input.erl"], Files),
    ?assertEqual(#{}, Calls).

%% Each test writes only into a unique disposable build subtree, retaining failures for inspection.
-spec fresh_directory(string()) -> file:filename().
fresh_directory(Prefix) -> filename:join("_build", Prefix ++ "-" ++
    integer_to_list(erlang:system_time(nanosecond)) ++ "-" ++
    integer_to_list(erlang:unique_integer([positive, monotonic]))).

%% Both actor implementations are reused rather than introducing an application-sized workload.
-spec sources() -> [hls_source_config:source_file()].
sources() -> [{"apps/hls_fabric/test/hls_protocol_network_fixture.erl", []}, {"apps/hls_fabric/test/hls_protocol_inbox_fixture.erl", []}].

%% Framing, placement and host control all derive from this three-actor feedback graph.
-spec base() -> hls_source_config:network().
base() -> #{sources => sources(), topology => {hls_protocol_network_fixture, framed, []},
    actor_limit => 3, control => rectangle}.

%% Catch only a deliberate diagnostic; a missing diagnostic or any internal error fails the test.
-spec diagnostic(fun(() -> term())) -> map().
diagnostic(Fun) ->
    try Fun() of _ -> error(expected_build_diagnostic)
    catch error:{hls_diagnostic, Diagnostic} -> Diagnostic end.

%% A stable code and a human message must survive text formatting without raw exception fallback.
-spec assert_readable(map()) -> ok.
assert_readable(Diagnostic = #{code := Code, message := Message}) ->
    ?assert(is_binary(Message)), ?assert(byte_size(Message) > 0),
    Formatted = iolist_to_binary(hls_diagnostic:format(Diagnostic)),
    ?assert(binary:match(Formatted, atom_to_binary(Code)) =/= nomatch),
    ?assert(binary:match(Formatted, Message) =/= nomatch).

%% Actual leaf renderers make early hardware generation observable independently of outer wrappers.
-spec renderer_targets() -> [{module(), atom(), arity()}].
renderer_targets() -> [{xls_activation_codegen, artifact, 1}, {xls_local_owner, ports, 2},
    {xls_template, render, 2}, {xls_protocol_transport, emit, 1},
    {xls_protocol_network, emit, 3}, {xls_protocol_boundary, emit, 2}, {xls_protocol_bridge, emit, 3}].

%% Invalid command/config structure must not reach source preparation.
-spec source_targets() -> [{module(), atom(), arity()}].
source_targets() -> [{compile, file, 2}, {xls_actor_program, from_file, 2}, {hls_protocol_transport, prepare, 1}].

%% The private trace session observes this process and drains every event before returning.
-spec trace_calls(fun(() -> term()), [{module(), atom(), arity()}]) -> {term(), map()}.
trace_calls(Fun, Targets) ->
    lists:foreach(fun({Module, _, _}) -> {module, Module} = code:ensure_loaded(Module) end, Targets),
    {Collector, Monitor} = spawn_monitor(fun() -> collect(#{}) end),
    Session = trace:session_create(build_diagnostics_rendering, Collector, []),
    try
        1 = trace:process(Session, self(), true, [call]),
        lists:foreach(fun(Target) -> 1 = trace:function(Session, Target, [], []) end, Targets),
        Result = Fun(),
        1 = trace:process(Session, self(), false, [call]),
        Ref = trace:delivered(Session, self()),
        receive {trace_delivered, _, Ref} -> ok
        after 5000 -> error(diagnostic_trace_delivery_timeout) end,
        Collector ! {collect, self(), Ref},
        receive {Ref, Counts} -> {Result, Counts}
        after 5000 -> error(diagnostic_trace_collection_timeout) end
    after
        trace:session_destroy(Session), exit(Collector, kill),
        receive {'DOWN', Monitor, process, Collector, _} -> ok
        after 5000 -> error(diagnostic_trace_cleanup_timeout) end
    end.

%% Retain only call counts, so source programs are not copied into test diagnostics.
-spec collect(map()) -> ok.
collect(Counts) ->
    receive
        %% A traced renderer or source preparation function was entered.
        {trace, _, call, {Module, Function, Arguments}} ->
            Key = {Module, Function, length(Arguments)},
            collect(maps:update_with(Key, fun(N) -> N + 1 end, 1, Counts));
        %% The owner has crossed the trace delivery barrier.
        {collect, Owner, Ref} -> Owner ! {Ref, Counts}, ok
    end.

%% Replace the group leader only for this call and restore it even if CLI execution fails.
-spec capture_io(fun(() -> term())) -> {term(), binary()}.
capture_io(Fun) ->
    Leader = group_leader(),
    {Collector, Monitor} = spawn_monitor(fun() -> collect_io([]) end),
    try
        true = group_leader(Collector, self()),
        Result = Fun(),
        Ref = make_ref(), Collector ! {collect, self(), Ref},
        receive {Ref, Bytes} -> {Result, Bytes}
        after 5000 -> error(diagnostic_output_timeout) end
    after
        true = group_leader(Leader, self()), exit(Collector, kill),
        receive {'DOWN', Monitor, process, Collector, _} -> ok
        after 5000 -> error(diagnostic_output_cleanup_timeout) end
    end.

%% Support the ordinary character-output requests used by io:put_chars and io:format.
-spec collect_io([unicode:chardata()]) -> ok.
collect_io(Chunks) ->
    receive
        %% Direct characters preserve their requested encoding when captured as UTF-8.
        {io_request, From, ReplyAs, {put_chars, Encoding, Characters}} ->
            From ! {io_reply, ReplyAs, ok},
            collect_io([unicode:characters_to_binary(Characters, Encoding) | Chunks]);
        %% Formatted output is evaluated by the standard requested formatter.
        {io_request, From, ReplyAs, {put_chars, Encoding, Module, Function, Arguments}} ->
            Characters = apply(Module, Function, Arguments),
            From ! {io_reply, ReplyAs, ok},
            collect_io([unicode:characters_to_binary(Characters, Encoding) | Chunks]);
        %% The synchronous CLI call finished, so all prior writes were acknowledged.
        {collect, Owner, Ref} -> Owner ! {Ref, iolist_to_binary(lists:reverse(Chunks))}, ok
    end.
