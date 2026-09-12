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
    case Base > 0 of
        true -> Initial = Base + 1;
        false -> Initial = hls_nums:wrap(hls_nums:u32(), 0)
    end,
    {ok, boot, #cell{value = Initial}}.

unused(enter, _OldPhase, Cell) -> {Cell, []}.

%% Initial entry precedes startup-message dispatch. Its data update must be
%% visible to configuration, while the initial phase remains quiescent.
boot(enter, _OldPhase, Cell) ->
    {add_offset(Cell, 1), []};
boot(cast, #configure{offset = Offset}, Cell) ->
    {active, add_offset(Cell, Offset), consume}.

active(enter, OldPhase, Cell) ->
    From = marker(OldPhase =:= boot),
    {Cell, [{cast, out, #report{value = Cell#cell.value,
        default = Cell#cell.default, old_phase = From}}]};
active(cast, #configure{offset = Offset}, Cell) ->
    {repeat_phase, Cell#cell{value = Offset}, consume}.

-spec add_offset(#cell{}, hls_nums:u32()) -> #cell{}.
add_offset(Cell, Offset) ->
    Cell#cell{value = Cell#cell.value + Offset}.

-spec marker(boolean()) -> hls_nums:u32().
marker(IsBoot) ->
    case IsBoot of
        true -> hls_nums:wrap(hls_nums:u32(), 7);
        false -> hls_nums:wrap(hls_nums:u32(), 0)
    end.
