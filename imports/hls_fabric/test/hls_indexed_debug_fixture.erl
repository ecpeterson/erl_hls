-module(hls_indexed_debug_fixture).
-moduledoc "A partial indexed gather and a provisional successor behind a stalled report sink.".
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-hls_data(cell).
-hls_phases([collecting, reporting]).
-hls_outputs([out_a, out_b, out_c, out_d]).
-hls_mailbox_capacity(4).
-hls_tags([piece, report]).
-export([init/1, collecting/3, reporting/3]).

%% Callback state retains only the epoch and the consumed scalar result.
-record(cell, {epoch = hls_type:zero() :: hls_nums:u32(), result = hls_type:zero() :: hls_nums:u8()}).
%% Contributions carry a source key, stable member index and one private element.
-record(piece, {key = hls_type:zero() :: hls_nums:u32(),
    member = hls_type:zero() :: hls_nums:u32(), value = hls_type:zero() :: hls_nums:u8()}).
%% Three ordered slots contain two members and one declared padding value.
-record(element, {value = hls_type:zero() :: hls_nums:u8()}).
%% Reports expose only the result of the pure completion calculation.
-record(report, {value = hls_type:zero() :: hls_nums:u8()}).
%% The second phase leaves a legal provisional key unopened.
-type phase() :: collecting | reporting.

-doc "Opens epoch zero through its initial entry callback.".
-spec init([]) -> {ok, collecting, #cell{}}.
init([]) -> {ok, collecting, #cell{}}.

-doc "Collects members zero and one while authorizing an unopened successor key.".
-spec collecting(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #piece{}, #cell{}) -> hls_statem:cast_result(phase(), #cell{});
    (internal, hls_statem:gather_complete(), #cell{}) -> hls_statem:internal_result(phase(), #cell{}).
collecting(enter, _, Cell) ->
    {Cell, [{open_gather, items, Cell#cell.epoch, {members_mask, 3, 3}, #element{}}]};
collecting(cast, #piece{key = Key, member = Member, value = Value}, Cell = #cell{epoch = Key}) when Member < 3 ->
    {collecting, Cell, {gather, items, Key, Member, #element{value = Value}}};
collecting(cast, #piece{key = Key}, Cell = #cell{epoch = Epoch}) when Key =:= Epoch + 1 ->
    {collecting, Cell, postpone};
collecting(cast, #piece{}, Cell) -> {collecting, Cell, fail};
collecting(internal, {gather_complete, items, Key, _Members, Values}, Cell = #cell{epoch = Key}) ->
    First = hls_lists:nth(1, Values),
    Second = hls_lists:nth(2, Values),
    Padding = hls_lists:nth(3, Values),
    Result = hls_type:as(hls_nums:u8(), First#element.value * 10 + Second#element.value + Padding#element.value),
    {reporting, Cell#cell{epoch = Key + 1, result = Result}, consume}.

-doc "Publishes four identical reports while keeping the successor provisional and invisible.".
-spec reporting(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #piece{}, #cell{}) -> hls_statem:cast_result(phase(), #cell{}).
reporting(enter, _, Cell) ->
    {Cell, [{cast, out_a, #report{value = Cell#cell.result}},
        {cast, out_b, #report{value = Cell#cell.result}},
        {cast, out_c, #report{value = Cell#cell.result}},
        {cast, out_d, #report{value = Cell#cell.result}}]};
reporting(cast, #piece{key = Key}, Cell = #cell{epoch = Key}) -> {reporting, Cell, postpone};
reporting(cast, #piece{}, Cell) -> {reporting, Cell, fail}.
