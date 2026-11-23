-module(hls_large_mailbox_fixture).
-moduledoc "A direct actor used to check oldest-first selection in large mailboxes.".
-behavior(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, ready/3]).
-hls_data(cell).
-hls_phases([ready]).
-hls_outputs([out]).
-hls_mailbox_capacity(64).
-hls_tags([value]).

%% Zero distinguishes no dispatch from the one-based identities in the test.
-record(cell, {selected = hls_type:zero() :: hls_nums:u8()}).
%% Each occupied slot carries its identity as an ordinary input message.
-record(value, {index = hls_type:zero() :: hls_nums:u8()}).

-doc "Starts ready to consume messages, without an earlier selected value.".
-spec init([]) -> {ok, ready, #cell{}}.
init([]) -> {ok, ready, #cell{}}.

-doc "Consumes one eligible message and remembers its identity.".
-spec ready(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #value{}, #cell{}) -> hls_statem:cast_result(ready, #cell{}).
ready(enter, _Old, Cell) -> {Cell, []};
%% Selection is performed by the normal direct-actor mailbox before this callback.
ready(cast, #value{index = Index}, Cell) ->
    {ready, Cell#cell{selected = Index}, consume}.
