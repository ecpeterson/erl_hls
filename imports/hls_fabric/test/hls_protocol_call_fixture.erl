-module(hls_protocol_call_fixture).
-moduledoc "Minimal bounded synchronous reply source for local protocol ownership and framing.".
-behaviour(hls_gs).
-compile({parse_transform, hls_pack}).
%% Source actor callbacks.
-export([init/1, handle_call/2, handle_cast/2]).
%% Exact positive and rejected reply-route fixtures.
-export([topology/0, internal_reply/0, internal_call/0]).
-hls_data(cell).
-hls_tags([read, report]).
-hls_mailbox_capacity(2).
-hls_replies([{read, [report]}]).

%% Ordinary actor state remains independent of caller ownership.
-record(cell, {value = hls_type:zero() :: hls_nums:u8()}).
%% The request has a real field so the test does not depend on empty-record encoding.
-record(read, {unused = hls_type:zero() :: hls_nums:u8()}).
%% The reply carries the current local value.
-record(report, {value = hls_type:zero() :: hls_nums:u8()}).

-doc "Initializes an immediate server without a retained caller table.".
-spec init([]) -> #cell{}.
init([]) -> #cell{}.

-doc "Returns the current local value to the implicit caller.".
-spec handle_call(#read{}, #cell{}) -> {reply, #report{}, #cell{}}.
handle_call(#read{}, Cell) -> {reply, #report{value = Cell#cell.value}, Cell}.

-doc "Accepts a report as a no-op cast for routing admission checks.".
-spec handle_cast(#report{}, #cell{}) -> {noreply, #cell{}}.
handle_cast(#report{}, Cell) -> {noreply, Cell}.

-doc "Binds a host call to one actor and a dedicated external reply stream.".
-spec topology() -> map().
topology() ->
    #{version => 1, actors => #{cell => ?MODULE}, families => #{}, route_relations => [],
        startup => [], ingresses => [{host, {rectangle, [1, 1]},
            [{cell, [read], [{actor, cell, {at, [0, 0]}}]}]}],
        externals => [{replies, out, [report]}],
        routes => [{{cell, reply}, [{external, replies}]}]}.

-doc "Rejects an internal reply route instead of interpreting its dynamic caller as a cast.".
-spec internal_reply() -> map().
internal_reply() ->
    (topology())#{routes := [{{cell, reply}, [{actor, cell}]}]}.

-doc "Rejects a cast into a retained-call schema rather than fabricating a host transaction.".
-spec internal_call() -> map().
internal_call() ->
    T = #{routes := Routes, actors := Actors} = topology(),
    T#{actors := Actors#{sender => hls_protocol_call_sender_fixture},
        routes := [{{sender, out}, [{actor, cell}]} | Routes]}.
