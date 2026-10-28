-module(telemetry).
-moduledoc """
Runnable windowed-telemetry project. Connects telemetry_calibrator to telemetry_window on BEAM, or lowers the same telemetry_topology into a portable source bundle. The actors and message records are application code; compilation, packing and transport come from erl_hls/hls_runtime. No hls_fabric or board shell is required.
""".
-include("telemetry.hrl").

%% Host-side finite application execution.
-export([run/1, example_commands/0]).
%% Portable hardware-source build; external XLS execution is separate.
-export([write_bundle/1]).
-export_type([command/0, report/0]).

-doc "Configuration changes and signed samples, in one logical sender's order.".
-type command() :: #configure{} | #raw{}.
-doc "Statistics for four consecutive calibrated samples; sequence identifies the last sample.".
-type report() :: #summary{}.

-doc "Two windows including signed values, saturation and a configuration change between windows.".
-spec example_commands() -> [command()].
example_commands() ->
    [#configure{offset = -10, gain = 3}] ++
        [#raw{sequence = I, value = V} || {I, V} <- [{0, -20000}, {1, -3}, {2, 4}, {3, 20000}]] ++
        [#configure{offset = 100, gain = 2}] ++
        [#raw{sequence = I, value = V} || {I, V} <- [{4, -50}, {5, 0}, {6, 100}, {7, 16000}]].

-doc "Runs real CPU actors and returns complete four-sample reports. Requires typed commands, a configuration before the fourth sample, and a sample count divisible by four. Up to three early samples postpone until the first configuration. Later configurations affect following samples, including within a window. Paces one window at a time because the CPU scheduler does not model hardware backpressure. Owns and stops both actors; failures propagate and a 30-second host deadline terminates its worker and linked actors. This is a finite host example, not a device session.".
-spec run([command()]) -> [report()].
run(Commands) ->
    ok = validate_commands(Commands, false, 0),
    Host = self(),
    Reference = make_ref(),
    {Worker, Monitor} = spawn_monitor(fun() -> Host ! {Reference, run_cpu(Commands)} end),
    receive
        {Reference, Reports} ->
            receive
                {'DOWN', Monitor, process, Worker, normal} -> Reports
            end;
        {'DOWN', Monitor, process, Worker, Reason} ->
            error({telemetry_run_failed, Reason})
    after 30000 ->
        exit(Worker, kill),
        receive
            {'DOWN', Monitor, process, Worker, _} -> ok
        end,
        error(telemetry_run_timeout)
    end.

%% Check the demonstration host's finite-input contract before starting actors.
-spec validate_commands([command()], boolean(), non_neg_integer()) -> ok.
validate_commands([], _Configured, Count) when Count rem 4 =:= 0 -> ok;
validate_commands([], _Configured, Count) ->
    error({incomplete_window, Count rem 4});
validate_commands([Command = #configure{} | Rest], _Configured, Count) ->
    _ = telemetry_calibrator:pack(Command),
    validate_commands(Rest, true, Count);
validate_commands([Command = #raw{} | Rest], Configured, Count) ->
    _ = telemetry_calibrator:pack(Command),
    case not Configured andalso Count >= 3 of
        true -> error(configuration_required);
        false -> validate_commands(Rest, Configured, Count + 1)
    end.

%% Linked actors belong to this isolated worker; failed startup also tears down peers.
-spec run_cpu([command()]) -> [report()].
run_cpu(Commands) ->
    {ok, Window} = hls_statem:start_link(telemetry_window, [], [
        {mailbox_capacity, 4}, {outputs, #{report => self()}}
    ]),
    {ok, Calibrator} = hls_statem:start_link(telemetry_calibrator, [], [
        {mailbox_capacity, 4}, {outputs, #{readings => Window}}
    ]),
    try
        feed(Commands, Calibrator, 0, [])
    after
        hls_statem:stop(Calibrator),
        hls_statem:stop(Window)
    end.

%% A scheduler inspection fences each host cast, while each report fences four downstream readings.
-spec feed([command()], pid(), non_neg_integer(), [report()]) -> [report()].
feed([], _Calibrator, _Count, Reports) ->
    lists:reverse(Reports);
feed([Command | Rest], Calibrator, Count, Reports) ->
    ok = hls_statem:cast(Calibrator, Command),
    _ = hls_statem:info(Calibrator),
    NextCount =
        case Command of
            #raw{} -> Count + 1;
            #configure{} -> Count
        end,
    case Command of
        #raw{} when NextCount rem 4 =:= 0 ->
            receive
                {'$gen_cast', Report = #summary{}} ->
                    feed(Rest, Calibrator, NextCount, [Report | Reports])
            after 5000 -> error({missing_telemetry_report, NextCount div 4})
            end;
        _ ->
            feed(Rest, Calibrator, NextCount, Reports)
    end.

-doc "Writes this project's actors, connected topology, failure-codebook sidecars and compiler support into a fresh directory. Freezes a source-build.json for compile-source-build, with a two-stage unit-delay XLS schedule and three payload words. Source modules come from this installed compiler's src/examples/telemetry (included in its release). Existing output fails and partial output is retained. No external tools run; the resulting RTL still needs a platform clock/reset/transport wrapper before deployment.".
-spec write_bundle(file:filename()) -> map().
write_bundle(Output) ->
    Plan = hls_topology:from_module(telemetry_topology),
    Profile = #{name => telemetry_topology, channel_depth => 1, actor_egress_depth => burst},
    Requirements = xls_topology_dslx:artifact_requirements(Plan, Profile),
    Directory = hls_artifact_bundle:open(Output),
    Sources = filename:join([code:lib_dir(erl_hls), "src", "examples", "telemetry"]),
    maps:foreach(
        fun(Module, Options) ->
            Source = filename:join(Sources, atom_to_list(Module) ++ ".erl"),
            Artifact = xls_parse:to_artifact(Source, Options#{source_options => [{i, Sources}]}),
            Name = atom_to_list(Module) ++ ".x",
            Bytes = xls_emitted:bytes(Artifact),
            ok = file:write_file(filename:join(Directory, Name), Bytes, [exclusive]),
            ok = file:write_file(
                filename:join(Directory, Name ++ ".json"),
                json:encode(#{
                    dslx_sha256 => binary:encode_hex(crypto:hash(sha256, Bytes), lowercase),
                    failure_sites => xls_emitted:sites(Artifact)
                }),
                [exclusive]
            )
        end,
        Requirements
    ),
    ok = file:write_file(
        filename:join(Directory, "telemetry_topology.x"),
        xls_topology_dslx:emit(Plan, Profile),
        [exclusive]
    ),
    Imports = hls_compile:support(Directory, []),
    Unit = #{
        role => <<".">>,
        directory => <<".">>,
        source => <<"telemetry_topology.x">>,
        top => <<"Top">>,
        module => <<"telemetry_top">>,
        output => <<"telemetry.v">>,
        dslx_path => [<<".">> | Imports],
        codegen_flags => [
            <<"--pipeline_stages=2">>,
            <<"--delay_model=unit">>,
            <<"--worst_case_throughput=1">>,
            <<"--flop_inputs=false">>,
            <<"--flop_outputs=true">>,
            <<"--use_system_verilog=false">>,
            <<"--reset=reset">>,
            <<"--fifo_module=">>
        ],
        rtl => [<<"telemetry.v">>]
    },
    hls_artifact_bundle:finish(Directory, [Unit], #{
        kind => telemetry, frame_abi => hls_frame_layout:descriptor(hls_frame_layout:default())
    }).
