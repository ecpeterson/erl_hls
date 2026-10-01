-module(xls_statem_gather_fixture).
-moduledoc "Typed ordered collection and scalar fold sharing one ordinary state machine.".
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-hls_data(cell).
-hls_phases([idle, collecting, copied, reducing, publishing, done]).
-hls_outputs([out]).
-hls_mailbox_capacity(8).
-hls_tags([begin_set, piece, scalar, result]).
-hls_continuations([fold, finish]).
-export([init/1, idle/3, collecting/3, copied/3, reducing/3, publishing/3, done/3, reduce/3]).

%% The actor retains only the scalar consumer result, never the ordered payload.
-record(cell, {key = hls_type:zero() :: hls_nums:u32(), mask = hls_type:zero() :: hls_nums:u8(),
    value = hls_type:zero() :: hls_nums:u32()}).
%% A bounded runtime participant subset may be empty.
-record(begin_set, {key = hls_type:zero() :: hls_nums:u32(), mask = hls_type:zero() :: hls_nums:u8()}).
%% Each member contributes one independently typed value.
-record(piece, {key = hls_type:zero() :: hls_nums:u32(), member = hls_type:zero() :: hls_nums:u32(),
    value = hls_type:zero() :: hls_nums:u8()}).
%% A scalar fold remains independent of the preceding indexed collection.
-record(scalar, {key = hls_type:zero() :: hls_nums:u32(), value = hls_type:zero() :: hls_nums:u8()}).
%% Results expose source completion and entry ordering.
-record(result, {value = hls_type:zero() :: hls_nums:u32()}).
%% The transient element has a default constructor accepted by the gather API.
-record(element, {value = hls_type:zero() :: hls_nums:u8()}).
%% A distinct scalar accumulator must not be widened into an ordered payload.
-record(parity, {value = hls_type:zero() :: hls_nums:u8()}).
%% Collection, pure continuation and externally observable phases are finite.
-type phase() :: idle | collecting | copied | reducing | publishing | done.

-doc "Starts with no open collection.".
-spec init([]) -> {ok, idle, #cell{}}.
init([]) -> {ok, idle, #cell{}}.

-doc "Opens the selected collection and postpones contributions that arrive early.".
-spec idle(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #begin_set{} | #piece{} | #scalar{}, #cell{}) -> hls_statem:cast_result(phase(), #cell{}).
idle(enter, _, Cell) -> {Cell, []};
idle(cast, #begin_set{key = Key, mask = Mask}, Cell) when Key =< 1 ->
    {collecting, Cell#cell{key = Key, mask = Mask}, consume, [{next_event, internal, fold}]};
idle(cast, #begin_set{key = Key, mask = Mask}, Cell) ->
    {collecting, Cell#cell{key = Key, mask = Mask}, consume};
idle(cast, #piece{}, Cell) -> {idle, Cell, postpone};
idle(cast, #scalar{}, Cell) -> {idle, Cell, postpone}.

-doc "Consumes selected values in numeric member order through an immediate pure helper.".
-spec collecting(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #piece{} | #scalar{}, #cell{}) -> hls_statem:cast_result(phase(), #cell{});
    (internal, hls_statem:gather_complete(), #cell{}) -> hls_statem:internal_result(phase(), #cell{}).
collecting(enter, _, Cell) ->
    {Cell, [{open_gather, items, Cell#cell.key, {members_mask, 4, Cell#cell.mask}, #element{}}]};
collecting(cast, #piece{key = Key, member = Member, value = Value}, Cell = #cell{key = Key}) ->
    {collecting, Cell, {gather, items, Key, Member, #element{value = Value}}};
collecting(cast, #piece{}, Cell) -> {collecting, Cell, postpone};
collecting(cast, #scalar{}, Cell) -> {collecting, Cell, postpone};
collecting(internal, {gather_complete, items, 0, _Members, Values}, Cell = #cell{key = 0}) ->
    {copied, Cell#cell{value = ordered(Values)}, consume};
collecting(internal, {gather_complete, items, Key, _Members, Values}, Cell = #cell{key = Key}) ->
    {copied, Cell#cell{value = ordered(Values)}, consume, [{next_event, internal, fold}]}.

%% Weight positions distinctly so accidental arrival-order storage is observable.
-spec ordered(hls_lists:list(#element{}, 4)) -> hls_nums:u32().
ordered(Values) ->
    A = hls_lists:nth(1, Values), B = hls_lists:nth(2, Values),
    C = hls_lists:nth(3, Values), D = hls_lists:nth(4, Values),
    hls_type:as(hls_nums:u32(), A#element.value) +
        hls_type:as(hls_nums:u32(), B#element.value) * 10 +
        hls_type:as(hls_nums:u32(), C#element.value) * 100 +
        hls_type:as(hls_nums:u32(), D#element.value) * 1000.

-doc "Publishes the gathered result before starting a scalar fold.".
-spec copied(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (internal, fold, #cell{}) -> hls_statem:internal_result(phase(), #cell{}).
copied(enter, _, Cell) -> {Cell, [{cast, out, #result{value = Cell#cell.value}}]};
copied(internal, fold, Cell) -> {reducing, Cell, consume}.

-doc "Completes a scalar fold using the same declared continuation mechanism.".
-spec reducing(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #scalar{}, #cell{}) -> hls_statem:cast_result(phase(), #cell{});
    (internal, hls_statem:reduction_complete(), #cell{}) -> hls_statem:internal_result(phase(), #cell{}).
reducing(enter, _, Cell) ->
    {Cell, [{open_reduction, parity, Cell#cell.key, {count, 1}, {commutative_monoid, #parity{value = 0}}}]};
reducing(cast, #scalar{key = Key, value = Value}, Cell) ->
    {reducing, Cell, {contribute, parity, Key, #parity{value = Value}}};
reducing(internal, {reduction_complete, parity, 0, #parity{value = Value}}, Cell = #cell{key = 0}) ->
    {publishing, Cell#cell{value = hls_type:as(hls_nums:u32(), Value)}, consume};
reducing(internal, {reduction_complete, parity, Key, #parity{value = Value}}, Cell = #cell{key = Key}) ->
    {publishing, Cell#cell{value = Cell#cell.value + hls_type:as(hls_nums:u32(), Value)}, consume,
        [{next_event, internal, finish}]}.

-doc "Publishes the folded result before a final continuation.".
-spec publishing(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (internal, finish, #cell{}) -> hls_statem:internal_result(phase(), #cell{}).
publishing(enter, _, Cell) -> {Cell, [{cast, out, #result{value = Cell#cell.value}}]};
publishing(internal, finish, Cell) -> {done, Cell, consume}.

-doc "Leaves the completed result stable.".
-spec done(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{}).
done(enter, _, Cell) -> {Cell, []}.

-doc "Combines scalar parity without inspecting gather values.".
-spec reduce(parity, #parity{}, #parity{}) -> #parity{}.
reduce(parity, #parity{value = A}, #parity{value = B}) -> #parity{value = A bxor B}.
