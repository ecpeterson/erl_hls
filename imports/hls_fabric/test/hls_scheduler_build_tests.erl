-module(hls_scheduler_build_tests).
-moduledoc "Generic scheduler packaging regressions; these inspect build contracts, not native hardware performance.".
-include_lib("eunit/include/eunit.hrl").

%% A normal non-decoder topology has the same semantic source under direct and RAM placements.
-spec direct_and_ram_test_() -> term().
direct_and_ram_test_() -> {timeout, 30, fun direct_and_ram/0}.

%% Placement changes the physical interfaces and RAM recipe, never the declared actor IDs.
-spec direct_and_ram() -> ok.
direct_and_ram() ->
    Direct = hls_scheduler_build:plan(config(#{})),
    #{backend := channel_scheduler, scheduler := #{groups := [], direct_members := DirectMembers},
      topology := Topology, requirements := Requirements} = hls_scheduler_build:descriptor(Direct),
    ?assertEqual([{actor, left}, {actor, right}], DirectMembers),
    ?assertEqual([hls_scheduler_build_fixture], maps:keys(Requirements)),
    #{data := [DirectUnit]} = hls_scheduler_build:inspect(Direct, schedule),
    ?assertNot(lists:any(fun(F) -> binary:match(F, <<"--ram_configurations=">>) =/= nomatch end,
        maps:get(codegen_flags, DirectUnit))),
    Ram = hls_scheduler_build:plan(config(groups())),
    #{topology := Topology, scheduler := #{groups := [_], direct_members := []}, ram_bindings := [Binding]} =
        hls_scheduler_build:descriptor(Ram),
    ?assertEqual(128, maps:get(mailbox_width, Binding)),
    #{data := [RamUnit]} = hls_scheduler_build:inspect(Ram, schedule),
    RamFlags = [F || F <- maps:get(codegen_flags, RamUnit),
        binary:match(F, <<"--ram_configurations=">>) =/= nomatch],
    ?assertMatch([_], RamFlags),
    ?assert(lists:member(<<"support/compiler/rtl/hls_1r1w_ram.v">>, maps:get(rtl, RamUnit))),
    ok.

%% Source removal after planning proves writing consumes retained generated material.
-spec retained_plan_test_() -> term().
retained_plan_test_() -> {timeout, 30, fun retained_plan/0}.

%% The bundle carries the same profile and schedule shown by in-process inspection.
-spec retained_plan() -> ok.
retained_plan() ->
    Root = fresh("retained"), ok = file:make_dir(Root),
    Source = filename:join(Root, "hls_scheduler_build_fixture.erl"),
    {ok, _} = file:copy("test/hls_scheduler_build_fixture.erl", Source),
    Config = (config(groups()))#{sources := [{Source, []}], schedule => #{pipeline_stages => 3}},
    Before = files(Root),
    Plan = hls_scheduler_build:plan(Config),
    ?assertEqual(Before, files(Root)),
    ok = file:rename(Source, Source ++ ".retained"),
    #{data := Profile} = hls_scheduler_build:inspect(Plan, profile),
    #{data := Units = [Unit]} = hls_scheduler_build:inspect(Plan, schedule),
    ?assert(lists:member(<<"--pipeline_stages=3">>, maps:get(codegen_flags, Unit))),
    Output = filename:join(Root, "bundle"),
    #{metadata := #{backend := channel_scheduler, profile := Encoded}, units := Units,
      eligible := false, native_measured := false} = hls_scheduler_build:write(Plan, Output),
    ?assertEqual(hls_diagnostic:json_value(Profile), Encoded),
    lists:foreach(fun(File) -> ?assert(filelib:is_regular(filename:join(Output, File))) end,
        ["actors/hls_scheduler_build_fixture.x", "scheduler/topology.x", "ram/bindings.json",
         "ram/wires.vh", "ram/application_ports.vh", "ram/instances.vh", "source-build.json"]),
    ?assertException(error, {generated_output_exists, _}, hls_scheduler_build:write(Plan, Output)),
    ok.

%% Include and macro options must agree between loaded interfaces and source-based hardware lowering.
-spec source_context_test_() -> term().
source_context_test_() -> {timeout, 30, fun source_context/0}.

