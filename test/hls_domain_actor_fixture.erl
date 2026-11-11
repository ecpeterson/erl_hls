-module(hls_domain_actor_fixture).
-moduledoc "Finite source actor for domain replacement: forwarding, retained calls and entry failure.".
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, ready/3]).
-hls_data(cell).
-hls_phases([ready]).
-hls_mailbox_capacity(4).
-hls_outputs([out, reply]).
-hls_reply_port(reply).
-hls_pending_calls(1).
-hls_replies([{get, [readout]}, {hold, [readout]}]).
-hls_tags([add, forward, explode, get, hold, release, readout]).
-record(cell, {value = hls_type:zero() :: hls_nums:u32(),
    pending = hls_type:zero() :: hls_nums:u32(),
    emit = hls_type:zero() :: hls_bool:bool(), bad_entry = hls_type:zero() :: hls_bool:bool(),
    held = hls_type:zero() :: hls_gs:from()}).
-record(add, {value = hls_type:zero() :: hls_nums:u32()}).
-record(forward, {value = hls_type:zero() :: hls_nums:u32()}).
-record(explode, {mode = hls_type:zero() :: hls_nums:u32()}).
-record(get, {unused = hls_type:zero() :: hls_nums:u32()}).
-record(hold, {unused = hls_type:zero() :: hls_nums:u32()}).
-record(release, {unused = hls_type:zero() :: hls_nums:u32()}).
-record(readout, {value = hls_type:zero() :: hls_nums:u32()}).

-doc "Starts silently, with no retained caller or external effect.".
-spec init([]) -> {ok, ready, #cell{}}.
init([]) -> {ok, ready, #cell{}}.

-doc "Forwards on explicit reentry, retains a call until release, and can fail after computing entry effects.".
-spec ready(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #add{} | #forward{} | #explode{} | #release{}, #cell{}) -> hls_statem:cast_result(#cell{});
    ({call, hls_gs:from()}, #get{} | #hold{}, #cell{}) -> hls_statem:call_result(#cell{}).
ready(enter, _, Cell) ->
    Actions = case Cell#cell.emit of
        true -> [{cast, out, #add{value = Cell#cell.pending}}];
        false -> []
    end,
    true = not Cell#cell.bad_entry,
    {Cell#cell{emit = false}, Actions};
ready(cast, #add{value = Value}, Cell) ->
    {ready, Cell#cell{value = Cell#cell.value + Value}, consume};
ready(cast, #forward{value = Value}, Cell) ->
    {repeat_phase, Cell#cell{emit = true, pending = Value}, consume};
ready(cast, #explode{mode = 1}, Cell) ->
    {repeat_phase, Cell#cell{emit = true, pending = 999, bad_entry = true}, consume};
ready(cast, #explode{}, Cell) ->
    {ready, Cell, fail};
ready({call, From}, #get{}, Cell) ->
    {ready, Cell, consume, [{reply, From, #readout{value = Cell#cell.value}}]};
ready({call, From}, #hold{}, Cell) ->
    {ready, Cell#cell{held = From}, consume};
ready(cast, #release{}, Cell) ->
    {ready, Cell, consume, [{reply, Cell#cell.held, #readout{value = Cell#cell.value}}]}.
