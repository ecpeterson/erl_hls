-module(hls_fabric_cli).
-moduledoc "Fabric build frontend: checked plan inspection, placement and protocol deployment emission. External tool execution remains separate.".
-export([main/0, run/1]).

-doc "Runs hls-fabric with human diagnostics by default or --diagnostics json. Unexpected failures retain their original exception and stack.".
-spec main() -> no_return().
main() -> hls_cli:main("hls-fabric", fun run/1).

-doc "Plans or emits one trusted source configuration, or writes a prepared-source experiment profile, without launching rebar or XLS. plan prints a read-only report; emit and profile require fresh output paths. Source paths are relative to the caller.".
-spec run([string()]) -> ok.
run([]) -> usage();
run(["--help"]) -> usage();
run(["emit" | Args]) ->
    Options = hls_cli:options(Args, [{"--backend", backend, value}, {"--kind", kind, value},
        {"--config", config, value}, {"--output", output, value}]),
    Request = request(Options, ""),
    ConfigPath = hls_cli:required(config, Options),
    Output = hls_cli:required(output, Options),
    _ = hls_build:write(hls_build:plan(Request#{configuration := ConfigPath}), Output),
    ok;
run(["profile" | Args]) ->
    Options = hls_cli:options(Args, [{"--output", output, value},
        {"--pipeline-stages", pipeline_stages, value}, {"--initiation-interval", initiation_interval, value},
        {"--delay-model", delay_model, value}, {"--executor-result-delay", executor_result_delay, value},
        {"--completion-storage", completion_storage, value}]),
    Output = hls_cli:required(output, Options),
    Interval = case maps:get(initiation_interval, Options, "1") of
        "tool_default" -> tool_default;
        Value -> hls_cli:integer(initiation_interval, Value)
    end,
    Schedule = #{pipeline_stages => hls_cli:integer(pipeline_stages, maps:get(pipeline_stages, Options, "2")),
        initiation_interval => Interval, delay_model => maps:get(delay_model, Options, "unit"),
        executor_result_delay => hls_cli:integer(executor_result_delay, maps:get(executor_result_delay, Options, "0"))},
    Policy = hls_build_profile:experiment(#{schedule => Schedule,
        completion_storage => completion_storage(maps:get(completion_storage, Options, "registers"))}),
    write_profile(Output, Policy);
