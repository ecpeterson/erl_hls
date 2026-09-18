-module(hls_deferred_fixture).
-moduledoc "A finite batch service exercising retained callers, continuations and stale handles.".
-behaviour(hls_gs).
-compile({parse_transform, hls_pack}).
-export([init/1, handle_call/3, handle_cast/2, handle_continue/2]).
-hls_data(state).
-hls_tags([wait, release, read, duplicate, explode, report, wrong]).
-hls_replies([{wait, [report]}, {read, [report]}]).
-hls_pending_calls(2).
-hls_continuations([drain]).

%% Two waiters are retained in application state; the runtime owns their actual callers.
-record(state, {handles = hls_type:zero() :: hls_lists:list(hls_gs:from(), 2),
    values = hls_type:zero() :: hls_lists:list(hls_nums:u32(), 2),
    count = hls_type:zero() :: hls_nums:u32(), cursor = hls_type:zero() :: hls_nums:u32(),
    last = hls_type:zero() :: hls_gs:from(), total = hls_type:zero() :: hls_nums:u32()}).
-record(wait, {value = hls_type:zero() :: hls_nums:u32()}).
-record(release, {unused = hls_type:zero() :: hls_nums:u32()}).
-record(read, {unused = hls_type:zero() :: hls_nums:u32()}).
-record(duplicate, {unused = hls_type:zero() :: hls_nums:u32()}).
-record(explode, {mode = hls_type:zero() :: hls_nums:u32()}).
-record(report, {value = hls_type:zero() :: hls_nums:u32()}).
-record(wrong, {unused = hls_type:zero() :: hls_nums:u32()}).

-doc "Starts an empty batch.".
-spec init([]) -> #state{}.
init([]) -> #state{}.

-doc "Retains waits and immediately reports the sum of completed replies.".
-spec handle_call(#wait{} | #read{}, hls_gs:from(), #state{}) -> hls_gs:call_result(#state{}).
%% Retain the opaque handle alongside the requested value.
handle_call(#wait{value = Value}, From, State = #state{count = Count}) ->
    {noreply, State#state{count = Count + 1,
        handles = hls_lists:set(Count + 1, State#state.handles, From),
        values = hls_lists:set(Count + 1, State#state.values, Value)}};
%% Erlang evaluates the reply expression before the proposed state; badarith must win over badarg.
handle_call(#read{unused = 1}, _From, State) ->
    {reply, #report{value = 8 div State#state.cursor},
        State#state{total = hls_lists:nth(3, State#state.values)}};
%% Continuation priority means this observes every preceding released reply.
handle_call(#read{}, _From, State) -> {reply, #report{value = State#state.total}, State}.

-doc "Starts draining, probes stale-handle isolation, or injects a callback failure.".
-spec handle_cast(#release{} | #duplicate{} | #explode{}, #state{}) -> hls_gs:async_result(#state{}).
%% Empty releases need no continuation.
handle_cast(#release{}, State = #state{count = 0}) -> {noreply, State};
%% A nonempty batch advances one response at a time without an outbox list.
handle_cast(#release{}, State) -> {noreply, State#state{cursor = 0}, {continue, drain}};
%% A previous completed handle must not address a newly allocated caller.
handle_cast(#duplicate{}, State) -> {noreply, State, [{reply, State#state.last, #report{value = 999}}]};
%% A reply contract failure must fail every outstanding call without publishing this value.
handle_cast(#explode{mode = 1}, State) ->
    From = hls_lists:nth(1, State#state.handles),
    {noreply, State, [{reply, From, #wrong{}}]};
%% A selected body failure must not let its apparently valid reply escape.
handle_cast(#explode{}, State) ->
    true = State#state.count =:= 0,
    {noreply, State}.

-doc "Replies to one waiter and repeats until the accepted batch has drained.".
-spec handle_continue(drain, #state{}) -> hls_gs:async_result(#state{}).
handle_continue(drain, State = #state{cursor = Cursor, count = Count}) ->
    From = hls_lists:nth(Cursor + 1, State#state.handles),
    Value = hls_lists:nth(Cursor + 1, State#state.values),
    Next = State#state{cursor = Cursor + 1, last = From, total = State#state.total + Value},
    case Cursor + 1 =:= Count of
        true ->
            Actions = [{reply, From, #report{value = Value}}],
            Result = {noreply, Next#state{count = 0}, Actions},
            Result;
        false -> {noreply, Next, [{reply, From, #report{value = Value}}, {continue, drain}]}
    end.
