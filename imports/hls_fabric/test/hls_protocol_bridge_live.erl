-module(hls_protocol_bridge_live).
-moduledoc "Finite two-role public-port witness with the production brokers and bounded relay. No private RTL probes or cross-sender chronology.".
-export([run/3]).

-doc "Attaches two fresh fixture builds, forwards actual source packets with credits, checks 39 per-sender records and final arithmetic, then retires both brokers and awaits descriptor closure. Distinct sessions must follow fresh reset. Ordinary source callbacks supply producer records. This is a finite simulation witness, not general progress or device qualification.".
-spec run(file:filename(),file:filename(),pos_integer()) -> ok.
run(Build,Stage,Incarnation) ->
    Devices=maps:from_list([{R,read(filename:join([Build,"role"++integer_to_list(R),"bridge.etf"]))}||R<-[0,1]]),
    Plan=#{devices=>Devices,actors=>3,limits=>#{crossings=>8,commands=>16,events=>32}},
    Brokers=maps:from_list([begin P=filename:join(Stage,"role"++integer_to_list(R)),
        {ok,B}=hls_fabric:start_link(P++"_tx",P++"_rx",#{rx_route_limit=>1}),{R,B} end||R<-[0,1]]),
    {ok,Stream}=hls_protocol_stream:start_link(Plan,Brokers,#{0=>Incarnation*2+1,1=>Incarnation*2+2}),
    try
        {ok,1}=hls_protocol_stream:submit(Stream,start),
        Deadline=erlang:monotonic_time(millisecond)+45000,
        Frames=collect(Stream,#{0=>[],1=>[],2=>[]},false,Deadline),
        Expected=producer(),Expected=lists:reverse(maps:get(0,Frames)),Expected=lists:reverse(maps:get(1,Frames)),
        [A,B,C|Totals]=lists:reverse(maps:get(2,Frames)),[A,B,C]=lists:sublist(Expected,3),
        Values=[begin 16#05000001=F band 16#ffffffff,F bsr 32 end||F<-Totals],
        60=lists:last(Values),
        Deltas=lists:zipwith(fun(X,Y)->X-Y end,Values,[0|lists:droplast(Values)]),
        [0,0,0,0,0,0,3,3,4,4,5,5,5,5,6,6,7,7]=lists:sort(Deltas),
        %% A rectangle reaches both sparse host masks after their finite workload.
        Rectangle= <<0:16/little,0:16/little,1:16/little,0:16/little,0:32,16#05000001:32/little,0:32>>,
        {ok,1}=hls_protocol_stream:submit(Stream,{control,Rectangle}),
        ok=drained(Stream,Deadline),timeout=hls_protocol_stream:next(Stream,20),
        Info=hls_protocol_stream:info(Stream),
        #{packets:=#{forwarded:=27,acknowledged:=27}}=Info,
        Leases=[begin #{io:=#{lease:=L}}=hls_fabric:info(P),L end||P<-maps:values(Brokers)],
        ok=hls_protocol_stream:stop(Stream),[ok=hls_fabric:stop(P)||P<-maps:values(Brokers)],
        ok=file:write_file(filename:join(Stage,"done"),<<>>,[exclusive]),
        [ok=hls_fabric:await_closed(L,5000)||L<-Leases],
        ok=file:write_file(filename:join(Stage,"result.json"),json:encode(#{passed=>true,frames=>39,
            total=>60,forwarded=>27,descriptors_closed=>true,stream=>Info}),[exclusive])
    after catch hls_protocol_stream:stop(Stream),[catch hls_fabric:stop(P)||P<-maps:values(Brokers)] end.

%% The first notification must acknowledge both actual source starts.
-spec collect(pid(),map(),boolean(),integer()) -> map().
collect(_,Frames,true,_) when map_get(0,Frames)=/=[] andalso length(map_get(0,Frames))=:=9,
        length(map_get(1,Frames))=:=9,length(map_get(2,Frames))=:=21 -> Frames;
collect(Stream,Frames,Started,Deadline) ->
    Left=Deadline-erlang:monotonic_time(millisecond),true=Left>0,
    case hls_protocol_stream:next(Stream,Left) of
        {ok,application,{started}} when not Started->collect(Stream,Frames,true,Deadline);
        {ok,{Role,I},Frame} when Started->
            true=(Role=:=0 andalso (I=:=0 orelse I=:=2)) orelse (Role=:=1 andalso I=:=1),
            Previous=maps:get(I,Frames),true=length(Previous)<case I of 2->21;_->9 end,
            collect(Stream,Frames#{I:=[Frame|Previous]},true,Deadline)
    end.

%% Source callbacks, not generated hardware, define each producer's ordered batches.
-spec producer() -> [non_neg_integer()].
producer() ->
    M=hls_protocol_network_fixture,{ok,sending,C}=M:init([]),
    {Records,_}=lists:foldl(fun(_, {Acc,Cell})->
        {_,Actions}=M:sending(enter,sending,Cell),
        Messages=[R||{cast,_,R}<-Actions],
        Next=case M:sending(cast,{total,0},Cell) of {_,New,consume}->New end,
        {Acc++Messages,Next}
    end,{[],C},lists:seq(1,3)),
    [begin Tag=element(1,R),Width=M:pack_width(Tag),
        Payload=binary:decode_unsigned(hls_codec:pad_to(M:pack(R),96),little),
        (Payload bsl 32) bor (M:pack_tag(Tag) bsl 24) bor ((Width+31) div 32) end||R<-Records].

%% No retained crossing or command may be abandoned by successful retirement.
-spec drained(pid(),integer()) -> ok.
drained(Stream,Deadline) ->
    true=erlang:monotonic_time(millisecond)<Deadline,
    case hls_protocol_stream:info(Stream) of
        #{counts:=#{crossings:=0,commands:=0,held:=0,writer:=0}}->ok;
        _->timer:sleep(5),drained(Stream,Deadline)
    end.

%% Only trusted local build descriptors are decoded, never network terms.
-spec read(file:filename()) -> map().
read(Path) -> {ok,B}=file:read_file(Path),binary_to_term(B).
