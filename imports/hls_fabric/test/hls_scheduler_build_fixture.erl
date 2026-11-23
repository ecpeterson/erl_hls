-module(hls_scheduler_build_fixture).
-moduledoc "Two small counter actors for the public scheduler source-build boundary.".
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, ready/3, reported/3, topology/0, topology/1]).
-hls_data(cell).
-hls_phases([ready, reported]).
-hls_outputs([out]).
-hls_tags([work]).
-hls_mailbox_capacity(2).

%% One byte of independent mutable state per logical actor.
-record(cell, {value = hls_type:zero() :: hls_nums:u8()}).
%% Input and output share an ordinary byte-valued frame schema.
-record(work, {value = hls_type:zero() :: hls_nums:u8()}).

-doc "Initializes one empty counter without publishing a message.".
-spec init([]) -> {ok, ready, #cell{}}.
init([]) -> {ok, ready, #cell{}}.

-doc "Accepts the startup value and requests the reporting phase.".
-spec ready(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #work{}, #cell{}) -> hls_statem:cast_result(#cell{}).
ready(enter, _, Cell) -> {Cell, []};
ready(cast, #work{value = Value}, Cell) -> {reported, Cell#cell{value = Value}, consume}.

-doc "Publishes the retained value once on entry and consumes subsequent work messages without repeating entry.".
-spec reported(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #work{}, #cell{}) -> hls_statem:cast_result(#cell{}).
reported(enter, _, Cell) -> {Cell, [{cast, out, #work{value = Cell#cell.value}}]};
reported(cast, #work{}, Cell) -> {reported, Cell, consume}.

-doc "Returns two independent actors with distinct startup values and one external result stream.".
-spec topology() -> map().
topology() -> topology(?MODULE).

-doc "Selects the declared actor module explicitly so source-ownership rejection can be tested before interface loading.".
-spec topology(module()) -> map().
topology(Module) ->
    #{version => 1, actors => #{left => Module, right => Module}, families => #{},
      ingresses => [], route_relations => [], externals => [{monitor, out, [work]}],
      routes => [{{Id, out}, [{external, monitor}]} || Id <- [left, right]],
      startup => [{left, [#work{value = 7}]}, {right, [#work{value = 9}]}]}.
