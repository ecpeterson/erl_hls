-module(xls_statem_gather_sites_fixture).
-moduledoc "Two gather sites with different element types, capacities and constant padding.".
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-hls_data(cell).
-hls_phases([narrow, wide, done]).
-hls_outputs([out]).
-hls_mailbox_capacity(4).
-hls_tags([narrow_piece, wide_piece, result]).
-export([init/1, narrow/3, wide/3, done/3]).

%% Only the consumer's small result survives either completion.
-record(cell, {value = hls_type:zero() :: hls_nums:u32()}).
%% The first collection has byte-valued elements.
-record(small, {value = hls_type:zero() :: hls_nums:u8()}).
%% The second collection has wider elements and separate padding.
-record(large, {value = hls_type:zero() :: hls_nums:u16()}).
%% A schema belongs to one source collection site.
-record(narrow_piece, {member = hls_type:zero() :: hls_nums:u32(), value = hls_type:zero() :: hls_nums:u8()}).
%% Wider contribution values do not change the first site's codec.
-record(wide_piece, {member = hls_type:zero() :: hls_nums:u32(), value = hls_type:zero() :: hls_nums:u16()}).
%% The final scalar is observable through the ordinary output.
-record(result, {value = hls_type:zero() :: hls_nums:u32()}).
%% Site ownership follows the declared source phase.
-type phase() :: narrow | wide | done.

-doc "Begins in the first collection's entry.".
-spec init([]) -> {ok, narrow, #cell{}}.
init([]) -> {ok, narrow, #cell{}}.

-doc "Gathers two byte values before moving to an independently typed site.".
-spec narrow(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #narrow_piece{}, #cell{}) -> hls_statem:cast_result(phase(), #cell{});
    (internal, hls_statem:gather_complete(), #cell{}) -> hls_statem:internal_result(phase(), #cell{}).
narrow(enter, _, Cell) -> {Cell, [{open_gather, first, 7, {members_mask, 2, 3}, #small{}}]};
narrow(cast, #narrow_piece{member = Member, value = Value}, Cell) ->
    {narrow, Cell, {gather, first, 7, Member, #small{value = Value}}};
narrow(internal, {gather_complete, first, 7, _, Values}, Cell) ->
    A = hls_lists:nth(1, Values), B = hls_lists:nth(2, Values),
    {wide, Cell#cell{value = hls_type:as(hls_nums:u32(), A#small.value) + hls_type:as(hls_nums:u32(), B#small.value)}, consume}.

-doc "Gathers a sparse wider collection whose absent slot is padded with nine.".
-spec wide(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #wide_piece{}, #cell{}) -> hls_statem:cast_result(phase(), #cell{});
    (internal, hls_statem:gather_complete(), #cell{}) -> hls_statem:internal_result(phase(), #cell{}).
wide(enter, _, Cell) -> {Cell, [{open_gather, second, 7, {members_mask, 3, 5}, #large{value = 9}}]};
wide(cast, #wide_piece{member = Member, value = Value}, Cell) ->
    {wide, Cell, {gather, second, 7, Member, #large{value = Value}}};
wide(internal, {gather_complete, second, 7, _, Values}, Cell) ->
    A = hls_lists:nth(1, Values), B = hls_lists:nth(2, Values), C = hls_lists:nth(3, Values),
    {done, Cell#cell{value = Cell#cell.value + hls_type:as(hls_nums:u32(), A#large.value) +
        hls_type:as(hls_nums:u32(), B#large.value) + hls_type:as(hls_nums:u32(), C#large.value)}, consume}.

-doc "Publishes the final consumer result.".
-spec done(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{}).
done(enter, _, Cell) -> {Cell, [{cast, out, #result{value = Cell#cell.value}}]}.
