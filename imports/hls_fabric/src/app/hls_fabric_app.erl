%%%-------------------------------------------------------------------
%% @doc hls_fabric public API
%% @end
%%%-------------------------------------------------------------------

-module(hls_fabric_app).
-moduledoc """
OTP starts this application callback, which delegates explicit virtual-node supervision to hls_fabric_sup. Device transports remain caller-owned.
""".

-behaviour(application).

%% Application callbacks.
-export([start/2, stop/1]).

-doc "Starts the fabric application supervisor; device attachment remains explicit.".
-spec start(application:start_type(), term()) -> {ok, pid()} | {error, term()}.
start(_StartType, _StartArgs) ->
    hls_fabric_sup:start_link().

-doc "Completes application shutdown after supervised nodes have stopped.".
-spec stop(term()) -> ok.
stop(_State) ->
    ok.

%% internal functions
