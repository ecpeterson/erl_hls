-module(hls_data_cell_fixture).
-moduledoc "Small source-derived routing fixture; no application algorithm or host driver.".
-behavior(hls_statem).
-compile({parse_transform, hls_pack}).
-include("hls_routing_fixture.hrl").
-hls_data(cell).
-hls_phases([configuring, replying]).
-hls_outputs([north, east, west, south, measurement]).
-hls_mailbox_capacity(1).

%% State-machine callbacks used by interface inference and topology lowering.
-export([init/1, configuring/3, replying/3]).

%% One bounded word makes fixture state independent of the routing topology.
-record(cell, {value = hls_type:zero() :: hls_nums:u32()}).

-doc "Starts the fixture with zero state and no runtime identity.".
-spec init([]) -> {ok, hls_statem:phase(), #cell{}}.
init([]) -> {ok, configuring, #cell{}}.

-doc "Emits no entry effects; a configuration or query advances to replying, retaining any supplied seed.".
-spec configuring(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, tuple(), #cell{}) -> hls_statem:cast_result(#cell{}).
configuring(enter, _Old, Cell) -> {Cell, []};
configuring(cast, #config{seed = Value}, Cell) -> {replying, Cell#cell{value = Value}, consume};
configuring(cast, #query{}, Cell) -> {replying, Cell, consume}.

-doc "Sends four cardinal replies then a measurement on entry; each query repeats that burst.".
-spec replying(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, tuple(), #cell{}) -> hls_statem:cast_result(#cell{}).
replying(enter, _Old, Cell) -> {Cell, [
        {cast, north, #reply{}},
        {cast, east, #reply{}},
        {cast, west, #reply{}},
        {cast, south, #reply{}},
        {cast, measurement, #measurement{}}
    ]};
replying(cast, #query{}, Cell) -> {repeat_phase, Cell, consume}.
