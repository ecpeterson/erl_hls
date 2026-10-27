-module(hls_closure_immediate_fixture).
-export([init/1, handle_call/2, handle_cast/2]).
-hls_data(state).
-hls_tags([request, report]).
-hls_replies([{request, [report]}]).
-include("hls_closure_types.hrl").

-doc "Initialization shares the helpers used by the immediate callbacks.".
-spec init([]) -> #state{}.
init([]) -> #state{value = hardware_value(0)}.

-doc "Immediate calls return the included helper's result.".
-spec handle_call(#request{}, #state{}) -> hls_gs:call_result(#state{}).
handle_call(#request{value = Value}, State) ->
    {reply, #report{value = hardware_value(Value)}, State}.

-doc "Casts retain the same helper result in application state.".
-spec handle_cast(#report{}, #state{}) -> hls_gs:async_result(#state{}).
handle_cast(#report{value = Value}, State) ->
    {noreply, State#state{value = hardware_value(Value)}}.

-include("hls_closure_helpers.hrl").
