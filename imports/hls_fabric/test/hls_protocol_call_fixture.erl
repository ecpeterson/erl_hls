-module(hls_protocol_call_fixture).
-moduledoc "Minimal synchronous reply source rejected by the local protocol owner.".
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, ready/3]).
-hls_data(cell).
-hls_tags([read, report]).
-hls_phases([ready]).
-hls_outputs([reply]).
-hls_reply_port(reply).
-hls_mailbox_capacity(2).
-hls_pending_calls(1).
-hls_replies([{read, [report]}]).

%% Ordinary actor state remains independent of caller ownership.
-record(cell, {value = hls_type:zero() :: hls_nums:u8()}).
%% The request has a real field so the test does not depend on empty-record encoding.
-record(read, {unused = hls_type:zero() :: hls_nums:u8()}).
%% The reply carries the current local value.
-record(report, {value = hls_type:zero() :: hls_nums:u8()}).

-doc "Initializes the reply-capable source without pending work.".
-spec init([]) -> {ok, ready, #cell{}}.
init([]) -> {ok, ready, #cell{}}.

-doc "Replies immediately to the supplied caller; no ordinary actor publication is needed.".
-spec ready(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    ({call, hls_gs:from()}, #read{}, #cell{}) -> hls_statem:call_result(#cell{}).
ready(enter, _, Cell) -> {Cell, []};
ready({call, From}, #read{}, Cell) ->
    {ready, Cell, consume, [{reply, From, #report{value = Cell#cell.value}}]}.
