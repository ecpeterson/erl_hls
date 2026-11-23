-module(telemetry_calibrator).
-moduledoc """
Applies configured gain and offset to signed telemetry samples, saturating each
result to signed 16 bits. Raw samples received before the first configuration
remain postponed in the bounded mailbox. Later configuration changes affect
subsequently selected samples; they do not restart the downstream window.

Publication retains its reading until the output accepts it. A private advance
then returns to ready before selecting later input, without needing a free
mailbox slot for a message to this actor.
""".
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).

%% Ordinary actor initialization and phase callbacks.
-export([init/1, configuring/3, ready/3, publishing/3]).

-hls_data(state).
-hls_phases([configuring, ready, publishing]).
-hls_outputs([readings]).
-hls_mailbox_capacity(4).
-hls_continuations([advance]).

-include("telemetry.hrl").

%% Configuration and the one reading whose ordered publication is pending.
-record(state, {
    offset = hls_type:zero() :: hls_nums:s16(),
    gain = hls_type:zero() :: hls_nums:u8(),
    sequence = hls_type:zero() :: hls_nums:u16(),
    value = hls_type:zero() :: hls_nums:s16(),
    clipped = hls_type:zero() :: hls_bool:bool()
}).

-doc "Starts without a configuration; no entry effects are emitted.".
-spec init([]) -> {ok, configuring, #state{}}.
init([]) -> {ok, configuring, #state{}}.

-doc "Retains early samples until configuration changes phase and releases them.".
-spec configuring
    (enter, hls_statem:phase(), #state{}) -> hls_statem:enter_result(#state{});
    (cast, #configure{} | #raw{}, #state{}) -> hls_statem:cast_result(#state{}).
configuring(enter, _, State) ->
    {State, []};
%% Retained samples wait for the phase boundary created by configuration.
configuring(cast, #raw{}, State) ->
    {configuring, State, postpone};
%% The first configuration releases earlier samples without discarding them.
configuring(cast, #configure{offset = Offset, gain = Gain}, State) ->
    {ready, State#state{offset = Offset, gain = Gain}, consume}.

-doc "Updates calibration or computes one reading before entering publication.".
-spec ready
    (enter, hls_statem:phase(), #state{}) -> hls_statem:enter_result(#state{});
    (cast, #configure{} | #raw{}, #state{}) -> hls_statem:cast_result(#state{}).
ready(enter, _, State) ->
    {State, []};
%% Reconfiguration affects subsequent inputs, including a partial window.
ready(cast, #configure{offset = Offset, gain = Gain}, State) ->
    {ready, State#state{offset = Offset, gain = Gain}, consume};
%% Save the complete calibrated reading before any output can become visible.
ready(cast, Sample = #raw{}, State) ->
    Reading = calibrate(Sample, State#state.gain, State#state.offset),
    Next = State#state{
        sequence = Reading#reading.sequence,
        value = Reading#reading.value,
        clipped = Reading#reading.clipped
    },
    {publishing, Next, consume, [{next_event, internal, advance}]}.

-doc "Publishes the saved reading before the private continuation releases later input.".
-spec publishing
    (enter, hls_statem:phase(), #state{}) -> hls_statem:enter_result(#state{});
    (internal, advance, #state{}) -> hls_statem:internal_result(#state{});
    (cast, #configure{} | #raw{}, #state{}) -> hls_statem:cast_result(#state{}).
publishing(enter, _, State) ->
    Reading = #reading{
        sequence = State#state.sequence,
        value = State#state.value,
        clipped = State#state.clipped
    },
    {State, [{cast, readings, Reading}]};
publishing(internal, advance, State) ->
    {ready, State, consume};
%% A pending publication retains the calibration under which it was computed.
publishing(cast, #configure{}, State) ->
    {publishing, State, postpone};
%% Later samples cannot replace the saved output before private advance.
publishing(cast, #raw{}, State) ->
    {publishing, State, postpone}.

%% Widen before multiplication: signed16 * unsigned8 + signed16 fits signed32.
%% Saturation is explicit, so CPU arbitrary-precision arithmetic and XLS agree.
-spec calibrate(#raw{}, hls_nums:u8(), hls_nums:s16()) -> #reading{}.
calibrate(#raw{sequence = Sequence, value = Value}, Gain, Offset) ->
    Scaled =
        hls_type:as(hls_nums:s32(), Value) * hls_type:as(hls_nums:s32(), Gain) +
            hls_type:as(hls_nums:s32(), Offset),
    Minimum = hls_type:as(hls_nums:s32(), -(1 bsl 15)),
    Maximum = hls_type:as(hls_nums:s32(), (1 bsl 15) - 1),
    if
        Scaled < Minimum ->
            #reading{
                sequence = Sequence, value = hls_type:as(hls_nums:s16(), Minimum), clipped = true
            };
        Scaled > Maximum ->
            #reading{
                sequence = Sequence, value = hls_type:as(hls_nums:s16(), Maximum), clipped = true
            };
        true ->
            #reading{
                sequence = Sequence,
                value = hls_type:as(hls_nums:s16(), Scaled),
                clipped = false
            }
    end.
