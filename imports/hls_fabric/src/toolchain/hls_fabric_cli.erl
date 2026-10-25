-module(hls_fabric_cli).
-moduledoc "Fabric build frontend: checked plan inspection, placement and protocol deployment emission. External tool execution remains separate.".
-export([main/0, run/1]).

-doc "Runs hls-fabric with human diagnostics by default or --diagnostics json. Unexpected failures retain their original exception and stack.".
-spec main() -> no_return().
main() -> hls_cli:main("hls-fabric", fun run/1).

-doc "Plans or emits one trusted source configuration without launching rebar or XLS. plan prints a read-only stage report; emit requires a fresh output path. Source paths are relative to the caller.".
-spec run([string()]) -> ok.
run([]) -> usage();
run(["--help"]) -> usage();
run(["emit" | Args]) ->
    Options = hls_cli:options(Args, [{"--kind", kind, value},
        {"--config", config, value}, {"--output", output, value}]),
    Kind = kind(maps:get(kind, Options, "application")),
    ConfigPath = hls_cli:required(config, Options),
    Output = hls_cli:required(output, Options),
    _ = hls_source_build:write(Kind, ConfigPath, Output),
    ok;
run(["plan" | Args]) ->
    Options = hls_cli:options(Args, [{"--kind", kind, value}, {"--config", config, value},
        {"--stage", stage, value}, {"--format", format, value}]),
    Kind = kind(maps:get(kind, Options, "application")),
    Stage = stage(maps:get(stage, Options, "summary")),
    Format = format(maps:get(format, Options, "erlang")),
    ConfigPath = hls_cli:required(config, Options),
    Plan = hls_source_build:plan(Kind, ConfigPath),
    Report = hls_source_build:inspect(Plan, Stage),
    case Format of
        erlang -> io:format("~tp.~n", [Report]);
        json -> io:put_chars([json:encode(hls_diagnostic:json_value(Report)), "\n"])
    end;
run(Args) -> hls_diagnostic:raise(command_line, unknown_command,
    <<"Expected plan or emit; use --help for syntax.">>, #{arguments => [unicode:characters_to_binary(Arg) || Arg <- Args]}).

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
    io:put_chars("Usage: hls-fabric plan --config FILE [--kind KIND] [--stage STAGE] [--format erlang|json]\n"
        "       hls-fabric emit --config FILE --output FRESH_DIRECTORY [--kind KIND]\n"
        "       Add --diagnostics text|json to either command (default text).\n"
        "Kinds: transport, network, boundary, application, bridge, deployment, mixed.\n"
        "Stages: summary, configuration, source, topology, placement, composition, schedule.\n"
        "Plans inspect checked source and wiring; emit writes source-build.json, DSLX and pin adapters.\n"
        "XLS is separate; compile-source-build --dry-run previews its commands.\n").
