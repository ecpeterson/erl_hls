-module(xls_message_facts_fixture).
-moduledoc "Literal, aliased, conditional and dynamic egress for message analysis tests.".
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-hls_data(cell).
-hls_phases([idle, dynamic]).
-hls_outputs([west, east, relation, mixed, silent]).
-hls_mailbox_capacity(1).
-hls_tags([piece, alternate]).
-export([init/1, idle/3, dynamic/3]).

%% Payloads remain dynamic while independent direction fields can be constant.
-record(cell, {value = hls_type:zero() :: hls_nums:u8()}).
%% A sub-byte discriminator tests the real ABI rather than host integer equality.
-record(piece, {direction = hls_type:zero() :: hls_nums:uN(3),
    value = hls_type:zero() :: hls_nums:u8()}).
%% Signed constants and omitted fields use their type-directed encodings.
-record(alternate, {signed = hls_type:zero() :: hls_nums:sN(5),
    omitted = hls_type:zero() :: hls_nums:uN(2)}).
%% Both phases remain possible; the analysis must retain their alternatives.
-type phase() :: idle | dynamic.

-doc "Initializes the finite witness actor.".
-spec init([]) -> {ok, idle, #cell{}}.
init([]) -> {ok, idle, #cell{}}.

-doc "Emits correlated alternatives without inferring which branch is reachable.".
-spec idle(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #piece{}, #cell{}) -> hls_statem:cast_result(phase(), #cell{}).
idle(enter, _, Cell) ->
    Base = #piece{value = Cell#cell.value},
    Alias = Base,
    Related = case Cell#cell.value =:= 0 of
        true -> [{cast, relation, #piece{direction = 2, value = 3}}];
        false -> [{cast, relation, #piece{direction = 3, value = 2}}]
    end,
    Mixed = case Cell#cell.value =:= 1 of
        true -> [{cast, mixed, #piece{direction = 1, value = 9}}];
        false -> [{cast, mixed, #alternate{signed = -3}}]
    end,
    {Cell, [{cast, west, Alias#piece{direction = 2}},
        {cast, east, Base#piece{direction = 1}}] ++ Related ++ Mixed};
idle(cast, #piece{value = Value}, Cell) -> {dynamic, Cell#cell{value = Value}, consume}.

-doc "Contributes an unknown discriminator to the same mixed output.".
-spec dynamic(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{}).
dynamic(enter, _, Cell) ->
    {Cell, [{cast, mixed, #piece{direction = hls_type:as(hls_nums:uN(3), Cell#cell.value), value = 9}}]}.
