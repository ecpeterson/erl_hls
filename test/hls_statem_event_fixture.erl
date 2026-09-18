-module(hls_statem_event_fixture).
-moduledoc "A short burst emitted by internal steps ahead of a postponed input.".
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, waiting/3, sending/3]).
-hls_data(cell).
-hls_tags([start, later, value]).
-hls_phases([waiting, sending]).
-hls_outputs([out]).
-hls_mailbox_capacity(4).
-hls_continuations([drain]).

%% Iteration arguments and progress live in the application record.
-record(cell, {remaining = hls_type:zero() :: hls_nums:u32(),
    value = hls_type:zero() :: hls_nums:u32()}).
-record(start, {count = hls_type:zero() :: hls_nums:u32()}).
-record(later, {value = hls_type:zero() :: hls_nums:u32()}).
-record(value, {value = hls_type:zero() :: hls_nums:u32()}).

-doc "Starts without work or output.".
-spec init([]) -> {ok, waiting, #cell{}}.
init([]) -> {ok, waiting, #cell{}}.

-doc "Defers early input until a burst has started.".
-spec waiting(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #start{} | #later{}, #cell{}) -> hls_statem:cast_result(#cell{}).
waiting(enter, _, Data) -> {Data, []};
waiting(cast, #later{}, Data) -> {waiting, Data, postpone};
waiting(cast, #start{count = Count}, Data) ->
    {sending, Data#cell{remaining = Count, value = 1}, consume, [{next_event, internal, drain}]}.

-doc "Emits one value per entry, then advances through finite internal steps.".
-spec sending(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #later{}, #cell{}) -> hls_statem:cast_result(#cell{});
    (internal, drain, #cell{}) -> hls_statem:internal_result(#cell{}).
sending(enter, _, Data) -> {Data, [{cast, out, #value{value = Data#cell.value}}]};
sending(internal, drain, Data = #cell{remaining = Remaining}) ->
    case Remaining > 1 of
        true -> {repeat_phase, Data#cell{remaining = Remaining - 1, value = Data#cell.value + 1},
            consume, [{next_event, internal, drain}]};
        false -> {sending, Data#cell{remaining = 0}, consume}
    end;
sending(cast, #later{value = Value}, Data) ->
    {repeat_phase, Data#cell{value = Value}, consume}.
