-module(hls_protocol_relay_queue).
-moduledoc "Bounded packet ownership among a fixed deployment of source-protocol RTL partitions. Each directed logical pair has one retained record; physical completion precedes source acknowledgment. This state machine does not establish transport retirement, reset or application progress.".
-export([new/2,event/3,next/1,complete/2,invalidate/1,info/1]).

-doc "Binds the deployment's disjoint, complete actor ownership to directed crossing routes and distinct nonzero sessions. Each outgoing descriptor must have exactly one matching incoming descriptor at the destination actor's device. The declared crossings limit bounds retained payload records. Old transports must be retired and all participating devices reset before constructing a replacement.".
-spec new(map(),map()) -> map().
new(#{devices:=Devices,actors:=Count,limits:=#{crossings:=Limit}},Sessions)
        when map_size(Devices)>0,is_integer(Limit),Limit>0 ->
    Roles=lists:sort(maps:keys(Devices)),Roles=lists:sort(maps:keys(Sessions)),
    Values=maps:values(Sessions),true=length(Values)=:=length(lists:usort(Values)),
    true=lists:all(fun(S)->is_integer(S) andalso S>0 andalso S<(1 bsl 64) end,Values),
    Owned=[{I,R}||{R,#{native_indices:=Is}}<-maps:to_list(Devices),I<-Is],
    true=lists:sort([I||{I,_}<-Owned])=:=lists:seq(0,Count-1),
    Owners=maps:from_list(Owned),
    Directed=[begin
        From=maps:get(S,Owners),To=maps:get(D,Owners),true=From=/=To,
        #{links:=PeerLinks}=maps:get(To,Devices),
        [Peer]=[L||L=#{index:=J,direction:=incoming}<-PeerLinks,J=:=I],
        true=maps:with([index,source_index,destination_index,classes],Link)=:=maps:with([index,source_index,destination_index,classes],Peer),
        {I,#{from=>From,to=>To,link=>Link}}
    end||{From,#{links:=Links}}<-maps:to_list(Devices),
         Link=#{index:=I,direction:=outgoing,source_index:=S,destination_index:=D}<-Links],
    Routes=maps:from_list(Directed),true=map_size(Routes)=:=length(Directed),
    Incoming=lists:sort([{R,I}||{R,#{links:=Ls}}<-maps:to_list(Devices),#{index:=I,direction:=incoming}<-Ls]),
    Incoming=lists:sort([{R,I}||{I,#{to:=R}}<-Directed]),
    true=map_size(Routes)>0 andalso map_size(Routes)=<Limit,
    #{live=>true,sessions=>Sessions,routes=>Routes,events=>maps:from_keys(Roles,0),pending=>#{},
      order=>lists:sort(maps:keys(Routes)),cursor=>0,writer=>none,
      credits=>maps:from_list([{{I,S},false}||{I,#{link:=#{classes:=Cs}}}<-Directed,#{slot:=S}<-Cs]),
      sequences=>maps:from_list([{I,0}||I<-maps:keys(Routes)]),forwarded=>0,acknowledged=>0,bypassed=>0}.

-doc "Accepts one route-bound participant's credit or data packet in exact output-event order. Rejects stale sessions, duplicate/skipped events, unknown routes/classes, noncanonical frames, duplicate grants and a second unacknowledged record for a pair. Output event sequences are independent of destination input sequences.".
-spec event(term(),map(),map()) -> map().
event(Role,Packet=#{session:=Session,sequence:=Event,link:=I},
        State=#{live:=true,sessions:=Sessions,events:=Events,routes:=Routes}) when Event<16#ffffffff ->
    Session=maps:get(Role,Sessions),Event=maps:get(Role,Events),
    Route=maps:get(I,Routes),
    accept(Role,Packet,Route,State#{events:=Events#{Role:=Event+1}}).

%% Credit advertises destination capacity; data retains the original source ACK identity.
-spec accept(term(),map(),map(),map()) -> map().
accept(Role,#{kind:=2,link:=I,slot:=Slot,frame:=0},#{to:=Role},State=#{credits:=Credits})->
    false=maps:get({I,Slot},Credits),State#{credits:=Credits#{{I,Slot}:=true}};
accept(Role,P=#{kind:=1,link:=I,slot:=Slot,frame:=Frame},#{from:=Role,link:=Link},State=#{pending:=Pending})->
    false=maps:is_key(I,Pending),ok=canonical(Link,Slot,Frame),
    State#{pending:=Pending#{I=>{pending,P}}}.

-doc "Reserves at most one physical write globally. ACKs take priority; otherwise round-robin selection may bypass an uncredited different pair, never a pair's head. Destination credit and its separate input sequence are consumed before returning a write. No rollback or replay is permitted after reservation.".
-spec next(map()) -> none | {term(),map(),tuple(),map()}.
next(#{live:=true,writer:=W}) when W=/=none->none;
next(State=#{live:=true,pending:=Pending,routes:=Routes})->
    case [{I,P}||{I,{ack,P}}<-lists:sort(maps:to_list(Pending))] of
        [{I,P}|_]->#{from:=From}=maps:get(I,Routes),
            Token={ack,I,maps:get(sequence,P)},
            {From,P#{kind:=2,frame:=0},Token,State#{writer:=Token,pending:=Pending#{I:={acking,P}}}};
        []->select(State)
    end.

%% Only credited heads compete; an unavailable slot never blocks a distinct pair.
-spec select(map()) -> none | {term(),map(),tuple(),map()}.
select(State=#{order:=Order,cursor:=Cursor,pending:=Pending,credits:=Credits}) ->
    N=length(Order),
    Waiting=[{J,I,P}||K<-lists:seq(0,N-1),J<-[(Cursor+K) rem N],I<-[lists:nth(J+1,Order)],
        {ok,{pending,P}}<-[maps:find(I,Pending)]],
    case [{J,I,P}||{J,I,P=#{slot:=S}}<-Waiting,maps:get({I,S},Credits)] of
        []->none;
        [{J,I,P=#{slot:=Slot}}|_]->
            #{routes:=Routes,sessions:=Sessions,sequences:=Sequences,bypassed:=Bypassed}=State,
            #{to:=To}=maps:get(I,Routes),Seq=maps:get(I,Sequences),true=Seq<16#ffffffff,
            Packet=P#{session:=maps:get(To,Sessions),sequence:=Seq},Token={data,I,Seq},
            Skipped=length(lists:takewhile(fun({_,L,_})->L=/=I end,Waiting)),
            {To,Packet,Token,State#{writer:=Token,cursor:=(J+1) rem N,pending:=Pending#{I:={writing,P}},
                sequences:=Sequences#{I:=Seq+1},credits:=Credits#{{I,Slot}:=false},bypassed:=Bypassed+Skipped}}
    end.

-doc "Commits the sole reserved write only after the broker confirms complete physical transmission. Data completion makes its original source ACK eligible; ACK completion releases the pair. A failed or ambiguous transmission must invalidate and retire the entire deployment incarnation, never call complete or retry.".
-spec complete(tuple(),map()) -> map().
complete(Token={data,I,_},State=#{live:=true,writer:=Token,pending:=Pending,forwarded:=Count})->
    {writing,P}=maps:get(I,Pending),State#{writer:=none,pending:=Pending#{I:={ack,P}},forwarded:=Count+1};
complete(Token={ack,I,_},State=#{live:=true,writer:=Token,pending:=Pending,acknowledged:=Count})->
    {acking,_}=maps:get(I,Pending),State#{writer:=none,pending:=maps:remove(I,Pending),acknowledged:=Count+1}.

-doc "Cancels every route, credit and retained record permanently. This does not cancel a physical write or prove transport retirement; the owning process must retire every participating connection and coordinate reset before constructing any replacement.".
-spec invalidate(map()) -> map().
invalidate(State)->State#{live:=false,routes:=#{},credits:=#{},pending:=#{},writer:=none}.

-doc "Reports bounded records, available credits and completed transfers without exposing payloads. Bypass counts are scheduler observations, not a fairness or progress proof.".
-spec info(map()) -> map().
info(#{live:=Live,pending:=Pending,credits:=Credits,writer:=Writer}=State)->
    (maps:with([events,forwarded,acknowledged,bypassed],State))#{live=>Live,records=>map_size(Pending),
      available_credits=>length([ok||true<-maps:values(Credits)]),writer=>Writer=/=none}.

%% A relay validates the destination codec without decoding or rewriting records.
-spec canonical(map(),byte(),non_neg_integer()) -> ok.
canonical(#{classes:=Classes},Slot,Frame) ->
    [#{codec:=Codec}]=[C||C=#{slot:=S}<-Classes,S=:=Slot],
    {ok,_}=hls_protocol_codec:encode(Codec,Frame),ok.
