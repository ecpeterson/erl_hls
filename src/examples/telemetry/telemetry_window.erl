-module(telemetry_window).
-moduledoc """
Summarizes nonoverlapping windows of four calibrated readings. Each report
contains the last sample's sequence label, signed sum, minimum, maximum and
number of saturated samples. A partial final window produces no report.

The fourth input enters a reporting phase whose publication may stall. Its
private advance clears the completed window only after publication commits,
so subsequent readings cannot overwrite the retained report.
""".
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).

%% Ordinary actor initialization and phase callbacks.
-export([init/1, collecting/3, reporting/3]).

-hls_data(state).
-hls_phases([collecting, reporting]).
-hls_outputs([report]).
-hls_mailbox_capacity(4).
-hls_continuations([advance]).

-include("telemetry.hrl").

%% The current partial window, or the completed window awaiting publication.
-record(state, {
    count = hls_type:zero() :: hls_nums:uN(3),
    sequence = hls_type:zero() :: hls_nums:u16(),
    sum = hls_type:zero() :: hls_nums:s32(),
    minimum = hls_type:zero() :: hls_nums:s16(),
    maximum = hls_type:zero() :: hls_nums:s16(),
    clipped = hls_type:zero() :: hls_nums:uN(3)
}).

-doc "Starts with an empty window and no emitted effects.".
-spec init([]) -> {ok, collecting, #state{}}.
init([]) -> {ok, collecting, #state{}}.

-doc "Accumulates one reading; the fourth schedules report publication and private advance.".
-spec collecting
    (enter, hls_statem:phase(), #state{}) -> hls_statem:enter_result(#state{});
    (cast, #reading{}, #state{}) -> hls_statem:cast_result(#state{}).
collecting(enter, _, State) ->
    {State, []};
%% Count accepted readings; a complete group becomes one retained report.
collecting(cast, Reading = #reading{}, State) ->
    Next = accumulate(Reading, State),
    case Next#state.count of
        4 ->
            {reporting, Next, consume, [{next_event, internal, advance}]};
        _ ->
            {collecting, Next, consume}
    end.

-doc "Publishes the complete window before clearing it and retrying later readings.".
-spec reporting
    (enter, hls_statem:phase(), #state{}) -> hls_statem:enter_result(#state{});
    (internal, advance, #state{}) -> hls_statem:internal_result(#state{});
    (cast, #reading{}, #state{}) -> hls_statem:cast_result(#state{}).
reporting(enter, _, State) ->
    Report = #summary{
        sequence = State#state.sequence,
        sum = State#state.sum,
        minimum = State#state.minimum,
        maximum = State#state.maximum,
        clipped = State#state.clipped
    },
    {State, [{cast, report, Report}]};
reporting(internal, advance, _State) ->
    {collecting, #state{}, consume};
%% Readings for the next window wait until publication and private advance.
reporting(cast, #reading{}, State) ->
    {reporting, State, postpone}.

%% The first reading initializes both extrema; four signed16 values fit signed32.
%% The clipped counter counts saturation events rather than saturated values.
-spec accumulate(#reading{}, #state{}) -> #state{}.
accumulate(#reading{sequence = Sequence, value = Value, clipped = Clipped}, State) ->
    Minimum =
        if
            State#state.count =:= 0 -> Value;
            Value < State#state.minimum -> Value;
            true -> State#state.minimum
        end,
    Maximum =
        if
            State#state.count =:= 0 -> Value;
            Value > State#state.maximum -> Value;
            true -> State#state.maximum
        end,
    Clip =
        case Clipped of
            true -> 1;
            false -> 0
        end,
    State#state{
        count = State#state.count + 1,
        sequence = Sequence,
        sum = State#state.sum + hls_type:as(hls_nums:s32(), Value),
        minimum = Minimum,
        maximum = Maximum,
        clipped = State#state.clipped + Clip
    }.
