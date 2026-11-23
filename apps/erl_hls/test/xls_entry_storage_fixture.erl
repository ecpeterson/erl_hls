-module(xls_entry_storage_fixture).
-moduledoc false.
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, repeated/3, independent/3, conditional/3]).
-hls_data(cell).
-hls_tags([packet]).
-hls_phases([repeated, independent, conditional]).
-hls_outputs([first, second, third]).
-hls_mailbox_capacity(1).

%% Deliberately unaligned nested fields exercise the public bit-order codec.
-record(sample, {positive = hls_type:zero() :: hls_nums:uN(5),
    negative = hls_type:zero() :: hls_nums:sN(5), flag = hls_type:zero() :: hls_bool:bool()}).
%% A common dynamic payload with destination-specific literals.
-record(packet, {key = hls_type:zero() :: hls_nums:u32(),
    direction = hls_type:zero() :: hls_nums:u8(), sample = hls_type:zero() :: #sample{},
    tail = hls_type:zero() :: hls_nums:u16()}).
%% Inputs vary independently to expose accidental field or alias sharing.
-record(cell, {key = hls_type:zero() :: hls_nums:u32(),
    sample = hls_type:zero() :: #sample{}, tail = hls_type:zero() :: hls_nums:u16()}).

-doc "Starts the field-sharing fixture with zero values.".
-spec init([]) -> {ok, repeated, #cell{}}.
init([]) -> {ok, repeated, #cell{}}.

-doc "Publishes related messages, retaining source order and distinct constant directions.".
-spec repeated(enter, atom(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #packet{}, #cell{}) -> hls_statem:cast_result(atom(), #cell{}).
repeated(enter, _, Cell) ->
    Message = #packet{key = Cell#cell.key, sample = Cell#cell.sample, tail = Cell#cell.tail},
    Alias = Message,
    {Cell, [{cast, first, Alias#packet{direction = 1}},
        {cast, second, Message#packet{direction = 2}},
        {cast, third, Message#packet{direction = 3}}]};
repeated(cast, #packet{key = Key, sample = Sample, tail = Tail}, Cell) ->
    {independent, Cell#cell{key = Key, sample = Sample, tail = Tail}, consume}.

-doc "Publishes independently evaluated values even when expressions resemble each other.".
-spec independent(enter, atom(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #packet{}, #cell{}) -> hls_statem:cast_result(atom(), #cell{}).
independent(enter, _, Cell) ->
    A = Cell#cell.key + 1,
    B = Cell#cell.key + 2,
    {Cell, [{cast, first, #packet{key = A, direction = 4}},
        {cast, second, #packet{key = B, direction = 5}},
        {cast, third, #packet{key = A, direction = 6}}]};
independent(cast, #packet{}, Cell) -> {conditional, Cell, consume}.

-doc "Keeps distinct sharing patterns separate across alternatives with identical ports and schemas.".
-spec conditional(enter, atom(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #packet{}, #cell{}) -> hls_statem:cast_result(atom(), #cell{}).
conditional(enter, _, Cell) ->
    case Cell#cell.key band 1 of
        0 ->
            Value = Cell#cell.key,
            Message = #packet{key = Value},
            {Cell, [{cast, first, Message}, {cast, second, Message}, {cast, third, Message}]};
        _ ->
            Value = Cell#cell.key + 1,
            Message = #packet{key = Value},
            {Cell, [{cast, first, Message}, {cast, second, #packet{key = Cell#cell.key}},
                {cast, third, Message}]}
    end;
conditional(cast, #packet{}, Cell) -> {repeated, Cell, consume}.
