-module(hls_protocol_activation_fixture).
-moduledoc "Finite setup-before-start witness: host configuration is consumed before queued peer messages may run.".
-behaviour(hls_statem).
-compile({parse_transform,hls_pack}).
-export([init/1,boot/3,configured/3,running/3,topology/0]).
-hls_data(cell).
-hls_phases([boot,configured,running]).
-hls_outputs([monitor,peer]).
-hls_tags([open,work,receipt,ack,sample]).
-hls_mailbox_capacity(8).

%% The configured sum is observed by later internal feedback.
-record(cell,{sum=hls_type:zero() :: hls_nums:u32()}).
%% Declared startup permits setup, but must not consume internal feedback yet.
-record(open,{key=hls_type:zero() :: hls_nums:u8()}).
%% All wire values are canonical; source rejects values above seven.
-record(work,{n=hls_type:zero() :: hls_nums:u32()}).
%% Startup publishes one request before activation.
-record(receipt,{n=hls_type:zero() :: hls_nums:u32()}).
%% Two real relay acknowledgments wake each configured actor after start.
-record(ack,{n=hls_type:zero() :: hls_nums:u32()}).
%% Monitor outputs distinguish setup from running accumulation.
-record(sample,{n=hls_type:zero() :: hls_nums:u32()}).

-doc "Starts waiting for the declared configuration record.".
-spec init([]) -> {ok,boot,#cell{}}.
init([]) -> {ok,boot,#cell{}}.

-doc "Consumes the opening key and publishes a peer request on entry to configured.".
-spec boot(enter,hls_statem:phase(),#cell{}) -> hls_statem:enter_result(#cell{});
    (cast,#open{},#cell{}) -> hls_statem:cast_result(#cell{}).
boot(enter,_,C) -> {C,[]};
boot(cast,#open{key=7},C) -> {configured,C,consume}.

-doc "Accepts host setup without internal feedback, except seven deliberately postpones. The first acknowledgment starts visible accumulation.".
-spec configured(enter,hls_statem:phase(),#cell{}) -> hls_statem:enter_result(#cell{});
    (cast,#work{} | #ack{},#cell{}) -> hls_statem:cast_result(#cell{}).
configured(enter,_,C) -> {C,[{cast,monitor,#sample{n=0}},{cast,peer,#receipt{n=1}}]};
configured(cast,#work{n=7},C) -> {configured,C,postpone};
configured(cast,#work{n=N},C) when N =< 7 -> {configured,C#cell{sum=N},consume};
configured(cast,#work{},C) -> {configured,C,fail};
configured(cast,#ack{n=N},C) -> {running,C#cell{sum=C#cell.sum+N},consume}.

-doc "Publishes each subsequent acknowledgment or host addition in source order.".
-spec running(enter,hls_statem:phase(),#cell{}) -> hls_statem:enter_result(#cell{});
    (cast,#work{} | #ack{},#cell{}) -> hls_statem:cast_result(#cell{}).
running(enter,_,C) -> {C,[{cast,monitor,#sample{n=C#cell.sum}}]};
running(cast,#work{n=N},C) when N =< 7 -> {repeat_phase,C#cell{sum=C#cell.sum+N},consume};
running(cast,#work{},C) -> {running,C,fail};
running(cast,#ack{n=N},C) -> {repeat_phase,C#cell{sum=C#cell.sum+N},consume}.

-doc "Builds two independently stalled setup recipients and an ordinary source relay.".
-spec topology() -> map().
topology() -> #{version=>1,actors=>#{a=>?MODULE,b=>?MODULE,relay=>hls_protocol_startup_peer},
    families=>#{},route_relations=>[],startup=>[{a,[#open{key=7}]},{b,[#open{key=7}]}],
    ingresses=>[{host,{rectangle,[2,1]},[
      {cells,[work],[{actor,a,{at,[0,0]}},{actor,b,{at,[1,0]}}]}]}],
    externals=>[{monitor,out,[sample,ack]}],
    routes=>[{{a,monitor},[{external,monitor}]},{{b,monitor},[{external,monitor}]},
      {{a,peer},[{actor,relay}]},{{b,peer},[{actor,relay}]},
      {{relay,reply},buffered,[{actor,a},{actor,b},{external,monitor}]}]}.
