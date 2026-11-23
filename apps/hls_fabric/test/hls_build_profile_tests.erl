-module(hls_build_profile_tests).
-moduledoc "Build-profile policy checks without source compilation or external tools.".
-include_lib("eunit/include/eunit.hrl").

%% Source feedback and framed gateway clocks retain different literal interface contracts.
-spec protocol_schedules_test() -> ok.
protocol_schedules_test() ->
    Config = source_config(),
    Boundary = hls_build_profile:protocol(boundary, Config),
    Application = hls_build_profile:protocol(application, Config#{device => board, host => 1}),
    ?assertEqual(sampled_flags(), hls_build_profile:flags(Boundary, sampled_clock)),
    ?assertEqual(sampled_flags(), hls_build_profile:flags(Application, sampled_clock)),
    ?assertEqual(channel_flags(2), hls_build_profile:flags(Application, gateway)),
    ?assertEqual(sampled_flags(), hls_build_profile:flags(hls_build_profile:owner(), sampled_clock)),
    ?assertException(error, {hls_diagnostic, #{code := unsupported_build_schedule}},
        hls_build_profile:flags(Boundary, gateway)).

%% Source identities and import paths stay outside hardware placement policy.
-spec protocol_placement_test() -> ok.
protocol_placement_test() ->
    Config = (source_config())#{native_actors => [left], activation => explicit_start,
        inspection => process, dslx_path => ["private/imports"]},
    #{backend := source_protocol, placement := Placement, frame_abi := Frame,
        tools := #{provider := xls, identity := external_compilation}} = hls_build_profile:protocol(boundary, Config),
    ?assertEqual(#{kind => boundary, actor_limit => 4, native_actors => [left], arithmetic_groups => [],
        activation => explicit_start, inspection => process}, Placement),
    ?assertEqual(#{name => canonical_actor_v1, header_bits => 32, payload_bits => 96,
        frame_bits => 128, payload_words => 3, parameterized => true}, Frame),
    ?assertException(error, {hls_diagnostic, #{code := unknown_config_fields}},
        hls_build_profile:protocol(boundary, Config#{schedule => #{pipeline_stages => 2}})).

%% Scheduler defaults and overrides use the existing channel schedule and placement normalization.
-spec scheduler_schedules_test() -> ok.
scheduler_schedules_test() ->
    Default = hls_build_profile:scheduler(scheduler_placement(), #{}),
    ?assertEqual(channel_flags(2) ++ [<<"--worst_case_throughput=1">>],
        hls_build_profile:flags(Default, channel)),
    #{backend := channel_scheduler, placement := #{name := "example", scheduler_groups := #{}},
        schedules := #{channel := #{pipeline_stages := 2, initiation_interval := 1,
            executor_result_delay := 0, delay_model := <<"unit">>}}} = Default,
    Changed = hls_build_profile:scheduler(scheduler_placement(), #{pipeline_stages => 4,
        initiation_interval => 3, delay_model => "unit", executor_result_delay => 7}),
    ?assertEqual(channel_flags(4) ++ [<<"--additional_channel_delay_ps=_result_out:send=7">>,
        <<"--worst_case_throughput=3">>], hls_build_profile:flags(Changed, channel)),
    ?assertException(error, {hls_diagnostic, #{code := unsupported_build_schedule}},
        hls_build_profile:flags(Default, sampled_clock)).

%% Unknown fields and coercible-looking values never silently change a clock contract.
-spec scheduler_rejection_test() -> ok.
scheduler_rejection_test() ->
    Placement = scheduler_placement(),
    ?assertException(error, {hls_diagnostic, #{code := unknown_schedule_options}},
        hls_build_profile:scheduler(Placement, #{flop_outputs => false})),
    lists:foreach(fun(Options) ->
        ?assertException(error, {hls_diagnostic, #{code := invalid_schedule_option}},
            hls_build_profile:scheduler(Placement, Options))
    end, [#{pipeline_stages => 0}, #{pipeline_stages => false}, #{pipeline_stages => 2.0},
        #{pipeline_stages => (1 bsl 32)}, #{initiation_interval => 0}, #{initiation_interval => true},
        #{executor_result_delay => -1}, #{executor_result_delay => false},
        #{executor_result_delay => (1 bsl 32)}, #{delay_model => false}, #{delay_model => <<>>},
        #{delay_model => "unit --flop_outputs=false"}, #{delay_model => <<"unit\n">>}]),
    ?assertError({invalid_dslx_profile_keys, [], [unknown]},
        hls_build_profile:scheduler(Placement#{unknown => true}, #{})).

%% Different textual representations identify the same XLS delay model.
-spec delay_model_normalization_test() -> ok.
delay_model_normalization_test() ->
    Profiles = [hls_build_profile:scheduler(scheduler_placement(), #{delay_model => Model})
        || Model <- [unit, "unit", <<"unit">>]],
    ?assertEqual(1, length(lists:usort(Profiles))).

%% Prepared experiment policy reuses the channel renderer and records its external placement boundary.
-spec experiment_policy_test() -> ok.
experiment_policy_test() ->
    #{version := 1, profile := Profile, codegen_flags := Flags} = hls_build_profile:experiment(#{
        schedule => #{pipeline_stages => 4, initiation_interval => tool_default,
            delay_model => "test-model", executor_result_delay => 7}, completion_storage => lutram}),
    ?assertMatch(#{backend := channel_scheduler, placement := prepared_source,
        postprocess := #{completion_storage := lutram},
        schedules := #{channel := #{initiation_interval := tool_default}}}, Profile),
    ?assertEqual([<<"--pipeline_stages=4">>, <<"--delay_model=test-model">>, <<"--flop_inputs=false">>,
        <<"--flop_outputs=true">>, <<"--use_system_verilog=false">>, <<"--reset=reset">>,
        <<"--fifo_module=">>, <<"--additional_channel_delay_ps=_result_out:send=7">>], Flags),
    Scheduler = hls_build_profile:scheduler(scheduler_placement(), #{pipeline_stages => 4,
        initiation_interval => tool_default, delay_model => <<"test-model">>, executor_result_delay => 7}),
    ?assertEqual(hls_build_profile:flags(Scheduler, channel), Flags),
    ?assertException(error, {hls_diagnostic, #{code := unsupported_build_schedule}},
        hls_build_profile:flags(Profile, sampled_clock)).

%% Defaults remain explicit; unsupported experiment fields and storage never fall through.
-spec experiment_rejection_test() -> ok.
experiment_rejection_test() ->
    #{profile := #{postprocess := #{completion_storage := registers}}, codegen_flags := Flags} =
        hls_build_profile:experiment(#{}),
    ?assertEqual(channel_flags(2) ++ [<<"--worst_case_throughput=1">>], Flags),
    ?assertException(error, {hls_diagnostic, #{code := unknown_experiment_options}},
        hls_build_profile:experiment(#{backend => source_protocol})),
    ?assertException(error, {hls_diagnostic, #{code := invalid_completion_storage}},
        hls_build_profile:experiment(#{completion_storage => block_ram})),
    ?assertException(error, {hls_diagnostic, #{code := invalid_schedule_option}},
        hls_build_profile:experiment(#{schedule => #{initiation_interval => false}})).

%% The CLI resolves duplicate options first, writes only valid JSON, and never replaces an existing file.
-spec profile_cli_test() -> ok.
profile_cli_test() ->
    Output = filename:join(["_build", "profile-tests", integer_to_list(erlang:unique_integer([positive, monotonic])) ++ ".json"]),
    try
        ?assertException(error, {hls_diagnostic, #{code := invalid_schedule_option}},
            hls_fabric_cli:run(["profile", "--output", Output, "--pipeline-stages", "0"])),
        ?assertNot(filelib:is_file(Output)),
        ok = hls_fabric_cli:run(["profile", "--output", Output, "--pipeline-stages", "bad", "--pipeline-stages", "4",
            "--initiation-interval", "tool_default", "--delay-model", "test-model", "--completion-storage", "lutram"]),
        {ok, Bytes} = file:read_file(Output),
        #{<<"version">> := 1, <<"profile">> := #{<<"placement">> := <<"prepared_source">>,
            <<"schedules">> := #{<<"channel">> := #{<<"pipeline_stages">> := 4,
                <<"initiation_interval">> := <<"tool_default">>}},
            <<"postprocess">> := #{<<"completion_storage">> := <<"lutram">>}}} = json:decode(Bytes),
        ?assertException(error, {hls_diagnostic, #{code := output_exists}},
            hls_fabric_cli:run(["profile", "--output", Output])),
        ?assertEqual({ok, Bytes}, file:read_file(Output))
    after file:delete(Output) end.

%% Configuration validation checks shape without opening these unused test inputs.
-spec source_config() -> hls_source_config:boundary().
source_config() -> #{sources => [{"unused.erl", []}], topology => {unused, topology, []}, actor_limit => 4}.

%% A tiny scheduler placement needs no compiled topology for policy normalization.
-spec scheduler_placement() -> xls_fabric_topology_profile:profile().
scheduler_placement() -> #{name => example, channel_depth => 1, actor_egress_depth => burst}.

%% This literal deliberately records the sampled schedule's existing external interface.
-spec sampled_flags() -> [binary()].
sampled_flags() -> [<<"--pipeline_stages=1">>, <<"--delay_model=unit">>, <<"--flop_inputs=false">>,
    <<"--flop_outputs=false">>, <<"--use_system_verilog=false">>, <<"--reset=reset">>].

%% Channel/gateway schedules preserve output flops and inline FIFO selection.
-spec channel_flags(pos_integer()) -> [binary()].
channel_flags(Stages) -> [<<"--pipeline_stages=", (integer_to_binary(Stages))/binary>>, <<"--delay_model=unit">>,
    <<"--flop_inputs=false">>, <<"--flop_outputs=true">>, <<"--use_system_verilog=false">>,
    <<"--reset=reset">>, <<"--fifo_module=">>].

%% Profile metadata records capacity without changing gateway or sampled-clock policy.
-spec frame_capacity_test() -> ok.
frame_capacity_test() ->
    #{frame_abi := Narrow, schedules := Schedules} =
        hls_build_profile:protocol(network, (source_config())#{frame_payload_words => 1}),
    #{frame_abi := Wide, schedules := Schedules} =
        hls_build_profile:protocol(network, (source_config())#{frame_payload_words => 3}),
    ?assertEqual({32, 64}, {maps:get(payload_bits, Narrow), maps:get(frame_bits, Narrow)}),
    ?assertEqual({96, 128}, {maps:get(payload_bits, Wide), maps:get(frame_bits, Wide)}).
