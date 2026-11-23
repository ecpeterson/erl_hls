-module(hls_partition_fixture).
-behavior(hls_statem).
-compile({parse_transform, hls_pack}).
-hls_data(state).
-hls_phases([waiting, sending]).
-hls_outputs([left, right, report]).
-hls_tags([work]).
-hls_mailbox_capacity(2).
-export([init/1, waiting/3, sending/3]).

-record(work, {value = hls_type:zero() :: hls_nums:u32()}).
-record(state, {value = hls_type:zero() :: hls_nums:u32()}).

init([]) -> {ok, waiting, #state{}}.

waiting(enter, _Old, State) -> {State, []};
waiting(cast, #work{value = Value}, State) -> {sending, State#state{value = Value}, consume}.

sending(enter, _Old, State) ->
    Value = State#state.value,
    {State, [{cast, left, #work{value = Value}},
        {cast, right, #work{value = Value}}, {cast, report, #work{value = Value}}]};
sending(cast, #work{value = Value}, State) -> {waiting, State#state{value = Value}, consume}.
