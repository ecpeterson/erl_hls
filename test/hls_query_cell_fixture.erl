-module(hls_query_cell_fixture).
-moduledoc "Small source-derived routing fixture; no application algorithm or host driver.".
-behavior(hls_statem).
-compile({parse_transform, hls_pack}).
-include("hls_routing_fixture.hrl").
-hls_data(cell).
-hls_phases([configuring, querying, reporting]).
-hls_outputs([north, east, west, south, grid]).
-hls_mailbox_capacity(1).

%% State-machine callbacks used by interface inference and topology lowering.
-export([init/1, configuring/3, querying/3, reporting/3]).

%% One bounded word makes fixture state independent of the routing topology.
-record(cell, {value = hls_type:zero() :: hls_nums:u32()}).

-doc "Starts the fixture with zero state and no runtime identity.".
-spec init([]) -> {ok, hls_statem:phase(), #cell{}}.
init([]) -> {ok, configuring, #cell{}}.

-doc "Emits no entry effects; configuration and requests begin querying, while a reply advances to reporting.".
-spec configuring(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, tuple(), #cell{}) -> hls_statem:cast_result(#cell{}).
configuring(enter, _Old, Cell) -> {Cell, []};
configuring(cast, #config{seed = Value}, Cell) -> {querying, Cell#cell{value = Value}, consume};
configuring(cast, #request{}, Cell) -> {querying, Cell, consume};
configuring(cast, #reply{}, Cell) -> {reporting, Cell, consume}.

-doc "Sends four cardinal queries on entry; a request repeats the burst and a reply advances to reporting.".
-spec querying(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, tuple(), #cell{}) -> hls_statem:cast_result(#cell{}).
querying(enter, _Old, Cell) -> {Cell, [
        {cast, north, #query{}},
        {cast, east, #query{}},
        {cast, west, #query{}},
        {cast, south, #query{}}
    ]};
querying(cast, #reply{}, Cell) -> {reporting, Cell, consume};
querying(cast, #request{}, Cell) -> {repeat_phase, Cell, consume}.

-doc "Sends one report to the grid on entry; a request returns to querying.".
-spec reporting(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, tuple(), #cell{}) -> hls_statem:cast_result(#cell{}).
reporting(enter, _Old, Cell) -> {Cell, [{cast, grid, #report{}}]};
reporting(cast, #request{}, Cell) -> {querying, Cell, consume}.
