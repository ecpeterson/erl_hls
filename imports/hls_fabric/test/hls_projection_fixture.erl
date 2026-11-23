-module(hls_projection_fixture).
-moduledoc "State-specialization witness with signed, unaligned configuration and changing payloads.".
-behavior(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, boot/3, ready/3]).
-hls_data(cell).
-hls_phases([boot, ready]).
-hls_outputs([out]).
-hls_mailbox_capacity(3).
-hls_tags([configure, put]).

%% The odd widths expose byte-order and field-boundary mistakes.
-record(configure, {id = hls_type:zero() :: hls_nums:uN(13),
    bias = hls_type:zero() :: hls_nums:sN(11)}).
%% Ordinary traffic has no authority to change configuration.
-record(put, {value = hls_type:zero() :: hls_nums:uN(7)}).
%% Mutable payload is deliberately between the two configuration fields.
-record(cell, {id = hls_type:zero() :: hls_nums:uN(13),
    value = hls_type:zero() :: hls_nums:uN(7),
    bias = hls_type:zero() :: hls_nums:sN(11)}).

-doc "Starts with zero configuration before the startup message arrives.".
-spec init([]) -> {ok, boot, #cell{}}.
init([]) -> {ok, boot, #cell{}}.

-doc "Accepts one configuration and enters the working phase.".
-spec boot(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #configure{} | #put{}, #cell{}) -> hls_statem:cast_result(#cell{}).
boot(enter, _, C) -> {C, []};
boot(cast, #configure{id=Id, bias=Bias}, C) -> {ready, C#cell{id=Id, bias=Bias}, consume};
boot(cast, #put{}, C) -> {boot, C, postpone}.

-doc "Updates and publishes the payload while retaining the configured identity and bias.".
-spec ready(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #configure{} | #put{}, #cell{}) -> hls_statem:cast_result(#cell{}).
ready(enter, _, C) -> {C, [{cast, out, #put{value=C#cell.value}}]};
ready(cast, #put{value=V}, C) -> {ready, C#cell{value=V}, consume};
ready(cast, #configure{}, C) -> {ready, C, fail}.
