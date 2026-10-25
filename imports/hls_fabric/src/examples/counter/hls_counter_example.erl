-module(hls_counter_example).
-moduledoc "Two independently addressed counters for the public backend build walkthrough. The same actor source and topology exercise source-protocol and channel-scheduler placement.".
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, counting/3, topology/0]).
-hls_data(counter).
-hls_phases([counting]).
-hls_outputs([out]).
-hls_tags([increment, total]).
-hls_mailbox_capacity(2).

%% Each actor owns its accumulated unsigned total.
-record(counter, {value = hls_type:zero() :: hls_nums:u32()}).
%% Host ingress addresses one counter or broadcasts the same increment to both.
-record(increment, {amount = hls_type:zero() :: hls_nums:u32()}).
%% Each external endpoint reports its counter's total after an accepted increment.
-record(total, {value = hls_type:zero() :: hls_nums:u32()}).

-doc "Initializes a zero counter; its first entry publishes that initial value.".
-spec init([]) -> {ok, counting, #counter{}}.
init([]) -> {ok, counting, #counter{}}.

-doc "Publishes the retained total on entry. Each increment is consumed and requests another entry after addition modulo 2^32, matching the fixed-width hardware state.".
-spec counting(enter, hls_statem:phase(), #counter{}) -> hls_statem:enter_result(#counter{});
    (cast, #increment{}, #counter{}) -> hls_statem:cast_result(#counter{}).
counting(enter, _, Counter) -> {Counter, [{cast, out, #total{value = Counter#counter.value}}]};
counting(cast, #increment{amount = Amount}, Counter) ->
    Value = (Counter#counter.value + Amount) band ((1 bsl 32) - 1),
    {repeat_phase, Counter#counter{value = Value}, consume}.

-doc "Declares two ordinary actors, one rectangular host ingress and one output per actor. Placement and clock schedules belong to the build configuration, not this logical graph.".
-spec topology() -> hls_topology:spec().
topology() ->
    #{version => 1, actors => #{left => ?MODULE, right => ?MODULE}, families => #{},
      startup => [], route_relations => [],
      ingresses => [{host, {rectangle, [2, 1]}, [{counters, [increment],
          [{actor, left, {at, [0, 0]}}, {actor, right, {at, [1, 0]}}]}]}],
      externals => [{left_total, out, [total]}, {right_total, out, [total]}],
      routes => [{{left, out}, [{external, left_total}]},
          {{right, out}, [{external, right_total}]}]}.
