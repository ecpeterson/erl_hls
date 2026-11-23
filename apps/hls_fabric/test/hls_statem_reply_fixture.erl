-module(hls_statem_reply_fixture).
-moduledoc "Two retained callers drained by named state-machine internal events.".
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, waiting/3, draining/3]).
-hls_data(cell).
-hls_tags([wait, release, read, duplicate, explode, report, wrong]).
-hls_phases([waiting, draining]).
-hls_outputs([reply]).
-hls_reply_port(reply).
-hls_mailbox_capacity(4).
-hls_pending_calls(2).
-hls_continuations([drain]).
-hls_replies([{wait, [report]}, {read, [report]}]).

%% The application decides which handles and per-call values it retains.
-record(cell, {handles = hls_type:zero() :: hls_lists:list(hls_gs:from(), 2),
    values = hls_type:zero() :: hls_lists:list(hls_nums:u32(), 2),
    count = hls_type:zero() :: hls_nums:u32(), cursor = hls_type:zero() :: hls_nums:u32(),
    last = hls_type:zero() :: hls_gs:from(), total = hls_type:zero() :: hls_nums:u32()}).
-record(wait, {value = hls_type:zero() :: hls_nums:u32()}).
-record(release, {unused = hls_type:zero() :: hls_nums:u32()}).
-record(read, {unused = hls_type:zero() :: hls_nums:u32()}).
-record(duplicate, {unused = hls_type:zero() :: hls_nums:u32()}).
-record(explode, {mode = hls_type:zero() :: hls_nums:u32()}).
-record(report, {value = hls_type:zero() :: hls_nums:u32()}).
-record(wrong, {unused = hls_type:zero() :: hls_nums:u32()}).

-doc "Starts with an empty retained batch.".
-spec init([]) -> {ok, waiting, #cell{}}.
init([]) -> {ok, waiting, #cell{}}.

-doc "Retains calls until release; diagnostics and stale-handle probes share the reply path.".
-spec waiting(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    ({call, hls_gs:from()}, #wait{} | #read{}, #cell{}) -> hls_statem:call_result(#cell{});
    (cast, #release{} | #duplicate{} | #explode{}, #cell{}) -> hls_statem:cast_result(#cell{}).
waiting(enter, _, Cell) -> {Cell, []};
waiting({call, From}, #wait{value = Value}, Cell = #cell{count = Count}) ->
    {waiting, Cell#cell{count = Count + 1,
        handles = hls_lists:set(Count + 1, Cell#cell.handles, From),
        values = hls_lists:set(Count + 1, Cell#cell.values, Value)}, consume};
waiting({call, From}, #read{}, Cell) ->
    {waiting, Cell, consume, [{reply, From, #report{value = Cell#cell.total}}]};
waiting(cast, #release{}, Cell = #cell{count = 0}) -> {waiting, Cell, consume};
waiting(cast, #release{}, Cell) ->
    {draining, Cell#cell{cursor = 0}, consume, [{next_event, internal, drain}]};
waiting(cast, #duplicate{}, Cell) ->
    {waiting, Cell, consume, [{reply, Cell#cell.last, #report{value = 999}}]};
waiting(cast, #explode{mode = 1}, Cell) ->
    {waiting, Cell#cell{total = 999}, consume, [{reply, hls_lists:nth(1, Cell#cell.handles), #wrong{}}]};
waiting(cast, #explode{}, Cell) ->
    true = Cell#cell.count =:= 0,
    {waiting, Cell, consume}.

-doc "Completes one caller per internal event, then returns to accepting a fresh batch.".
-spec draining(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (internal, drain, #cell{}) -> hls_statem:internal_result(#cell{}).
draining(enter, _, Cell) -> {Cell, []};
draining(internal, drain, Cell = #cell{cursor = Cursor, count = Count}) ->
    From = hls_lists:nth(Cursor + 1, Cell#cell.handles),
    Value = hls_lists:nth(Cursor + 1, Cell#cell.values),
    Next = Cell#cell{cursor = Cursor + 1, last = From, total = Cell#cell.total + Value},
    case Cursor + 1 =:= Count of
        true -> {waiting, Next#cell{count = 0}, consume, [{reply, From, #report{value = Value}}]};
        false -> {draining, Next, consume, [{reply, From, #report{value = Value}}, {next_event, internal, drain}]}
    end.
