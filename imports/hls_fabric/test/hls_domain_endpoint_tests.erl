-module(hls_domain_endpoint_tests).
-include_lib("eunit/include/eunit.hrl").

%% The endpoint, not its backend, sends effects and the following monitor termination signal.
-spec effect_before_down_test() -> ok.
effect_before_down_test() ->
    {ok, Endpoint} = hls_domain_endpoint:start(self(), worker, 7, #{cast=>1,call=>1}),
    Monitor = monitor(process, Endpoint),
    Endpoint ! {domain_effect,self(),self(),{effect,23}},
    Endpoint ! {domain_retire,self(),source_failed},
    receive
        {'$gen_cast',{effect,23}} -> ok;
        {'DOWN',Monitor,process,Endpoint,Reason} -> error({retired_before_effect,Reason})
    after 1000 -> error(no_effect) end,
    receive {'DOWN',Monitor,process,Endpoint,source_failed} -> ok after 1000 -> error(no_retirement) end.

%% Bounded pending observers reject before submission while the old request remains owned.
-spec pending_limit_and_exact_reply_test() -> ok.
pending_limit_and_exact_reply_test() ->
    {ok, Endpoint} = hls_domain_endpoint:start(self(), worker, 7, #{cast=>1,call=>1}),
    Request = gen_server:send_request(Endpoint, {sample,3}),
    Ref = receive {'$gen_cast',{application,Endpoint,R,worker,7,call,{sample,3}}} -> R
        after 1000 -> error(no_request) end,
    ?assertEqual({error,busy}, gen_server:call(Endpoint, {sample,4})),
    Endpoint ! {domain_result,self(),make_ref(),wrong},
    Endpoint ! {domain_result,self(),Ref,{answer,6}},
    ?assertEqual({reply,{answer,6}}, gen_server:receive_response(Request,1000)),
    Monitor=monitor(process,Endpoint), Endpoint!{domain_retire,self(),normal},
    receive {'DOWN',Monitor,process,Endpoint,normal}->ok after 1000->error(no_retirement) end.

%% A backend process disappearing retires its observer as connection uncertainty.
-spec backend_death_test() -> ok.
backend_death_test() ->
    Backend=spawn(fun()->receive stop->ok end end),
    {ok,Endpoint}=hls_domain_endpoint:start(Backend,worker,1,#{cast=>1,call=>1}),
    Monitor=monitor(process,Endpoint), Backend!stop,
    receive {'DOWN',Monitor,process,Endpoint,noconnection}->ok after 1000->error(no_disconnect) end.

%% Full reply ownership does not consume the separate window needed by a release cast.
-spec held_calls_allow_cast_and_capacity_wait_test() -> ok.
held_calls_allow_cast_and_capacity_wait_test() ->
    {ok,E}=hls_domain_endpoint:start(self(),worker,7,#{cast=>1,call=>1}),
    T=make_ref(), C=gen_server:send_request(E,{'$hls_submit',T,call,{sample,3}}),
    R=submitted(E,call), E!{domain_admitted,self(),R},
    receive {hls_admitted,E,T}->ok after 1000->error(no_admission) end,
    ?assertEqual(timeout,gen_server:wait_response(C,0)),
    CT=make_ref(), Cast=gen_server:send_request(E,{'$hls_submit',CT,cast,release}),
    CR=submitted(E,cast),
    ?assertEqual({error,busy},gen_server:call(E,{'$hls_submit',make_ref(),cast,extra})),
    Wait=gen_server:send_request(E,'$hls_capacity'),
    ?assertEqual(timeout,gen_server:wait_response(Wait,0)),
    E!{domain_result,self(),CR,ok},
    receive {hls_admitted,E,CT}->ok after 1000->error(no_cast_admission) end,
    ?assertEqual({reply,ok},gen_server:receive_response(Cast,1000)),
    ?assertEqual({reply,ok},gen_server:receive_response(Wait,1000)),
    E!{domain_result,self(),R,{answer,6}},
    ?assertEqual({reply,{answer,6}},gen_server:receive_response(C,1000)),
    gen_server:stop(E).

%% An explicit pre-I/O rejection has no admission notification and no later replay.
-spec rejected_submit_has_no_admission_test() -> ok.
rejected_submit_has_no_admission_test() ->
    {ok,E}=hls_domain_endpoint:start(self(),worker,7,#{cast=>1,call=>1}),
    T=make_ref(), C=gen_server:send_request(E,{'$hls_submit',T,call,{sample,3}}),
    R=submitted(E,call), E!{domain_result,self(),R,{error,invalid_message}},
    ?assertEqual({reply,{error,invalid_message}},gen_server:receive_response(C,1000)),
    receive {hls_admitted,E,T}->error(false_admission) after 0->ok end,
    gen_server:stop(E).

%% Ordered closure suppresses only late cast rejection, while prior calls still receive their result.
-spec closing_preserves_prior_reply_test() -> ok.
closing_preserves_prior_reply_test() ->
    {ok,E}=hls_domain_endpoint:start(self(),worker,7,#{cast=>1,call=>1}),
    Monitor=monitor(process,E),
    Call=gen_server:send_request(E,{sample,3}), CallRef=submitted(E,call),
    gen_server:cast(E,release), CastRef=submitted(E,cast),
    E!{domain_closing,self()},
    E!{domain_result,self(),CastRef,{error,not_ready_or_stale}},
    gen_server:cast(E,late_release),
    ?assertEqual({error,not_ready_or_stale},gen_server:call(E,{sample,4})),
    receive {'$gen_cast',{application,E,_,_,_,_,_}} -> error(submitted_after_closing)
    after 0 -> ok end,
    E!{domain_result,self(),CallRef,{answer,6}},
    E!{domain_retire,self(),shutdown},
    ?assertEqual({reply,{answer,6}},gen_server:receive_response(Call,1000)),
    receive {'DOWN',Monitor,process,E,shutdown}->ok after 1000->error(no_shutdown) end.

%% Outside ordered retirement, an unacknowledged cast rejection remains a real endpoint failure.
-spec unreported_cast_rejection_test() -> ok.
unreported_cast_rejection_test() ->
    {ok,E}=hls_domain_endpoint:start(self(),worker,7,#{cast=>1,call=>1}),
    Monitor=monitor(process,E), gen_server:cast(E,release), Ref=submitted(E,cast),
    E!{domain_result,self(),Ref,{error,invalid_message}},
    receive {'DOWN',Monitor,process,E,{cast_not_admitted,{error,invalid_message}}}->ok
    after 1000->error(no_cast_failure) end.

%% Requests reach the backend exactly once; hardware observations are supplied separately.
-spec submitted(pid(),call|cast) -> reference().
submitted(E,Mode) ->
    receive {'$gen_cast',{application,E,R,worker,7,Mode,_}}->R
    after 1000->error(no_submission) end.
