-module(hls_protocol_mixed_admission_tests).
-moduledoc "Finite admission/lifetime witnesses against actual hls_statem processes. No full RTL application, general progress or isolation claim.".
-export([run/0]).
-include_lib("eunit/include/eunit.hrl").

%% Bound real-process lifetime witnesses independently of the RTL integration job.
-spec runtime_test_() -> tuple().
runtime_test_()->{timeout,30,fun run/0}.


-doc "Checks postponement, full-mailbox backpressure, independent actors, same-sender barriers, stale owner, actor death and ambiguous post-cast timeout. Stops every fixture actor before returning.".
-spec run() -> ok.
run()->
    basic(),death(),ambiguous(),
    io:format("PASS actual BEAM admission: postponement, bounded mailbox, independent actor, owner, death, ambiguous timeout/no replay~n"),ok.

%% A full postponed actor must not prevent a different actor from admitting its phase-advancing input.
-spec basic() -> ok.
basic()->
    A=start(),B=start(),
    try
        S=hls_protocol_mixed_admission:new(#{0=>#{pid=>A,capacity=>2},1=>#{pid=>B,capacity=>2}},1000),
        {ok,S1}=hls_protocol_mixed_admission:deliver(0,{later,10},S),
        {ok,S2}=hls_protocol_mixed_admission:deliver(0,{later,11},S1),
        {busy,S2}=hls_protocol_mixed_admission:deliver(0,{go},S2),
        #{postponed:=2,mailbox:=#{occupied:=2}}=hls_statem:info(A),
        {ok,S3}=hls_protocol_mixed_admission:deliver(1,{later,20},S2),
        {ok,S4}=hls_protocol_mixed_admission:deliver(1,{go},S3),
        #{phase:=running,data:=[20],mailbox:=#{occupied:=0}}=hls_statem:info(B),
        {ok,S5}=hls_protocol_mixed_admission:deliver(1,{later,21},S4),
        #{data:=[21,20]}=hls_statem:info(B),
        #{admitted:=5}=hls_protocol_mixed_admission:info(S5),
        Owner=self(),{_,Ref}=spawn_monitor(fun()->Owner!{foreign,reject(deliver,[1,{later,22},S5])} end),
        receive {foreign,ok}->ok after 1000->error(foreign_owner) end,
        receive {'DOWN',Ref,process,_,normal}->ok after 1000->error(foreign_retirement) end,
        Dead=hls_protocol_mixed_admission:retire(S5),
        ok=reject(deliver,[1,{later,22},Dead]),
        #{data:=[21,20]}=hls_statem:info(B),ok
    after stop(A),stop(B) end.

%% Monitors belong to the central owner; one bound actor's death retires the whole attachment.
-spec death() -> ok.
death()->
    A=start(),S=hls_protocol_mixed_admission:new(#{0=>#{pid=>A,capacity=>2}},1000),
    stop(A),
    receive {'DOWN',Ref,process,A,normal}->
        {error,{actor_down,0,normal},Dead}=hls_protocol_mixed_admission:down(Ref,normal,S),
        #{live:=false,actors:=0}=hls_protocol_mixed_admission:info(Dead),ok
    after 1000->error(missing_monitor) end.

%% The cast executes once after our barrier times out; absence of ACK is not permission to replay it.
-spec ambiguous() -> ok.
ambiguous()->
    A=start(),
    try
        S=hls_protocol_mixed_admission:new(#{0=>#{pid=>A,capacity=>2}},20),
        {error,{admission_failed,exit,_},Dead}=hls_protocol_mixed_admission:deliver(0,{slow,7},S),
        #{live:=false,admitted:=0}=hls_protocol_mixed_admission:info(Dead),
        ok=reject(deliver,[0,{slow,7},Dead]),
        #{data:=[7],mailbox:=#{occupied:=0}}=hls_statem:info(A,1000),ok
    after stop(A) end.

%% All normal application messages originate in the central test owner; fixture actors never send to each other.
-spec start() -> pid().
start()->{ok,P}=hls_statem:start_link(hls_protocol_mixed_admission_actor,[],[{mailbox_capacity,2},{outputs,#{}}]),unlink(P),P.

%% Synchronous retirement leaves no fixture processes behind, including failed assertions.
-spec stop(pid()) -> ok.
stop(P)->case is_process_alive(P) of true->hls_statem:stop(P);false->ok end.

%% Deliberate invalid-domain calls use runtime dispatch, without suppressing production type errors.
-spec reject(atom(),[term()]) -> ok.
reject(F,Args)->R=try apply(hls_protocol_mixed_admission,F,Args),accepted catch error:_->rejected end,rejected=R,ok.
