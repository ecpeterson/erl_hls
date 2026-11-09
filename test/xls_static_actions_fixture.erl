-module(xls_static_actions_fixture).
-moduledoc "Small actor exercising static entry comprehensions independently of any decoder workload.".
-behavior(hls_statem).
-compile({parse_transform, hls_pack}).
-hls_data(cell).
-hls_phases([ordered, empty, discarded, shadowed, locals]).
-hls_outputs([first, second, third]).
-hls_mailbox_capacity(1).
-hls_tags([value]).

%% State-machine initialization and phase callbacks.
-export([init/1, ordered/3, empty/3, discarded/3, shadowed/3, locals/3]).

-record(value, {value = hls_type:zero() :: hls_nums:u32()}).
-record(cell, {value = hls_type:zero() :: hls_nums:u32()}).
%% Every phase is entered directly by the finite DSLX test harness.
-type phase() :: ordered | empty | discarded | shadowed | locals.

-doc "Starts an empty cell in the ordered broadcast phase.".
-spec init([]) -> {ok, phase(), #cell{}}.
init([]) -> {ok, ordered, #cell{}}.

-doc "Publishes two table-selected ports in table order with distinct payload offsets.".
-spec ordered(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{}).
ordered(enter, _OldPhase, Cell) ->
    {Cell#cell{value = Cell#cell.value + 10},
        [{cast, Port, #value{value = Cell#cell.value + Offset}}
         || {Port, Offset} <- [{second, 2}, {first, 1}]]}.

-doc "An empty generator suppresses the otherwise failing payload computation.".
-spec empty(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{}).
empty(enter, _OldPhase, Cell) ->
    {Cell#cell{value = Cell#cell.value + 10},
        [{cast, Port, #value{value = nonzero(Cell#cell.value)}} || Port <- []]}.

-doc "A constructed but discarded batch retains its payload failure.".
-spec discarded(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{}).
discarded(enter, _OldPhase, Cell) ->
    Unused = [{cast, Port, #value{value = nonzero(Cell#cell.value)}} || Port <- [first]],
    {Cell#cell{value = Cell#cell.value + 10}, case false of true -> Unused; false -> [] end}.

-doc "Generator ports shadow an outer numeric binding without changing its later value.".
-spec shadowed(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{}).
shadowed(enter, _OldPhase, Cell) ->
    Port = hls_type:as(hls_nums:u32(), 7),
    Actions = [{cast, Port, #value{value = Cell#cell.value}} || Port <- [first, second]],
    {Cell#cell{value = Cell#cell.value + Port}, Actions}.

-doc "Each iteration owns its local payload binding and exports no binding to the continuation.".
-spec locals(enter, phase(), #cell{}) -> hls_statem:enter_result(#cell{}).
locals(enter, _OldPhase, Cell) ->
    Actions = [{cast, Port, #value{value = begin
        Local = Cell#cell.value + Offset,
        Local
    end}} || {Port, Offset} <- [{first, 1}, {second, 2}]],
    Local = hls_type:as(hls_nums:u32(), 10),
    {Cell#cell{value = Cell#cell.value + Local}, Actions}.

%% Fail before any effect can become visible when the supplied scalar is zero.
-spec nonzero(hls_nums:u32()) -> hls_nums:u32().
nonzero(Value) -> true = Value =/= 0, Value.
