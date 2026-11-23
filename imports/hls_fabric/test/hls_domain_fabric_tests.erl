-module(hls_domain_fabric_tests).
-include_lib("eunit/include/eunit.hrl").
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").

%% A ready successor cannot bypass old accepted replies/effects or old endpoint death.
-spec frontier_drains_before_successor_test() -> ok.
frontier_drains_before_successor_test() ->
    with_backend(fun(Backend, Management, Application, Authority, Endpoint) ->
        Monitor = monitor(process, Endpoint),
        Call = gen_server:send_request(Endpoint, {sample, 3}),
        {_, <<41:64/little,1:64/little,3:32/little,Request:32/little,1:32/little,0:32/little,_/binary>>} =
            sent(Application, 2),
        deliver(Backend, {0,1}, 2, response(1, 1, Request, 0, <<>>)),
        ?assertMatch({ok, #{state := #domain_state{phase = failed}, actors := #{}}},
            status(Backend, Management, failed, 1, 3)),
        ?assertEqual({error, delivery_pending}, status(Backend, Management, ready, 2, 3)),
        ?assertMatch(#{actors := #{worker := Endpoint}, pending := 1, received := 1},
            hls_domain_fabric:info(Backend)),
        deliver(Backend, {0,1}, 3, response(2, 1, Request, 16#02000001, <<6:3,0:29>>)),
        ?assertEqual({reply, {answer, 6}}, gen_server:receive_response(Call, 1000)),
        ?assertMatch(#{actors := #{worker := Endpoint}, received := 2}, hls_domain_fabric:info(Backend)),
        deliver(Backend, {0,1}, 4, response(3, 1, 0, 16#02000001, <<7:3,0:29>>)),
        receive
            {'$gen_cast',{answer,7}} -> ok;
            {'DOWN',Monitor,process,Endpoint,_} -> error(retired_before_effect)
        after 1000 -> error(effect_missing) end,
        receive {'DOWN',Monitor,process,Endpoint,{hls_actor_failure,3,_}} -> ok
        after 1000 -> error(retirement_missing) end,
        Successor = endpoint(Backend, Authority, 2, 100),
        ?assertNotEqual(Endpoint, Successor)
    end).

%% Stop completion waits for already-produced replies/effects and actual endpoint death.
-spec stopped_waits_for_frontier_and_endpoint_test() -> ok.
stopped_waits_for_frontier_and_endpoint_test() ->
    with_backend(fun(Backend, Management, Application, Authority, Endpoint) ->
        Monitor = monitor(process, Endpoint),
        Call = gen_server:send_request(Endpoint, {sample, 3}),
        {_, <<41:64/little,1:64/little,3:32/little,Request:32/little,1:32/little,0:32/little,_/binary>>} =
            sent(Application, 2),
        deliver(Backend, {0,1}, 2, response(1, 1, Request, 0, <<>>)),
        Stop = gen_server:send_request(Backend, {request, Authority,
            #domain_input{op=stop,expected=1,target=1,transition=1}}),
        {Route, <<41:64/little,Sequence:32/little,9:32/little,1:64/little,1:64/little,1:64/little,0:32/little>>} =
            sent(Management, 1),
        deliver(Backend, Route, 1, stop_snapshot(Sequence, accepted, closing, 1, 3)),
        ?assertMatch({reply,#domain_output{status=accepted,state=#domain_state{phase=closing}}},
            gen_server:receive_response(Stop, 1000)),
        ?assertEqual({error,delivery_pending}, status(Backend, Management, stopped, 1, 3)),
        %% Cached PIDs may still receive traffic, but it cannot overtake old output retirement.
        gen_server:cast(Endpoint, {sample, 4}),
        ?assertEqual({error,not_ready_or_stale}, gen_server:call(Endpoint, {sample, 5})),
        ?assertMatch(#{actors:=#{worker:=Endpoint},pending:=1,received:=1},
            hls_domain_fabric:info(Backend)),
        deliver(Backend, {0,1}, 3, response(2, 1, Request, 16#02000001, <<6:3,0:29>>)),
        ?assertEqual({reply,{answer,6}}, gen_server:receive_response(Call, 1000)),
        deliver(Backend, {0,1}, 4, response(3, 1, 0, 16#02000001, <<7:3,0:29>>)),
        receive
            {'$gen_cast',{answer,7}} -> ok;
            {'DOWN',Monitor,process,Endpoint,_} -> error(shutdown_before_effect)
        after 1000 -> error(effect_missing) end,
        receive {'DOWN',Monitor,process,Endpoint,shutdown} -> ok
        after 1000 -> error(shutdown_missing) end,
        stopped(Backend, Management, 1, 3, 100),
        ?assertEqual({error,not_ready_or_stale}, hls_domain_fabric:endpoint(Backend, Authority, 1, worker))
    end).

%% A stopped device with missing promised output is still an uncertain host shutdown.
-spec stopped_missing_frontier_is_uncertain_test() -> ok.
stopped_missing_frontier_is_uncertain_test() ->
    with_backend(#{delivery_timeout_ms=>100}, fun(Backend, Management, _Application, _Authority, Endpoint) ->
        Monitor = monitor(process, Endpoint),
        ?assertEqual({error,delivery_pending}, status(Backend, Management, stopped, 1, 1)),
        receive {'DOWN',Monitor,process,Endpoint,noconnection} -> ok
        after 1000 -> error(uncertainty_missing) end
    end).

%% Different monitors deliver independently; a stopped status requires this backend's own DOWN.
-spec stopped(pid(), pid(), pos_integer(), non_neg_integer(), non_neg_integer()) -> ok.
stopped(_Backend, _Management, _Incarnation, _Frontier, 0) -> error(stop_completion_missing);
stopped(Backend, Management, Incarnation, Frontier, Attempts) ->
    case status(Backend, Management, stopped, Incarnation, Frontier) of
        {ok,#{state:=#domain_state{phase=stopped,current=Incarnation},actors:=Actors}} when map_size(Actors) =:= 0 -> ok;
        {error,delivery_pending} -> stopped(Backend, Management, Incarnation, Frontier, Attempts-1)
    end.

%% A reply without its earlier in-band admission record is corrupt evidence, not completion.
-spec unadmitted_reply_closes_backend_test() -> ok.
unadmitted_reply_closes_backend_test() ->
    with_backend(fun(Backend, _Management, Application, _Authority, Endpoint) ->
        Monitor = monitor(process, Endpoint),
        _Call = gen_server:send_request(Endpoint, {sample, 3}),
        {_, <<_:160,Request:32/little,_/binary>>} = sent(Application, 2),
        deliver(Backend, {0,1}, 3, response(1, 1, Request, 16#02000001, <<6:3,0:29>>)),
        receive {'DOWN',Monitor,process,Endpoint,noconnection} -> ok
        after 1000 -> error(uncertainty_missing) end
    end).

%% Effects do not carry a call transaction; corrupt nonzero txids cannot reach recipients.
-spec effect_transaction_closes_backend_test() -> ok.
effect_transaction_closes_backend_test() ->
    with_backend(fun(Backend, _Management, _Application, _Authority, Endpoint) ->
        Monitor = monitor(process, Endpoint),
        deliver(Backend, {0,1}, 4, response(1, 1, 0, 16#02000101, <<6:3,0:29>>)),
        receive
            {'DOWN',Monitor,process,Endpoint,noconnection} -> ok;
            {'$gen_cast',{answer,_}} -> error(corrupt_effect_delivered)
        after 1000 -> error(uncertainty_missing) end
    end).

%% A cold controller reset is detectable even before an output frontier has advanced.
-spec incarnation_regression_closes_backend_test() -> ok.
incarnation_regression_closes_backend_test() ->
    with_backend(fun(Backend, Management, _Application, _Authority, Endpoint) ->
        Monitor = monitor(process, Endpoint),
        Query = gen_server:send_request(Backend, status),
        {Route, <<41:64/little,Sequence:32/little>>} = sent(Management, 0),
        deliver(Backend, Route, 1, snapshot(Sequence, unbound, 0, 0)),
        ?assertMatch({error, _}, gen_server:receive_response(Query, 1000)),
        receive {'DOWN',Monitor,process,Endpoint,noconnection} -> ok
        after 1000 -> error(uncertainty_missing) end
    end).

%% Host delivery timeout cannot turn an undelivered accepted output into orderly source retirement.
-spec missing_frontier_delivery_is_uncertain_test() -> ok.
missing_frontier_delivery_is_uncertain_test() ->
    with_backend(#{delivery_timeout_ms=>100}, fun(Backend, Management, _Application, _Authority, Endpoint) ->
        Monitor = monitor(process, Endpoint),
        ?assertMatch({ok, #{state := #domain_state{phase=failed}}},
            status(Backend, Management, failed, 1, 1)),
        ?assertMatch(#{received:=0,frontier:=1,actors:=#{worker:=Endpoint}},
            hls_domain_fabric:info(Backend)),
        receive {'DOWN',Monitor,process,Endpoint,Reason} -> ?assertEqual(noconnection, Reason)
        after 1000 -> error(frontier_timeout_missing) end
    end).

%% A missing host management response is not retransmitted; only a fresh inspect adopts newer evidence.
-spec management_timeout_reconciles_without_retry_test() -> ok.
management_timeout_reconciles_without_retry_test() ->
    with_backend(#{management_timeout_ms=>100}, fun(Backend, Management, _Application, Authority, Endpoint) ->
        Monitor = monitor(process, Endpoint),
        Lost = gen_server:send_request(Backend, status),
        {Route, <<41:64/little,Sequence:32/little>>} = sent(Management, 0),
        ?assertEqual({reply,{error,management_timeout}}, gen_server:receive_response(Lost, 1000)),
        receive {wire,Management,_,_,_} -> error(management_retransmitted)
        after 100 -> ok end,
        %% A late response cannot authenticate a later exchange or change readiness.
        deliver(Backend, Route, 1, snapshot(Sequence, ready, 2, 0)),
        ?assertMatch(#{state:=#domain_state{current=1},ignored:=1}, hls_domain_fabric:info(Backend)),
        Fresh = gen_server:send_request(Backend, status),
        {Route, <<41:64/little,FreshSequence:32/little>>} = sent(Management, 0),
        ?assertEqual(Sequence+1, FreshSequence),
        deliver(Backend, Route, 1, snapshot(FreshSequence, ready, 2, 0)),
        ?assertEqual({reply,{error,delivery_pending}}, gen_server:receive_response(Fresh, 1000)),
        receive {'DOWN',Monitor,process,Endpoint,_Reason} -> ok
        after 1000 -> error(old_endpoint_survived) end,
        Successor = endpoint(Backend, Authority, 2, 100),
        ?assertNotEqual(Endpoint, Successor),
        ?assertMatch(#{state:=#domain_state{current=2},actors:=#{worker:=Successor}},
            hls_domain_fabric:info(Backend))
    end).

%% Host owner death excludes new authority until an actual device response confirms closure.
-spec owner_death_waits_for_device_closure_test() -> ok.
owner_death_waits_for_device_closure_test() ->
    with_transport(#{owner_loss=>fail}, fun(Backend, Management, _Application) ->
        Parent = self(),
        Owner = spawn(fun() ->
            {ok, Authority} = hls_domain_fabric:attach(Backend, self()),
            Parent ! {attached,self(),Authority},
            receive stop -> ok end
        end),
        try
            OldAuthority = receive {attached,Owner,A} -> A after 1000 -> error(owner_missing) end,
            {ok,#{actors:=#{worker:=Endpoint}}} = status(Backend, Management, ready, 1, 0),
            Monitor = monitor(process, Endpoint),
            exit(Owner, kill),
            {Route, <<41:64/little,Inspect:32/little>>} = sent(Management, 0),
            ?assertEqual({error,owned_or_retiring}, hls_domain_fabric:attach(Backend, self())),
            deliver(Backend, Route, 1, snapshot(Inspect, ready, 1, 0)),
            {Route, <<41:64/little,Close:32/little,3:32/little,1:64/little,0:64/little,0:64/little,2:32/little>>} =
                sent(Management, 1),
            ?assertEqual({error,owned_or_retiring}, hls_domain_fabric:attach(Backend, self())),
            ?assertMatch(#{retiring_owner:=true}, hls_domain_fabric:info(Backend)),
            %% This fixture supplies device evidence; the host monitor alone did not establish it.
            deliver(Backend, Route, 1, snapshot(Close, failed, 1, 0)),
            {ok, FreshAuthority} = hls_domain_fabric:attach(Backend, self()),
            ?assertNotEqual(OldAuthority, FreshAuthority),
            ?assertEqual({error,unauthorized},
                hls_domain_fabric:request(Backend, OldAuthority, #domain_input{})),
            receive {'DOWN',Monitor,process,Endpoint,Reason} -> ?assertEqual(noconnection, Reason)
            after 1000 -> error(owner_endpoint_survived) end
        after exit(Owner, kill) end
    end).

%% Route mismatches reject before either broker is acquired.
-spec retained_routes_test() -> ok.
retained_routes_test() ->
    ?assertException(error, _, hls_domain_fabric:init({
        #{management=>self(),application=>spawn(fun()->ok end),application_route=>{0,2},session=>41},
        interface(), #{}})).

%% This broker fixture models host delivery only; it makes no claims about RTL or physical fencing.
-spec with_backend(fun((pid(),pid(),pid(),reference(),pid()) -> term())) -> ok.
with_backend(Test) -> with_backend(#{}, Test).

%% Explicit short deadlines exercise host timeout behavior without changing production defaults.
-spec with_backend(hls_domain_fabric:options(), fun((pid(),pid(),pid(),reference(),pid()) -> term())) -> ok.
with_backend(Options, Test) ->
    with_transport(Options, fun(Backend, Management, Application) ->
        {ok, Authority} = hls_domain_fabric:attach(Backend, self()),
        {ok, #{actors := #{worker := Endpoint}}} = status(Backend, Management, ready, 1, 0),
        Test(Backend, Management, Application, Authority, Endpoint)
    end).

%% Deployment attachment is independent of the subsequently selected lifecycle owner.
-spec with_transport(hls_domain_fabric:options(), fun((pid(),pid(),pid()) -> term())) -> ok.
with_transport(Options, Test) -> with_transport(interface(), Options, Test).

%% Multiple actors share wire order, but do not share retained-call capacity.
-spec with_transport(hls_domain_wire:interface(), hls_domain_fabric:options(), fun((pid(),pid(),pid()) -> term())) -> ok.
with_transport(Interface, Options, Test) ->
    Parent = self(),
    Management = spawn(fun() -> broker(Parent) end),
    Application = spawn(fun() -> broker(Parent) end),
    Defaults = #{recipients=>#{{worker,effect}=>self()},poll_ms=>60000},
    {ok, Backend} = hls_domain_fabric:start_link(#{management=>Management,application=>Application,session=>41},
        Interface, maps:merge(Defaults, Options)),
    unlink(Backend),
    try Test(Backend, Management, Application), ok
    after
        %% Fault tests may already be terminating after retiring their endpoint.
        _ = catch hls_domain_fabric:stop(Backend),
        Management ! stop, Application ! stop
    end.

%% Register/send/ack are precisely the public broker boundary used by the adapter.
-spec broker(pid()) -> ok.
broker(Parent) ->
    receive
        {'$gen_call', From, {register_route, _Route, _Owner}} ->
            gen_server:reply(From, ok), broker(Parent);
        {'$gen_call', From, {send, Route, {Tag,0,0}, Payload, _Deadline}} ->
            Parent ! {wire, self(), Route, Tag, Payload},
            gen_server:reply(From, ok), broker(Parent);
        {'$gen_cast', {ack, _Owner, _Receipt}} -> broker(Parent);
        stop -> ok
    end.

%% One generated exchange is consumed once, with no fixture retransmission.
-spec sent(pid(), byte()) -> {hls_fabric:route(), binary()}.
sent(Broker, Tag) ->
    receive {wire, Broker, Route, Tag, Payload} -> {Route, Payload}
    after 1000 -> error({missing_write, Tag}) end.

%% Delivery is an independently acknowledged broker frame, not a backend-private shortcut.
-spec deliver(pid(), hls_fabric:route(), byte(), binary()) -> ok.
deliver(Backend, Route, Tag, Payload) ->
    gen_server:cast(Backend, {'$hls_fabric_frame',make_ref(),Route,{Tag,0,0},Payload}).

%% All statuses are fresh explicit responses to their own management correlation identity.
-spec status(pid(), pid(), hls_domain_lifecycle:phase(), non_neg_integer(), non_neg_integer()) -> term().
status(Backend, Management, Phase, Incarnation, Frontier) ->
    Request = gen_server:send_request(Backend, status),
    {Route, <<41:64/little,Sequence:32/little>>} = sent(Management, 0),
    deliver(Backend, Route, 1, snapshot(Sequence, Phase, Incarnation, Frontier)),
    {reply, Result} = gen_server:receive_response(Request, 1000),
    Result.

%% Lifecycle enum values below are independently specified wire fixtures.
-spec snapshot(non_neg_integer(), hls_domain_lifecycle:phase(), non_neg_integer(), non_neg_integer()) -> binary().
snapshot(Sequence, stopped, Incarnation, Frontier) ->
    stop_snapshot(Sequence, ok, stopped, Incarnation, Frontier);
snapshot(Sequence, Phase, Incarnation, Frontier) ->
    {Code, Fault, Source} = case Phase of unbound -> {0,0,0}; ready -> {1,0,0}; failed -> {5,1,17} end,
    <<41:64/little,Sequence:32/little,0:32/little,0:32/little,Code:32/little,Incarnation:64/little,
        0:64/little,Incarnation:64/little,0:64/little,Fault:32/little,Source:32/little,3:32/little,Frontier:32/little>>.

%% Stop uses its existing incarnation as both transition endpoints and allocates no successor.
-spec stop_snapshot(non_neg_integer(), ok | accepted, closing | stopped, pos_integer(), non_neg_integer()) -> binary().
stop_snapshot(Sequence, Status, Phase, Incarnation, Frontier) ->
    Code = case Phase of closing -> 2; stopped -> 6 end,
    Disposition = case Status of ok -> 0; accepted -> 1 end,
    <<41:64/little,Sequence:32/little,Disposition:32/little,0:32/little,Code:32/little,Incarnation:64/little,
        Incarnation:64/little,Incarnation:64/little,Incarnation:64/little,0:32/little,0:32/little,3:32/little,Frontier:32/little>>.

%% Reply/effect frame headers use the established op/flags/txid/length order.
-spec response(pos_integer(), pos_integer(), non_neg_integer(), non_neg_integer(), binary()) -> binary().
response(Sequence, Incarnation, Request, Header, Payload) ->
    <<41:64/little,Sequence:32/little,Incarnation:64/little,3:32/little,Request:32/little,
        0:32/little,0:32/little,Header:32/little,Payload/binary>>.

%% Endpoint DOWN reaches different monitors independently; wait only for that bounded local delivery.
-spec endpoint(pid(), reference(), pos_integer(), non_neg_integer()) -> pid().
endpoint(_Backend, _Authority, _Incarnation, 0) -> error(successor_missing);
endpoint(Backend, Authority, Incarnation, Attempts) ->
    case hls_domain_fabric:endpoint(Backend, Authority, Incarnation, worker) of
        {ok, Endpoint} -> Endpoint;
        {error, not_ready_or_stale} -> receive after 1 -> endpoint(Backend, Authority, Incarnation, Attempts-1) end
    end.

%% Trusted retained descriptors are small source-independent inputs to the host boundary.
-spec interface() -> hls_domain_wire:interface().
interface() ->
    Schemas = maps:from_list([begin
        Codec = hls_record_codec:bind(Tag, [{value,hls_nums:uN(3)}]),
        {Tag,#{name=>Tag,selector=>Selector,width=>3,codec=>Codec}}
    end || {Tag,Selector} <- [{sample,1},{answer,2}]]),
    #{actors=>#{worker=>#{index=>3,schemas=>Schemas,
        contract=>#{calls=>#{sample=>[answer]},casts=>[],pending_calls=>1},
        outputs=>#{effect=>[answer]},ports=>#{effect=>0}}},frame_payload_words=>4,
      management_route=>{0,0},application_route=>{0,1},codecs=>maps:from_list([
        {Name,{hls_type,hls_enum,enum,[Members]}} || {Name,Members} <- [
            {operation,[inspect,activate,replace,fault,fenced,reset_done,initialized,abort,reject,stop]},
            {phase,[unbound,ready,closing,isolated,initializing,failed,stopped]},
            {status,[ok,accepted,replay,stale,busy,invalid,failure,completed]},
            {action,[none,fence,reset,initialize,publish]},
            {fault,[none,actor_failure,owner_down,initialization_failure,lifecycle_failure,protocol_failure]}]])}.

%% The former domain-wide limit cannot block an independent actor's retained call.
-spec independent_actor_call_capacity_test() -> ok.
independent_actor_call_capacity_test() ->
    I=interface(), #{actors:=#{worker:=Binding}}=I,
    Two=I#{actors:=#{worker=>Binding,other=>Binding#{index:=4}}},
    with_transport(Two,#{pending_limit=>1},fun(Backend,Management,Application)->
        {ok,_}=hls_domain_fabric:attach(Backend,self()),
        {ok,#{actors:=#{worker:=A,other:=B}}}=status(Backend,Management,ready,1,0),
        T1=make_ref(), T2=make_ref(),
        R1=gen_server:send_request(A,{'$hls_submit',T1,call,{sample,3}}),
        {_,<<_:160,Q1:32/little,_/binary>>}=sent(Application,2),
        deliver(Backend,{0,1},2,response(1,1,Q1,0,<<>>)),
        receive {hls_admitted,A,T1}->ok after 1000->error(first_not_admitted) end,
        R2=gen_server:send_request(B,{'$hls_submit',T2,call,{sample,4}}),
        {_,<<_:128,4:32/little,Q2:32/little,_/binary>>}=sent(Application,2),
        %% Actor B completes while A still owns its original reply slot.
        deliver(Backend,{0,1},2,actor_response(2,4,Q2,0,<<>>)),
        receive {hls_admitted,B,T2}->ok after 1000->error(second_not_admitted) end,
        deliver(Backend,{0,1},3,actor_response(3,4,Q2,16#02000001,<<5:3,0:29>>)),
        ?assertEqual({reply,{answer,5}},gen_server:receive_response(R2,1000)),
        ?assertEqual(timeout,gen_server:wait_response(R1,0)),
        deliver(Backend,{0,1},3,response(4,1,Q1,16#02000001,<<6:3,0:29>>)),
        ?assertEqual({reply,{answer,6}},gen_server:receive_response(R1,1000))
    end).

%% A second independent actor has its own numeric wire identity.
-spec actor_response(pos_integer(),non_neg_integer(),non_neg_integer(),non_neg_integer(),binary()) -> binary().
actor_response(Sequence,Actor,Request,Header,Payload) ->
    <<41:64/little,Sequence:32/little,1:64/little,Actor:32/little,Request:32/little,
        0:32/little,0:32/little,Header:32/little,Payload/binary>>.

%% Logical polling deadlines cannot multiply physical writes behind a stalled broker.
-spec management_timeout_keeps_physical_write_owned_test() -> ok.
management_timeout_keeps_physical_write_owned_test() ->
    Parent=self(), M=spawn(fun()->held_broker(Parent) end), A=spawn(fun()->broker(Parent) end),
    {ok,B}=hls_domain_fabric:start_link(#{management=>M,application=>A,session=>41},interface(),
        #{poll_ms=>1,management_timeout_ms=>1}), unlink(B),
    try
        receive {held_write,M,From}->
            receive {held_write,M,_}->error(overlapping_physical_write) after 80->ok end,
            ?assert(is_process_alive(B)),
            ?assertMatch(#{management_queued:=1},hls_domain_fabric:info(B)),
            gen_server:reply(From,ok),
            receive {held_write,M,_}->ok after 1000->error(write_not_released) end
        after 1000->error(no_inspect) end
    after catch hls_domain_fabric:stop(B), M!stop, A!stop end.

%% The fixture deliberately withholds write completion independently of device responses.
-spec held_broker(pid()) -> ok.
held_broker(Parent) ->
    receive
        {'$gen_call',From,{register_route,_,_}} -> gen_server:reply(From,ok),held_broker(Parent);
        {'$gen_call',From,{send,_,_,_,_}} -> Parent!{held_write,self(),From},held_broker(Parent);
        {'$gen_cast',{ack,_,_}} -> held_broker(Parent);
        stop -> ok
    end.

%% Revoking owner authority does not send a lifecycle fault or change live actor endpoints.
-spec owner_death_preserves_incarnation_test() -> ok.
owner_death_preserves_incarnation_test() ->
    with_transport(#{}, fun(Backend, Management, Application) ->
        Parent=self(),
        Owner=spawn(fun()-> {ok,A}=hls_domain_fabric:attach(Backend,self()),
            Parent!{attached,self(),A}, receive stop->ok end end),
        Old=receive {attached,Owner,A}->A after 1000->error(no_owner) end,
        {ok,#{actors:=#{worker:=Endpoint}}}=status(Backend,Management,ready,7,0),
        Monitor=monitor(process,Endpoint), exit(Owner,kill),
        Fresh=attach_after_owner_down(Backend,100),
        ?assertNotEqual(Old,Fresh),
        ?assertEqual({error,unauthorized},hls_domain_fabric:request(Backend,Old,#domain_input{})),
        ?assertEqual({ok,Endpoint},hls_domain_fabric:endpoint(Backend,Fresh,7,worker)),
        receive {wire,Management,_,_,_}->error(unrequested_lifecycle_work);
            {'DOWN',Monitor,process,Endpoint,Reason}->error({actor_died,Reason}) after 20->ok end,
        Call=gen_server:send_request(Endpoint,{sample,3}),
        {_,<<41:64/little,7:64/little,3:32/little,Q:32/little,_/binary>>}=sent(Application,2),
        deliver(Backend,{0,1},2,response(1,7,Q,0,<<>>)),
        deliver(Backend,{0,1},3,response(2,7,Q,16#02000001,<<6:3,0:29>>)),
        ?assertEqual({reply,{answer,6}},gen_server:receive_response(Call,1000)),
        demonitor(Monitor,[flush])
    end).

%% The owner's DOWN can arrive after a fresh attachment call from this independent process.
-spec attach_after_owner_down(pid(), non_neg_integer()) -> reference().
attach_after_owner_down(_Backend,0)->error(owner_down_not_observed);
attach_after_owner_down(Backend,N)->
    case hls_domain_fabric:attach(Backend,self()) of
        {ok,Authority}->Authority;
        {error,owned_or_retiring}->receive after 1->attach_after_owner_down(Backend,N-1) end
    end.

%% A stale connection cannot advance current output sequence even with malformed inner content.
-spec old_session_does_not_affect_live_calls_test() -> ok.
old_session_does_not_affect_live_calls_test() ->
    with_backend(fun(Backend,Management,Application,_Authority,Endpoint)->
        Call=gen_server:send_request(Endpoint,{sample,3}),
        {_,<<_:160,Q:32/little,_/binary>>}=sent(Application,2),
        deliver(Backend,{0,1},3,<<40:64/little,255:32/little>>),
        deliver(Backend,{0,0},1,<<40:64/little,255:32/little>>),
        ?assertMatch(#{received:=0,pending:=1,ignored:=2},hls_domain_fabric:info(Backend)),
        ?assertEqual(timeout,gen_server:wait_response(Call,0)),
        deliver(Backend,{0,1},2,response(1,1,Q,0,<<>>)),
        deliver(Backend,{0,1},3,response(2,1,Q,16#02000001,<<6:3,0:29>>)),
        ?assertEqual({reply,{answer,6}},gen_server:receive_response(Call,1000)),
        ?assertMatch({ok,#{actors:=#{worker:=Endpoint}}},status(Backend,Management,ready,1,2))
    end).

%% A proved pre-admission rejection rotates slots; it never retransmits the rejected request.
-spec busy_orphan_slot_does_not_starve_free_slots_test() -> ok.
busy_orphan_slot_does_not_starve_free_slots_test() ->
    I=interface(),#{actors:=#{worker:=Binding=#{contract:=Contract}}}=I,
    Two=I#{actors:=#{worker=>Binding#{contract:=Contract#{pending_calls:=2}}}},
    with_transport(Two,#{},fun(Backend,Management,Application)->
        {ok,_}=hls_domain_fabric:attach(Backend,self()),
        {ok,#{actors:=#{worker:=Endpoint}}}=status(Backend,Management,ready,1,0),
        First=gen_server:send_request(Endpoint,{sample,3}),
        {_,<<_:160,Q1:32/little,1:32/little,0:32/little,_/binary>>}=sent(Application,2),
        deliver(Backend,{0,1},2,<<41:64/little,1:32/little,1:64/little,3:32/little,Q1:32/little,3:32/little,0:64>>),
        ?assertEqual({reply,{error,busy}},gen_server:receive_response(First,1000)),
        receive {wire,Application,_,_,_}->error(automatic_retry) after 10->ok end,
        Second=gen_server:send_request(Endpoint,{sample,4}),
        {_,<<_:160,Q2:32/little,1:32/little,1:32/little,_/binary>>}=sent(Application,2),
        ?assertNotEqual(Q1,Q2),
        deliver(Backend,{0,1},2,response(2,1,Q2,0,<<>>)),
        deliver(Backend,{0,1},3,response(3,1,Q2,16#02000101,<<5:3,0:29>>)),
        ?assertEqual({reply,{answer,5}},gen_server:receive_response(Second,1000))
    end).

%% Local restart may precede host observation, but old replies must precede terminal DOWN and acknowledgement.
-spec supervised_receipt_orders_publication_test() -> ok.
supervised_receipt_orders_publication_test() ->
    with_supervised(fun(Backend, Management, Application, Authority, Endpoint) ->
        Monitor = monitor(process, Endpoint),
        Call = gen_server:send_request(Endpoint, {sample, 3}),
        {_, <<41:64/little,1:64/little,3:32/little,Request:32/little,_/binary>>} = sent(Application, 2),
        deliver(Backend, {0,1}, 2, response(1, 1, Request, 0, <<>>)),
        Receipt = #{incarnation=>1, phase=>failed, fault=>actor_failure, source=>17, actor=>3, frontier=>2},
        ?assertEqual({error,delivery_pending}, supervised_status(Backend, Management, 3, 2, 1, Receipt)),
        ?assertMatch(#{actors:=#{worker:=Endpoint}, received:=1,
            publication:=#{watched:=1,retirement:=Receipt}}, hls_domain_fabric:info(Backend)),
        ?assertEqual({error,not_ready_or_stale}, hls_domain_fabric:endpoint(Backend, Authority, 3, worker)),
        receive {wire,Management,_,3,_}->error(ack_before_delivery) after 10->ok end,
        deliver(Backend, {0,1}, 3, response(2, 1, Request, 16#02000001, <<6:3,0:29>>)),
        ?assertEqual({reply,{answer,6}}, gen_server:receive_response(Call, 1000)),
        receive {'DOWN',Monitor,process,Endpoint,{hls_actor_failure,3,#{source_code:=17}}}->ok
        after 1000->error(old_endpoint_survived) end,
        {Route,<<41:64/little,Ack:32/little,1:64/little>>} = sent(Management,3),
        ?assertNot(is_process_alive(Endpoint)),
        ?assertEqual({error,not_ready_or_stale}, hls_domain_fabric:endpoint(Backend, Authority, 3, worker)),
        deliver(Backend,Route,1,supervised_snapshot(Ack,accepted,3,2,0,none)),
        {Route,<<41:64/little,Watch:32/little,3:64/little>>} = sent(Management,2),
        deliver(Backend,Route,1,supervised_snapshot(Watch,accepted,3,2,3,none)),
        Successor = endpoint(Backend,Authority,3,100),
        ?assertNotEqual(Endpoint,Successor),
        %% A late old-incarnation effect advances the ordered wire but never reaches the new actor.
        deliver(Backend,{0,1},4,response(3,1,0,16#02000001,<<4:3,0:29>>)),
        ?assertMatch(#{received:=3,ignored:=1,actors:=#{worker:=Successor}}, hls_domain_fabric:info(Backend)),
        receive {'$gen_cast',{answer,4}}->error(old_effect_rebound) after 10->ok end
    end).

%% No receipt means connection uncertainty even if a newer ready snapshot looks plausible.
-spec supervised_missing_receipt_is_uncertain_test() -> ok.
supervised_missing_receipt_is_uncertain_test() ->
    with_supervised(fun(Backend,Management,_Application,_Authority,Endpoint)->
        M=monitor(process,Endpoint),
        Request=gen_server:send_request(Backend,status),
        {Route,<<41:64/little,Sequence:32/little>>}=sent(Management,0),
        deliver(Backend,Route,1,supervised_snapshot(Sequence,ok,2,0,1,none)),
        receive {'DOWN',M,process,Endpoint,Reason}->?assertEqual(noconnection,Reason)
        after 1000->error(missing_uncertainty) end,
        ?assertMatch({error,_},gen_server:receive_response(Request,1000))
    end).

%% Supervisor authority cannot be bypassed by an attached host owner.
-spec supervised_child_rejects_lifecycle_test() -> ok.
supervised_child_rejects_lifecycle_test() ->
    with_supervised(fun(Backend,Management,_Application,Authority,_Endpoint)->
        ?assertEqual({error,supervised_child},hls_domain_fabric:request(Backend,Authority,
            #domain_input{op=replace,expected=1,target=2,transition=2})),
        receive {wire,Management,_,1,_}->error(host_mutated_child) after 10->ok end
    end).

%% A watch race skips an unseen lifetime without producing a PID or a terminal source claim for it.
-spec supervised_watch_race_test() -> ok.
supervised_watch_race_test() ->
    with_transport((interface())#{supervision=>local},#{},fun(Backend,Management,_Application)->
        {ok,Authority}=hls_domain_fabric:attach(Backend,self()),
        ?assertEqual({error,publication_pending},supervised_status(Backend,Management,1,0,0,none)),
        {Route,<<41:64/little,First:32/little,1:64/little>>}=sent(Management,2),
        deliver(Backend,Route,1,supervised_snapshot(First,stale,2,0,0,none)),
        {Route,<<41:64/little,Next:32/little,2:64/little>>}=sent(Management,2),
        ?assertEqual({error,not_ready_or_stale},hls_domain_fabric:endpoint(Backend,Authority,1,worker)),
        deliver(Backend,Route,1,supervised_snapshot(Next,accepted,2,0,2,none)),
        ?assert(is_pid(endpoint(Backend,Authority,2,100)))
    end).

%% A retained record cannot quietly change after it has promised a particular output frontier.
-spec supervised_receipt_is_immutable_test() -> ok.
supervised_receipt_is_immutable_test() ->
    with_supervised(fun(Backend,Management,_Application,_Authority,Endpoint)->
        M=monitor(process,Endpoint),
        Receipt=#{incarnation=>1,phase=>failed,fault=>actor_failure,source=>17,actor=>3,frontier=>1},
        ?assertEqual({error,delivery_pending},supervised_status(Backend,Management,2,1,1,Receipt)),
        Request=gen_server:send_request(Backend,status),
        {Route,<<41:64/little,Sequence:32/little>>}=sent(Management,0),
        deliver(Backend,Route,1,supervised_snapshot(Sequence,ok,3,2,1,Receipt#{frontier:=2})),
        receive {'DOWN',M,process,Endpoint,Reason}->?assertEqual(noconnection,Reason)
        after 1000->error(mutable_receipt_accepted) end,
        ?assertMatch({error,_},gen_server:receive_response(Request,1000))
    end).

%% An independent management handshake watches the ready lifetime before its endpoint is exposed.
-spec with_supervised(fun((pid(),pid(),pid(),reference(),pid())->term())) -> ok.
with_supervised(Test) ->
    with_transport((interface())#{supervision=>local},#{},fun(Backend,Management,Application)->
        {ok,Authority}=hls_domain_fabric:attach(Backend,self()),
        ?assertEqual({error,publication_pending},supervised_status(Backend,Management,1,0,0,none)),
        {Route,<<41:64/little,Sequence:32/little,1:64/little>>}=sent(Management,2),
        deliver(Backend,Route,1,supervised_snapshot(Sequence,accepted,1,0,1,none)),
        Endpoint=endpoint(Backend,Authority,1,100),
        Test(Backend,Management,Application,Authority,Endpoint)
    end).

%% The fixture supplies each explicit device observation through the ordinary broker frame callback.
-spec supervised_status(pid(),pid(),non_neg_integer(),non_neg_integer(),non_neg_integer(),none|map()) -> term().
supervised_status(Backend,Management,Current,Frontier,Watched,Receipt) ->
    Request=gen_server:send_request(Backend,status),
    {Route,<<41:64/little,Sequence:32/little>>}=sent(Management,0),
    deliver(Backend,Route,1,supervised_snapshot(Sequence,ok,Current,Frontier,Watched,Receipt)),
    {reply,Result}=gen_server:receive_response(Request,1000),Result.

%% Wire literals are deliberately independent of the production encoder and hardware implementation.
-spec supervised_snapshot(pos_integer(),ok|accepted|stale,non_neg_integer(),non_neg_integer(),non_neg_integer(),none|map()) -> binary().
supervised_snapshot(Sequence,Status,Current,Frontier,Watched,Receipt) ->
    <<Prefix:12/binary,_Status:32/little,Rest/binary>>=snapshot(Sequence,ready,Current,Frontier),
    Code=case Status of ok->0;accepted->1;stale->3 end,
    Suffix=case Receipt of
        none-><<Watched:64/little,0:32,0:64,0:160>>;
        #{incarnation:=Epoch,phase:=failed,fault:=actor_failure,source:=Source,actor:=Actor,frontier:=End}->
            <<Watched:64/little,1:32/little,Epoch:64/little,5:32/little,1:32/little,Source:32/little,Actor:32/little,End:32/little>>
    end,
    <<Prefix/binary,Code:32/little,Rest/binary,Suffix/binary>>.

%% Parent reset clears a child core but preserves its terminal receipt and the host's incarnation floor.
-spec supervised_parent_reset_test() -> ok.
supervised_parent_reset_test() ->
    with_supervised(fun(Backend,Management,_Application,Authority,Endpoint)->
        Monitor=monitor(process,Endpoint),
        Receipt=#{incarnation=>1,phase=>failed,fault=>actor_failure,source=>17,actor=>3,frontier=>0},
        Query=gen_server:send_request(Backend,status),
        {Route,<<41:64/little,Sequence:32/little>>}=sent(Management,0),
        deliver(Backend,Route,1,supervised_phase_snapshot(Sequence,ok,unbound,0,0,1,Receipt)),
        ?assertMatch({reply,{ok,#{state:=#domain_state{phase=unbound,current=0}}}},
            gen_server:receive_response(Query,1000)),
        receive {'DOWN',Monitor,process,Endpoint,{hls_actor_failure,3,_}}->ok
        after 1000->error(reset_receipt_not_delivered) end,
        {Route,<<41:64/little,Ack:32/little,1:64/little>>}=sent(Management,3),
        deliver(Backend,Route,1,supervised_phase_snapshot(Ack,accepted,unbound,0,0,0,none)),
        ?assertEqual({error,publication_pending},supervised_status(Backend,Management,5,0,0,none)),
        {Route,<<41:64/little,Watch:32/little,5:64/little>>}=sent(Management,2),
        deliver(Backend,Route,1,supervised_snapshot(Watch,accepted,5,0,5,none)),
        ?assertNotEqual(Endpoint,endpoint(Backend,Authority,5,100))
    end).

%% A reset cannot justify recycling an earlier incarnation, even after every old endpoint has died.
-spec supervised_reset_rejects_identity_reuse_test() -> ok.
supervised_reset_rejects_identity_reuse_test() ->
    with_transport((interface())#{supervision=>local},#{},fun(Backend,Management,_Application)->
        %% No attached observer is needed to retain the authoritative high-water observation.
        ?assertMatch({ok,#{state:=#domain_state{current=7}}},
            supervised_status(Backend,Management,7,0,0,none)),
        Query=gen_server:send_request(Backend,status),
        {Route,<<41:64/little,Reset:32/little>>}=sent(Management,0),
        deliver(Backend,Route,1,supervised_phase_snapshot(Reset,ok,unbound,0,0,0,none)),
        ?assertMatch({reply,{ok,#{state:=#domain_state{current=0}}}},gen_server:receive_response(Query,1000)),
        Monitor=monitor(process,Backend),
        Again=gen_server:send_request(Backend,status),
        {Route,<<41:64/little,Reuse:32/little>>}=sent(Management,0),
        deliver(Backend,Route,1,supervised_snapshot(Reuse,ok,7,0,0,none)),
        receive {'DOWN',Monitor,process,Backend,{invalid_domain_frame,error,incarnation_regression}}->ok
        after 1000->error(reused_incarnation_accepted) end,
        ?assertMatch({error,_},gen_server:receive_response(Again,1000))
    end).

%% Reset observations vary only the current lifecycle fields; receipt evidence is independently retained.
-spec supervised_phase_snapshot(pos_integer(),ok|accepted|stale,unbound|ready,
    non_neg_integer(),non_neg_integer(),non_neg_integer(),none|map()) -> binary().
supervised_phase_snapshot(Sequence,Status,Phase,Current,Frontier,Watched,Receipt) ->
    <<Prefix:20/binary,_OldPhase:32/little,Rest/binary>>=
        supervised_snapshot(Sequence,Status,Current,Frontier,Watched,Receipt),
    Code=case Phase of unbound->0;ready->1 end,
    <<Prefix/binary,Code:32/little,Rest/binary>>.

%% Independent application delivery may win the race with a successful management watch response.
-spec supervised_effect_before_watch_response_test() -> ok.
supervised_effect_before_watch_response_test() ->
    with_transport((interface())#{supervision=>local},#{},fun(Backend,Management,_Application)->
        {ok,Authority}=hls_domain_fabric:attach(Backend,self()),
        ?assertEqual({error,publication_pending},supervised_status(Backend,Management,1,0,0,none)),
        {Route,<<41:64/little,Watch:32/little,1:64/little>>}=sent(Management,2),
        deliver(Backend,{0,1},4,response(1,1,0,16#02000001,<<5:3,0:29>>)),
        ?assertMatch(#{received:=0,deferred:=true,actors:=#{}},hls_domain_fabric:info(Backend)),
        receive {'$gen_cast',{answer,5}}->error(effect_before_watch_confirmation) after 10->ok end,
        deliver(Backend,Route,1,supervised_snapshot(Watch,accepted,1,1,1,none)),
        receive {'$gen_cast',{answer,5}}->ok after 1000->error(watched_effect_lost) end,
        ?assert(is_pid(endpoint(Backend,Authority,1,100))),
        ?assertMatch(#{received:=1,deferred:=false},hls_domain_fabric:info(Backend))
    end).

%% Even a watch that ends before confirmation must deliver accepted effects before its receipt is released.
-spec supervised_effect_and_failure_before_watch_response_test() -> ok.
supervised_effect_and_failure_before_watch_response_test() ->
    with_transport((interface())#{supervision=>local},#{},fun(Backend,Management,_Application)->
        {ok,Authority}=hls_domain_fabric:attach(Backend,self()),
        ?assertEqual({error,publication_pending},supervised_status(Backend,Management,1,0,0,none)),
        {Route,<<41:64/little,Watch:32/little,1:64/little>>}=sent(Management,2),
        deliver(Backend,{0,1},4,response(1,1,0,16#02000001,<<6:3,0:29>>)),
        Receipt=#{incarnation=>1,phase=>failed,fault=>actor_failure,source=>17,actor=>3,frontier=>1},
        deliver(Backend,Route,1,supervised_snapshot(Watch,accepted,2,1,1,Receipt)),
        receive {'$gen_cast',{answer,6}}->ok after 1000->error(terminal_watch_effect_lost) end,
        {Route,<<41:64/little,Ack:32/little,1:64/little>>}=sent(Management,3),
        ?assertEqual({error,not_ready_or_stale},hls_domain_fabric:endpoint(Backend,Authority,1,worker)),
        deliver(Backend,Route,1,supervised_snapshot(Ack,accepted,2,1,0,none)),
        {Route,<<41:64/little,Next:32/little,2:64/little>>}=sent(Management,2),
        deliver(Backend,Route,1,supervised_snapshot(Next,accepted,2,1,2,none)),
        ?assert(is_pid(endpoint(Backend,Authority,2,100)))
    end).

%% A still-ready raw child after parent closure cannot reacquire its retired host identity.
-spec supervised_terminal_identity_not_republished_test() -> ok.
supervised_terminal_identity_not_republished_test() ->
    with_supervised(fun(Backend,Management,_Application,Authority,Endpoint)->
        Monitor=monitor(process,Endpoint),
        Receipt=#{incarnation=>1,phase=>failed,fault=>actor_failure,source=>17,actor=>3,frontier=>0},
        ?assertEqual({error,delivery_pending},supervised_status(Backend,Management,1,0,1,Receipt)),
        receive {'DOWN',Monitor,process,Endpoint,{hls_actor_failure,3,_}}->ok
        after 1000->error(old_endpoint_survived) end,
        {Route,<<41:64/little,Ack:32/little,1:64/little>>}=sent(Management,3),
        deliver(Backend,Route,1,supervised_snapshot(Ack,accepted,1,0,0,none)),
        ?assertEqual({error,not_ready_or_stale},hls_domain_fabric:endpoint(Backend,Authority,1,worker)),
        receive {wire,Management,_,2,_}->error(retired_incarnation_watched) after 10->ok end,
        ?assertEqual({error,publication_pending},supervised_status(Backend,Management,2,0,0,none)),
        {Route,<<41:64/little,Watch:32/little,2:64/little>>}=sent(Management,2),
        deliver(Backend,Route,1,supervised_snapshot(Watch,accepted,2,0,2,none)),
        ?assertNotEqual(Endpoint,endpoint(Backend,Authority,2,100))
    end).
