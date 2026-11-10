-module(xls_remote_selection_fixture).
-moduledoc "Small actor that causes the compiler to emit a public source-helper module.".
-behavior(hls_statem).
-compile({parse_transform, hls_pack}).
-hls_data(cell).
-hls_phases([selecting]).
-hls_outputs([out]).
-hls_mailbox_capacity(1).
-hls_tags([value]).
%% BEAM oracle and ordinary actor callbacks.
-export([init/1, selecting/3]).

-record(value, {value = hls_type:zero() :: hls_nums:u32()}).
-record(cell, {value = hls_type:zero() :: hls_nums:u32()}).

-doc "Starts one pending selection with an empty value.".
-spec init([]) -> {ok, selecting, #cell{}}.
init([]) -> {ok, selecting, #cell{}}.

-doc "Publishes a value chosen by an ordinary helper from another source module.".
-spec selecting(enter, selecting, #cell{}) -> hls_statem:enter_result(#cell{}).
selecting(enter, _Old, Cell) ->
    Value = xls_remote_selector:choose(Cell#cell.value =:= 0, Cell#cell.value, 7),
    {Cell#cell{value = Value}, [{cast, out, #value{value = Value}}]}.
