-module(hls_protocol_relay_tests).
-moduledoc "Bounded relay rejection and physical-completion ownership tests; these do not model a device.".
-include_lib("eunit/include/eunit.hrl").

%% A pair head waits for credit; its source reservation spans two definite writes.
-spec ownership_test() -> ok.
ownership_test() ->
    Q=new(),P=packet(1,11,0,0),Q1=hls_protocol_relay_queue:event(0,P,Q),
    none=hls_protocol_relay_queue:next(Q1),
    Q2=hls_protocol_relay_queue:event(1,packet(2,12,0,0),Q1),
    {1,#{session:=12,sequence:=0,frame:=0},{data,0,0}=T,Q3}=hls_protocol_relay_queue:next(Q2),
    none=hls_protocol_relay_queue:next(Q3),
    Q4=hls_protocol_relay_queue:complete(T,Q3),
    {0,#{session:=11,sequence:=0,kind:=2},{ack,0,0}=A,Q5}=hls_protocol_relay_queue:next(Q4),
    #{records:=1}=hls_protocol_relay_queue:info(Q5),
    #{records:=0,forwarded:=1,acknowledged:=1}=hls_protocol_relay_queue:info(hls_protocol_relay_queue:complete(A,Q5)).

%% Stale/duplicate sequence, wrong endpoint, noncanonical payload and duplicate grants reject.
-spec rejection_test() -> ok.
rejection_test() ->
    Q=new(),
    lists:foreach(fun({R,P})->?assertException(error,_,hls_protocol_relay_queue:event(R,P,Q)) end,
        [{0,packet(1,99,0,0)},{0,packet(1,11,1,0)},{1,packet(1,12,0,0)},
         {0,(packet(1,11,0,0))#{frame:=1}},{0,(packet(1,11,0,0))#{slot:=1}}]),
    G=hls_protocol_relay_queue:event(1,packet(2,12,0,0),Q),
    ?assertException(error,_,hls_protocol_relay_queue:event(1,packet(2,12,1,0),G)),
    ?assertException(error,_,hls_protocol_relay_queue:next(hls_protocol_relay_queue:invalidate(Q))),ok.

%% ABI round trips preserve all packet fields and distinguish attach/start from actor traffic.
-spec wire_test() -> ok.
wire_test() ->
    Identity= <<42:256>>,{{1,0,0},<<11:64/little,Identity/binary>>}=hls_protocol_bridge_wire:attach(Identity,11),
    {{3,0,0},<<11:64/little,0:32>>}=hls_protocol_bridge_wire:command(11,start),
    P=packet(1,11,4,0),{{4,0,0},B}=hls_protocol_bridge_wire:packet(P),
    {packet,P}=hls_protocol_bridge_wire:event(11,{16#84,0,0},B),
    ?assertException(error,_,hls_protocol_bridge_wire:event(12,{16#84,0,0},B)),
    ?assertException(error,_,hls_protocol_bridge_wire:packet((packet(2,11,0,0))#{frame:=1})),ok.

%% Invalid endpoint types fail before reading sources or creating a build directory.
-spec endpoint_test() -> ok.
endpoint_test() ->
    lists:foreach(fun({H,S})->?assertError(function_clause,
        hls_protocol_bridge:write(#{native_actors=>[a],host=>H,service=>S},"unused")) end,
        [{1.5,7},{1,7.5},{0,7},{1,1},{1,65536}]),ok.

%% Shared identities or incomplete native ownership must never create a new incarnation.
-spec plan_test() -> ok.
plan_test() ->
    ?assertException(error,_,hls_protocol_relay_queue:new(plan(),#{0=>11,1=>11})),
    ?assertException(error,_,hls_protocol_relay_queue:new((plan())#{actors:=3},#{0=>11,1=>12})),ok.

%% One fully constant canonical frame suffices to test ownership without a fake compiler.
-spec plan() -> map().
plan() ->
    C=#{slot=>0,codec=>#{mask=>(1 bsl 128)-1,value=>0,frame_positions=>[],physical_width=>1}},
    L=#{index=>0,source_index=>0,destination_index=>1,classes=>[C]},
    #{actors=>2,limits=>#{crossings=>8},devices=>maps:from_list([{R,#{native_indices=>[R],links=>[L#{direction=>D}]}}
        ||{R,D}<-[{0,outgoing},{1,incoming}]])}.

%% Every test starts with no granted credits and distinct fresh sessions.
-spec new() -> map().
new() -> hls_protocol_relay_queue:new(plan(),#{0=>11,1=>12}).
%% One packet identity is retained across destination forwarding and source acknowledgment.
-spec packet(1|2,pos_integer(),non_neg_integer(),non_neg_integer()) -> map().
packet(Kind,Session,Seq,Link) -> #{kind=>Kind,session=>Session,sequence=>Seq,link=>Link,slot=>0,frame=>0}.

%% Three arbitrary device keys and irregular endpoints expose accidental two-board assumptions.
-spec deployment_stream_test() -> ok.
deployment_stream_test() ->
    with_deployment(fun(Stream,Peers,Sessions)->
        First=maps:get(42,Peers),North=maps:get(north,Peers),South=maps:get({tile,south},Peers),
        ok=hls_protocol_relay_peer:set(First,hold),
        {ok,1}=hls_protocol_stream:submit(Stream,{control,<<0:128>>}),
        await(fun()->maps:get(held,hls_protocol_relay_peer:stats(First))=/=none end),
        ?assertEqual({error,busy},hls_protocol_stream:submit(Stream,{control,<<0:128>>})),
        ok=hls_protocol_relay_peer:set(First,normal),
        await(fun()->#{counts:=C}=hls_protocol_stream:info(Stream),maps:get(commands,C)+maps:get(writer,C)=:=0 end),
        {ok,1}=hls_protocol_stream:submit(Stream,start),
        await(fun()->#{phases:=P}=hls_protocol_stream:info(Stream),lists:usort(maps:values(P))=:=[starting] end),
        [ok=started(R,Peers,Sessions)||R<-[42,north]],
        ok=hls_protocol_relay_peer:emit(North,{16#85,0,0},<<101:64/little,0:128>>),
        ?assertEqual(timeout,hls_protocol_stream:next(Stream,10)),
        ok=started({tile,south},Peers,Sessions),
        ?assertEqual({ok,application,{started}},hls_protocol_stream:next(Stream,1000)),
        ?assertEqual({ok,{north,0},0},hls_protocol_stream:next(Stream,1000)),
        %% One source has two actual destinations; the uncredited first route is bypassed.
        ok=emit_packet(North,packet(1,101,0,0)),ok=emit_packet(North,packet(1,101,1,1)),
        ok=emit_packet(South,packet(2,103,0,1)),
        await(fun()->#{packets:=#{acknowledged:=N}}=hls_protocol_stream:info(Stream),N=:=1 end),
        ?assertEqual([#{kind=>1,session=>103,sequence=>0,link=>1,slot=>0,frame=>0}],packets(South)),
        ?assertEqual([#{kind=>2,session=>101,sequence=>1,link=>1,slot=>0,frame=>0}],packets(North)),
        %% A delayed forwarding completion cannot release the original source reservation.
        ok=hls_protocol_relay_peer:set(First,hold),ok=emit_packet(First,packet(2,102,0,0)),
        await(fun()->maps:get(held,hls_protocol_relay_peer:stats(First))=/=none end),
        #{packets:=#{records:=1,acknowledged:=1},record_limit:=9}=hls_protocol_stream:info(Stream),
        ?assertEqual(1,length(packets(North))),
        ok=hls_protocol_relay_peer:set(First,normal),
        await(fun()->#{packets:=#{acknowledged:=N}}=hls_protocol_stream:info(Stream),N=:=2 end),
        ?assertEqual([#{kind=>1,session=>102,sequence=>0,link=>0,slot=>0,frame=>0}],packets(First)),
        ok=hls_protocol_stream:stop(Stream),
        await(fun()->lists:all(fun(P)->maps:get(owner,hls_protocol_relay_peer:stats(P))=:=retired end,maps:values(Peers)) end)
    end).

%% Losing any member retires the remaining participants without replay or replacement.
-spec deployment_failure_test() -> ok.
deployment_failure_test() ->
    with_deployment(fun(Stream,Peers,_)->
        Ref=monitor(process,Stream),exit(maps:get({tile,south},Peers),kill),
        receive {'DOWN',Ref,process,Stream,_}->ok after 1000->error(owner_survived) end,
        await(fun()->lists:all(fun(R)->maps:get(owner,hls_protocol_relay_peer:stats(maps:get(R,Peers)))=:=retired end,[42,north]) end)
    end).

%% Deployment validation rejects incomplete ownership, mismatched codecs and exceeded explicit bounds.
-spec deployment_rejection_test() -> ok.
deployment_rejection_test() ->
    P=#{devices:=D}=deployment(),Sessions=sessions(),
    ?assertException(error,_,hls_protocol_relay_queue:new(P#{limits:=#{crossings=>1}},Sessions)),
    ?assertException(error,_,hls_protocol_relay_queue:new(P,maps:remove(42,Sessions))),
    #{links:=Links}=maps:get(42,D),[L]=Links,
    Bad=D#{42:=(maps:get(42,D))#{links:=[L#{source_index:=2}]}},
    ?assertException(error,_,hls_protocol_relay_queue:new(P#{devices:=Bad},Sessions)),
    %% Duplicate descriptors must not be silently collapsed by maps:from_list.
    N=maps:get(north,D),Bad2=D#{north:=N#{links:=maps:get(links,N)++maps:get(links,N)}},
    ?assertException(error,_,hls_protocol_relay_queue:new(P#{devices:=Bad2},Sessions)),ok.

%% A three-node fanout uses ordinary constant codecs, not application arithmetic.
-spec deployment() -> map().
deployment() ->
    C=#{slot=>0,codec=>#{mask=>(1 bsl 128)-1,value=>0,frame_positions=>[],physical_width=>1}},
    Links=[#{index=>I,source_index=>0,destination_index=>I+1,classes=>[C]}||I<-[0,1]],
    Devices=maps:from_list([{R,#{native_indices=>[I],host=>H,service=>V,identity=><<I:256>>,externals=>[#{index=>0}],
        links=>[L#{direction=>case I of 0->outgoing;_->incoming end}||L=#{destination_index:=D}<-Links,I=:=0 orelse I=:=D]}}
        ||{R,I,H,V}<-[{north,0,55,301},{42,1,55,911},{{tile,south},2,77,301}]]),
    #{actors=>3,devices=>Devices,limits=>#{crossings=>2,commands=>1,events=>2}}.
%% Incarnation identities are independent of arbitrary device keys.
-spec sessions() -> map().
sessions()->#{north=>101,42=>102,{tile,south}=>103}.
%% Every test gets fresh brokers and a fresh deployment owner; no model claims physical reset.
-spec with_deployment(fun((pid(),map(),map())->term())) -> ok.
with_deployment(Fun)->
    Plan=#{devices:=Devices}=deployment(),Sessions=sessions(),
    Peers=maps:map(fun(_,B)->{ok,P}=hls_protocol_relay_peer:start(B),P end,Devices),
    {ok,Stream}=hls_protocol_stream:start_link(Plan,Peers,Sessions),unlink(Stream),
    try await(fun()->maps:get(phase,hls_protocol_stream:info(Stream))=:=attached end),Fun(Stream,Peers,Sessions),ok
    after catch hls_protocol_stream:stop(Stream),[catch gen_server:stop(P)||P<-maps:values(Peers)] end.
%% Inject a start acknowledgment only after the test observes the actual start write.
-spec started(term(),map(),map()) -> ok.
started(R,Peers,Sessions)->S=maps:get(R,Sessions),hls_protocol_relay_peer:emit(maps:get(R,Peers),{16#83,0,0},<<S:64/little,0:32>>).
%% Device output and host forwarding use the same packet layout with different envelope operations.
-spec emit_packet(pid(),map()) -> ok.
emit_packet(P,Packet)->{_,Bytes}=hls_protocol_bridge_wire:packet(Packet),hls_protocol_relay_peer:emit(P,{16#84,0,0},Bytes).
%% Inspect only complete public packet writes, retaining their issue order.
-spec packets(pid()) -> [map()].
packets(P)->
    #{writes:=Writes}=hls_protocol_relay_peer:stats(P),
    [begin <<_:8,S:64,_/bitstring>>= <<(binary:decode_unsigned(B,little)):256>>,
        {packet,Packet}=hls_protocol_bridge_wire:event(S,{16#84,0,0},B),Packet end
        ||{_,{4,0,0},B}<-lists:reverse(Writes)].
%% Wait on meaningful asynchronous state transitions with a finite deadline.
-spec await(fun(()->boolean())) -> ok.
await(F)->hls_bridge_phi_live:await(F,1000).

%% Ambiguous return routes and invalid capacities fail before registering any broker route.
-spec endpoint_binding_rejection_test() -> ok.
endpoint_binding_rejection_test() ->
    P=#{devices:=D}=deployment(),Sessions=sessions(),
    Peers=maps:map(fun(_,B)->{ok,Peer}=hls_protocol_relay_peer:start(B),Peer end,D),
    try
        South=maps:get({tile,south},D),North=maps:get(north,D),
        Ambiguous=P#{devices:=D#{{tile,south}:=South#{host:=maps:get(host,North),service:=maps:get(service,North)}}},
        ?assertException(error,_,hls_protocol_stream:init({Ambiguous,Peers,Sessions,self()})),
        ?assertException(error,_,hls_protocol_stream:init({P#{limits:=#{crossings=>2,commands=>1,events=>1}},Peers,Sessions,self()})),
        [?assertEqual(none,maps:get(owner,hls_protocol_relay_peer:stats(Peer)))||Peer<-maps:values(Peers)]
    after [gen_server:stop(Peer)||Peer<-maps:values(Peers)] end,ok.
