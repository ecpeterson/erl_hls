-module(hls_protocol_mixed_queue).
-moduledoc "Bounded sender-aware host admission for a source-protocol partition. This state belongs to one transport owner, not to forwarding processes per actor.".
-export([new/4, offer/4, next/1, credit/5, delivery/6, invalidate/1, info/1]).

-doc "Creates an uncredited incarnation with exact local BEAM PID bindings for every host actor. Caller must own a freshly reset hardware attachment, authenticate distribution senders and monitor every bound actor and transport. Rebinding or recovering an ambiguous write requires invalidation, complete transport retirement and a new reset-owned incarnation. Limit bounds queued records; native slot credits separately bound sent records.".
-spec new(map(),#{non_neg_integer()=>pid()},1..18446744073709551615,pos_integer()) -> map().
new(#{host_actors:=Host,links:=Links,identity:=Identity},Pids,Session,Limit)
        when Session>0,Session<(1 bsl 64),Limit>0 ->
    true=lists:sort(Host)=:=lists:sort(maps:keys(Pids)),
    true=lists:all(fun(P)->is_pid(P) andalso node(P)=:=node() end,maps:values(Pids)),
    true=map_size(Pids)=:=length(lists:usort(maps:values(Pids))),
    ToRtl=[L||L=#{direction:=to_rtl}<-Links],
    #{live=>true,session=>Session,identity=>Identity,pids=>Pids,
      senders=>maps:from_list([{P,I}||{I,P}<-maps:to_list(Pids)]),
      links=>maps:from_list([{I,L}||L=#{index:=I}<-Links]),
      order=>[I||#{index:=I}<-ToRtl],cursor=>0,limit=>Limit,queued=>0,next_event=>0,
      queues=>maps:from_list([{I,queue:new()}||#{index:=I}<-ToRtl]),
      sequence=>maps:from_list([{I,0}||#{index:=I}<-ToRtl]),
      credits=>maps:from_list([{{I,S},false}||#{index:=I,classes:=Cs}<-ToRtl,#{slot:=S}<-Cs])}.

-doc "Queues an ordinary cast from an exactly bound sender PID to one native actor index. Class selection requires one canonical source-bound encoding, including omitted sender constants. Unknown identities, ambiguous classes and stale owners fail; a full bounded queue returns busy without admitting the message. Within each logical sender/destination pair, offer order is preserved.".
-spec offer(map(),pid(),non_neg_integer(),tuple()) -> {ok,map()} | {error,busy}.
offer(State=#{live:=true,queued:=Count,limit:=Limit},Sender,Target,Message) when Count<Limit ->
    #{senders:=Senders,links:=Links,queues:=Queues}=State,
    Source=maps:get(Sender,Senders),
    [Link=#{index:=I,classes:=Classes}]=[L||L=#{source_index:=S,destination_index:=D,direction:=to_rtl}<-maps:values(Links),S=:=Source,D=:=Target],
    Candidates=lists:usort(lists:append([encoded(Link,P,Message)||#{port:=P}<-Classes])),
    [{Slot,Frame}]=Candidates,
    Q=maps:get(I,Queues),
    {ok,State#{queued:=Count+1,queues:=Queues#{I:=queue:in({Slot,Frame},Q)}}};
offer(#{live:=true},_,_,_) -> {error,busy}.

%% A message's canonical source constants can disambiguate ports sharing a destination.
-spec encoded(map(),atom(),tuple()) -> [{byte(),non_neg_integer()}].
encoded(Link,Port,Message) ->
    try [hls_protocol_mixed:encode(Link,Port,Message)] catch error:_->[] end.

-doc "Reserves one eligible pair's head packet and consumes its slot credit before returning it. Round-robin arbitration may pass a blocked different sender, but never skips a pair's head. No sequence wrap or rollback is available: an ambiguous transport outcome invalidates the incarnation. Caller serializes physical writes and must not replay this reservation.".
-spec next(map()) -> none | {map(),map()}.
next(State=#{live:=true,order:=Order,cursor:=Cursor,queues:=Queues,credits:=Credits}) ->
    N=length(Order),
    Candidates=[{J,I,S,F}||K<-lists:seq(0,N-1),J<-[(Cursor+K) rem N],I<-[lists:nth(J+1,Order)],
        {value,{S,F}}<-[queue:peek(maps:get(I,Queues))],maps:get({I,S},Credits)],
    case Candidates of
        []->none;
        [{J,I,Slot,Frame}|_]->
            #{sequence:=Sequences,queued:=Count,session:=Session}=State,
            Seq=maps:get(I,Sequences),true=Seq<16#ffffffff,
            {{value,{Slot,Frame}},Tail}=queue:out(maps:get(I,Queues)),
            Packet=#{session=>Session,sequence=>Seq,link=>I,slot=>Slot,frame=>Frame},
            {Packet,State#{cursor:=(J+1) rem N,queued:=Count-1,
                queues:=Queues#{I:=Tail},credits:=Credits#{{I,Slot}:=false},sequence:=Sequences#{I:=Seq+1}}}
    end.

-doc "Accepts one hardware credit event in the single ordered output stream. Exact session and event sequence reject stale, duplicate and skipped packets before a slot can be reused. An already available or unknown credit is rejected. Hardware must return credits only after native final release; event sequence covers both credits and data and must never wrap.".
-spec credit(map(),1..18446744073709551615,non_neg_integer(),non_neg_integer(),byte()) -> map().
credit(State,Session,Event,Link,Slot) ->
    Next=#{credits:=Credits}=event(State,Session,Event),
    false=maps:get({Link,Slot},Credits),Next#{credits:=Credits#{{Link,Slot}:=true}}.

-doc "Validates and decodes one hardware-to-BEAM cast in the common ordered event stream. Returns the exact bound destination PID and ordinary record, never a reply to the most recent caller. The transport owner must deliver once and acknowledge only after delivery admission; a failure during delivery ends the incarnation without replay. This function alone gives no BEAM mailbox-capacity guarantee.".
-spec delivery(map(),1..18446744073709551615,non_neg_integer(),non_neg_integer(),byte(),non_neg_integer()) -> {pid(),tuple(),map()}.
delivery(State,Session,Event,Link,Slot,Frame) ->
    Next=#{links:=Links,pids:=Pids}=event(State,Session,Event),
    L=#{direction:=to_beam,destination_index:=Target}=maps:get(Link,Links),
    Message=hls_protocol_mixed:decode(L,Slot,Frame),
    {maps:get(Target,Pids),Message,Next}.

%% Output packet order authenticates credits against delayed duplicates as well as data replay.
-spec event(map(),pos_integer(),non_neg_integer()) -> map().
event(State=#{live:=true,session:=Session,next_event:=Event},Session,Event) when Event<16#ffffffff ->
    State#{next_event:=Event+1}.

-doc "Permanently cancels this owner's queues, bindings and credits. A dead state cannot be reused by next, offer, credit or delivery; opening a replacement requires new/4 after coordinated reset and transport retirement.".
-spec invalidate(map()) -> map().
invalidate(State)->State#{live:=false,pids:=#{},senders:=#{},queues:=#{},credits:=#{},queued:=0}.

-doc "Returns bounded queue and credit counts without exposing application payloads or PID bindings. Sent records can remain in native captures until their final read.".
-spec info(map()) -> map().
info(#{live:=Live,queued:=Count,limit:=Limit,credits:=Credits,next_event:=Event})->
    #{live=>Live,queued=>Count,limit=>Limit,available_credits=>length([ok||true<-maps:values(Credits)]),
      next_event=>Event}.
