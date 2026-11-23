-module(hls_domain_relay).
-moduledoc "Second real source actor in each recovery domain; relays committed counter values.".
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-hls_data(cell).
-hls_phases([idle, publishing]).
-hls_outputs([out]).
-hls_tags([value]).
-hls_mailbox_capacity(2).

%% Source state-machine callbacks.
-export([init/1, idle/3, publishing/3]).

%% Last received value is ordinary source state, reset with the complete domain.
-record(cell, {request = hls_type:zero() :: hls_nums:u32(), value = hls_type:zero() :: hls_nums:u32()}).
-record(value, {request = hls_type:zero() :: hls_nums:u32(), value = hls_type:zero() :: hls_nums:u32()}).

-doc "Starts in a silent entry phase.".
-spec init([]) -> {ok, idle, #cell{}}.
init([]) -> {ok, idle, #cell{}}.

-doc "Consumes the first internal message and enters publication.".
-spec idle(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #value{}, #cell{}) -> hls_statem:cast_result(#cell{}).
idle(enter, _, Cell) -> {Cell, []};
idle(cast, #value{request = Request, value = Value}, Cell) ->
    {publishing, Cell#cell{request = Request, value = Value}, consume}.

-doc "Emits each consumed value once, repeating entry for later internal messages.".
-spec publishing(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #value{}, #cell{}) -> hls_statem:cast_result(#cell{}).
publishing(enter, _, Cell) -> {Cell, [{cast, out, #value{request = Cell#cell.request, value = Cell#cell.value}}]};
publishing(cast, #value{request = Request, value = Value}, Cell) ->
    {repeat_phase, Cell#cell{request = Request, value = Value}, consume}.
