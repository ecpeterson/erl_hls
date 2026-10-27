-module(hls_closure_statem_fixture).
-export([init/1, waiting/3]).
-hls_data(state).
-hls_tags([request, report]).
-hls_phases([waiting]).
-hls_outputs([out]).
-hls_mailbox_capacity(1).
-include("hls_closure_types.hrl").

-doc "Initialization and phase callbacks retain their common helper dependency.".
-spec init([]) -> {ok, waiting, #state{}}.
init([]) -> {ok, waiting, #state{value = hardware_value(0)}}.

-doc "Accepted requests update state through a helper from an included file.".
-spec waiting(enter, hls_statem:phase(), #state{}) -> hls_statem:enter_result(#state{});
    (cast, #request{}, #state{}) -> hls_statem:cast_result(waiting, #state{}).
waiting(enter, _Old, State) ->
    {State, [{cast, out, #report{value = State#state.value}}]};
waiting(cast, #request{value = Value}, State) ->
    {waiting, State#state{value = hardware_value(Value)}, consume}.

-include("hls_closure_helpers.hrl").
