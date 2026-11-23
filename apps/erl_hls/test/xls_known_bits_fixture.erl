-module(xls_known_bits_fixture).
-moduledoc false.
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, active/3]).
-hls_data(cell).
-hls_tags([packet]).
-hls_phases([active]).
-hls_outputs([first, second]).
-hls_mailbox_capacity(1).

%% Separate typed inputs exercise signed, unaligned and failed computations.
-record(cell, {value = hls_type:zero() :: hls_nums:u16(),
    small = hls_type:zero() :: hls_nums:uN(5),
    signed = hls_type:zero() :: hls_nums:sN(5),
    denominator = hls_type:zero() :: hls_nums:u16()}).
%% Original schema remains 58 bits even when entry storage uses only 30.
-record(packet, {coded = hls_type:zero() :: hls_nums:u16(),
    small = hls_type:zero() :: hls_nums:uN(5),
    signed = hls_type:zero() :: hls_nums:sN(5),
    opaque = hls_type:zero() :: hls_nums:u16(),
    zeroed = hls_type:zero() :: hls_nums:u16()}).

-doc "Starts the codec witness with a nonzero divisor.".
-spec init([]) -> {ok, active, #cell{}}.
init([]) -> {ok, active, #cell{denominator = 1}}.

-doc "Emits two aliased values in source order; masked-out division must still fail at zero.".
-spec active(enter, atom(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #packet{}, #cell{}) -> hls_statem:cast_result(atom(), #cell{}).
active(enter, _, Cell) ->
    Coded = ((Cell#cell.value band 16#0f0f) bor 16#8040) bxor 16#20,
    Message = #packet{coded = Coded, small = (Cell#cell.small band 21) bor 2,
        signed = (Cell#cell.signed band 7) bor -8,
        opaque = opaque(Cell#cell.value),
        zeroed = (Cell#cell.value div Cell#cell.denominator) band 0},
    Alias = Message,
    {Cell, [{cast, first, Message}, {cast, second, Alias}]};
active(cast, #packet{}, Cell) -> {active, Cell, consume}.

%% Unknown helpers remain opaque even when this particular body is an identity.
-spec opaque(hls_nums:u16()) -> hls_nums:u16().
opaque(Value) -> Value.
