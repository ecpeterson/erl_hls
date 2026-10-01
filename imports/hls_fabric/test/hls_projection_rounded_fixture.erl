-module(hls_projection_rounded_fixture).
-moduledoc "State-projection witness whose legal float32 startup value rounds on the wire.".
-behavior(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, boot/3, ready/3]).
-hls_data(cell).
-hls_phases([boot, ready]).
-hls_outputs([out]).
-hls_mailbox_capacity(1).
-hls_tags([configure]).

%% Float32 accepts host doubles even when the wire representation rounds them.
-record(configure, {value = hls_type:zero() :: hls_nums:float32()}).
%% The integer marker is independently eligible for omission.
-record(cell, {value = hls_type:zero() :: hls_nums:float32(), marker = hls_type:zero() :: hls_nums:u8()}).

-doc "Starts with zero data and a fixed marker.".
-spec init([]) -> {ok, boot, #cell{}}.
init([]) -> {ok, boot, #cell{marker = 7}}.

-doc "Accepts one startup value without changing the marker.".
-spec boot(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #configure{}, #cell{}) -> hls_statem:cast_result(#cell{}).
boot(enter, _, Cell) -> {Cell, []};
boot(cast, #configure{value = Value}, Cell) -> {ready, Cell#cell{value = Value}, consume}.

-doc "Retains the configured value and fails on any second configuration.".
-spec ready(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #configure{}, #cell{}) -> hls_statem:cast_result(#cell{}).
ready(enter, _, Cell) -> {Cell, []};
ready(cast, #configure{}, Cell) -> {ready, Cell, fail}.
