-module(xls_remote_values_fixture).
-moduledoc "Finite owner witness for ordinary source helpers across module boundaries.".
-behavior(hls_statem).
-compile({parse_transform, hls_pack}).
-hls_data(cell).
-hls_phases([nested, discarded, arguments, selected, tupled]).
-hls_outputs([first, second, third]).
-hls_mailbox_capacity(1).
-hls_tags([value]).
%% Ordinary actor callbacks used by the BEAM oracle and generated owner.
-export([init/1, nested/3, discarded/3, arguments/3, selected/3, tupled/3]).
-record(value, {value = hls_type:zero() :: hls_nums:u32()}).
-record(cell, {value = hls_type:zero() :: hls_nums:u32()}).
%% Harness phase order is explicit and independent of the generated enum spelling.
-type phase() :: nested | discarded | arguments | selected | tupled.
-doc "Starts with an empty value and a pending nested entry.".
-spec init([]) -> {ok, phase(), #cell{}}.
init([]) -> {ok, nested, #cell{}}.
-doc "Calls a remote helper that itself calls a private and another remote helper.".
-spec nested(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{}).
nested(enter, _Old, Cell) ->
    Value = xls_remote_value_math:calculate(Cell#cell.value),
    {Cell#cell{value=Value}, [{cast, first, #value{value=Value}}]}.
-doc "Retains a failure even when a remote return value is ignored.".
-spec discarded(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{}).
discarded(enter, _Old, Cell) ->
    xls_remote_value_math:nonzero(Cell#cell.value),
    {Cell, []}.
-doc "Evaluates a failing argument even though the callee ignores it.".
-spec arguments(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{}).
arguments(enter, _Old, Cell) ->
    Value = xls_remote_value_math:first(Cell#cell.value,
        xls_remote_value_math:nonzero(Cell#cell.value)),
    {Cell, [{cast, second, #value{value=Value}}]}.
-doc "Suppresses helper failures in an unselected branch.".
-spec selected(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{}).
selected(enter, _Old, Cell) ->
    Value = case Cell#cell.value of
        0 -> 7;
        _ -> xls_remote_value_math:nonzero(Cell#cell.value)
    end,
    {Cell#cell{value=Value}, []}.
-doc "Carries a concrete tuple through two ordinary module boundaries.".
-spec tupled(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{}).
tupled(enter, _Old, Cell) ->
    {Flag, Value} = xls_remote_value_math:pair({true, Cell#cell.value}),
    Next = case Flag of true -> Value; false -> 0 end,
    {Cell#cell{value=Next}, [{cast, first, #value{value=Next}}]}.
