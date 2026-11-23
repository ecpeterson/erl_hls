-module(hls_admission_tests).
-include_lib("eunit/include/eunit.hrl").

%% Long calls release transport admission credit while retaining ordinary reply ownership.
-spec native_admission_before_reply_test() -> ok.
native_admission_before_reply_test() ->
    {ok, Actor} = hls_statem:start_link(hls_statem_reply_fixture, [],
        [{mailbox_capacity, 4}, {outputs, #{reply => self()}}]),
    try
        T1=make_ref(), T2=make_ref(), T3=make_ref(),
        R1=gen_server:send_request(Actor, {'$hls_submit',T1,call,{wait,11}}),
        admitted(Actor,T1),
        R2=gen_server:send_request(Actor, {'$hls_submit',T2,call,{wait,13}}),
        admitted(Actor,T2),
        ?assertEqual(timeout,gen_server:wait_response(R1,0)),
        ?assertEqual(ok,gen_server:call(Actor,'$hls_capacity')),
        Cast=gen_server:send_request(Actor,{'$hls_submit',T3,cast,{release,0}}),
        admitted(Actor,T3),
        ?assertEqual({reply,{report,11}},gen_server:receive_response(R1,1000)),
        ?assertEqual({reply,{report,13}},gen_server:receive_response(R2,1000)),
        ?assertEqual({reply,ok},gen_server:receive_response(Cast,1000))
    after gen_server:stop(Actor) end.

%% A caller cannot consume an unbounded number of capacity subscriptions.
-spec duplicate_capacity_wait_is_bounded_test() -> ok.
duplicate_capacity_wait_is_bounded_test() ->
    First=make_ref(), Duplicate=make_ref(),
    W=hls_admission:wait({self(),First},false,#{}),
    ?assertEqual(W,hls_admission:wait({self(),Duplicate},false,W)),
    receive {Duplicate,Reply}->?assertEqual({error,busy},Reply) after 1000->error(no_busy) end,
    ?assertEqual(#{},hls_admission:ready(true,W)),
    receive {First,ok}->ok after 1000->error(no_capacity) end.

%% Only 32 independent callers are retained, regardless of producer count.
-spec capacity_observer_bound_test() -> ok.
capacity_observer_bound_test() ->
    Parent=self(),
    Ps=[spawn(fun()->receive {Tag,Reply}->Parent!{observed,self(),Tag,Reply} end end)
        || _<-lists:seq(1,33)],
    Tags=[make_ref()||_<-Ps],
    W=lists:foldl(fun({P,T},Acc)->hls_admission:wait({P,T},false,Acc) end,#{},lists:zip(Ps,Tags)),
    ?assertEqual(32,map_size(W)), Last=lists:last(Ps),
    receive {observed,Last,_,{error,busy}}->ok after 1000->error(no_bound) end,
    ?assertEqual(#{},hls_admission:ready(true,W)),
    [receive {observed,P,_,ok}->ok after 1000->error({no_capacity,P}) end || P<-lists:sublist(Ps,32)],
    ok.

%% A dead capacity observer leaves no retained application work or monitor bookkeeping.
-spec dead_capacity_observer_test() -> ok.
dead_capacity_observer_test() ->
    P=spawn(fun()->receive stop->ok end end),
    W=hls_admission:wait({P,make_ref()},false,#{}), P!stop,
    receive {'DOWN',Ref,process,P,_}->?assertEqual({true,#{}},hls_admission:down(Ref,W))
    after 1000->error(no_down) end.

%% Unrelated admission tokens cannot stand in for this request's acceptance.
-spec admitted(pid(), reference()) -> ok.
admitted(Pid,Token) -> receive {hls_admitted,Pid,Token}->ok after 1000->error(no_admission) end.
