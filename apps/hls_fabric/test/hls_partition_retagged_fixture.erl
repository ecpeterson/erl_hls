-module(hls_partition_retagged_fixture).
-behavior(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, waiting/3]).
-hls_data(state).
-hls_phases([waiting]).
-hls_outputs([out]).
-hls_mailbox_capacity(2).
-hls_tags([padding, work]).
-record(padding, {value = hls_type:zero() :: hls_nums:u32()}).
-record(work, {value = hls_type:zero() :: hls_nums:u32()}).
-record(state, {value = hls_type:zero() :: hls_nums:u32()}).

init([]) -> {ok, waiting, #state{}}.
waiting(enter, _, State) -> {State, [{cast, out, #work{value = State#state.value}}]};
waiting(cast, #work{value = Value}, State) -> {waiting, State#state{value = Value}, consume}.
