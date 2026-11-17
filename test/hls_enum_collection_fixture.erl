-module(hls_enum_collection_fixture).
-moduledoc false.
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, active/3]).
-hls_data(cell).
-hls_phases([active]).
-hls_outputs([out]).
-hls_mailbox_capacity(1).
-hls_tags([request]).
%% Concrete numeric aliases and atom domains also occur inside nested records.
-type index() :: hls_nums:uN(2).
%% Input storage preserves this declaration order.
-type mode() :: idle | busy | done.
%% Overlapping atoms have an independent codebook.
-type fault() :: none | actor | busy.
-record(sample, {mode = hls_type:zero() :: mode(), fault = hls_type:zero() :: fault()}).
-record(cell, {samples = hls_type:zero() :: hls_vec:vector(#sample{}, 2),
               modes = hls_type:zero() :: hls_vec:vector(mode(), 2)}).
-record(request, {index = hls_type:zero() :: index(), mode = hls_type:zero() :: mode()}).
-doc "Initializes two independent queue slots with declared zero values.".
-spec init([]) -> {ok, active, #cell{}}.
init([]) -> {ok, active, #cell{}}.
-doc "Updates an indexed enum and nested record through a source-module helper.".
-spec active(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #request{}, #cell{}) -> hls_statem:cast_result(active, #cell{}).
active(enter, _, Cell) -> {Cell, []};
active(cast, #request{index = Index, mode = Mode}, Cell) ->
    Modes = hls_vec:set(Index, Cell#cell.modes, Mode),
    Sample = hls_vec:nth(Index, Cell#cell.samples),
    Updated = Sample#sample{mode = hls_vec:nth(Index, Modes), fault = enum_collection_math:fault(Mode)},
    {active, Cell#cell{modes = Modes, samples = hls_vec:set(Index, Cell#cell.samples, Updated)}, consume}.
