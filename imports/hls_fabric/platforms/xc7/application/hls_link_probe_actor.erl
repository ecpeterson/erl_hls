-module(hls_link_probe_actor).
-moduledoc "Typed request/reply actor for the two-board PL-link acceptance fixture.".
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).

-export([init/1, ready/3, launching/3, responding/3, confirming/3]).

-hls_data(cell).
-hls_tags([launch, request, reply, observed]).
-hls_phases([ready, launching, responding, confirming]).
-hls_outputs([peer, report]).
-hls_mailbox_capacity(4).
-hls_continuations([complete]).

-record(cell, {
    nonce = hls_type:zero() :: hls_nums:u32()
}).
-record(launch, {
    nonce = hls_type:zero() :: hls_nums:u32()
}).
-record(request, {
    nonce = hls_type:zero() :: hls_nums:u32()
}).
-record(reply, {
    nonce = hls_type:zero() :: hls_nums:u32()
}).
-record(observed, {
    nonce = hls_type:zero() :: hls_nums:u32(),
    stage = hls_type:zero() :: hls_nums:u32()
}).

-doc "Starts ready to accept either a host launch or one peer message.".
-spec init([]) -> {ok, ready, #cell{}}.
init([]) -> {ok, ready, #cell{}}.

-doc "Classifies one typed input and schedules its bounded output phase.".
-spec ready(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #launch{} | #request{} | #reply{}, #cell{}) -> hls_statem:cast_result(#cell{}).
ready(enter, _Old, Cell) -> {Cell, []};
ready(cast, #launch{nonce = Nonce}, Cell) ->
    {launching, Cell#cell{nonce = Nonce}, consume, [{next_event, internal, complete}]};
ready(cast, #request{nonce = Nonce}, Cell) ->
    {responding, Cell#cell{nonce = Nonce}, consume, [{next_event, internal, complete}]};
ready(cast, #reply{nonce = Nonce}, Cell) ->
    {confirming, Cell#cell{nonce = Nonce}, consume, [{next_event, internal, complete}]}.

-doc "Emits the request and local stage-one observation before accepting new input.".
-spec launching(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (internal, complete, #cell{}) -> hls_statem:internal_result(#cell{}).
launching(enter, _Old, Cell) ->
    Nonce = Cell#cell.nonce,
    {Cell, [{cast, peer, #request{nonce = Nonce}},
        {cast, report, #observed{nonce = Nonce, stage = 1}}]};
launching(internal, complete, Cell) -> {ready, Cell, consume}.

-doc "Emits the reply and local stage-two observation before accepting new input.".
-spec responding(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (internal, complete, #cell{}) -> hls_statem:internal_result(#cell{}).
responding(enter, _Old, Cell) ->
    Nonce = Cell#cell.nonce,
    {Cell, [{cast, peer, #reply{nonce = Nonce}},
        {cast, report, #observed{nonce = Nonce, stage = 2}}]};
responding(internal, complete, Cell) -> {ready, Cell, consume}.

-doc "Publishes local stage three only after the remote reply reaches this actor.".
-spec confirming(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (internal, complete, #cell{}) -> hls_statem:internal_result(#cell{}).
confirming(enter, _Old, Cell) ->
    Nonce = Cell#cell.nonce,
    {Cell, [{cast, report, #observed{nonce = Nonce, stage = 3}}]};
confirming(internal, complete, Cell) -> {ready, Cell, consume}.
