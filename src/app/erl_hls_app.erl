%%%-------------------------------------------------------------------
%% @doc erl_hls public API
%% @end
%%%-------------------------------------------------------------------

-module(erl_hls_app).
-moduledoc """
OTP application callback declared in erl_hls.app.src. Starts erl_hls_sup; it does not compile actors or create device sessions. Compiler and runtime clients invoke their own public entry points.
""".

-behaviour(application).

%% application callbacks.
-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    erl_hls_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
