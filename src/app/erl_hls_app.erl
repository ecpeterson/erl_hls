%%%-------------------------------------------------------------------
%% @doc erl_hls public API
%% @end
%%%-------------------------------------------------------------------

-module(erl_hls_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    erl_hls_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
