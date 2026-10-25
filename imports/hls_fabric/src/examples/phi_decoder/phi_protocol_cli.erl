-module(phi_protocol_cli).
-moduledoc "Repetition-code example frontend. Presets belong to the application, not the compiler or fabric CLI.".
-export([main/0, run/1]).

-doc "Runs the repetition example emitter; HLS_DEBUG=1 includes diagnostic stacks.".
-spec main() -> no_return().
main() -> hls_cli:main("hls-repetition", fun run/1).

-doc "Constructs a repetition configuration and emits a fabric bundle. Width/split are decimal; incompatible placement, inspection and sharing choices fail in phi_protocol_config. Output must be fresh; no XLS or rebar process is launched.".
-spec run([string()]) -> ok.
run([]) -> usage();
run(["--help"]) -> usage();
run(Args) ->
    Options = hls_cli:options(Args, [{"--width", width, value}, {"--split", split, value},
        {"--mixed", mixed, flag}, {"--inspect", inspect, flag},
        {"--share-arithmetic", share_arithmetic, flag}, {"--output", output, value}]),
    Output = hls_cli:required(output, Options),
    Width = hls_cli:integer(width, maps:get(width, Options, "3")),
    Placement = case maps:take(split, maps:without([width, output], Options)) of
        error -> maps:without([width, output], Options);
        {Value, Rest} -> Rest#{split => hls_cli:integer(split, Value)}
    end,
    {Kind, Config} = phi_protocol_config:repetition(Width, Placement),
    _ = hls_build:write(hls_build:plan(#{backend => source_protocol,
        kind => Kind, configuration => Config}), Output),
    ok.

%% Keep example-specific placement choices discoverable without extending compiler options.
-spec usage() -> ok.
usage() ->
    io:put_chars("Usage: hls-repetition --output FRESH_DIRECTORY [--width N] [--split K | --mixed]\n"
        "                      [--inspect] [--share-arithmetic]\n").
