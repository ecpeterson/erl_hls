-module(hls_domain_rtl_backend_tests).
-include_lib("eunit/include/eunit.hrl").
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").

%% These direct adapter witnesses supply controller observations; they are not hardware histories.
%% The obsolete source vocabulary is still rejected before any frame reaches the broker.
-spec invalid_source_commands_do_not_write_test() -> ok.
invalid_source_commands_do_not_write_test() ->
    with_broker(fun(Broker) ->
        State = state(Broker, self()),
        lists:foreach(fun(Command) ->
            Ref = make_ref(),
            ?assertEqual({noreply, State}, hls_domain_rtl_backend:handle_cast(
                {application, self(), Ref, counter, 7, call, Command}, State)),
            receive {domain_result, Backend, Ref, {error, unsupported_request}} ->
                ?assertEqual(self(), Backend)
            after 1000 -> error(no_rejection) end
        end, [{add,-1},{add,1 bsl 32},{add,1.0},unknown]),
        receive {wire, Broker, _, _} -> error(invalid_command_wrote_frame) after 0 -> ok end
    end).

%% The owner remains the real sender when the fixture uses the asynchronous backend contract.
-spec asynchronous_request_retains_caller_test() -> ok.
asynchronous_request_retains_caller_test() ->
    with_broker(fun(Broker) ->
        Request = hls_domain_rtl_backend:send_request(Broker, status),
        ?assertEqual({reply, {caller, self()}}, gen_server:receive_response(Request, 1000))
    end).

%% Eight retained calls do not consume the independent cast lane in either adapter or endpoint.
-spec independent_call_and_cast_windows_test() -> ok.
independent_call_and_cast_windows_test() ->
    with_endpoint(fun(Endpoint, Broker) ->
        {State, Calls} = lists:foldl(fun(_, {Previous, Requests}) ->
            Call = gen_server:send_request(Endpoint, read),
            Next = submit(Endpoint, Previous),
            ?assertMatch([7,0,4,_,0], sent(Broker, 2)),
            {Next, [Call | Requests]}
        end, {state(Broker, Endpoint), []}, lists:seq(1, 8)),
        ?assertEqual({error,busy}, gen_server:call(Endpoint, read)),
        Cast = gen_server:send_request(Endpoint, {'$hls_domain_cast',{add,3}}),
        Next = submit(Endpoint, State),
        ?assertEqual([7,0,3,9,3], sent(Broker, 2)),
        ?assertEqual(9, map_size(maps:get(pending, Next))),
        Acked = frame(2, [1,7,0,9,0], Next),
        ?assertEqual({reply,ok}, gen_server:receive_response(Cast, 1000)),
        ?assertEqual(8, map_size(maps:get(pending, Acked))),
        lists:foreach(fun(Call) ->
            ?assertEqual(timeout, gen_server:wait_response(Call, 0)),
            _ = gen_server:receive_response(Call, 0)
        end, Calls),
        release_writes(Acked)
    end).

