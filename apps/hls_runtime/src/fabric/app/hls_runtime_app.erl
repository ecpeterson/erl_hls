-module(hls_runtime_app).
-moduledoc """
OTP application callback for live actor execution and virtual-node supervision.
Device transports remain caller-owned.
""".

-behaviour(application).

%% Application callbacks.
-export([start/2, stop/1]).

-doc "Starts the runtime supervisor; device attachment remains explicit.".
-spec start(application:start_type(), term()) -> {ok, pid()} | {error, term()}.
start(_StartType, _StartArgs) ->
    hls_runtime_sup:start_link().

-doc "Completes application shutdown after supervised nodes have stopped.".
-spec stop(term()) -> ok.
stop(_State) ->
    ok.
