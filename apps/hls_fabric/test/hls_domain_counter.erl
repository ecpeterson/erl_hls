-module(hls_domain_counter).
-moduledoc "Source recovery witness: persistent counter, silent initialization and a terminal callback fault.".
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-hls_data(cell).
-hls_phases([idle, publishing]).
-hls_outputs([out]).
-hls_tags([add, read, explode, value]).
-hls_mailbox_capacity(4).

%% Source callbacks and closed static topology used by the RTL witness.
-export([init/1, idle/3, publishing/3, topology/0]).

%% One committed value; failed callbacks must not publish their proposed replacement.
-record(cell, {request = hls_type:zero() :: hls_nums:u32(), total = hls_type:zero() :: hls_nums:u32()}).
%% All public commands have two words, including diagnostics with no data argument.
-record(add, {request = hls_type:zero() :: hls_nums:u32(), value = hls_type:zero() :: hls_nums:u32()}).
-record(read, {request = hls_type:zero() :: hls_nums:u32(), unused = hls_type:zero() :: hls_nums:u32()}).
-record(explode, {request = hls_type:zero() :: hls_nums:u32(), unused = hls_type:zero() :: hls_nums:u32()}).
-record(value, {request = hls_type:zero() :: hls_nums:u32(), value = hls_type:zero() :: hls_nums:u32()}).

-ifndef(DOMAIN_BAD_INITIALIZATION).
-define(INITIAL_VALUE, 0).
-else.
-define(INITIAL_VALUE, 1).
-endif.

-doc "Sets a compile-time source initial value; the negative fixture fails in entry, after reset.".
-spec init([]) -> {ok, idle, #cell{}}.
init([]) -> {ok, idle, #cell{total = ?INITIAL_VALUE}}.

-doc "Initial entry is silent and checked; commands update, read, or fail through ordinary source callbacks.".
-spec idle(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #add{} | #read{} | #explode{}, #cell{}) -> hls_statem:cast_result(#cell{}).
idle(enter, _, Cell) ->
    true = Cell#cell.total =:= 0,
    {Cell, []};
idle(cast, #add{request = Request, value = Value}, Cell) ->
    {publishing, Cell#cell{request = Request, total = Cell#cell.total + Value}, consume};
idle(cast, #read{request = Request}, Cell) -> {publishing, Cell#cell{request = Request}, consume};
idle(cast, #explode{}, Cell) ->
    false = Cell#cell.total =:= 0,
    {publishing, Cell#cell{total = 999}, consume}.

-doc "Publishes through the actual internal link; subsequent requests repeat the source entry.".
-spec publishing(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #add{} | #read{} | #explode{}, #cell{}) -> hls_statem:cast_result(#cell{}).
publishing(enter, _, Cell) -> {Cell, [{cast, out, #value{request = Cell#cell.request, value = Cell#cell.total}}]};
publishing(cast, #add{request = Request, value = Value}, Cell) ->
    {repeat_phase, Cell#cell{request = Request, total = Cell#cell.total + Value}, consume};
publishing(cast, #read{request = Request}, Cell) -> {repeat_phase, Cell#cell{request = Request}, consume};
publishing(cast, #explode{}, Cell) ->
    true = Cell#cell.total =:= 0,
    {repeat_phase, Cell#cell{total = 999}, consume}.

-doc "Connects the counter to an independently compiled relay, with one host ingress and one result stream.".
-spec topology() -> map().
topology() ->
    #{version => 1, actors => #{counter => ?MODULE, relay => hls_domain_relay},
      families => #{}, startup => [], route_relations => [],
      ingresses => [{commands, {rectangle, [1, 1]},
          [{all, [add, read, explode], [{actor, counter, {at, [0, 0]}}]}]}],
      externals => [{reports, out, [value]}],
      routes => [{{counter, out}, [{actor, relay}]},
          {{relay, out}, [{external, reports}]}]}.
