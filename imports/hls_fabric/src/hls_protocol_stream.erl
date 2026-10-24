-module(hls_protocol_stream).
-moduledoc "One bounded framed owner for a fixed deployment of source-protocol RTL partitions. The sole application client submits ordered controls and consumes canonical external frames. Any participant failure retires all deployment routes; no write is retried. Transport closure and coordinated hardware reset remain caller obligations.".
-behaviour(gen_server).
-export([start_link/3,start_application/3,submit/2,next/2,info/1,stop/1]).
-export([init/1,handle_call/3,handle_cast/2,handle_info/2,terminate/2]).

-doc "Attaches one fresh broker per deployment device using the descriptor's identity, host and service. Device keys must match brokers and distinct nonzero sessions. Return route pairs must be unique because broker deliveries contain a route but no broker identity. All participants share one reset/retirement domain; the caller exclusively owns commands/events and must retire old transports before reuse.".
-spec start_link(map(),map(),map()) -> gen_server:start_ret().
start_link(Plan,Brokers,Sessions)->gen_server:start_link(?MODULE,{Plan,Brokers,Sessions,self(),raw},[]).

-doc "Attaches a fresh deployment emitted by hls_protocol_deployment with source-checked application codecs. submit accepts typed rectangle commands and next returns {ok,Device,External,Record}; aggregate start uses Device=application. The same bounded owner, crossing queue and collective retirement rules apply; descriptors must be trusted local build outputs.".
-spec start_application(map(),map(),map()) -> gen_server:start_ret().
start_application(Plan=#{application:=Application},Brokers,Sessions)->
    gen_server:start_link(?MODULE,{Plan,Brokers,Sessions,self(),Application},[]).
-doc "Admits raw control bytes (start_link) or a source-checked typed rectangle (start_application), or one-shot start within the deployment command limit. A command reaches all participants before the next command is issued; recipients are not atomically updated. Failure after partial delivery is terminal and must never trigger replay.".
-spec submit(pid(),hls_partition_wire:command() | {control,binary()}) -> {ok,1}|{error,busy}.
submit(Pid,Command)->gen_server:call(Pid,{submit,Command},infinity).
-doc "Returns a canonical external frame in raw mode or a decoded {ok,Device,External,Record} in application mode, or timeout after cancelling the sole waiter. The single started event precedes application output and means all participants acknowledged start; this is not a simultaneous clock-edge guarantee.".
-spec next(pid(),pos_integer()) -> {ok,application | {term(),byte()},term()}|{ok,term(),term(),tuple()}|timeout.
next(Pid,Timeout)->gen_server:call(Pid,{next,Timeout},infinity).
-doc "Reports bounded categories and packet counters without private actor state. ERTS client mailboxes and OS transport buffers are outside the record count.".
-spec info(pid()) -> map().
info(Pid)->gen_server:call(Pid,info).
-doc "Stops new work and waits for the current physical write, then retires all registered routes by ending their owner. Caller must close all transports and await descriptor release before resetting any participant.".
-spec stop(pid()) -> ok.
stop(Pid)->gen_server:call(Pid,retire,infinity).

-doc "Checks complete actor ownership, reserves distinct return routes, and starts serialized attachment. Each broker may hold one credited frame for this owner.".
-spec init(tuple()) -> {ok,map()}.
init({Plan=#{devices:=Devices,limits:=Limits=#{commands:=Commands,events:=Events,crossings:=Crossings}},Brokers,Sessions,Client,Application})
        when is_integer(Commands),Commands>0,is_integer(Events),Events>=2 ->
    Roles=lists:sort(maps:keys(Devices)),Roles=lists:sort(maps:keys(Brokers)),
    true=length(Roles)=:=length(lists:usort(maps:values(Brokers))),
    Queue=hls_protocol_relay_queue:new(Plan,Sessions),
    Bindings=[begin
        true=is_integer(H) andalso H>0 andalso H<65536,
        true=is_integer(V) andalso V>0 andalso V<65536 andalso V=/=H,
        true=is_binary(I) andalso byte_size(I)=:=32,
        {{V,H},R}
    end||{R,#{host:=H,service:=V,identity:=I}}<-maps:to_list(Devices)],
    Returns=maps:from_list(Bindings),true=map_size(Returns)=:=length(Roles),
    [ok=hls_fabric:register_route(maps:get(R,Brokers),Route,self())||{Route,R}<-Bindings],
    Monitors=maps:from_list([{monitor(process,P),{device,R}}||{R,P}<-maps:to_list(Brokers)]++[{monitor(process,Client),client}]),
    Identities=maps:map(fun(_,#{identity:=I})->I end,Devices),
    S=#{application=>Application,devices=>Devices,roles=>Roles,returns=>Returns,limits=>Limits,
      record_limit=>Commands+Events+Crossings+length(Roles)+1,
      brokers=>Brokers,sessions=>Sessions,client=>Client,monitors=>Monitors,identities=>Identities,
      queue=>Queue,phases=>maps:from_keys(Roles,pending),phase=>attaching,starts=>false,
      commands=>queue:new(),events=>queue:new(),held=>#{},writer=>none,sends=>gen_server:reqids_new(),
      waiter=>none,retiring=>none,received=>0,written=>0},
    {ok,work(S)}.

-doc "Serializes control admission, one bounded read and graceful retirement for the sole client.".
-spec handle_call(term(),gen_server:from(),map()) -> {reply,term(),map()}|{noreply,map()}|{stop,normal,ok,map()}.
%% Retire only after the outstanding write is definite; no further packets will be issued.
handle_call(retire,From={Client,_},S=#{client:=Client,retiring:=none,writer:=Writer})->
    case Writer of none->{stop,normal,ok,S};_->{noreply,S#{retiring:=From}} end;
%% One command record carries a deployment fanout cursor; no duplicate per-board queues are hidden.
handle_call({submit,Command},{Client,_},S=#{client:=Client,commands:=Commands,starts:=Started,roles:=Roles,application:=Application,limits:=#{commands:=Limit}})->
    case queue:len(Commands)<Limit of
        false->{reply,{error,busy},S};
        true->Bytes=case Command of start->false=Started,start;
            _->control(Application,Command) end,
            {reply,{ok,1},work(S#{commands:=queue:in({Roles,Bytes},Commands),starts:=Started orelse Command=:=start})}
    end;
%% The owner cancels the timer before replying, avoiding an abandoned late event.
handle_call({next,Timeout},From={Client,_},S=#{client:=Client,waiter:=none}) when Timeout>0->
    Token=make_ref(),Timer=erlang:send_after(Timeout,self(),{next_timeout,Token}),
    {noreply,work(S#{waiter:={From,Token,Timer}})};
%% Count retained records conservatively, including the writer's descriptor.
handle_call(info,_,S=#{queue:=Q,commands:=C,events:=E,held:=H,writer:=W,record_limit:=Limit})->
    QI=hls_protocol_relay_queue:info(Q),
    Counts=#{crossings=>maps:get(records,QI),commands=>queue:len(C),events=>queue:len(E),held=>map_size(H),writer=>occupied(W)},
    true=lists:sum(maps:values(Counts))=<Limit,
    {reply,(maps:with([phase,phases,received,written],S))#{counts=>Counts,record_limit=>Limit,packets=>QI},S}.

-doc "Accepts one credited broker frame per role. Distinct return routes bind the sender to its role before packet validation.".
-spec handle_cast(term(),map()) -> {noreply,map()}.
%% Broker receipt credit is released separately from destination capacity and source delivery ACK.
handle_cast({'$hls_fabric_frame',Receipt,Route,Header,Payload},S=#{held:=Held,returns:=Returns})->
    Role=maps:get(Route,Returns),false=maps:is_key(Role,Held),
    {noreply,work(S#{held:=Held#{Role=>{Receipt,Header,Payload}}})}.

-doc "Commits definite physical completion, cancels timed-out reads and stops globally on a participant failure. Write errors, including definitely-unsent ones, are terminal in this implementation.".
-spec handle_info(term(),map()) -> {noreply,map()}|{stop,term(),map()}.
%% Any transport or client death invalidates all credits and all participant attachments.
handle_info({'DOWN',Ref,process,_,Reason},S=#{monitors:=Monitors})->
    {stop,{shutdown,{maps:get(Ref,Monitors),Reason}},S};
%% Remove the sole waiter before returning timeout.
handle_info({next_timeout,Token},S=#{waiter:={From,Token,_}})->
    gen_server:reply(From,timeout),{noreply,S#{waiter:=none}};
%% A cancelled timer may already have delivered its message.
handle_info({next_timeout,_},S)->{noreply,S};
%% Only a successful write response makes a peer-delivery ACK eligible.
handle_info(Message,S=#{sends:=Sends,writer:=Writer,written:=Count})->
    case gen_server:check_response(Message,Sends,true) of
        {{reply,ok},Writer,Rest}->
            Next=completed(Writer,S#{writer:=none,sends:=Rest,written:=Count+1}),
            case maps:get(retiring,S) of none->{noreply,work(Next)};
                From->gen_server:reply(From,ok),{stop,normal,Next} end;
        {{reply,Error},_,_}->{stop,{shutdown,{write_failed,Error}},S};
        {{error,Error},_,_}->{stop,{shutdown,{writer_failed,Error}},S};
        _->{noreply,S}
    end.

-doc "Cancels a pending read timer. All brokers monitor this same route owner, so its death retires all deployment routes. This callback does not establish physical descriptor closure or reset; the caller must await all transport leases before replacement.".
-spec terminate(term(),map()) -> ok.
terminate(_,#{waiter:=Waiter})->
    case Waiter of none->ok;{_,_,Timer}->erlang:cancel_timer(Timer),ok end.

%% Receive capacity and serialized sends are reconsidered only on real events; no packet retry timer exists.
-spec work(map()) -> map().
work(S=#{retiring:=From}) when From=/=none->S;
work(S)->send_work(notify(receive_frames(notify(S)))).
%% Hold application events until the aggregate started event has been queued in front of them.
-spec notify(map()) -> map().
notify(S=#{phase:=Phase}) when Phase=/=running->S;
notify(S=#{waiter:=none})->S;
notify(S=#{waiter:={From,_,Timer},events:=Events,application:=Application})->
    case queue:out(Events) of {empty,_}->S;
        {{value,{Id,Record}},Rest}->erlang:cancel_timer(Timer),gen_server:reply(From,reply(Application,Id,Record)),S#{waiter:=none,events:=Rest} end.
%% Reserving one event slot for aggregate start prevents early output from blocking the last start ACK.
-spec receive_frames(map()) -> map().
receive_frames(S=#{roles:=Roles})->lists:foldl(fun receive_role/2,S,Roles).
%% Retain the broker receipt while either application capacity or ACK completion blocks admission.
-spec receive_role(term(),map()) -> map().
receive_role(Role,S=#{held:=Held,sessions:=Sessions,brokers:=Brokers,received:=Count})->
    case maps:find(Role,Held) of error->S;
        {ok,{Receipt,Header,Payload}}->
            Event=hls_protocol_bridge_wire:event(maps:get(Role,Sessions),Header,Payload),
            case receive_blocked(Role,Event,S) of true->S;
                false->Next=event(Role,Event,S),hls_fabric:ack(maps:get(Role,Brokers),Receipt),
                    Next#{held:=maps:remove(Role,Held),received:=Count+1} end
    end.

%% The peer may observe its ACK before our asynchronous write-completion message arrives.
%% Keep its next same-link data under the existing one-frame broker credit until complete/2
%% retires the old reservation. Other packets still undergo the ordinary duplicate checks.
-spec receive_blocked(term(),term(),map()) -> boolean().
receive_blocked(Role,{packet,#{kind:=1,link:=Link}},#{writer:={Role,{packet,{ack,Link,_}}}})->true;
receive_blocked(_,{external,_,_},#{events:=Events,limits:=#{events:=Limit}})->queue:len(Events)>=Limit-1;
receive_blocked(_,_,_)->false.

%% The final participant start acknowledgment opens the single application event stream.
-spec event(term(),term(),map()) -> map().
event(Role,attached,S=#{phases:=Phases})->
    attaching=maps:get(Role,Phases),P=Phases#{Role:=attached},
    S#{phases:=P,phase:=case lists:usort(maps:values(P)) of [attached]->attached;_->attaching end};
event(Role,started,S=#{phases:=Phases,events:=Events})->
    starting=maps:get(Role,Phases),P=Phases#{Role:=running},
    case lists:usort(maps:values(P)) of [running]->S#{phases:=P,phase:=running,events:=queue:in_r({application,{started}},Events)};
        _->S#{phases:=P} end;
event(Role,{packet,Packet},S=#{queue:=Q})->S#{queue:=hls_protocol_relay_queue:event(Role,Packet,Q)};
event(Role,{external,Index,Frame},S=#{devices:=Devices,events:=Events})->
    #{externals:=Externals}=maps:get(Role,Devices),
    true=Index<length(Externals),Words=Frame band 255,true=Words=<3,
    0=(Frame bsr 8) band 65535,true=(Frame bsr 32)<(1 bsl (Words*32)),
    S#{events:=queue:in({{Role,Index},Frame},Events)}.

%% Complete a peer transfer only after the shared physical writer succeeds.
-spec completed(tuple(),map()) -> map().
completed({_,{packet,Token}},S=#{queue:=Q})->S#{queue:=hls_protocol_relay_queue:complete(Token,Q)};
completed(_,S)->S.
%% Attachment and command fanout preserve per-board order; data uses the independently checked link scheduler.
-spec send_work(map()) -> map().
send_work(S=#{writer:=W}) when W=/=none->S;
send_work(S=#{phases:=Phases,identities:=Identities,sessions:=Sessions})->
    case [R||{R,pending}<-lists:sort(maps:to_list(Phases))] of
        [R|_]->write(R,attach,hls_protocol_bridge_wire:attach(maps:get(R,Identities),maps:get(R,Sessions)),S#{phases:=Phases#{R:=attaching}});
        []->case lists:member(attaching,maps:values(Phases)) of true->S;false->command(S) end
    end.
%% Keep all participant destinations in one command record until each is reserved exactly once.
-spec command(map()) -> map().
command(S=#{commands:=Commands,sessions:=Sessions,phases:=Phases})->
    case queue:out(Commands) of
        {empty,_}->data(S);
        {{value,{[Role|Roles],Bytes}},Rest}->
            NextCommands=case Roles of []->Rest;_->queue:in_r({Roles,Bytes},Rest) end,
            Next=case Bytes of start->attached=maps:get(Role,Phases),S#{phases:=Phases#{Role:=starting},phase:=starting};_->S end,
            write(Role,control,hls_protocol_bridge_wire:command(maps:get(Role,Sessions),Bytes),Next#{commands:=NextCommands})
    end.
%% The queue reserves destination capacity and retains source identity until physical ACK completion.
-spec data(map()) -> map().
data(S=#{queue:=Q})->case hls_protocol_relay_queue:next(Q) of none->S;
    {Role,Packet,Token,Next}->write(Role,{packet,Token},hls_protocol_bridge_wire:packet(Packet),S#{queue:=Next}) end.
%% There is one physical writer across all brokers; its role and purpose remain bound to the response alias.
-spec write(term(),term(),{hls_fabric:header(),binary()},map()) -> map().
write(Role,Kind,{Header,Payload},S=#{brokers:=Brokers,devices:=Devices,writer:=none,sends:=Sends})->
    #{host:=Host,service:=Service}=maps:get(Role,Devices),
    Tag={Role,Kind},Ref=hls_fabric:send_request(maps:get(Role,Brokers),{Host,Service},Header,Payload,infinity),
    S#{writer:=Tag,sends:=gen_server:reqids_add(Ref,Tag,Sends)}.
%% Count an occupied descriptor without exposing application data.
-spec occupied(term()) -> 0|1.
occupied(none)->0;
occupied(_)->1.

%% Raw and typed modes have distinct command boundaries; neither silently accepts the other's data.
-spec control(raw|map(),term()) -> binary().
control(raw,{control,Payload})->_=hls_protocol_bridge_wire:command(1,Payload),Payload;
control(Application,Command) when is_map(Application)->hls_protocol_application_binding:control(Application,Command).

%% Decode before returning to the sole caller; no additional event buffering is introduced.
-spec reply(raw|map(),term(),term()) -> tuple().
reply(raw,Id,Record)->{ok,Id,Record};
reply(_,application,{started})->{ok,application,application,{started}};
reply(Application,{Device,Index},Frame)->
    {External,Record}=hls_protocol_application_binding:event(Application,Device,Index,Frame),
    {ok,Device,External,Record}.