%% A macro-selected record width and mailbox capacity survive both compilation paths and packaging.
-spec source_context() -> ok.
source_context() ->
    Root = fresh("source-context"), ok = file:make_dir(Root),
    Include = filename:join(Root, "includes"),
    Header = filename:join(Include, "scheduler_value.hrl"),
    ok = filelib:ensure_dir(Header),
    ok = file:write_file(Header,
        "-ifdef(WIDE_WORD).\n-define(VALUE_TYPE, hls_nums:u16()).\n"
        "-else.\n-define(VALUE_TYPE, hls_nums:u8()).\n-endif.\n", [exclusive]),
    {ok, Original} = file:read_file("test/hls_scheduler_build_fixture.erl"),
    Typed = binary:replace(Original, <<"hls_nums:u8()">>, <<"?VALUE_TYPE">>, [global]),
    SourceBytes = binary:replace(Typed, <<"-hls_mailbox_capacity(2).">>,
        <<"-hls_mailbox_capacity(?CAPACITY).">>),
    Source = filename:join(Root, "hls_scheduler_build_fixture.erl"),
    Included = binary:replace(SourceBytes, <<"-module(hls_scheduler_build_fixture).">>,
        <<"-module(hls_scheduler_build_fixture).\n-include(\"scheduler_value.hrl\").">>),
    ok = file:write_file(Source, Included, [exclusive]),
    Options = [{i, Include}, {d, 'WIDE_WORD'}, {d, 'CAPACITY', 5}],
    Plan = hls_scheduler_build:plan((config(groups()))#{sources := [{Source, Options}]}),
    #{scheduler := #{groups := [#{state := #{width := 16}, mailbox_capacity := 5}]}} =
        hls_scheduler_build:descriptor(Plan),
    ?assertEqual(16, hls_scheduler_build_fixture:pack_width(cell)),
    ok = file:rename(Header, Header ++ ".retained"),
    Output = filename:join(Root, "bundle"),
    _ = hls_scheduler_build:write(Plan, Output),
    {ok, Dslx} = file:read_file(filename:join([Output, "actors", "hls_scheduler_build_fixture.x"])),
    ?assertNotEqual(nomatch, binary:match(Dslx, <<"value : u16">>)),
    ok.

%% Configuration shape and placement errors cannot trigger a missing source read.
-spec configuration_rejection_test() -> ok.
configuration_rejection_test() ->
    Config = (config(#{}))#{sources := [{"missing-scheduler-source.erl", []}]},
    ?assertException(error, {hls_diagnostic, #{code := scheduler_config_fields}},
        hls_scheduler_build:plan(Config#{unexpected => true})),
    ?assertException(error, {hls_diagnostic, #{code := scheduler_config_fields}},
        hls_scheduler_build:plan(maps:remove(placement, Config))),
    ?assertException(error, {hls_diagnostic, #{code := invalid_config_field}},
        hls_scheduler_build:plan(Config#{sources := broken})),
    ?assertError({invalid_dslx_channel_depth, 0}, hls_scheduler_build:plan(
        Config#{placement := (maps:get(placement, Config))#{channel_depth := 0}})),
    ok.

%% Two declarations of one module are rejected rather than silently choosing the last source.
-spec duplicate_source_test_() -> term().
duplicate_source_test_() -> {timeout, 30, fun() ->
    Config = config(#{}), [Source] = maps:get(sources, Config),
    ?assertException(error, {hls_diagnostic, #{code := duplicate_scheduler_source}},
        hls_scheduler_build:plan(Config#{sources := [Source, Source]}))
end}.

%% Even an already available actor module must be explicitly declared in this build.
-spec undeclared_actor_test_() -> term().
undeclared_actor_test_() -> {timeout, 30, fun() ->
    Config = (config(#{}))#{topology := {hls_scheduler_build_fixture, topology, [hls_actor_pid_fixture]}},
    ?assertException(error, {hls_diagnostic, #{code := missing_scheduler_actor_sources}},
        hls_scheduler_build:plan(Config))
end}.

%% Tests select only physical placement; their application source is unchanged.
-spec config(hls_scheduler_plan:spec()) -> hls_scheduler_build:config().
config(Groups) ->
    #{sources => [{"test/hls_scheduler_build_fixture.erl", []}],
      topology => {hls_scheduler_build_fixture, topology, []},
      placement => #{name => scheduler_fixture, channel_depth => 1, actor_egress_depth => burst,
        scheduler_groups => Groups}}.

%% Both actors share one supported executor while retaining separate RAM rows.
-spec groups() -> hls_scheduler_plan:spec().
groups() -> #{counters => #{members => [{actor, left}, {actor, right}],
    state_storage => block_ram, mailbox_storage => block_ram}}.

%% Each test owns a fresh disposable directory and never replaces an earlier fixture.
-spec fresh(string()) -> string().
fresh(Name) ->
    Path = filename:join(["_build", "scheduler-build-tests", Name ++ "-" ++
        integer_to_list(erlang:system_time(nanosecond)) ++ "-" ++
        integer_to_list(erlang:unique_integer([positive, monotonic]))]),
    ok = filelib:ensure_dir(Path), Path.

%% Root enumeration is enough to detect unexpected plan-time writes beside the copied source.
-spec files(file:filename()) -> [file:filename()].
files(Root) -> {ok, Names} = file:list_dir(Root), lists:sort(Names).
