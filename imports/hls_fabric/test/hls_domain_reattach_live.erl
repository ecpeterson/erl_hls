-module(hls_domain_reattach_live).
-moduledoc "Finite real-peer/FIFO/RTL witness of transport replacement. Public packets and sampled pins provide the evidence; no simulator register mutation or actor replay is used.".
-include("hls_recovery_profile.hrl").
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").
%% External driver and helpers executed on the separate ERTS peer.
-export([run/1, uncertain_selection/2, watch/2, unavailable/1]).

-doc "Disconnects an admitted call, retires its actual broker descriptors, and reattaches the same virtual PID to surviving RTL state in a fresh transport session.".
-spec run(file:filename()) -> ok.
run(Stage) ->
    Interface=filename:join(Stage,"interface.etf"),
    {ok,DA}=hls_recovery_device_model:start_link(), unlink(DA),
    {ok,DB}=hls_recovery_device_model:start_link(), unlink(DB),
    ABase=filename:join(Stage,"domain0"), BBase=filename:join(Stage,"domain1"),
    ok=hls_recovery_stream_live:session(ABase,1),
    ok=hls_recovery_stream_live:session(BBase,1),
    {A,ABrokers}=hls_recovery_stream_live:backend(ABase,Interface,DA,1),
    {B,BBrokers}=hls_recovery_stream_live:backend(BBase,Interface,DB,1),
    OwnerA=owner(a,A,Stage), OwnerB=owner(b,B,Stage),
    {ok,_}=hls_domain:activate(OwnerA,a), {ok,_}=hls_domain:activate(OwnerB,b),
    #{handle:=HA}=ready(OwnerA,a), #{handle:=HB}=ready(OwnerB,b),
    hls_test_nodes:distribution(), {ok,_}=application:ensure_all_started(crypto),
    Name=list_to_atom("reattach_"++integer_to_list(erlang:unique_integer([positive]))++"@localhost"),
    {ok,Node}=hls_node:start_link(Name,#{},[#{name=>a,domain=>#{owner=>OwnerA,id=>a}},
        #{name=>b,domain=>#{owner=>OwnerB,id=>b}}],#{}), unlink(Node),
    {Peer,Remote}=hls_test_nodes:start_peer(),
    try
        #{a:=#{actors:=#{actuator:=VA}},b:=Published=#{actors:=#{actuator:=VB}}}=hls_node:services(Node),
        #profile_status{status=?PROFILE_PENDING}=erpc:call(Remote,hls_statem,call,
            [VA,#select_profile{request=7,epoch=0,profile=0}]),
        ok=erpc:call(Remote,gen_server,cast,[VA,#apply_profile{request=7,epoch=0}]),
        #profile_status{status=?PROFILE_APPLIED,epoch=1}=erpc:call(Remote,hls_statem,call,
            [VA,#query_profile{request=7,epoch=0}]),
        {ok,OldProxy}=hls_domain:resolve(OwnerB,HB,actuator),
        ProxyMonitor=monitor(process,OldProxy),
        ok=hls_recovery_stream_live:delivery(Stage,1,application,hold),
        Waiter=erpc:call(Remote,?MODULE,uncertain_selection,[VB,self()]),
        %% Admission and reply have actually left the RTL, but remain in the old adapter queue.
        _=await(fun()-> case hls_domain_fabric:info(B) of
            #{received:=0,frontier:=F}=I when F>=2 -> {ok,I}; _->wait end end),
        exit(B,kill),
        receive {'DOWN',ProxyMonitor,process,OldProxy,noconnection}->ok
            after 5000->error(proxy_did_not_disconnect) end,
        %% OTP gen:do_call translates monitor noconnection to a nodedown call exit.
        VirtualNode=node(VB),
        receive {uncertain,Waiter,Outcome,Down}->
            {error,{{nodedown,VirtualNode},_}}=Outcome, noconnection=Down
            after 5000->error(remote_call_did_not_fail) end,
        noconnection=erpc:call(Remote,?MODULE,unavailable,[VB]),
        #profile_status{status=?PROFILE_APPLIED,epoch=1}=erpc:call(Remote,hls_statem,call,
            [VA,#query_profile{request=7,epoch=0}]),
        OldLeases=leases(BBrokers), [ok=hls_fabric:stop(P)||P<-BBrokers],
        %% A deliberately incomplete physical packet is accepted on the old input before rotation.
        %% It cannot be repaired by sending an in-band reset through that parser.
        {ok,Partial}=file:open(BBase++"_application_tx",[write,raw,binary]),
        ok=file:write(Partial,<<1:16/little,0:16/little,16#0200000a:32/little,16#d00dfeed:32/little>>),
        ok=file:close(Partial),
        %% Scheduling allows acceptance; the driver requires its actual accepted-word trace after the run.
        receive after 10->ok end,
        ok=control(BBase++"_transport",2),
        [ok=hls_fabric:await_closed(L,5000)||L<-OldLeases],
        ok=hls_recovery_stream_live:session(BBase,2),
        ok=hls_recovery_stream_live:delivery(Stage,1,application,resume),
        {Fresh,FreshBrokers}=hls_recovery_stream_live:backend(BBase++"_transport2",Interface,DB,2),
        try
            {ok,#{handle:=HB}}=hls_domain:reattach(OwnerB,HB,Fresh),
            {ok,FreshProxy}=hls_domain:resolve(OwnerB,HB,actuator),
            true=FreshProxy=/=OldProxy,
            {ok,Published}=hls_node:reattach_domain(Node,b),
            #profile_status{status=?PROFILE_PENDING,epoch=0}=erpc:call(Remote,hls_statem,call,
                [VB,#query_profile{request=25,epoch=0}]),
            FreshWatcher=erpc:call(Remote,?MODULE,watch,[VB,self()]),
            receive {watching,FreshWatcher}->ok after 5000->error(no_new_monitor) end,
            Waiter!check_old_monitor,
            receive {old_monitor_terminal,Waiter}->ok after 5000->error(old_monitor_revived) end,
            ok=stale_packets(FreshBrokers,Interface,HB),
            %% Matching current-session reads still see the selected state; stale fault/apply packets had no effect.
            #profile_status{status=?PROFILE_PENDING,epoch=0}=erpc:call(Remote,hls_statem,call,
                [VB,#query_profile{request=25,epoch=0}]),
            ok=erpc:call(Remote,gen_server,cast,[VB,#apply_profile{request=25,epoch=0}]),
            #profile_status{status=?PROFILE_APPLIED,epoch=1,profile=1,enabled=16#fe}=
                erpc:call(Remote,hls_statem,call,[VB,#query_profile{request=25,epoch=0}]),
            _=await(fun()->case hls_recovery_device_model:snapshot(DB) of
                #{effects:=[#profile_applied{request=25,epoch=1,profile=1}]}->{ok,done}; _->wait end end),
            {ok,#{handle:=HA}}=hls_domain:status(OwnerA,a),
            {ok,#{handle:=HB}}=hls_domain:status(OwnerB,b),
            %% A real source failure still terminates the incarnation and the newly established monitor.
            ok=erpc:call(Remote,gen_server,cast,[VB,#controller_failure{reason=1}]),
            receive {down,FreshWatcher,Reason}->true=Reason=/=noconnection andalso Reason=/=noproc
                after 5000->error(no_source_failure) end,
            Result=#{passed=>true,evidence=>finite_public_port_reattachment_witness,
                real_erts_peer=>true,uncertain_call_not_replayed=>true,actor_state_preserved=>true,
                domain_incarnation_preserved=>true,virtual_pid_preserved=>true,old_monitor_terminal=>true,
                new_monitor_observed_source_failure=>true,stale_session_fault_and_cast_ignored=>true,
                independent_domain_progress=>true,old_descriptor_closure=>true,
                transport_sessions=>[1,2],old_buffered_reply_discarded=>true},
            [ok=gen_server:stop(P,normal,5000)||P<-[OwnerA,OwnerB,A,Fresh]],
            CurrentBrokers=ABrokers++FreshBrokers, Leases=leases(CurrentBrokers),
            [ok=hls_fabric:stop(P)||P<-CurrentBrokers],
            ok=file:write_file(filename:join(Stage,"finished"),<<>>,[exclusive]),
            [ok=hls_fabric:await_closed(L,5000)||L<-Leases],
            ok=file:write_file(filename:join(Stage,"result.json"),json:encode(Result#{descriptor_closure=>true}),[exclusive])
        after catch hls_domain_fabric:stop(Fresh), [catch hls_fabric:stop(P)||P<-FreshBrokers] end
    after
        peer:stop(Peer),catch hls_node:stop(Node),
        [catch gen_server:stop(P,normal,5000)||P<-[OwnerA,OwnerB,A,B,DA,DB]++ABrokers++BBrokers]
    end.

-doc "Issues one remote call whose reply will be withheld; a later monitor remains independent of this one-shot monitor.".
-spec uncertain_selection(pid(),pid()) -> pid().
uncertain_selection(Actor,Parent)->spawn(fun()->
    Ref=monitor(process,Actor),
    Outcome=try hls_statem:call(Actor,#select_profile{request=25,epoch=0,profile=1}) of
        Reply->{reply,Reply} catch exit:Reason->{error,Reason} end,
    Down=receive {'DOWN',Ref,process,Actor,R}->R after 5000->error(missing_down) end,
    Parent!{uncertain,self(),Outcome,Down},
    receive check_old_monitor->
        receive {'DOWN',Ref,process,Actor,_}->error(repeated_down)
            after 20->Parent!{old_monitor_terminal,self()} end
    after 5000->error(no_reconnect_check) end
end).

-doc "Installs a fresh real distribution monitor after reattachment.".
-spec watch(pid(),pid()) -> pid().
watch(Actor,Parent)->spawn(fun()->Ref=monitor(process,Actor),Parent!{watching,self()},
    receive {'DOWN',Ref,process,Actor,Reason}->Parent!{down,self(),Reason}
        after 5000->error(new_monitor_missing_down) end end).

-doc "An unavailable surviving identity reports connection uncertainty, not fabricated actor death.".
-spec unavailable(pid()) -> term().
unavailable(Actor)->Ref=monitor(process,Actor),
    receive {'DOWN',Ref,process,Actor,Reason}->Reason after 5000->error(unavailable_monitor_missing) end.

%% Old sessions cannot fault the surviving domain or apply its selected profile.
-spec stale_packets([pid()],file:filename(),hls_domain:handle()) -> ok.
stale_packets([Management,Application],Path,{_Domain,Incarnation})->
    Interface=#{actors:=#{actuator:=Binding},management_route:=MR,application_route:=AR}=hls_domain_wire:load(Path),
    {Tag,Fault}=hls_domain_wire:management(1,700,#domain_input{op=fault,expected=Incarnation,fault=protocol_failure},Interface),
    ok=hls_fabric:send(Management,MR,{Tag,0,0},Fault),
    {Apply,[]}=hls_domain_wire:request(Binding,cast,#apply_profile{request=25,epoch=0},1,Incarnation,701,255),
    ok=hls_fabric:send(Application,AR,{2,0,0},Apply),ok.

%% Each deployment owns an independent native authority and persistent incarnation allocator.
-spec owner(atom(),pid(),file:filename()) -> pid().
owner(Domain,Backend,Stage)->
    Store=filename:join(Stage,atom_to_list(Domain)++".incarnations"),ok=hls_domain_ids:create(Store),
    {ok,Owner}=hls_domain:start_link(#{Domain=>manual},#{module=>hls_domain_fabric,
        endpoints=>#{Domain=>Backend},incarnation_file=>Store}),unlink(Owner),Owner.

%% Public readiness, never elapsed initialization time, permits publication.
-spec ready(pid(),atom()) -> hls_domain:snapshot().
ready(Owner,Domain)->await(fun()->case hls_domain:status(Owner,Domain) of
    {ok,S=#{phase:=ready}}->{ok,S}; _->wait end end).

%% Descriptor leases survive broker death and certify the actual OS handles closed.
-spec leases([pid()]) -> [reference()].
leases(Brokers)->[begin #{io:=#{lease:=Lease}}=hls_fabric:info(B),Lease end||B<-Brokers].

%% Simulator transport rotation acknowledgement is separate from hardware session acknowledgement.
-spec control(file:filename(),pos_integer()) -> ok.
control(Prefix,Value)->
    Bytes=integer_to_binary(Value),ok=file:write_file(Prefix++".next",Bytes),
    ok=file:rename(Prefix++".next",Prefix++".control"),
    await(fun()->case file:read_file(Prefix++".ack") of
        {ok,Actual}->case string:trim(Actual)=:=Bytes of true->{ok,ok};false->wait end;
        _->wait end end).

%% Bound all asynchronous observations without treating a timeout as remote cancellation.
-spec await(fun(() -> {ok,term()} | wait)) -> term().
await(Fun)->await(Fun,erlang:monotonic_time(millisecond)+5000).

%% Preserve failed evidence by terminating this finite witness at its deadline.
-spec await(fun(() -> {ok,term()} | wait),integer()) -> term().
await(Fun,Deadline)->case Fun() of {ok,Result}->Result;wait->
    true=erlang:monotonic_time(millisecond)<Deadline,receive after 1->await(Fun,Deadline) end end.
