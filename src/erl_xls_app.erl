%%%-------------------------------------------------------------------
%% @doc erl_xls public API
%% @end
%%%-------------------------------------------------------------------

-module(erl_xls_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    erl_xls_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
