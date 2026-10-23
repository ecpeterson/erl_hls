-module(hls_protocol_boundary_fixture).
-moduledoc "Finite identified producer batches exercise shared, singleton and unused external endpoints.".
-behaviour(hls_statem).
-compile({parse_transform,hls_pack}).
-export([init/1,boot/3,sending/3,topology/0,expected/0]).
-hls_data(cell).
-hls_phases([boot,sending]).
-hls_outputs([monitor]).
-hls_tags([cfg,work,sample]).
-hls_mailbox_capacity(4).

%% Identifiers make each producer's order visible through a merged endpoint.
-record(cell,{id=hls_type:zero() :: hls_nums:u32(),base=hls_type:zero() :: hls_nums:u32()}).
%% Configuration assigns an identifier; two producers are configured through host input.
-record(cfg,{id=hls_type:zero() :: hls_nums:u32()}).
%% A later broadcast requests another source-ordered batch.
-record(work,{base=hls_type:zero() :: hls_nums:u32()}).
%% Every ordinary frame names its logical producer and position within the batch.
-record(sample,{id=hls_type:zero() :: hls_nums:u32(),seq=hls_type:zero() :: hls_nums:u32()}).

-doc "Waits for declared or host-supplied configuration without publishing.".
-spec init([]) -> {ok,boot,#cell{}}.
init([]) -> {ok,boot,#cell{}}.

-doc "Consumes configuration and starts the first frame.".
-spec boot(enter,hls_statem:phase(),#cell{}) -> hls_statem:enter_result(#cell{});
    (cast,#cfg{},#cell{}) -> hls_statem:cast_result(#cell{}).
boot(enter,_,C) -> {C,[]};
boot(cast,#cfg{id=Id},C) -> {sending,C#cell{id=Id},consume}.

-doc "Publishes one identifiable frame per entry; each host work command changes its sequence.".
-spec sending(enter,hls_statem:phase(),#cell{}) -> hls_statem:enter_result(#cell{});
    (cast,#work{},#cell{}) -> hls_statem:cast_result(#cell{}).
sending(enter,_,C) -> {C,[{cast,monitor,#sample{id=C#cell.id,seq=C#cell.base}}]};
sending(cast,#work{base=N},C) -> {repeat_phase,C#cell{base=N},consume}.

-doc "Declares three shared producers, one independent singleton and one unused endpoint. The third producer arrives first so later low-index arrivals must not replace its stalled frame.".
-spec topology() -> map().
topology() -> #{version=>1,actors=>maps:from_list([{Id,?MODULE}||Id<-[a,b,c,d]]),families=>#{},route_relations=>[],
    startup=>[{c,[#cfg{id=3}]},{d,[#cfg{id=4}]}],
    ingresses=>[{host,{rectangle,[4,1]},[{cells,[cfg,work],[{actor,Id,{at,[I,0]}}||{I,Id}<-lists:enumerate(0,[a,b,c,d])]}]}],
    externals=>[{shared,out,[sample]},{single,out,[sample]},{unused,out,[sample]}],
    routes=>[{{Id,monitor},[{external,case Id of d->single;_->shared end}]}||Id<-[a,b,c,d]]}.

-doc "Evaluates the ordinary callbacks and encodes their per-producer frames for the finite RTL scoreboard. The actor bit codec interprets packed payload bytes little-endian; no generated DSLX is used.".
-spec expected() -> [[binary()]].
expected() -> [[begin
    {ok,boot,C0}=init([]),{sending,C1,consume}=boot(cast,#cfg{id=Id},C0),
    {repeat_phase,C2,consume}=sending(cast,#work{base=Seq},C1),
    {_,[{cast,monitor,Message}]}=sending(enter,boot,C2),
    P=binary:decode_unsigned(hls_codec:align(pack(Message),96),little),
    Frame=(P bsl 32) bor (pack_tag(sample) bsl 24) bor 2,
    binary:encode_hex(<<Frame:128>>,lowercase) end||Seq<-[0,1,2,10,11,12]]||Id<-lists:seq(1,4)].
