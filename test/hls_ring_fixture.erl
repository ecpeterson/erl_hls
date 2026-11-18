-module(hls_ring_fixture).
-moduledoc false.
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, active/3]).
-hls_data(cell).
-hls_phases([active]).
-hls_outputs([out]).
-hls_mailbox_capacity(1).
-hls_tags([request]).
%% Bare enums and nested enum/Boolean records both retain their element domains.
-type mode() :: cold | warm | hot.
-record(sample, {mode = hls_type:zero() :: mode(), flag = hls_type:zero() :: boolean()}).
-record(cell, {modes = hls_type:zero() :: hls_ring:ring(mode(), 3),
    samples = hls_type:zero() :: hls_ring:ring(#sample{}, 2),
    observed = hls_type:zero() :: mode()}).
-record(request, {mode = hls_type:zero() :: mode(), flag = hls_type:zero() :: boolean()}).
-doc "Initializes empty typed rings.".
-spec init([]) -> {ok, active, #cell{}}.
init([]) -> {ok, active, #cell{}}.
-doc "Inserts or replaces a concrete enum and record, then reads the enum through the provider.".
-spec active(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #request{}, #cell{}) -> hls_statem:cast_result(active, #cell{}).
active(enter, _, S) -> {S, []};
active(cast, #request{mode = Mode, flag = Flag}, S) ->
    Modes = hls_ring:rewind(S#cell.modes), Samples = hls_ring:rewind(S#cell.samples),
    Sample = #sample{mode = Mode, flag = Flag},
    case hls_ring:empty(Modes) of
        true ->
            {true, NextModes} = hls_ring:insert_step(Mode, hls_ring:begin_insert(Modes)),
            {true, NextSamples} = hls_ring:insert_step(Sample, hls_ring:begin_insert(Samples)), true;
        false ->
            NextModes = hls_ring:replace(Mode, Modes),
            NextSamples = hls_ring:replace(Sample, Samples), true
    end,
    {active, S#cell{modes = NextModes, samples = NextSamples,
        observed = hls_ring:current(NextModes)}, consume}.
