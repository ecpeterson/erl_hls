-module(hls_grid_cell_fixture).
-moduledoc "Small source-derived routing fixture; no application algorithm or host driver.".
-behavior(hls_statem).
-compile({parse_transform, hls_pack}).
-include("hls_routing_fixture.hrl").
-hls_data(cell).
-hls_phases([configuring, sampling, moving, reporting]).
-hls_outputs([north, east, west, south, query, result, status]).
-hls_mailbox_capacity(1).

%% State-machine callbacks used by interface inference and topology lowering.
-export([init/1, configuring/3, sampling/3, moving/3, reporting/3]).

%% One bounded word makes fixture state independent of the routing topology.
-record(cell, {value = hls_type:zero() :: hls_nums:u32()}).

-doc "Starts the fixture with zero state and no runtime identity.".
-spec init([]) -> {ok, hls_statem:phase(), #cell{}}.
init([]) -> {ok, configuring, #cell{}}.

-doc "Emits no entry effects; each accepted input advances to sampling, and a seed initializes the stored word.".
-spec configuring(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, tuple(), #cell{}) -> hls_statem:cast_result(#cell{}).
configuring(enter, _Old, Cell) -> {Cell, []};
configuring(cast, #seed{seed = Value}, Cell) -> {sampling, Cell#cell{value = Value}, consume};
configuring(cast, #sample{}, Cell) -> {sampling, Cell, consume};
configuring(cast, #delta{}, Cell) -> {sampling, Cell, consume};
configuring(cast, #move{}, Cell) -> {sampling, Cell, consume};
configuring(cast, #report{}, Cell) -> {sampling, Cell, consume}.

-doc "Sends four cardinal samples then one query on entry; a received sample advances to moving.".
-spec sampling(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, tuple(), #cell{}) -> hls_statem:cast_result(#cell{}).
sampling(enter, _Old, Cell) ->
    {Cell, [
        {cast, north, #sample{}},
        {cast, east, #sample{}},
        {cast, west, #sample{}},
        {cast, south, #sample{}},
        {cast, query, #request{}}
    ]};
sampling(cast, #sample{}, Cell) -> {moving, Cell, consume}.

-doc "Sends four cardinal moves then one result on entry; a received move advances to reporting.".
-spec moving(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, tuple(), #cell{}) -> hls_statem:cast_result(#cell{}).
moving(enter, _Old, Cell) ->
    {Cell, [
        {cast, north, #move{}},
        {cast, east, #move{}},
        {cast, west, #move{}},
        {cast, south, #move{}},
        {cast, result, #result{}}
    ]};
moving(cast, #move{}, Cell) -> {reporting, Cell, consume}.

-doc "Sends four cardinal deltas then one status on entry; a delta or report returns to sampling.".
-spec reporting(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, tuple(), #cell{}) -> hls_statem:cast_result(#cell{}).
reporting(enter, _Old, Cell) ->
    {Cell, [
        {cast, north, #delta{}},
        {cast, east, #delta{}},
        {cast, west, #delta{}},
        {cast, south, #delta{}},
        {cast, status, #status{}}
    ]};
reporting(cast, #delta{}, Cell) -> {sampling, Cell, consume};
reporting(cast, #report{}, Cell) -> {sampling, Cell, consume}.
