-module(hls_projection_wide_fixture).
-moduledoc "State-specialization fixture whose configuration exceeds the default ordinary frame.".
-behavior(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, boot/3, ready/3]).
-hls_data(cell).
-hls_phases([boot, ready]).
-hls_outputs([out]).
-hls_mailbox_capacity(1).
-hls_tags([configure, put]).

%% Configuration needs four transport words while ordinary updates need one.
-record(configure, {id = hls_type:zero() :: hls_nums:uN(97)}).
%% Mutable traffic cannot alter the configured identity.
-record(put, {value = hls_type:zero() :: hls_nums:uN(1)}).
%% The constant identity and changing payload must retain distinct projections.
-record(cell, {id = hls_type:zero() :: hls_nums:uN(97),
    value = hls_type:zero() :: hls_nums:uN(1)}).

-doc "Starts before the wide startup configuration is consumed.".
-spec init([]) -> {ok, boot, #cell{}}.
init([]) -> {ok, boot, #cell{}}.

-doc "Consumes one wide configuration and postpones earlier updates.".
-spec boot(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #configure{} | #put{}, #cell{}) -> hls_statem:cast_result(#cell{}).
boot(enter, _, C) -> {C, []};
boot(cast, #configure{id = Id}, C) -> {ready, C#cell{id = Id}, consume};
boot(cast, #put{}, C) -> {boot, C, postpone}.

-doc "Publishes and updates the mutable bit without changing configuration.".
-spec ready(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #configure{} | #put{}, #cell{}) -> hls_statem:cast_result(#cell{}).
ready(enter, _, C) -> {C, [{cast, out, #put{value = C#cell.value}}]};
ready(cast, #put{value = Value}, C) -> {ready, C#cell{value = Value}, consume};
ready(cast, #configure{}, C) -> {ready, C, fail}.
