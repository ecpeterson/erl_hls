-module(hls_closure_deferred_fixture).
-export([init/1, handle_call/3, handle_cast/2, handle_continue/2]).
-hls_data(state).
-hls_tags([request, report]).
-hls_replies([{request, [report]}]).
-hls_pending_calls(1).
-hls_continuations([refresh]).
-include("hls_closure_types.hrl").

-doc "Initialization shares the retained server's included helper graph.".
-spec init([]) -> #state{}.
init([]) -> #state{value = hardware_value(0)}.

-doc "A three-argument callback selects the retained-reply backend.".
-spec handle_call(#request{}, hls_gs:from(), #state{}) -> hls_gs:call_result(#state{}).
handle_call(#request{value = Value}, _From, State) ->
    {reply, #report{value = hardware_value(Value)}, State, {continue, refresh}}.

-doc "Casts retain a value before the next continuation.".
-spec handle_cast(#report{}, #state{}) -> hls_gs:async_result(#state{}).
handle_cast(#report{value = Value}, State) ->
    {noreply, State#state{value = hardware_value(Value)}, {continue, refresh}}.

-doc "Continuations are hardware roots even though callbacks do not call them.".
-spec handle_continue(refresh, #state{}) -> hls_gs:async_result(#state{}).
handle_continue(refresh, State) ->
    {noreply, State#state{value = continuation_value(State#state.value)}}.

%% This helper is reachable only through the continuation root.
-spec continuation_value(hls_nums:u32()) -> hls_nums:u32().
continuation_value(Value) -> hardware_value(Value) + 1.

-include("hls_closure_helpers.hrl").

-ifdef(MIXED_CALL_ARITY).
%% Callback selection must reject a second call arity before pruning functions.
-spec handle_call(#request{}, #state{}) -> hls_gs:call_result(#state{}).
handle_call(#request{value = Value}, State) ->
    {reply, #report{value = Value}, State}.
-endif.
