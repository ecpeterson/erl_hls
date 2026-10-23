-module(hls_protocol_mixed_distribution_fixture).
-moduledoc "Bounded central-owner fixture for distribution witnesses; models neither hardware credits nor an application.".
-behaviour(gen_server).
-export([start/2, sender/0, init/1, handle_call/3, handle_cast/2, handle_info/2]).

-doc "Starts an unbound owner with exact sender PIDs and a test observer.".
-spec start([pid()],pid()) -> gen_server:start_ret().
start(Senders,Observer)->gen_server:start(?MODULE,{Senders,Observer},[]).
-doc "Runs a real BEAM sender used to exercise negotiated sender identity; stops on stop.".
-spec sender() -> ok.
sender()->receive
    {send,Targets,Values,Observer}->
        [gen_server:cast(lists:nth(1+((V-1) rem length(Targets)),Targets),{work,V})||V<-Values],
        Observer!{sent,self()},sender();
    stop->ok
end.
-doc "Retains one withheld handoff and finite witnessed events.".
-spec init({[pid()],pid()}) -> {ok,map()}.
init({Senders,Observer})->{ok,#{senders=>Senders,observer=>Observer,bound=>false,
    connected=>false,hold=>true,pending=>none,events=>[],count=>0}}.
-doc "Checks one binding/connection and records authenticated handoffs, optionally withholding their capacity reply.".
-spec handle_call(term(),gen_server:from(),map()) -> {reply,term(),map()}|{noreply,map()}.
%% The same owner cannot bind a replacement virtual incarnation.
handle_call({source_bind,Identity,Handles},{Manager,_},State=#{bound:=false})->
    Ref=monitor(process,Manager),
    {reply,ok,State#{bound:=true,identity=>Identity,handles=>Handles,manager=>Manager,manager_ref=>Ref}};
%% One connection only, from the manager that activated this owner.
handle_call({source_attach,Connection},{Manager,_},State=#{manager:=Manager,connected:=false})->
    {reply,ok,State#{connected:=true,connection=>Connection}};
%% Hold exactly one incoming record; connection credit prevents another call until reply.
handle_call({source_send,Sender,Destination,Record},From={Connection,_},
        State=#{connection:=Connection,senders:=Senders,hold:=Hold,pending:=none,count:=Count})->
    true=lists:member(Sender,Senders),true=lists:member(Destination,[{actor,2},{actor,3}]),
    Next=State#{count:=Count+1},
    case Hold of true->{noreply,Next#{pending:={From,{Sender,Destination,Record}}}};
        false->{reply,ok,record({Sender,Destination,Record},Next)} end;
%% Release withheld work once, then admit later requests immediately.
handle_call(release,_From,State=#{pending:={From,Event}})->
    gen_server:reply(From,ok),{reply,ok,record(Event,State#{hold:=false,pending:=none})};
%% Report fixture events and request count for exact boundedness assertions.
handle_call(info,_From,State)->{reply,State,State}.
-doc "Rejects unexpected asynchronous input to the central owner.".
-spec handle_cast(term(),map()) -> {stop,term(),map()}.
handle_cast(Message,State)->{stop,{unexpected_cast,Message},State}.
-doc "Ends ownership when the bound virtual manager terminates.".
-spec handle_info(term(),map()) -> {stop,term(),map()}.
handle_info({'DOWN',Ref,process,_Pid,_Reason},State=#{manager_ref:=Ref})->{stop,normal,State}.
%% The observer is diagnostic only; the production central owner will consume real source records.
-spec record(tuple(),map()) -> map().
record(Event,State=#{events:=Events,observer:=Observer})->
    Observer!{source_event,Event},State#{events:=[Event|Events]}.
