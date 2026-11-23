-module(hls_cross_domain_producer).
-moduledoc "Source producer for the cross-domain retirement witness. Private source continuations publish an ordered item/open/item sequence through one peer route; readouts expose committed burst count.".
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-hls_data(cell).
-hls_phases([idle, first, opening, publishing, reporting]).
-hls_continuations([advance]).
-hls_outputs([peer, out]).
-hls_tags([burst, read, item, open, produced]).
-hls_mailbox_capacity(4).

%% Source state-machine callbacks.
-export([init/1, idle/3, first/3, opening/3, publishing/3, reporting/3]).
%% Shared topology used by all three separately lowered actor roles.
-export([topology/0]).

%% Request/value belong to the current publication; count survives until replacement.
-record(cell, {request = hls_type:zero() :: hls_nums:u32(),
    value = hls_type:zero() :: hls_nums:u32(), count = hls_type:zero() :: hls_nums:u32()}).
%% Host triggers and readouts share two-word command shapes.
-record(burst, {request = hls_type:zero() :: hls_nums:u32(), value = hls_type:zero() :: hls_nums:u32()}).
-record(read, {request = hls_type:zero() :: hls_nums:u32(), unused = hls_type:zero() :: hls_nums:u32()}).
%% Distinct classes let the receiver postpone an item while accepting its later open.
-record(item, {request = hls_type:zero() :: hls_nums:u32(), value = hls_type:zero() :: hls_nums:u32()}).
-record(open, {request = hls_type:zero() :: hls_nums:u32(), unused = hls_type:zero() :: hls_nums:u32()}).
-record(produced, {request = hls_type:zero() :: hls_nums:u32(), count = hls_type:zero() :: hls_nums:u32()}).

-doc "Initializes silently; no cross-domain publication occurs before admission.".
-spec init([]) -> {ok, idle, #cell{}}.
init([]) -> {ok, idle, #cell{}}.

-doc "Accepts a bounded burst or reads the burst count without creating peer traffic.".
-spec idle(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #burst{} | #read{}, #cell{}) -> hls_statem:cast_result(#cell{}).
idle(enter, _, Cell) -> {Cell, []};
idle(cast, #burst{request = Request, value = Value}, Cell) ->
    {first, Cell#cell{request = Request, value = Value, count = Cell#cell.count + 1}, consume,
        [{next_event, internal, advance}]};
idle(cast, #read{request = Request}, Cell) -> {reporting, Cell#cell{request = Request}, consume}.

-doc "Publishes the first item, then advances privately after its entry has completed.".
-spec first(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (internal, advance, #cell{}) -> hls_statem:internal_result(#cell{}).
first(enter, _, Cell) ->
    {Cell, [{cast, peer, #item{request = Cell#cell.request, value = Cell#cell.value}}]};
first(internal, advance, Cell) ->
    {opening, Cell, consume, [{next_event, internal, advance}]}.

-doc "Publishes the opening class on the same peer route, then advances to the second item.".
-spec opening(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (internal, advance, #cell{}) -> hls_statem:internal_result(#cell{}).
opening(enter, _, Cell) -> {Cell, [{cast, peer, #open{request = Cell#cell.request}}]};
opening(internal, advance, Cell) -> {publishing, Cell, consume}.

-doc "Publishes the second item after the two previous source entries, then accepts later commands.".
-spec publishing(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #burst{} | #read{}, #cell{}) -> hls_statem:cast_result(#cell{}).
publishing(enter, _, Cell) ->
    {Cell, [{cast, peer, #item{request = Cell#cell.request + 1, value = Cell#cell.value + 1}}]};
publishing(cast, #burst{request = Request, value = Value}, Cell) ->
    {first, Cell#cell{request = Request, value = Value, count = Cell#cell.count + 1}, consume,
        [{next_event, internal, advance}]};
publishing(cast, #read{request = Request}, Cell) -> {reporting, Cell#cell{request = Request}, consume}.

-doc "Reports committed burst count without changing peer state; later bursts use the same outbox.".
-spec reporting(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #burst{} | #read{}, #cell{}) -> hls_statem:cast_result(#cell{}).
reporting(enter, _, Cell) ->
    {Cell, [{cast, out, #produced{request = Cell#cell.request, count = Cell#cell.count}}]};
reporting(cast, #burst{request = Request, value = Value}, Cell) ->
    {first, Cell#cell{request = Request, value = Value, count = Cell#cell.count + 1}, consume,
        [{next_event, internal, advance}]};
reporting(cast, #read{request = Request}, Cell) -> {repeat_phase, Cell#cell{request = Request}, consume}.

-doc "Declares A to B and independent C with silent startup, rectangle host commands and distinct external reports.".
-spec topology() -> map().
topology() ->
    #{version => 1, actors => #{a => ?MODULE, b => hls_cross_domain_consumer, c => hls_domain_counter},
      families => #{}, startup => [], route_relations => [],
      ingresses => [{commands, {rectangle, [3, 1]}, [
          {producer, [burst, read], [{actor, a, {at, [0, 0]}}]},
          {consumer, [read, explode], [{actor, b, {at, [1, 0]}}]},
          {counter, [add, read, explode], [{actor, c, {at, [2, 0]}}]}]}],
      externals => [{producer_reports, out, [produced]},
          {consumer_reports, out, [received]}, {counter_reports, out, [value]}],
      routes => [{{a, peer}, [{actor, b}]}, {{a, out}, [{external, producer_reports}]},
          {{b, out}, [{external, consumer_reports}]}, {{c, out}, [{external, counter_reports}]}]}.