%% Only an actual application ACK reports admission; a typed reply stays ahead of retirement.
-spec admitted_reply_and_retirement_order_test() -> ok.
admitted_reply_and_retirement_order_test() ->
    with_endpoint(fun(Endpoint, Broker) ->
        Token = make_ref(),
        Call = gen_server:send_request(Endpoint, {'$hls_submit',Token,call,read}),
        Submitted = submit(Endpoint, state(Broker, Endpoint)),
        ?assertEqual([7,0,4,1,0], sent(Broker, 2)),
        receive {hls_admitted,Endpoint,Token} -> error(early_admission) after 0 -> ok end,
        Acked = frame(2, [1,7,0,1,0], Submitted),
        receive {hls_admitted,Endpoint,Token} -> ok after 1000 -> error(missing_admission) end,
        ?assertEqual(timeout, gen_server:wait_response(Call, 0)),
        Monitor = monitor(process, Endpoint),
        Reported = frame(3, [2,7,0,1,23], Acked),
        OwnerMonitor = maps:get(owner_monitor, Reported),
        {noreply, Retired} = hls_domain_rtl_backend:handle_info(
            {'DOWN',OwnerMonitor,process,self(),normal}, Reported),
        ?assertEqual({reply,{value,23}}, gen_server:receive_response(Call, 1000)),
        receive {'DOWN',Monitor,process,Endpoint,noconnection} -> ok
        after 1000 -> error(missing_retirement) end,
        ?assertEqual(#{}, maps:get(pending, Retired)),
        ?assertMatch([_Sequence], sent(Broker, 0)),
        #{timer := Timer} = maps:get(management_pending, Retired),
        erlang:cancel_timer(Timer),
        release_writes(Retired)
    end).

%% Initialize only the adapter fields exercised here, with explicit synthetic ready evidence.
-spec state(pid(), pid()) -> map().
state(Broker, Endpoint) ->
    #{application => Broker, management => Broker, codecs => #{},
        actors => #{counter => Endpoint}, pending => #{}, app_next => 1,
        state => #domain_state{phase=ready,current=7}, actor_incarnation => 7,
        actor_monitor => undefined, owner_monitor => make_ref(), owner => self(), authority => make_ref(),
        sends => gen_server:reqids_new(), management_pending => none, management_queue => queue:new(),
        sequence => 1, retirement => none, retiring_owner => false, retirement_attempts => 0,
        ready_incarnations => 1, last_ready => 7, delivery_received => 0,
        wire_rejected => 0, rejected => 0, ignored => 0}.

%% The real endpoint emits the exact reusable backend application envelope once.
-spec submit(pid(), map()) -> map().
submit(Endpoint, State) ->
    receive {'$gen_cast',Message={application,Endpoint,_Ref,counter,7,_Mode,_Command}} ->
        {noreply, Next} = hls_domain_rtl_backend:handle_cast(Message, State), Next
    after 1000 -> error(no_endpoint_submission) end.

%% Supply one sequenced observation through the fixture's public broker callback.
-spec frame(byte(), [non_neg_integer()], map()) -> map().
frame(Tag, Words, State) ->
    Payload = << <<W:32/little>> || W <- Words >>,
    {noreply, Next} = hls_domain_rtl_backend:handle_cast(
        {'$hls_fabric_frame',make_ref(),{0,0},{Tag,0,0},Payload}, State),
    Next.

%% Consume the public broker write, checking its source-specific framing separately from ACKs.
-spec sent(pid(), byte()) -> [non_neg_integer()].
sent(Broker, Tag) ->
    receive {wire,Broker,Tag,Payload} -> [W || <<W:32/little>> <= Payload]
    after 1000 -> error({missing_frame,Tag}) end.

%% The fixture callback retains write correlations; tests retire every one during cleanup.
-spec release_writes(map()) -> ok.
release_writes(#{sends := Sends}) ->
    lists:foreach(fun({Request,_}) ->
        ?assertEqual({reply,ok}, gen_server:receive_response(Request,1000))
    end, gen_server:reqids_to_list(Sends)).

%% Production endpoints remain monitored; no duplicate request/retirement implementation is used.
-spec with_endpoint(fun((pid(), pid()) -> term())) -> ok.
with_endpoint(Test) ->
    with_broker(fun(Broker) ->
        {ok, Endpoint} = hls_domain_endpoint:start(self(), counter, 7, #{cast=>8,call=>8}),
        try Test(Endpoint,Broker), ok after catch gen_server:stop(Endpoint) end
    end).

%% This broker records writes but deliberately does not invent hardware admission observations.
-spec with_broker(fun((pid()) -> term())) -> ok.
with_broker(Test) ->
    Parent = self(), Broker = spawn(fun() -> broker(Parent) end),
    try Test(Broker), ok after Broker ! stop end.

%% Public broker calls have actual caller identity and ordinary correlated responses.
-spec broker(pid()) -> ok.
broker(Observer) ->
    receive
        {'$gen_call',From={Caller,_},status} ->
            gen_server:reply(From,{caller,Caller}), broker(Observer);
        {'$gen_call',From,{send,{0,0},{Tag,0,0},Payload,_Deadline}} ->
            Observer ! {wire,self(),Tag,Payload}, gen_server:reply(From,ok), broker(Observer);
        {'$gen_cast',{ack,_Owner,_Receipt}} -> broker(Observer);
        stop -> ok
    end.
