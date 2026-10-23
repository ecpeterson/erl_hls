-module(hls_protocol_ingress_fixture).
-moduledoc "Finite host-input receiver: postpone the first work item, request real peer feedback, then accumulate ordered host values.".
-behaviour(hls_statem).
-compile({parse_transform,hls_pack}).
-export([init/1,boot/3,waiting/3,opening/3,running/3,topology/0]).
-hls_data(cell).
-hls_phases([boot,waiting,opening,running]).
-hls_outputs([monitor,peer]).
-hls_tags([open,work,receipt,ack,sample]).
-hls_mailbox_capacity(8).

%% State changes only at committed ordinary source actions.
-record(cell,{sum=hls_type:zero() :: hls_nums:u32()}).
%% Declared startup enables the waiting phase, not application completion.
-record(open,{key=hls_type:zero() :: hls_nums:u8()}).
%% All wire values are canonical; the running callback rejects values above seven.
-record(work,{n=hls_type:zero() :: hls_nums:u32()}).
%% A real third actor turns this request into a wake-up acknowledgment.
-record(receipt,{n=hls_type:zero() :: hls_nums:u32()}).
%% Fanout acknowledgments are harmless in waiting/running, and wake opening.
-record(ack,{n=hls_type:zero() :: hls_nums:u32()}).
%% Each committed running entry exposes the sum on its own stalled stream.
-record(sample,{n=hls_type:zero() :: hls_nums:u32()}).

-doc "Starts with no external work admitted until declared startup consumes.".
-spec init([]) -> {ok,boot,#cell{}}.
init([]) -> {ok,boot,#cell{}}.

-doc "Consumes the declared opening key before host input becomes enabled.".
-spec boot(enter,hls_statem:phase(),#cell{}) -> hls_statem:enter_result(#cell{});
    (cast,#open{},#cell{}) -> hls_statem:cast_result(#cell{}).
boot(enter,_,C) -> {C,[]};
boot(cast,#open{key=7},C) -> {waiting,C,consume}.

-doc "Postpones the first host work item while moving to a peer-controlled opening phase.".
-spec waiting(enter,hls_statem:phase(),#cell{}) -> hls_statem:enter_result(#cell{});
    (cast,#work{} | #ack{},#cell{}) -> hls_statem:cast_result(#cell{}).
waiting(enter,_,C) -> {C,[{cast,monitor,#sample{n=0}}]};
waiting(cast,#work{},C) -> {opening,C,postpone};
waiting(cast,#ack{},C) -> {waiting,C,consume}.

-doc "Publishes a real wake request, retaining host work until feedback changes phase.".
-spec opening(enter,hls_statem:phase(),#cell{}) -> hls_statem:enter_result(#cell{});
    (cast,#work{} | #ack{},#cell{}) -> hls_statem:cast_result(#cell{}).
opening(enter,_,C) -> {C,[{cast,peer,#receipt{n=0}}]};
opening(cast,#work{},C) -> {opening,C,postpone};
opening(cast,#ack{},C) -> {running,C,consume}.

-doc "Accumulates at most seven per host command, publishes the updated sum and rejects larger canonical values.".
-spec running(enter,hls_statem:phase(),#cell{}) -> hls_statem:enter_result(#cell{});
    (cast,#work{} | #ack{},#cell{}) -> hls_statem:cast_result(#cell{}).
running(enter,_,C) -> {C,[{cast,monitor,#sample{n=C#cell.sum}}]};
running(cast,#work{n=N},C) when N =< 7 -> {repeat_phase,C#cell{sum=C#cell.sum+N},consume};
running(cast,#work{},C) -> {running,C,fail};
running(cast,#ack{},C) -> {running,C,consume}.

-doc "Builds two independently consumed rectangle recipients plus a source feedback relay. The second target names only the first recipient.".
-spec topology() -> map().
topology() -> #{version=>1,actors=>#{a=>?MODULE,b=>?MODULE,relay=>hls_protocol_startup_peer},
    families=>#{},route_relations=>[],startup=>[{a,[#open{key=7}]},{b,[#open{key=7}]}],
    ingresses=>[{host,{rectangle,[3,2]},[
      {cells,[work],[{actor,a,{at,[0,0]}},{actor,b,{at,[2,1]}}]},
      {first,[work],[{actor,a,{at,[0,0]}}]}]}],
    externals=>[{monitor,out,[sample,ack]}],
    routes=>[{{a,monitor},[{external,monitor}]},{{b,monitor},[{external,monitor}]},
      {{a,peer},[{actor,relay}]},{{b,peer},[{actor,relay}]},
      {{relay,reply},buffered,[{actor,a},{actor,b},{external,monitor}]}]}.
