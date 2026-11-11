-module(hls_protocol_call_sender_fixture).
-moduledoc "A genuine ordinary entry send used to reject an internal cast into a call schema.".
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
%% Source actor callbacks.
-export([init/1, ready/3]).
-hls_data(cell).
-hls_tags([read]).
-hls_phases([ready]).
-hls_outputs([out]).
-hls_mailbox_capacity(1).

%% This producer has no caller book or transaction ownership.
-record(cell, {unused = hls_type:zero() :: hls_nums:u8()}).
%% Exactly the receiving call's record layout, but sent by an ordinary cast.
-record(read, {unused = hls_type:zero() :: hls_nums:u8()}).

-doc "Initializes one producer with a pending entry publication.".
-spec init([]) -> {ok, ready, #cell{}}.
init([]) -> {ok, ready, #cell{}}.

-doc "Publishes an ordinary cast; its destination determines why the topology rejects.".
-spec ready(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #read{}, #cell{}) -> hls_statem:cast_result(#cell{}).
ready(enter, _, Cell) -> {Cell, [{cast, out, #read{}}]};
ready(cast, #read{}, Cell) -> {ready, Cell, consume}.
