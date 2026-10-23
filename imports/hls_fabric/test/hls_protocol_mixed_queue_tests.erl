-module(hls_protocol_mixed_queue_tests).
-moduledoc "Finite host-admission witness against the actual N3 source cut. Fixture PIDs test binding and lifetime bookkeeping; this is not the complete BEAM/RTL application witness.".
-export([run/1, retired/1]).

-doc "Exercises bounded admission, cross-sender progress, per-pair order, credits, replay rejection, exact reverse destinations and invalidation from a retained mixed plan. All fixture processes are stopped before returning.".
-spec run(file:filename()) -> ok.
run(Path) ->
    {ok,B}=file:read_file(Path),Plan=#{host_actors:=Ids,links:=Links}=binary_to_term(B),
    Pids=maps:from_list([{I,spawn(fun()->receive stop->ok end end)}||I<-Ids]),
    try
        Q=hls_protocol_mixed_queue:new(Plan,Pids,123,2),
        [First,Second|_]=Ids,
        A=hd([L||L=#{source_index:=I,direction:=to_rtl}<-Links,I=:=First]),
        Other=hd([L||L=#{source_index:=I,direction:=to_rtl}<-Links,I=:=Second]),
        {AI,AS,AT,AM}=message(A),{BI,BS,BT,BM}=message(Other),
        {ok,Q1}=hls_protocol_mixed_queue:offer(Q,maps:get(First,Pids),AT,AM),
        {ok,Q2}=hls_protocol_mixed_queue:offer(Q1,maps:get(Second,Pids),BT,BM),
        {error,busy}=hls_protocol_mixed_queue:offer(Q2,maps:get(First,Pids),AT,AM),
        none=hls_protocol_mixed_queue:next(Q2),
        Q3=hls_protocol_mixed_queue:credit(Q2,123,0,BI,BS),
        {#{link:=BI,sequence:=0},Q4}=hls_protocol_mixed_queue:next(Q3),
        none=hls_protocol_mixed_queue:next(Q4),
        Q5=hls_protocol_mixed_queue:credit(Q4,123,1,AI,AS),
        {#{link:=AI,sequence:=0},Q6}=hls_protocol_mixed_queue:next(Q5),
        rejected(fun()->hls_protocol_mixed_queue:credit(Q6,123,1,AI,AS) end),
        rejected(fun()->hls_protocol_mixed_queue:credit(Q6,122,2,AI,AS) end),
        rejected(fun()->hls_protocol_mixed_queue:credit(Q6,123,3,AI,AS) end),
        rejected(fun()->hls_protocol_mixed_queue:offer(Q6,self(),AT,AM) end),
        {ok,Q7}=hls_protocol_mixed_queue:offer(Q6,maps:get(First,Pids),AT,AM),
        none=hls_protocol_mixed_queue:next(Q7),
        Q8=hls_protocol_mixed_queue:credit(Q7,123,2,AI,AS),
        rejected(fun()->hls_protocol_mixed_queue:credit(Q8,123,3,AI,AS) end),
        {#{link:=AI,sequence:=1},Q9}=hls_protocol_mixed_queue:next(Q8),
        Reverse=hd([L||L=#{direction:=to_beam}<-Links]),
        #{index:=RI,destination_index:=Target,classes:=[#{slot:=RS,codec:=Codec}|_]}=Reverse,
        Frame=maps:get(value,Codec),
        {Destination,Message,Q10}=hls_protocol_mixed_queue:delivery(Q9,123,3,RI,RS,Frame),
        Destination=maps:get(Target,Pids),Message=hls_protocol_mixed:decode(Reverse,RS,Frame),
        rejected(fun()->hls_protocol_mixed_queue:delivery(Q10,123,3,RI,RS,Frame) end),
        Dead=hls_protocol_mixed_queue:invalidate(Q10),
        #{live:=false,queued:=0,available_credits:=0}=hls_protocol_mixed_queue:info(Dead),
        ok=retired(Dead),
        io:format("PASS mixed host admission: two senders, bounded queue, exact routes, ordered credits, duplicate/stale rejection, retirement~n"),ok
    after maps:foreach(fun(_,P)->Ref=monitor(process,P),P!stop,receive {'DOWN',Ref,process,P,normal}->ok after 1000->error(fixture_retirement) end end,Pids) end.

%% Form a canonical finite record from each actual source-bound class, without inventing message schemas.
-spec message(map()) -> {non_neg_integer(),byte(),non_neg_integer(),tuple()}.
message(L=#{index:=I,destination_index:=Target,classes:=[#{slot:=Slot,codec:=#{value:=Frame}}|_]}) ->
    {I,Slot,Target,hls_protocol_mixed:decode(L,Slot,Frame)}.

%% Accept only an actual rejection, not a successful return with a different state.
-spec rejected(fun(() -> term())) -> ok.
rejected(F)->R=try F(),accepted catch error:_->rejected end,rejected=R,ok.

-doc "Checks deliberate calls outside the live-state success domain. Dynamic dispatch keeps the runtime rejection witness distinct from Dialyzer proving these exact invalid calls cannot return; no production warning is suppressed.".
-spec retired(map()) -> ok.
retired(Dead) ->
    lists:foreach(fun({F,Args})->rejected_call(F,Args) end,
        [{next,[Dead]},{offer,[Dead,self(),0,{invalid}]},{credit,[Dead,123,4,0,0]}]).

%% These calls intentionally violate the success domain to exercise runtime retirement checks.
-spec rejected_call(atom(),[term()]) -> ok.
rejected_call(F,Args) ->
    R=try apply(hls_protocol_mixed_queue,F,Args),accepted catch error:_->rejected end,
    rejected=R,ok.
