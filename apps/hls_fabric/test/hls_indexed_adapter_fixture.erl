-module(hls_indexed_adapter_fixture).
-moduledoc "A bounded keyed source contract for physical indexed-adapter witnesses.".
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-hls_data(cell).
-hls_phases([waiting, collecting]).
-hls_outputs([out]).
-hls_mailbox_capacity(4).
-hls_tags([piece]).
-hls_continuations([advance]).
-export([init/1, waiting/3, collecting/3]).

%% Future-key and current-key policies expose source revalidation at opening.
-record(cell, {epoch = hls_type:zero() :: hls_nums:u32(),
    future = hls_type:zero() :: hls_bool:bool(),
    current_mode = hls_type:zero() :: hls_nums:u8()}).
%% Member identity is independent of arrival order and value.
-record(piece, {key = hls_type:zero() :: hls_nums:u32(),
    member = hls_type:zero() :: hls_nums:u32(), value = hls_type:zero() :: hls_nums:u8()}).
%% Payload is transient and never copied into callback state.
-record(element, {value = hls_type:zero() :: hls_nums:u8()}).
%% Only collecting opens storage; waiting can authorize a provisional successor.
-type phase() :: waiting | collecting.

-doc "Starts in a stable state which permits current and successor keys.".
-spec init([]) -> {ok, waiting, #cell{}}.
init([]) -> {ok, waiting, #cell{future = true}}.

-doc "Postpones exactly the current key and an enabled successor; rejects every other key.".
-spec waiting(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #piece{}, #cell{}) -> hls_statem:cast_result(phase(), #cell{});
    (internal, advance, #cell{}) -> hls_statem:internal_result(phase(), #cell{}).
waiting(enter, _, Cell) -> {Cell, []};
waiting(cast, #piece{key = Key}, Cell = #cell{epoch = Key}) -> {waiting, Cell, postpone};
waiting(cast, #piece{key = Key}, Cell = #cell{epoch = Epoch, future = true}) when Key =:= Epoch + 1 ->
    {waiting, Cell, postpone};
waiting(cast, #piece{}, Cell) -> {waiting, Cell, fail};
waiting(internal, advance, Cell) -> {collecting, Cell, consume}.

-doc "Opens members zero and one, then releases the transient payload after its callback.".
-spec collecting(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #piece{}, #cell{}) -> hls_statem:cast_result(phase(), #cell{});
    (internal, hls_statem:gather_complete(), #cell{}) -> hls_statem:internal_result(phase(), #cell{}).
collecting(enter, _, Cell) -> {Cell, [{open_gather, items, Cell#cell.epoch, {members_mask, 3, 3}, #element{}}]};
collecting(cast, #piece{key = Key, member = Member, value = Value}, Cell = #cell{epoch = Key, current_mode = 0}) when Member < 3 ->
    {collecting, Cell, {gather, items, Key, Member, #element{value = Value}}};
collecting(cast, #piece{key = Key}, Cell = #cell{epoch = Key, current_mode = 1}) ->
    {collecting, Cell, postpone};
collecting(cast, #piece{key = Key}, Cell = #cell{epoch = Epoch, future = true}) when Key =:= Epoch + 1 ->
    {collecting, Cell, postpone};
collecting(cast, #piece{}, Cell) -> {collecting, Cell, fail};
collecting(internal, {gather_complete, items, Key, _Members, _Values}, Cell = #cell{epoch = Key}) ->
    {waiting, Cell, consume}.
