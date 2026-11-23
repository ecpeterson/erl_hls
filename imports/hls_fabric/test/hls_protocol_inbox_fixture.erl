-module(hls_protocol_inbox_fixture).
-moduledoc "Two sender histories offer early values, an opening message and later values to one source actor.".
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, waiting/3, running/3, topology/0]).
-hls_data(cell).
-hls_phases([waiting, running]).
-hls_outputs([early, open, later, result]).
-hls_tags([value, go, total]).
-hls_mailbox_capacity(8).

%% The committed sum is observable through ordinary entry effects.
-record(cell, {sum = hls_type:zero() :: hls_nums:u32()}).
%% Independent ports share this schema and the sender's delivery history.
-record(value, {value = hls_type:zero() :: hls_nums:u32()}).
%% A source-literal field exercises compact-to-ordinary reconstruction.
-record(go, {key = hls_type:zero() :: hls_nums:u8()}).
%% Each accepted value publishes the updated sum.
-record(total, {value = hls_type:zero() :: hls_nums:u32()}).

-doc "Starts with zero accumulated values and a source-ordered initial batch.".
-spec init([]) -> {ok, waiting, #cell{}}.
init([]) -> {ok, waiting, #cell{}}.

-doc "Publishes the finite sender batch; early values postpone until the opening message.".
-spec waiting(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #value{} | #go{}, #cell{}) -> hls_statem:cast_result(#cell{}).
waiting(enter, _, C) -> {C, [{cast, early, #value{value = C#cell.sum + 3}},
    {cast, open, #go{key = 7}}, {cast, later, #value{value = C#cell.sum + 5}}]};
waiting(cast, #value{}, C) -> {waiting, C, postpone};
waiting(cast, #go{key = 7}, C) -> {running, C, consume}.

-doc "Publishes every sum; repeated openings are accepted, and oversized values fail.".
-spec running(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #value{} | #go{}, #cell{}) -> hls_statem:cast_result(#cell{}).
running(enter, _, C) -> {C, [{cast, result, #total{value = C#cell.sum}}]};
running(cast, #value{value = V}, C) when V =< 7 -> {repeat_phase, C#cell{sum = C#cell.sum + V}, consume};
running(cast, #value{}, C) -> {running, C, fail};
running(cast, #go{key = 7}, C) -> {repeat_phase, C, consume}.

-doc "Binds two independent sender pairs to one sink; all other publications are external.".
-spec topology() -> map().
topology() ->
    Ids = [left, right, sink],
    #{version => 1, actors => maps:from_list([{I, ?MODULE} || I <- Ids]),
      families => #{}, ingresses => [], route_relations => [], startup => [],
      externals => [{monitor, out, [value, go, total]}],
      routes => [{{I, P}, [case I =/= sink andalso P =/= result of
          true -> {actor, sink}; false -> {external, monitor} end]}
          || I <- Ids, P <- [early, open, later, result]]}.
