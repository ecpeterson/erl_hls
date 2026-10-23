-module(hls_protocol_network_fixture).
-moduledoc "Finite feedback producer: three source-ordered batches, triggered by the sink's ordinary result messages.".
-behaviour(hls_statem).
-compile({parse_transform,hls_pack}).
-export([init/1, sending/3, topology/0, unsupported/1, isolated/0]).
-hls_data(cell).
-hls_phases([sending]).
-hls_outputs([early,open,later]).
-hls_tags([value,go,total]).
-hls_mailbox_capacity(8).

%% The two producer instances own separate feedback counters.
-record(cell,{round=hls_type:zero() :: hls_nums:u32()}).
%% Wire schemas intentionally agree with the independently compiled sink fixture.
-record(value,{value=hls_type:zero() :: hls_nums:u32()}).
%% The opening key is a source-proved literal on every send.
-record(go,{key=hls_type:zero() :: hls_nums:u8()}).
%% Sink totals drive source progress without any testbench-generated publication.
-record(total,{value=hls_type:zero() :: hls_nums:u32()}).

-doc "Starts the first source entry without a startup message or host input.".
-spec init([]) -> {ok,sending,#cell{}}.
init([]) -> {ok,sending,#cell{}}.

-doc "Publishes three ordered messages; the first two feedback receipts request another batch. Later receipts consume without publication.".
-spec sending(enter,hls_statem:phase(),#cell{}) -> hls_statem:enter_result(#cell{});
    (cast,#total{},#cell{}) -> hls_statem:cast_result(#cell{}).
sending(enter,_,C) -> {C,[{cast,early,#value{value=3+C#cell.round}},
    {cast,open,#go{key=7}},{cast,later,#value{value=5+C#cell.round}}]};
sending(cast,#total{},C) when C#cell.round < 2 -> {repeat_phase,C#cell{round=C#cell.round+1},consume};
sending(cast,#total{},C) -> {sending,C,consume}.

-doc "Two producers multicast to an external observer and a sink; sink results feed both producers and its separate observer.".
-spec topology() -> map().
topology() ->
    #{version=>1,actors=>#{left=>?MODULE,right=>?MODULE,sink=>hls_protocol_inbox_fixture},
      families=>#{},ingresses=>[],route_relations=>[],startup=>[],
      externals=>[{monitor,out,[value,go,total]}],
      routes=>[{{I,P},buffered,[{actor,sink},{external,monitor}]}||I<-[left,right],P<-[early,open,later]]++
        [case P of result->{{sink,P},buffered,[{actor,left},{actor,right},{external,monitor}]};
            _->{{sink,P},[{external,monitor}]} end||P<-[early,open,later,result]]}.

-doc "Marks unsupported boundary requirements so the complete-network command must reject them.".
-spec unsupported(startup | ingresses) -> map().
unsupported(startup) -> (topology())#{startup:=[{left,[#total{}]}]};
unsupported(ingresses) -> (topology())#{ingresses:=[{Name,{rectangle,[1,1]},[{all,[total],[{actor,left,{at,[0,0]}}]}]}||Name<-[host,other]]}.

-doc "A single source with no incoming links still initializes and publishes once.".
-spec isolated() -> map().
isolated() -> (topology())#{actors:=#{left=>?MODULE},
    routes:=[{{left,P},[{external,monitor}]}||P<-[early,open,later]]}.
