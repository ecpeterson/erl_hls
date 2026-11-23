-module(hls_protocol_mixed_distribution_tests).
-moduledoc "Finite witnesses for actual ERTS sender identity, single handoff backpressure and sealed source lifetime. No hardware/application closure claim.".
-export([run/0]).
-include_lib("eunit/include/eunit.hrl").

%% Bound real-process lifetime witnesses independently of the RTL integration job.
-spec runtime_test_() -> tuple().
runtime_test_()->{timeout,30,fun run/0}.

-doc "Exercises real local distribution and direct decoded-packet negatives; raises on any mismatch. Requires the common hls_node distribution adapter on the VM path.".
-spec run() -> ok.
run()->
    hls_test_nodes:distribution(),{ok,_}=application:ensure_all_started(crypto),
    with_node(fun ordered/1),with_node(fun foreign_sender/1),with_node(fun owner_death/1),
    direct_rejection(),io:format("mixed distribution: authentic senders, one handoff, order, lifetime and packet rejection pass~n"),ok.
%% Create one source owner and real sender processes, reusing inert brokers only for node lifetime.
-spec with_node(fun((map())->ok)) -> ok.
with_node(Check)->
    A=spawn(fun hls_protocol_mixed_distribution_fixture:sender/0),
    B=spawn(fun hls_protocol_mixed_distribution_fixture:sender/0),
    {ok,Owner}=hls_protocol_mixed_distribution_fixture:start([A,B],self()),
    {ok,App}=hls_actor_broker_fixture:start(application),{ok,Debug}=hls_actor_broker_fixture:start(debug),
    [_Name,Host]=string:split(atom_to_list(node()),"@"),
    Name=list_to_atom("mixed_source_"++integer_to_list(erlang:unique_integer([positive]))++"@"++Host),
    Services=[#{name=>source,source=>#{owner=>Owner,senders=>[A,B],
        targets=>#{left=>{actor,2},right=>{actor,3}}}}],
    {ok,Node}=hls_node:start_link(Name,#{application=>App,debug=>Debug},Services,#{}),unlink(Node),
    #{source:=#{actors:=Handles}}=hls_node:services(Node),
    try
        pong=net_adm:ping(Name),
        #{connections:=Cs}=hls_node:info(Node),[Connection]=maps:keys(Cs),
        [#{carrier:=Carrier}]=maps:values(Cs),
        Carrier=case init:get_argument(proto_dist) of {ok,[["hls_local"]]}->local;_->tcp end,
        ok=Check(#{node=>Node,name=>Name,owner=>Owner,a=>A,b=>B,handles=>Handles,connection=>Connection}),
        #{events:=[],routes:=#{}}=hls_actor_broker_fixture:stats(App),ok
    after
        catch hls_node:stop(Node),catch gen_server:stop(Owner),
        A!stop,B!stop,catch hls_actor_broker_fixture:stop(App),catch hls_actor_broker_fixture:stop(Debug),flush()
    end.
%% One withheld owner reply stops reading distribution records; resumption retains each sender's order.
-spec ordered(map()) -> ok.
ordered(#{node:=Node,name:=Name,owner:=Owner,a:=A,b:=B,handles:=#{left:=L,right:=R},connection:=C})->
    A!{send,[L,R],lists:seq(1,6),self()},B!{send,[R,L],lists:seq(11,13),self()},
    await(fun()->maps:get(count,gen_server:call(Owner,info))=:=1 end),
    #{source_pending:=true,clients:=2}=gen_server:call(C,info),
    timer:sleep(30),#{count:=1,pending:={_,_}}=gen_server:call(Owner,info),
    ok=gen_server:call(Owner,release),
    await(fun()->maps:get(count,gen_server:call(Owner,info))=:=9 end),
    #{events:=Reverse}=gen_server:call(Owner,info),Events=lists:reverse(Reverse),
    [1,2,3,4,5,6]=[V||{P,_,{work,V}}<-Events,P=:=A],
    [11,12,13]=[V||{P,_,{work,V}}<-Events,P=:=B],
    [{actor,2},{actor,3},{actor,2},{actor,3},{actor,2},{actor,3}]=[D||{P,D,_}<-Events,P=:=A],
    #{source_pending:=false}=gen_server:call(C,info),
    Ref=monitor(process,Node),OR=monitor(process,Owner),true=erlang:disconnect_node(Name),
    down(Ref),down(OR),undefined=hls_node:local_manager(Name),ok.
%% A cookie-authenticated peer still cannot submit an unbound sender PID to this source owner.
-spec foreign_sender(map()) -> ok.
foreign_sender(#{node:=Node,owner:=Owner,handles:=#{left:=L}})->
    Ref=monitor(process,Node),OR=monitor(process,Owner),gen_server:cast(L,{work,99}),
    down(Ref),down(OR),
    receive {source_event,_}->error(accepted_forged_sender) after 20->ok end.
%% Losing the central owner terminates both virtual node and adapter, preserving no reconnect path.
-spec owner_death(map()) -> ok.
owner_death(#{node:=Node,owner:=Owner,connection:=C})->
    Ref=monitor(process,Node),CR=monitor(process,C),ok=gen_server:stop(Owner),down(Ref),down(CR),ok.
%% Feed unsupported wire signals through the real decode/dispatch handler without a socket-side effect.
-spec direct_rejection() -> ok.
direct_rejection()->
    State=#{source_owner=>self(),socket=>fixture,armed=>false,last_received=>0,kernel_pid=>kernel},
    Packet=iolist_to_binary(hls_node_wire:encode({2,unused,self()},{'$gen_cast',{work,1}})),
    try hls_node_connection:handle_info({tcp,fixture,Packet},State) of _->error(senderless_accepted)
    catch error:sender_required->ok end,
    ok.
%% Observe actual process termination with a finite deadline.
-spec down(reference()) -> ok.
down(Ref)->receive {'DOWN',Ref,process,_,_}->ok after 5000->error(lifetime_timeout) end.
%% Bound asynchronous fixture observations without assuming cross-sender chronology.
-spec await(fun(()->boolean())) -> ok.
await(Check)->await(Check,erlang:monotonic_time(millisecond)+5000).
%% Poll only live local fixture state until its finite witness deadline.
-spec await(fun(()->boolean()),integer()) -> ok.
await(Check,Deadline)->case Check() of true->ok;false->
    true=erlang:monotonic_time(millisecond)<Deadline,timer:sleep(5),await(Check,Deadline) end.
%% Discard only finite fixture notifications between independent incarnations.
-spec flush() -> ok.
flush()->receive {source_event,_}->flush();{sent,_}->flush() after 0->ok end.
