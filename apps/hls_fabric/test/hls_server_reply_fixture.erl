-module(hls_server_reply_fixture).
-moduledoc "Server callbacks for the same two-caller scheduler workload as hls_statem_reply_fixture.".
-behaviour(hls_gs).
-compile({parse_transform, hls_pack}).
%% Bounded server callbacks; no state-machine phases appear in the source.
-export([init/1, handle_call/3, handle_cast/2, handle_continue/2]).
-hls_data(cell).
-hls_tags([wait, release, read, duplicate, explode, report, wrong]).
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
-spec init([]) -> #cell{}.
init([]) -> #cell{}.

-doc "Retains waits or returns the sum of completed values.".
-spec %% Retain the opaque caller with the value until release.
handle_call(#wait{} | #read{}, hls_gs:from(), #cell{}) -> hls_gs:call_result(#cell{}).
%% Retain the opaque caller with the value until release.
handle_call(#wait{value = Value}, From, Cell = #cell{count = Count}) ->
    {noreply, Cell#cell{count = Count + 1,
        handles = hls_lists:set(Count + 1, Cell#cell.handles, From),
        values = hls_lists:set(Count + 1, Cell#cell.values, Value)}};
%% Reports observe all preceding continuation completions.
handle_call(#read{}, _From, Cell) -> {reply, #report{value = Cell#cell.total}, Cell}.

-doc "Releases the batch or injects stale-handle and reply-contract faults.".
-spec handle_cast(#release{} | #duplicate{} | #explode{}, #cell{}) -> hls_gs:async_result(#cell{}).
%% Empty releases do not enqueue private work.
handle_cast(#release{}, Cell = #cell{count = 0}) -> {noreply, Cell};
%% Drain private work before the next external callback.
handle_cast(#release{}, Cell) -> {noreply, Cell#cell{cursor = 0}, {continue, drain}};
%% A completed handle must not target its replacement.
handle_cast(#duplicate{}, Cell) -> {noreply, Cell, [{reply, Cell#cell.last, #report{value = 999}}]};
%% Invalid reply shape suppresses the proposed data update.
handle_cast(#explode{mode = 1}, Cell) ->
    {noreply, Cell#cell{total = 999}, [{reply, hls_lists:nth(1, Cell#cell.handles), #wrong{}}]};
%% A callback exception retires the affected actor.
handle_cast(#explode{}, Cell) ->
    true = Cell#cell.count =:= 0,
    {noreply, Cell}.

-doc "Completes one caller per continuation before accepting another external request.".
-spec handle_continue(drain, #cell{}) -> hls_gs:async_result(#cell{}).
handle_continue(drain, Cell = #cell{cursor = Cursor, count = Count}) ->
    From = hls_lists:nth(Cursor + 1, Cell#cell.handles),
    Value = hls_lists:nth(Cursor + 1, Cell#cell.values),
    Next = Cell#cell{cursor = Cursor + 1, last = From, total = Cell#cell.total + Value},
    case Cursor + 1 =:= Count of
        true -> {noreply, Next#cell{count = 0}, [{reply, From, #report{value = Value}}]};
        false -> {noreply, Next, [{reply, From, #report{value = Value}}, {continue, drain}]}
    end.
