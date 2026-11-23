-module(hls_dense_statem_fixture).
-behavior(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, boot/3, active/3]).
-hls_data(cell).
-hls_phases([boot, active]).
-hls_outputs([out]).
-hls_mailbox_capacity(2).
-hls_tags([configure, report]).

-record(configure, {
    enabled = hls_type:zero() :: hls_bool:bool(),
    count = hls_type:zero() :: hls_nums:uN(3),
    delta = hls_type:zero() :: hls_nums:sN(9)
}).
-record(cell, {
    enabled = hls_type:zero() :: hls_bool:bool(),
    count = hls_type:zero() :: hls_nums:uN(3),
    value = hls_type:zero() :: hls_nums:sN(9)
}).
-record(report, {
    enabled = hls_type:zero() :: hls_bool:bool(),
    count = hls_type:zero() :: hls_nums:uN(3),
    value = hls_type:zero() :: hls_nums:sN(9)
}).

init([]) -> {ok, boot, #cell{enabled = true, count = 5, value = -129}}.
boot(enter, _Old, Cell) -> {Cell, []};
boot(cast, #configure{enabled = Enabled, count = Count, delta = Delta}, Cell) ->
    {active, Cell#cell{enabled = Enabled,
        count = hls_nums:wrap(hls_nums:uN(3), Cell#cell.count + Count),
        value = hls_nums:wrap(hls_nums:sN(9), Cell#cell.value + Delta)}, consume}.
active(enter, _Old, Cell) ->
    {Cell, [{cast, out, #report{enabled = Cell#cell.enabled,
        count = Cell#cell.count, value = Cell#cell.value}}]};
active(cast, #report{}, Cell) -> {active, Cell, consume}.
