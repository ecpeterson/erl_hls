-module(hls_statem_mask_reduction_fixture).
-moduledoc "A configurable participant set gathering independent parity contributions.".
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-hls_data(cell).
-hls_phases([idle, collecting, complete]).
-hls_outputs([out]).
-hls_mailbox_capacity(8).
-hls_tags([begin_set, piece, result]).
-export([init/1, idle/3, collecting/3, complete/3, reduce/3]).

%% Participant masks intentionally have spare high bits to exercise invalid bounds.
-record(cell, {key = hls_type:zero() :: hls_nums:u32(), mask = hls_type:zero() :: hls_nums:u8(),
    value = hls_type:zero() :: hls_nums:u8()}).
%% Start a new six-member-capacity collection with a runtime subset.
-record(begin_set, {key = hls_type:zero() :: hls_nums:u32(), mask = hls_type:zero() :: hls_nums:u8()}).
%% Each selected contributor provides one independent parity value.
-record(piece, {key = hls_type:zero() :: hls_nums:u32(), member = hls_type:zero() :: hls_nums:u32(),
    value = hls_type:zero() :: hls_nums:u8()}).
%% Completed parity is an ordinary externally observable message.
-record(result, {value = hls_type:zero() :: hls_nums:u8()}).
%% The private accumulator never appears in the actor's ordinary state or wire input.
-record(parity, {value = hls_type:zero() :: hls_nums:u8()}).
%% The finite phase vocabulary remains independent of participant identities.
-type phase() :: idle | collecting | complete.

-doc "Starts with no open collection.".
-spec init([]) -> {ok, idle, #cell{}}.
init([]) -> {ok, idle, #cell{}}.

-doc "Waits for a nonempty bounded participant mask.".
-spec idle(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #begin_set{} | #piece{}, #cell{}) -> hls_statem:cast_result(phase(), #cell{}).
idle(enter, _, Cell) -> {Cell, []};
idle(cast, #begin_set{key = Key, mask = Mask}, Cell) ->
    {collecting, Cell#cell{key = Key, mask = Mask}, consume};
idle(cast, #piece{}, Cell) -> {idle, Cell, postpone}.

-doc "Folds one contribution from every member selected when this collection opens.".
-spec collecting(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #piece{}, #cell{}) -> hls_statem:cast_result(phase(), #cell{});
    (internal, hls_statem:reduction_complete(), #cell{}) -> hls_statem:internal_result(phase(), #cell{}).
collecting(enter, _, Cell) ->
    {Cell, [{open_reduction, parity, Cell#cell.key, {members_mask, 6, Cell#cell.mask},
        {commutative_monoid, #parity{value = 0}}}]};
collecting(cast, #piece{key = Key, member = Member, value = Value}, Cell) ->
    {collecting, Cell, {contribute, parity, Key, Member, #parity{value = Value}}};
collecting(internal, {reduction_complete, parity, Key, #parity{value = Value}}, Cell = #cell{key = Key}) ->
    {complete, Cell#cell{value = Value}, consume}.

-doc "Publishes the completed parity value exactly once.".
-spec complete(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{}).
complete(enter, _, Cell) -> {Cell, [{cast, out, #result{value = Cell#cell.value}}]}.

-doc "Combines parity independently of contribution order.".
-spec reduce(parity, #parity{}, #parity{}) -> #parity{}.
reduce(parity, #parity{value = A}, #parity{value = B}) -> #parity{value = A bxor B}.
