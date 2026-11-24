-module(hls_runtime_consumer).
-moduledoc "Runs a precompiled callback with no synthesis application on the code path.".

-export([witness/0]).

-doc "Starts only the deployed runtime, executes the callback, and rejects build-code leakage.".
-spec witness() -> ok.
witness() ->
    [
        non_existing = code:which(Module)
     || Module <- [xls_parse, hls_build, hls_protocol_deployment, hls_target_physical]
    ],
    {ok, _} = application:ensure_all_started(hls_runtime),
    {ok, Server} = hls_gs:start_link(hls_runtime_consumer_actor, []),
    try
        0 = gen_server:call(Server, read),
        ok = gen_server:cast(Server, advance),
        1 = gen_server:call(Server, read)
    after
        ok = hls_gs:stop(Server)
    end,
    ok.
