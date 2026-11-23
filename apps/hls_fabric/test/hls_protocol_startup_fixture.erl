-module(hls_protocol_startup_fixture).
-moduledoc "Finite startup receiver: postpone a value, consume ordered duplicate records, then await four peer acknowledgments.".
-behaviour(hls_statem).
-compile({parse_transform,hls_pack}).
-export([init/1, waiting/3, running/3, finished/3, topology/0, failing/0]).
-hls_data(cell).
-hls_phases([waiting,running,finished]).
-hls_outputs([monitor,peer]).
-hls_tags([value,open,receipt,ack,sample,done]).
-hls_mailbox_capacity(8).

%% Source state records only committed data and feedback, independent of clock stalls.
-record(cell,{sum=hls_type:zero() :: hls_nums:u32(),acks=hls_type:zero() :: hls_nums:u32()}).
%% Startup values include identical records that must retain separate ownership.
-record(value,{n=hls_type:zero() :: hls_nums:u32()}).
%% A later startup record enables the postponed first value.
-record(open,{key=hls_type:zero() :: hls_nums:u8()}).
%% Each running entry asks the peer to acknowledge this cumulative sum.
-record(receipt,{n=hls_type:zero() :: hls_nums:u32()}).
%% Peer responses exercise ordinary dynamic capture alongside static startup slots.
-record(ack,{n=hls_type:zero() :: hls_nums:u32()}).
%% Observable entry output gives an independent source-order arithmetic scoreboard.
-record(sample,{n=hls_type:zero() :: hls_nums:u32()}).
%% Completion requires actual peer traffic, not just a startup mask.
-record(done,{sum=hls_type:zero() :: hls_nums:u32(),acks=hls_type:zero() :: hls_nums:u32()}).

-doc "Starts in the phase that postpones values until the opening record arrives.".
-spec init([]) -> {ok,waiting,#cell{}}.
init([]) -> {ok,waiting,#cell{}}.

-doc "Emits an initial marker, postpones early values and opens only on key seven.".
-spec waiting(enter,hls_statem:phase(),#cell{}) -> hls_statem:enter_result(#cell{});
    (cast,#value{} | #open{},#cell{}) -> hls_statem:cast_result(#cell{}).
waiting(enter,_,C) -> {C,[{cast,monitor,#sample{n=0}}]};
waiting(cast,#value{},C) -> {waiting,C,postpone};
waiting(cast,#open{key=7},C) -> {running,C,consume}.

-doc "Publishes each updated sum, counts peer acknowledgments and fails on a value above seven.".
-spec running(enter,hls_statem:phase(),#cell{}) -> hls_statem:enter_result(#cell{});
    (cast,#value{} | #ack{},#cell{}) -> hls_statem:cast_result(#cell{}).
running(enter,_,C) -> {C,[{cast,monitor,#sample{n=C#cell.sum}},{cast,peer,#receipt{n=C#cell.sum}}]};
running(cast,#value{n=V},C) when V =< 7 -> {repeat_phase,C#cell{sum=C#cell.sum+V},consume};
running(cast,#value{},C) -> {running,C,fail};
running(cast,#ack{},C) when C#cell.acks =:= 3 -> {finished,C#cell{acks=4},consume};
running(cast,#ack{},C) -> {running,C#cell{acks=C#cell.acks+1},consume}.

-doc "Publishes the final sum and the number of real peer acknowledgments.".
-spec finished(enter,hls_statem:phase(),#cell{}) -> hls_statem:enter_result(#cell{}).
finished(enter,_,C) -> {C,[{cast,monitor,#done{sum=C#cell.sum,acks=C#cell.acks}}]}.

-doc "Builds two actors with one ordered startup sender and independently stalled external streams.".
-spec topology() -> map().
topology() -> #{version=>1,actors=>#{receiver=>?MODULE,relay=>hls_protocol_startup_peer},
    families=>#{},ingresses=>[],route_relations=>[],
    startup=>[{receiver,[#value{n=2},#open{key=7},#value{n=3},#value{n=3}]}],
    externals=>[{monitor,out,[sample,done,ack]}],
    routes=>[{{receiver,monitor},[{external,monitor}]},{{receiver,peer},[{actor,relay}]},
      {{relay,reply},buffered,[{actor,receiver},{external,monitor}]}]}.

-doc "Includes a canonical but source-invalid value; it must fail without retiring that record.".
-spec failing() -> map().
failing() -> (topology())#{startup:=[{receiver,[#open{key=7},#value{n=9}]}]}.
