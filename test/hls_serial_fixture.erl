-module(hls_serial_fixture).
-moduledoc "A wrapping step service used to compare BEAM and stalled RTL.".
-behaviour(hls_gs).
-compile({parse_transform, hls_pack}).
-export([init/1, handle_call/2, handle_cast/2]).

-hls_data(clock).
-hls_tags([advance, inspect, load, report]).
-hls_replies([{advance, [report]}, {inspect, [report]}]).
-record(clock, {step = hls_type:zero() :: hls_serial:counter(32)}).
-record(advance, {offset = hls_type:zero() :: hls_nums:s32()}).
-record(inspect, {other = hls_type:zero() :: hls_serial:counter(32),
    check = hls_type:zero() :: hls_bool:bool()}).
-record(load, {step = hls_type:zero() :: hls_serial:counter(32)}).
-record(report, {step = hls_type:zero() :: hls_serial:counter(32),
    delta = hls_type:zero() :: hls_nums:s32(),
    earlier = hls_type:zero() :: hls_bool:bool()}).

-doc "Starts two steps before rollover.".
-spec init([]) -> #clock{}.
init([]) -> #clock{step = hls_serial:wrap(hls_serial:counter(32), -2)}.

-doc "Advances the counter or compares it with another nearby counter.".
-spec handle_call(#advance{} | #inspect{}, #clock{}) -> {reply, #report{}, #clock{}}.
%% Advance by a signed offset and return the normalized state.
handle_call(#advance{offset = Offset}, Clock = #clock{step = Step}) ->
    Next = hls_serial:add(hls_serial:counter(32), Step, Offset),
    {reply, #report{step = Next, delta = Offset}, Clock#clock{step = Next}};
%% A skipped comparison must not fail, even if its operands are antipodal.
handle_call(#inspect{other = Other, check = Check}, Clock = #clock{step = Step}) ->
    {Delta, Earlier} = case Check of
        true -> {hls_serial:difference(hls_serial:counter(32), Step, Other),
            hls_serial:before(hls_serial:counter(32), Step, Other)};
        false -> {hls_type:as(hls_nums:s32(), 0), false}
    end,
    {reply, #report{step = Step, delta = Delta, earlier = Earlier}, Clock}.

-doc "Loads a counter through its public codec.".
-spec handle_cast(#load{}, #clock{}) -> {noreply, #clock{}}.
%% Set the reference point before another rollover or ambiguity scenario.
handle_cast(#load{step = Step}, Clock) -> {noreply, Clock#clock{step = Step}}.
