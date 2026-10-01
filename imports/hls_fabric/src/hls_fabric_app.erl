%%%-------------------------------------------------------------------
%% @doc hls_fabric public API
%% @end
%%%-------------------------------------------------------------------

-module(hls_fabric_app).

-behaviour(application).

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
