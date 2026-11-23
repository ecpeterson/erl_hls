-module(hls_statem_reduction_reply_fixture).
-moduledoc "A retained call survives a reduction and completes through a later internal step.".
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, idle/3, collecting/3, ready/3, reduce/3]).
-hls_data(cell).
-hls_phases([idle, collecting, ready]).
-hls_outputs([reply]).
-hls_reply_port(reply).
-hls_mailbox_capacity(4).
-hls_tags([run, value, release, result]).
-hls_pending_calls(1).
-hls_continuations([finish]).
-hls_replies([{run, [result]}]).

-record(cell, {from = hls_type:zero() :: hls_gs:from(), total = hls_type:zero() :: hls_nums:u32()}).
-record(run, {unused = hls_type:zero() :: hls_nums:u32()}).
-record(value, {value = hls_type:zero() :: hls_nums:u32()}).
-record(release, {unused = hls_type:zero() :: hls_nums:u32()}).
-record(result, {value = hls_type:zero() :: hls_nums:u32()}).
-record(sum, {value = hls_type:zero() :: hls_nums:u32()}).

-doc "Starts with no caller or open reduction.".
-spec init([]) -> {ok, idle, #cell{}}.
init([]) -> {ok, idle, #cell{}}.

-doc "Retains the caller and enters a two-contributor reduction.".
-spec idle(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    ({call, hls_gs:from()}, #run{}, #cell{}) -> hls_statem:call_result(#cell{}).
idle(enter, _, Cell) -> {Cell, []};
idle({call, From}, #run{}, Cell) -> {collecting, Cell#cell{from = From}, consume}.

-doc "Sums two inputs before exposing completion to the application.".
-spec collecting(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #value{}, #cell{}) -> hls_statem:cast_result(#cell{});
    (internal, hls_statem:reduction_complete(), #cell{}) -> hls_statem:internal_result(#cell{}).
collecting(enter, _, Cell) ->
    {Cell, [{open_reduction, sum, 0, {count, 2}, {commutative_monoid, #sum{value = 0}}}]};
collecting(cast, #value{value = Value}, Cell) ->
    {collecting, Cell, {contribute, sum, 0, #sum{value = Value}}};
collecting(internal, {reduction_complete, sum, 0, #sum{value = Value}}, Cell) ->
    {ready, Cell#cell{total = Value}, consume}.

-doc "A separate release starts the reply step after reduction completion.".
-spec ready(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #release{}, #cell{}) -> hls_statem:cast_result(#cell{});
    (internal, finish, #cell{}) -> hls_statem:internal_result(#cell{}).
ready(enter, _, Cell) -> {Cell, []};
ready(cast, #release{}, Cell) -> {ready, Cell, consume, [{next_event, internal, finish}]};
ready(internal, finish, Cell) ->
    {idle, Cell, consume, [{reply, Cell#cell.from, #result{value = Cell#cell.total}}]}.

-doc "Combines one bounded contribution with the accumulated sum.".
-spec reduce(sum, #sum{}, #sum{}) -> #sum{}.
reduce(sum, #sum{value = Left}, #sum{value = Right}) -> #sum{value = Left + Right}.