run(["plan" | Args]) ->
    Options = hls_cli:options(Args, [{"--backend", backend, value}, {"--kind", kind, value}, {"--config", config, value},
        {"--stage", stage, value}, {"--format", format, value}]),
    Stage = stage(maps:get(stage, Options, "summary")),
    Format = format(maps:get(format, Options, "erlang")),
    Request = request(Options, ""),
    ConfigPath = hls_cli:required(config, Options),
    Plan = hls_build:plan(Request#{configuration := ConfigPath}),
    Report = hls_build:inspect(Plan, Stage),
    case Format of
        erlang -> io:format("~tp.~n", [Report]);
        json -> io:put_chars([json:encode(hls_diagnostic:json_value(Report)), "\n"])
    end;
run(Args) -> hls_diagnostic:raise(command_line, unknown_command,
    <<"Expected plan, emit or profile; use --help for syntax.">>, #{arguments => [unicode:characters_to_binary(Arg) || Arg <- Args]}).

%% Storage names are a closed backend vocabulary; command input never creates atoms.
-spec completion_storage(string()) -> registers | lutram.
completion_storage("registers") -> registers;
completion_storage("lutram") -> lutram;
completion_storage(Other) -> hls_diagnostic:raise(command_line, invalid_completion_storage,
    <<"Completion storage must be registers or lutram.">>, #{value => unicode:characters_to_binary(Other)}).

%% Resolve policy before touching the filesystem and preserve any existing profile exactly.
-spec write_profile(file:filename(), hls_build_profile:experiment()) -> ok.
write_profile(Output, Policy) ->
    Data = [json:encode(hls_diagnostic:json_value(Policy)), "\n"],
    Result = case filelib:ensure_dir(Output) of
        ok -> file:write_file(Output, Data, [exclusive]);
        Error -> Error
    end,
    case Result of
        ok -> ok;
        {error, eexist} -> hls_diagnostic:raise(packaging, output_exists,
            <<"Profile output must be a fresh file.">>, #{output => unicode:characters_to_binary(Output)});
        {error, Reason} -> hls_diagnostic:raise(packaging, output_unavailable,
            unicode:characters_to_binary(file:format_error(Reason)), #{output => unicode:characters_to_binary(Output)})
    end.

%% A missing backend preserves the explicit source-kind frontend; scheduler placement has its own config.
-spec request(map(), file:filename()) -> hls_build:request().
request(Options, Config) ->
    case maps:get(backend, Options, "source_protocol") of
        "source_protocol" -> #{backend => source_protocol,
            kind => kind(maps:get(kind, Options, "application")), configuration => Config};
        "channel_scheduler" ->
            case maps:is_key(kind, Options) of
                false -> #{backend => channel_scheduler, configuration => Config};
                true -> hls_diagnostic:raise(command_line, incompatible_build_kind,
                    <<"--kind selects a source-protocol boundary; omit it for channel_scheduler.">>, #{})
            end;
        Other -> hls_diagnostic:raise(command_line, unknown_backend,
            <<"Backend must be source_protocol or channel_scheduler.">>,
            #{value => unicode:characters_to_binary(Other)})
    end.

%% Unknown kinds fail before any source compilation; command input never creates atoms.
-spec kind(string()) -> hls_source_build:kind().
kind("transport") -> transport;
kind("network") -> network;
kind("boundary") -> boundary;
kind("application") -> application;
kind("bridge") -> bridge;
kind("deployment") -> deployment;
kind("mixed") -> mixed;
kind(Other) -> hls_diagnostic:raise(command_line, unknown_emitter,
    <<"Unknown build kind; use --help for supported kinds.">>, #{value => unicode:characters_to_binary(Other)}).

%% Views are a fixed API, not module/function names supplied by the command line.
-spec stage(string()) -> hls_source_build:inspection_stage().
stage("summary") -> summary;
stage("configuration") -> configuration;
stage("source") -> source;
stage("topology") -> topology;
stage("placement") -> placement;
stage("composition") -> composition;
stage("schedule") -> schedule;
stage("profile") -> profile;
stage(Other) -> hls_diagnostic:raise(command_line, unknown_inspection_stage,
    <<"Unknown plan view; use --help for supported stages.">>, #{value => unicode:characters_to_binary(Other)}).

%% Printed Erlang terms and tagged JSON are diagnostic formats, not saved executable plans.
-spec format(string()) -> erlang | json.
format("erlang") -> erlang;
format("json") -> json;
format(Other) -> hls_diagnostic:raise(command_line, unknown_output_format,
    <<"Plan format must be erlang or json.">>, #{value => unicode:characters_to_binary(Other)}).

%% Keep application presets outside the generic fabric command.
-spec usage() -> ok.
usage() ->
    io:put_chars("Usage: hls-fabric plan --config FILE [--backend BACKEND] [--kind KIND] [--stage STAGE] [--format erlang|json]\n"
        "       hls-fabric emit --config FILE --output FRESH_DIRECTORY [--backend BACKEND] [--kind KIND]\n"
        "       hls-fabric profile --output FRESH_FILE [--pipeline-stages N] [--initiation-interval N|tool_default]\n"
        "           [--delay-model NAME] [--executor-result-delay N] [--completion-storage registers|lutram]\n"
        "       Add --diagnostics text|json to any command (default text).\n"
        "Backends: source_protocol (default), channel_scheduler.\n"
        "Source kinds: transport, network, boundary, application, bridge, deployment, mixed.\n"
        "Stages: summary, configuration, source, topology, placement, composition, schedule, profile.\n"
        "Plans inspect checked source and wiring; emit writes source-build.json, DSLX and pin adapters.\n"
        "profile records channel policy for prepared experiment DSLX; it does not read source or invoke XLS.\n"
        "XLS is separate; compile-source-build --dry-run previews its commands.\n").
