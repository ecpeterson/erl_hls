-module(hls_statem_bad_mode_fixture).

-behavior(hls_statem).

-export([callback_mode/0, init/1, waiting/3]).

callback_mode() ->
    state_functions.

init(Observer) ->
    Observer ! initialized,
    {ok, waiting, undefined}.

waiting(enter, _OldPhase, Data) ->
    {keep_state, Data}.
