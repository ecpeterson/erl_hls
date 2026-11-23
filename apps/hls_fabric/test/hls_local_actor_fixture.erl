-module(hls_local_actor_fixture).
-moduledoc "A guarded accumulating actor for source-driven local execution checks.".
-behaviour(hls_statem).
-export([init/1, ready/3]).
-hls_data(counter).
-hls_phases([ready]).
-hls_outputs([result]).
-hls_tags([add, total]).
-hls_mailbox_capacity(2).

%% Algorithm state is separate from the publication predicate.
-record(counter, {value = hls_type:zero() :: hls_nums:u32(),
    publish = hls_type:zero() :: hls_bool:bool()}).
%% Only values admitted by the callback guard can change state.
-record(add, {value = hls_type:zero() :: hls_nums:u32()}).
%% Publication reports the newly committed sum.
-record(total, {value = hls_type:zero() :: hls_nums:u32()}).

-doc "Initializes the sum with no output pending.".
-spec init([]) -> {ok, ready, #counter{}}.
init([]) -> {ok, ready, #counter{}}.

-doc "Accepts increments up to seven, publishes each accepted sum, and fails otherwise.".
-spec ready(enter, ready, #counter{}) -> hls_statem:enter_result(#counter{});
    (cast, #add{}, #counter{}) -> hls_statem:cast_result(ready, #counter{}).
ready(enter, _, C) ->
    Value = C#counter.value,
    Actions = case C#counter.publish of
        true -> [{cast, result, #total{value = Value}}];
        false -> []
    end,
    {C#counter{publish = false}, Actions};
ready(cast, #add{value = Added}, C) when Added =< 7 ->
    {repeat_phase, C#counter{value = C#counter.value + Added, publish = true}, consume};
ready(cast, #add{}, C) -> {ready, C, fail}.
