-module(xls_actor_outbox_fixture).
-moduledoc "A stateful three-effect callback for independent-outbox progress tests.".
-behavior(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, idle/3, reporting/3]).
-hls_data(counter).
-hls_phases([idle, reporting]).
-hls_outputs([first, second, third]).
-hls_mailbox_capacity(2).
-hls_tags([add, report]).
-record(add, {value = hls_type:zero() :: hls_nums:u32()}).
-record(report, {value = hls_type:zero() :: hls_nums:u32(), part = hls_type:zero() :: hls_nums:u32()}).
-record(counter, {value = hls_type:zero() :: hls_nums:u32()}).

-doc "Starts with an empty counter and no output.".
-spec init([]) -> {ok, idle, #counter{}}.
init([]) -> {ok, idle, #counter{}}.

-doc "Adds the first command and schedules its ordered report batch.".
-spec idle(enter | cast, atom() | #add{}, #counter{}) -> {#counter{}, []} | {reporting, #counter{}, consume}.
%% Initial entry has no effects; its reservation must be released automatically.
idle(enter, _Old, State) -> {State, []};
%% A command changes phase and must be visible to the following entry.
idle(cast, #add{value = Value}, State) ->
    {reporting, State#counter{value = State#counter.value + Value}, consume}.

-doc "Reports three ordered parts per update; each command accumulates into the counter.".
-spec reporting(enter | cast, atom() | #add{}, #counter{}) -> {#counter{}, [{cast, first | second | third, #report{}}]} | {repeat_phase, #counter{}, consume}.
%% All three parts must survive a stall in the middle of the batch.
reporting(enter, _Old, State) ->
    {State, [{cast, first, #report{value = State#counter.value, part = 0}},
             {cast, second, #report{value = State#counter.value, part = 1}},
             {cast, third, #report{value = State#counter.value, part = 2}}]};
%% Re-enter the same phase after committing the updated state.
reporting(cast, #add{value = Value}, State) ->
    {repeat_phase, State#counter{value = State#counter.value + Value}, consume}.
