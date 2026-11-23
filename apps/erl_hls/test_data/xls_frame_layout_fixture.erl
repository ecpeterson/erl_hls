-module(xls_frame_layout_fixture).
-moduledoc "A four-word emitted schema exercises selected ordinary frame capacities.".
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-hls_data(cell).
-hls_phases([idle]).
-hls_outputs([out]).
-hls_mailbox_capacity(1).
-hls_tags([message]).
-export([init/1, idle/3]).

%% Actor state stays small while its public message exceeds the default capacity.
-record(cell, {value = hls_type:zero() :: hls_nums:u8()}).
%% Both words retain their exact provider stream order in emitted frames.
-record(message, {left = hls_type:zero() :: hls_nums:u64(),
    right = hls_type:zero() :: hls_nums:u64()}).

-doc "Starts the witness actor with zero state.".
-spec init([]) -> {ok, idle, #cell{}}.
init([]) -> {ok, idle, #cell{}}.

-doc "Emits a complete four-word message on entry and consumes matching input messages.".
-spec idle(enter, idle, #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #message{}, #cell{}) -> hls_statem:cast_result(idle, #cell{}).
idle(enter, _, Cell) -> {Cell, [{cast, out, #message{left = 1, right = 2}}]};
idle(cast, #message{}, Cell) -> {idle, Cell, consume}.
