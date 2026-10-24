-module(hls_fabric_cli).
-moduledoc "Fabric build frontend: placement, protocol clock schedules and deployment emission.".
-export([main/0, run/1]).

-doc "Runs hls-fabric; HLS_DEBUG=1 includes diagnostic stacks.".
-spec main() -> no_return().
main() -> hls_cli:main("hls-fabric", fun run/1).

-doc "Emits one fabric configuration without launching rebar or XLS. Reads a trusted Erlang map; paths are relative to the caller and output must be fresh.".
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
run(Args) -> error({unknown_command, Args}).

%% Unknown kinds fail before any source compilation.
-spec kind(string()) -> hls_source_build:kind().
kind("transport") -> transport;
kind("network") -> network;
kind("boundary") -> boundary;
kind("application") -> application;
kind("bridge") -> bridge;
kind("deployment") -> deployment;
kind("mixed") -> mixed;
kind(Other) -> error({unknown_emitter, Other}).

%% Keep application presets outside the generic fabric command.
-spec usage() -> ok.
usage() ->
    io:put_chars("Usage: hls-fabric emit --config FILE --output FRESH_DIRECTORY [--kind KIND]\n"
        "Kinds: transport, network, boundary, application, bridge, deployment, mixed.\n"
        "Emits source-build.json, DSLX and pin adapters; XLS is separate.\n").
