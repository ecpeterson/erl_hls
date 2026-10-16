-module(xls_phase_values_fixture).
-moduledoc "Finite source fixture with helper aliases, failed transitions and phase-specific values.".
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, idle/3, active/3]).
-hls_data(cell).
-hls_tags([command, report]).
-hls_phases([idle, active]).
-hls_outputs([out]).
-hls_mailbox_capacity(2).
%% Only successful commands may select the terminal field.
-record(cell, {kind = hls_type:zero() :: hls_nums:u8(),
    value = hls_type:zero() :: hls_nums:u8()}).
%% Arbitrary external commands remain checked dynamically.
-record(command, {kind = hls_type:zero() :: hls_nums:u8()}).
%% Keep the original wire encoding and externally observable field width.
-record(report, {mask = hls_type:zero() :: hls_nums:u8()}).

-doc "Starts in the zero-valued idle phase.".
-spec init([]) -> {ok, idle, #cell{}}.
init([]) -> {ok, idle, #cell{}}.

-doc "Checks commands before committing a helper-derived terminal kind.".
-spec idle(enter, atom(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #command{}, #cell{}) -> hls_statem:cast_result(atom(), #cell{}).
idle(enter, _, Cell) -> {Cell, []};
idle(cast, Message = #command{kind = Kind}, Cell) ->
    true = Kind =:= 0 orelse Kind =:= 3,
    {active, arm(Message, Cell), consume}.

-doc "Emits a kind-dependent mask; accepts a new kind only through a checked command.".
-spec active(enter, atom(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #command{}, #cell{}) -> hls_statem:cast_result(atom(), #cell{}).
active(enter, _, Cell) ->
    {Cell, [{cast, out, #report{mask = hls_type:as(hls_nums:u8(), 1) bsl Cell#cell.kind}}]};
active(cast, #command{kind = 9}, Cell) -> {active, Cell#cell{kind = 9}, fail};
active(cast, Message = #command{kind = Kind}, Cell) ->
    true = case Cell#cell.kind of
        2 -> Kind =:= 2 orelse Kind =:= 3;
        4 -> Kind =:= 4 orelse Kind =:= 0
    end,
    {active, arm(Message, Cell), consume}.

%% Helpers retain message aliases and untouched fields of the existing record.
-spec arm(#command{}, #cell{}) -> #cell{}.
arm(#command{kind = Kind}, Cell) ->
    Terminal = case Kind of 0 -> 2; 3 -> 4; _ -> Kind end,
    Cell#cell{kind = Terminal}.
