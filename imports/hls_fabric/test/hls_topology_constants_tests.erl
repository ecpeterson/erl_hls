-module(hls_topology_constants_tests).
-include_lib("eunit/include/eunit.hrl").

%% Source facts, all instance identities, RAM dimensions and debug offsets must agree.
-spec closed_state_projection_test() -> ok.
closed_state_projection_test() ->
    Plan = plan(false), Groups = groups(),
    #{groups := [Group]} = hls_scheduler_plan:normalize(Plan, Groups),
    #{state_projection := P, physical_data_width := 7} = Group,
    ?assertEqual([id, bias], maps:get(constants, P)),
    ?assertEqual([0, 1], [S || #{slot := S} <- maps:get(rows, P)]),
    [Binding] = xls_scheduler_ram_v:bindings(#{groups => [Group]}),
    ?assertEqual(40, maps:get(state_width, Binding)),
    Requirements = xls_shared_topology_dslx:artifact_requirements(Plan,
        #{name => projection_fixture, channel_depth => 1, actor_egress_depth => burst, scheduler_groups => Groups}),
    Options = maps:get(hls_projection_fixture, Requirements),
    Source = source(),
    Text = iolist_to_binary(xls_shared_parse:to_xls(Source, Options)),
    ?assertNotEqual(nomatch, binary:match(Text, <<"pub type MachineBits = bits[40]">>)),
    Debug = xls_scheduler_debug:projection(Plan, Groups, #{hls_projection_fixture => Text}),
    [Bank] = maps:get(<<"banks">>, Debug),
    ?assertEqual(40, maps:get(<<"width">>, Bank)),
    ?assertEqual(24, maps:get(<<"offset">>, maps:get(<<"failure">>, maps:get(<<"fields">>, Bank)))),
    ?assert(maps:is_key(<<"state_projection">>, Bank)),
    ?assertEqual(ok, xls_scheduler_debug:validate(Plan, Groups, Debug)),
    %% Codecs are exercised by the XLS witness, separately from textual checks.
    ok = filelib:ensure_dir("_build/state-projection/fixture.x"),
    {ok, Checks} = file:read_file("test/xls/state_projection_checks.xinc"),
    ok = file:write_file("_build/state-projection/fixture.x", [Text, Checks]).

%% An entirely constant record needs no physical data bits; metadata and both codecs still exist.
-spec all_constant_state_test() -> ok.
all_constant_state_test() ->
    Plan = (plan(false))#{startup := []}, Groups = groups(),
    #{groups := [#{physical_data_width := 0}]} = hls_scheduler_plan:normalize(Plan, Groups),
    Requirements = xls_shared_topology_dslx:artifact_requirements(Plan,
        #{name => projection_fixture, channel_depth => 1, actor_egress_depth => burst, scheduler_groups => Groups}),
    Text = xls_shared_parse:to_xls(source(), maps:get(hls_projection_fixture, Requirements)),
    Check = "\n#[test]\nfn empty_data_roundtrip() {\n"
        "  let initial = initial_shared_machine();\n"
        "  assert_eq(machine_from_bits<u32:0>(bits_from_machine(initial), u32:1), initial);\n}\n",
    ok = filelib:ensure_dir("_build/state-projection/empty.x"),
    ok = file:write_file("_build/state-projection/empty.x", [Text, Check]).

%% Declared ingress schemas cannot establish that foreign raw frames are impossible.
-spec external_input_prevents_configuration_specialization_test() -> ok.
external_input_prevents_configuration_specialization_test() ->
    #{groups := [Group]} = hls_scheduler_plan:normalize(plan(true), groups()),
    ?assertNot(maps:is_key(state_projection, Group)).

%% A module's shared representation cannot differ between opted-in and ordinary groups.
-spec partial_module_opt_in_retains_full_state_test() -> ok.
partial_module_opt_in_retains_full_state_test() ->
    #{workers := G} = groups(),
    Specs = #{first => G#{members := [{actor, a}]},
        second => maps:remove(specialize_state, G#{members := [{actor, b}]})},
    #{groups := Result} = hls_scheduler_plan:normalize(plan(false), Specs),
    ?assert(lists:all(fun(R) -> not maps:is_key(state_projection, R) end, Result)).

%% Separate groups use one generated actor module but expose only their own configuration rows.
-spec debug_configuration_is_bank_scoped_test() -> ok.
debug_configuration_is_bank_scoped_test() ->
    #{workers := G} = groups(), Plan = plan(false),
    Specs = #{first => G#{members := [{actor, a}]}, second => G#{members := [{actor, b}]}},
    Requirements = xls_shared_topology_dslx:artifact_requirements(Plan,
        #{name => projection_fixture, channel_depth => 1, actor_egress_depth => burst, scheduler_groups => Specs}),
    Text = xls_shared_parse:to_xls(source(), maps:get(hls_projection_fixture, Requirements)),
    #{<<"banks">> := Banks} = xls_scheduler_debug:projection(Plan, Specs, #{hls_projection_fixture => Text}),
    lists:foreach(fun(#{<<"index">> := I, <<"state_projection">> := #{<<"rows">> := Rows}}) ->
        ?assertMatch([#{<<"instance">> := I, <<"slot">> := 0}], Rows)
    end, Banks).

%% A callback source change invalidates the inferred representation before generation.
-spec projection_source_identity_test() -> ok.
projection_source_identity_test() ->
    #{groups := [#{state_projection := P}]} = hls_scheduler_plan:normalize(plan(false), groups()),
    Spec = xls_parse:actor_artifact(source(), []),
    ?assertError(state_projection_source_mismatch,
        xls_state_projection:validate(Spec, P,
            hls_source:read(source(), context()) ++ [{attribute, 0, changed_source, true}])).

%% Unsupported execution protocols must not silently ignore a requested physical layout.
-spec unsupported_protocol_test() -> ok.
unsupported_protocol_test() ->
    ?assertError(state_projection_requires_hls_statem,
        xls_shared_parse:to_xls("src/examples/regsvc/regsvc.erl", #{state_projection => #{}})),
    ?assertError(state_projection_protocol,
        xls_state_projection:validate(#{retained_calls => #{}}, #{}, [])).

%% A legal float32 startup payload may round without rejecting specialization.
-spec rounded_startup_retains_storage_test() -> ok.
rounded_startup_retains_storage_test() ->
    Plan = hls_topology:normalize(#{version => 1,
        actors => #{a => hls_projection_rounded_fixture}, families => #{},
        externals => [], route_relations => [], routes => [{{a, out}, [{actor, a}]}], ingresses => [],
        startup => [{a, [{configure, 0.1}]}]}),
    Specs = #{only => #{members => [{actor, a}], state_storage => block_ram,
        mailbox_storage => block_ram, specialize_state => true}},
    #{groups := [#{state_projection := Projection, physical_data_width := 32}]} =
        hls_scheduler_plan:normalize(Plan, Specs),
    ?assertEqual([marker], maps:get(constants, Projection)).

%% Internal self-messages keep the payload unconstrained without introducing configuration traffic.
-spec plan(boolean()) -> hls_topology:plan().
plan(Open) ->
    Ingress = case Open of false -> []; true -> [{input, {rectangle, [1, 1]},
        [{values, [put], [{actor, a, {at, [0, 0]}}]}]}] end,
    hls_topology:normalize(#{version => 1, actors => #{a => hls_projection_fixture, b => hls_projection_fixture},
        families => #{}, externals => [], route_relations => [], ingresses => Ingress,
        routes => [{{a, out}, [{actor, a}]}, {{b, out}, [{actor, b}]}],
        startup => [{a, [{configure, 4567, -731}]}, {b, [{configure, 1234, 513}]}]}).

%% Both actors share one executor, requiring distinct per-slot configuration values.
-spec groups() -> hls_scheduler_plan:spec().
groups() -> #{workers => #{members => [{actor, a}, {actor, b}], state_storage => block_ram,
    mailbox_storage => block_ram, specialize_state => true}}.

%% Read the current fixture rather than a dependency's similarly named test data.
-spec source() -> file:filename().
source() -> "test/hls_projection_fixture.erl".

%% Match includes, feature flags and source names captured when the fixture was compiled.
-spec context() -> hls_source:context().
context() ->
    [Context] = proplists:get_value(hls_source_context, hls_projection_fixture:module_info(attributes)),
    Context.

%% Completion payloads remain mutable while private membership and failure bits retain storage.
-spec reduction_projection_test() -> ok.
reduction_projection_test() ->
    Module = hls_projection_reduction_fixture,
    Plan = hls_topology:normalize(#{version => 1, actors => #{a => Module}, families => #{},
        externals => [{results, out, [result]}], route_relations => [], ingresses => [],
        routes => [{{a, out}, [{external, results}]}, {{a, marker}, [{external, results}]}], startup => [{a, [{begin_set, 7, 33}]}]}),
    Specs = #{workers => #{members => [{actor, a}], state_storage => block_ram,
        mailbox_storage => block_ram, specialize_state => true}},
    #{groups := [Group]} = hls_scheduler_plan:normalize(Plan, Specs),
    #{state_projection := Projection} = Group,
    ?assertNot(lists:member(value, maps:get(constants, Projection))),
    Requirements = xls_shared_topology_dslx:artifact_requirements(Plan,
        #{name => projected_reduction, channel_depth => 1, actor_egress_depth => burst, scheduler_groups => Specs}),
    Text = xls_shared_parse:to_xls("test/hls_projection_reduction_fixture.erl", maps:get(Module, Requirements)),
    #{<<"banks">> := [Bank]} = xls_scheduler_debug:projection(Plan, Specs, #{Module => Text}),
    ?assert(maps:is_key(<<"reduction">>, Bank)),
    ok = filelib:ensure_dir("_build/state-projection/reduction.x"),
    Check = "\n#[test]\nfn private_reduction_codec() {\n"
        "  let m = ActorState {phase: Phase::COLLECTING, data: Cell {key: u32:7, mask: u8:33, value: u8:123},\n"
        "    reduction: ReductionState {status: ReductionStatus::OPEN, site: ReductionSite::COLLECTING,\n"
        "      key: u32:7, remaining: ReductionRemaining:1, seen: ReductionMembers:32, expected: ReductionMembers:33,\n"
        "      accumulator: Parity {value: u8:91}, failure: u16:17}, ..initial_shared_machine()};\n"
        "  assert_eq(machine_from_bits<u32:0>(bits_from_machine(m), u32:0), m);\n}\n",
    file:write_file("_build/state-projection/reduction.x", [Text, Check]).

%% A fixed-population transport must not substitute capacity for a runtime subset.
-spec runtime_membership_requires_ordinary_service_test() -> ok.
runtime_membership_requires_ordinary_service_test() ->
    #{reductions := Reduction} = xls_parse:actor_artifact("test/hls_projection_reduction_fixture.erl", []),
    ?assertEqual([], xls_shared_reduction_codegen:declarations(Reduction, ordinary)),
    ?assertError(aggregate_only_runtime_membership,
        xls_shared_reduction_codegen:declarations(Reduction, aggregate_only)),
    ?assertError(aggregate_only_runtime_membership,
        xls_shared_reduction_codegen:functions(Reduction, aggregate_only)).
