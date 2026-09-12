-module(xls_init_statem_fixture).
-behavior(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, unused/3, boot/3, active/3]).

-hls_data(cell).
-hls_phases([unused, boot, active]).
-hls_outputs([out]).
-hls_mailbox_capacity(2).
-hls_tags([configure, report]).

-record(configure, {offset = hls_type:zero() :: hls_nums:u32()}).
-record(report, {
    value = hls_type:zero() :: hls_nums:u32(),
    default = hls_type:zero() :: hls_nums:u32(),
    old_phase = hls_type:zero() :: hls_nums:u32()
}).
-record(cell, {
    value = hls_type:zero() :: hls_nums:u32(),
    default = hls_type:zero() :: hls_nums:u32()
}).

init([]) ->
    Base = hls_nums:wrap(hls_nums:u32(), 41),
    Expected = hls_nums:wrap(hls_nums:u32(), 41),
    Expected = Base,
    {ok, boot, #cell{value = Base + 1}}.

unused(enter, _OldPhase, Cell) -> {Cell, []}.

%% Initial entry precedes startup-message dispatch. Its data update must be
%% visible to configuration, while the initial phase remains quiescent.
boot(enter, _OldPhase, Cell) ->
    {Cell#cell{value = Cell#cell.value + 1}, []};
boot(cast, #configure{offset = Offset}, Cell) ->
    {active, Cell#cell{value = Cell#cell.value + Offset}, consume}.

active(enter, OldPhase, Cell) ->
    From = case OldPhase of
        boot -> hls_nums:wrap(hls_nums:u32(), 7);
        _ -> hls_nums:wrap(hls_nums:u32(), 0)
    end,
    {Cell, [{cast, out, #report{value = Cell#cell.value,
        default = Cell#cell.default, old_phase = From}}]};
active(cast, #configure{offset = Offset}, Cell) ->
    {repeat_phase, Cell#cell{value = Offset}, consume}.
