-module(hls_protocol_mixed_stream).
-moduledoc "One bounded owner for source actors, shared framing and BEAM admission. A failed incarnation never reconnects or replays. Trusted source actors must use this owner as their exclusive input writer; ERTS outbound queues are outside the 128-record transport budget.".
-behaviour(gen_server).
-export([start_link/5, submit/2, next/2, info/1, stop/1]).
-export([init/1,handle_call/3,handle_cast/2,handle_info/2,terminate/2]).

-doc "Starts a fresh owner with exact source-bound host plan, broker, disconnected BEAM PIDs and nonzero fresh session. Options accepts admission_timeout only. Caller becomes the sole control/event consumer. Prior transport retirement and hardware reset must be established externally; this does not reset hardware. Starts one framed attachment, admits retained startup through public BEAM barriers, and requires a separately bound sealed virtual node before start.".
-spec start_link(map(),pid(),#{non_neg_integer()=>pid()},pos_integer(),map()) -> gen_server:start_ret().
start_link(Plan,Broker,Pids,Session,Options)->
    gen_server:start_link(?MODULE,{Plan,Broker,Pids,Session,Options,self()},[]).
-doc "Queues one checked rectangle or single-use start, returning busy without admission at the 16-command limit. Only the owner client may call. An accepted command may be partially executed on later failure; never replay.".
-spec submit(pid(),hls_partition_wire:command()) -> {ok,1}|{error,busy}.
submit(Stream,Command)->gen_server:call(Stream,{submit,Command},infinity).
-doc "Takes one typed event, or timeout without abandoning an invisible waiter. Only one call by the owner client may be outstanding; consumer death retires the activation.".
-spec next(pid(),pos_integer()) -> {ok,pos_integer(),atom(),tuple()}|timeout.
next(Stream,Timeout)->gen_server:call(Stream,{next,Timeout},infinity).
-doc "Returns bounded counters and lifecycle, excluding payloads and actor bindings.".
-spec info(pid()) -> map().
info(Stream)->gen_server:call(Stream,info).
-doc "Retires this owner after its current physical write completes, then retires the broker route; does not reset hardware or stop source actors. Complete transport retirement and coordinated reset precede any new owner.".
-spec stop(pid()) -> ok.
stop(Stream)->gen_server:call(Stream,retire,infinity).

-doc "Installs actor/transport/consumer monitors and reserves one broker route. Startup admission and any write ambiguity are terminal on failure.".
-spec init(tuple()) -> {ok,map()}.
init({Plan=#{actors:=Actors,mixed:=Mixed=#{identity:=Identity,links:=Links},binding:=#{host:=Host,control:=Service}},
        Broker,Pids,Session,Options,Client})->
    #{admission_timeout:=Timeout}=Config=maps:merge(#{admission_timeout=>1000},Options),
    1=map_size(Config),true=Timeout>0,
    true=lists:sort(maps:keys(Pids))=:=lists:sort(maps:keys(Actors)),
    Bindings=maps:map(fun(I,#{capacity:=Capacity})->#{pid=>maps:get(I,Pids),capacity=>Capacity} end,Actors),
    Reverse=length([ok||#{direction:=to_beam}<-Links]),true=Reverse>0 andalso Reverse=<12,
    Queue=hls_protocol_mixed_queue:new(Mixed,Pids,Session,min(64,77-Reverse)),
    Admission0=hls_protocol_mixed_admission:new(Bindings,Timeout),
    Admission=lists:foldl(fun({I,Record},Acc)->{ok,Next}=hls_protocol_mixed_admission:deliver(I,Record,Acc),Next end,
        Admission0,hls_protocol_mixed_host:startup(Plan)),
    true=lists:all(fun(P)->#{lifecycle:=disconnected}=hls_statem:info(P,Timeout),true end,maps:values(Pids)),
    ok=hls_fabric:register_route(Broker,{Service,Host},self()),
    State=#{plan=>Plan,broker=>Broker,pids=>Pids,session=>Session,client=>Client,route=>{Host,Service},
        monitors=>#{monitor(process,Broker)=>broker,monitor(process,Client)=>consumer},
        admission=>Admission,queue=>Queue,phase=>attaching,bound=>false,connected=>false,beam_connected=>false,
        starts=>false,commands=>queue:new(),events=>queue:new(),reverse=>#{},
        handoff=>none,held=>none,writer=>none,sends=>gen_server:reqids_new(),waiter=>none,retry=>false,
        received=>0,written=>0,source_messages=>0,retiring=>none},
    {ok,write(attach,hls_protocol_bridge_wire:attach(Identity,Session),State)}.

-doc "Binds one virtual incarnation/connection, admits bounded source handoffs and serves the single application client.".
-spec handle_call(term(),gen_server:from(),map()) -> {reply,term(),map()}|{noreply,map()}|{stop,normal,ok,map()}.
%% Stop issuing packets; complete an already reserved physical write before releasing the route.
handle_call(retire,From={Client,_},State=#{client:=Client,retiring:=none,writer:=Writer})->
    case Writer of none->{stop,normal,ok,State};_->{noreply,State#{retiring:=From}} end;
%% Binding is one-shot and must match every source-derived virtual destination.
handle_call({source_bind,Identity,Handles},{Manager,_},State=#{bound:=false,plan:=#{targets:=Targets},monitors:=Monitors})->
    true=lists:sort(maps:keys(Handles))=:=lists:sort(maps:keys(Targets)),
    #{name:=Node}=Identity,true=lists:all(fun(P)->is_pid(P) andalso node(P)=:=Node end,maps:values(Handles)),
    true=length(lists:usort(maps:values(Handles)))=:=map_size(Handles),
    {reply,ok,State#{bound:=true,manager=>Manager,handles=>Handles,monitors:=Monitors#{monitor(process,Manager)=>manager}}};
%% The bound manager may attach exactly one distribution connection.
handle_call({source_attach,Connection},{Manager,_},State=#{manager:=Manager,connected:=false,monitors:=Monitors})->
    {reply,ok,State#{connected:=true,connection=>Connection,monitors:=Monitors#{monitor(process,Connection)=>connection}}};
%% Withhold the sole handoff reply until the correct bounded queue has room.
handle_call({source_send,Sender,Destination,Record},From={Connection,_},
        State=#{connection:=Connection,handoff:=none,pids:=Pids}) ->
    true=lists:member(Sender,maps:values(Pids)),
    {noreply,work(State#{handoff:={From,Sender,Destination,Record}})};
%% Admission preserves command order; start is explicitly one-shot.
handle_call({submit,Command},{Client,_},State=#{client:=Client,commands:=Commands,starts:=Started,plan:=Plan})->
    case queue:len(Commands)<16 of
        false->{reply,{error,busy},State};
        true->Entry=case Command of start->false=Started,start;
            _->{Bytes,Targets,Record}=hls_protocol_mixed_host:controls(Plan,Command),{control,Bytes,Targets,Record} end,
            {reply,{ok,1},work(State#{commands:=queue:in(Entry,Commands),starts:=Started orelse Command=:=start})}
    end;
%% One pending read is bounded and cancelled by the owner's timer before a timeout reply.
handle_call({next,Timeout},From={Client,_},State=#{client:=Client,waiter:=none}) when Timeout>0 ->
    Token=make_ref(),Timer=erlang:send_after(Timeout,self(),{next_timeout,Token}),
    {noreply,work(State#{waiter:={From,Token,Timer}})};
%% Counters include every transport category without private actor-state access.
handle_call(info,_From,State=#{queue:=Queue,admission:=Admission,commands:=Commands,events:=Events,reverse:=Reverse})->
    Counts=#{outgoing=>maps:get(queued,hls_protocol_mixed_queue:info(Queue)),commands=>queue:len(Commands),
        events=>queue:len(Events),reverse=>map_size(Reverse),handoff=>occupied(maps:get(handoff,State)),
        held=>occupied(maps:get(held,State)),writer=>occupied(maps:get(writer,State))},
    true=lists:sum(maps:values(Counts))=<128,
    {reply,(maps:with([phase,bound,connected,received,written,source_messages],State))#{counts=>Counts,
        admission=>hls_protocol_mixed_admission:info(Admission)},State}.

-doc "Retains at most one credited broker frame; all other casts are unsupported.".
-spec handle_cast(term(),map()) -> {noreply,map()}.
%% A broker receipt is independent of the later native delivery ACK.
handle_cast({'$hls_fabric_frame',Receipt,{Service,Host},Header,Payload},
        State=#{route:={Host,Service},held:=none})->
    {noreply,work(State#{held:={Receipt,Header,Payload}})}.

-doc "Completes one physical write, retries capacity checks and retires on any monitored lifetime failure.".
-spec handle_info(term(),map()) -> {noreply,map()}|{stop,term(),map()}.
%% A failed participant makes the whole incarnation unusable; never retry ambiguous input.
handle_info({'DOWN',Ref,process,_Pid,Reason},State=#{monitors:=Monitors,admission:=Admission})->
    case maps:find(Ref,Monitors) of
        {ok,Kind}->{stop,{shutdown,{Kind,Reason}},State};
        error->case hls_protocol_mixed_admission:down(Ref,Reason,Admission) of
            {error,Failure,Next}->{stop,{shutdown,Failure},State#{admission:=Next}};
            {unrelated,_}->{noreply,State} end
    end;
%% Recheck bounded postponed work without holding a BEAM actor or physical receive lock.
handle_info(retry,State)->{noreply,work(State#{retry:=false})};
%% Timeout removes the single waiter before replying, so a later event cannot vanish into an abandoned alias.
handle_info({next_timeout,Token},State=#{waiter:={From,Token,_}})->
    gen_server:reply(From,timeout),{noreply,State#{waiter:=none}};
%% Ignore a timeout already cancelled by delivery.
handle_info({next_timeout,_},State)->{noreply,State};
%% Only a successful writer completion releases the physical slot. Even definitely-unsent errors retire this first implementation.
handle_info(Message,State=#{sends:=Sends,writer:=Writer,written:=Count})->
    case gen_server:check_response(Message,Sends,true) of
        {{reply,ok},Writer,Remaining}->
            Next=State#{writer:=none,sends:=Remaining,written:=Count+1},
            case maps:get(retiring,State) of none->{noreply,work(Next)};
                From->gen_server:reply(From,ok),{stop,normal,Next} end;
        {{reply,Result},_,_}->{stop,{shutdown,{write_failed,Result}},State};
        {{error,Reason},_,_}->{stop,{shutdown,{writer_failed,Reason}},State};
        _->{noreply,State}
    end.
-doc "Cancels admission monitors and a pending client timer. Broker owner death retires its route; source actors and hardware require separate coordinated shutdown/reset.".
-spec terminate(term(),map()) -> ok.
terminate(_,#{admission:=Admission,waiter:=Waiter})->
    _=hls_protocol_mixed_admission:retire(Admission),
    case Waiter of none->ok;{_,_,Timer}->erlang:cancel_timer(Timer),ok end.

%% One owner serializes the independent categories; packet admission never waits on another actor's selective receive.
-spec work(map()) -> map().
work(State=#{retiring:=From}) when From=/=none->State;
work(State)->
    S1=receive_frame(notify(State)),S2=reverse(S1),S3=handoff(S2),S4=send_work(notify(S3)),
    retry(S4).
%% Deliver one queued event to a waiting client without an unbounded notification mailbox.
-spec notify(map()) -> map().
notify(State=#{waiter:=none})->State;
notify(State=#{waiter:={From,_,Timer},events:=Events,session:=Session})->
    case queue:out(Events) of {empty,_}->State;
        {{value,{Id,Record}},Rest}->erlang:cancel_timer(Timer),gen_server:reply(From,{ok,Session,Id,Record}),
            State#{waiter:=none,events:=Rest} end.
%% Admit credited broker traffic only when its destination storage is available.
-spec receive_frame(map()) -> map().
receive_frame(State=#{held:=none})->State;
receive_frame(State=#{held:={Receipt,Header,Payload},session:=Session,events:=Events,broker:=Broker,received:=Count})->
    Event=hls_protocol_bridge_wire:event(Session,Header,Payload),
    Blocked=case Event of {external,_,_}->queue:len(Events)>=32;started->queue:len(Events)>=32;_->false end,
    case Blocked of true->State;false->
        Next=event(Event,State),hls_fabric:ack(Broker,Receipt),Next#{held:=none,received:=Count+1} end.
%% Attachment/start replies are single-use; the queue validates the one monotone native credit/data sequence.
-spec event(term(),map()) -> map().
event(attached,State=#{phase:=attaching})->State#{phase:=attached};
event(started,State=#{phase:=starting,events:=Events})->State#{phase:=running,events:=queue:in({application,{started}},Events)};
event({external,Index,Frame},State=#{plan:=Plan,events:=Events})->
    State#{events:=queue:in(hls_protocol_mixed_host:native_event(Plan,Index,Frame),Events)};
event({packet,#{kind:=2,session:=Session,sequence:=Seq,link:=Link,slot:=Slot}},State=#{queue:=Queue})->
    State#{queue:=hls_protocol_mixed_queue:credit(Queue,Session,Seq,Link,Slot)};
event({packet,Packet=#{kind:=1,session:=Session,sequence:=Seq,link:=Link,slot:=Slot,frame:=Frame}},
        State=#{queue:=Queue,reverse:=Reverse,pids:=Pids})->
    false=maps:is_key(Link,Reverse),
    {Pid,Record,Next}=hls_protocol_mixed_queue:delivery(Queue,Session,Seq,Link,Slot,Frame),
    [Target]=[I||{I,P}<-maps:to_list(Pids),P=:=Pid],
    State#{queue:=Next,reverse:=Reverse#{Link=>{pending,Target,Record,Packet}}}.
%% Retain bootstrap queries outside disconnected actors until setup is admitted and outputs connected.
%% Then try each actual reverse pair once, leaving full actors pending while another pair can advance.
-spec reverse(map()) -> map().
reverse(State=#{beam_connected:=false})->State;
reverse(State=#{reverse:=Reverse})->lists:foldl(fun
    ({Link,{pending,Target,Record,Packet}},S=#{admission:=Admission,reverse:=Current})->
        case hls_protocol_mixed_admission:deliver(Target,Record,Admission) of
            {ok,Next}->S#{admission:=Next,reverse:=Current#{Link:={ack,Packet}}};
            {busy,Next}->S#{admission:=Next};
            {error,Reason,_}->error(Reason) end;
    (_,S)->S
end,State,lists:sort(maps:to_list(Reverse))).
%% The connection holds one authenticated record until a per-pair queue or external queue accepts it.
-spec handoff(map()) -> map().
handoff(State=#{handoff:=none})->State;
handoff(State=#{handoff:={From,Sender,{actor,Target},Record},queue:=Queue})->
    case hls_protocol_mixed_queue:offer(Queue,Sender,Target,Record) of
        {error,busy}->State;{ok,Next}->accepted(From,State#{queue:=Next}) end;
handoff(State=#{handoff:={From,Sender,{external,Id},Record},plan:=Plan,pids:=Pids,events:=Events})->
    case queue:len(Events)<32 of false->State;true->
        [Index]=[I||{I,P}<-maps:to_list(Pids),P=:=Sender],
        Event=hls_protocol_mixed_host:external(Plan,Index,Id,Record),
        accepted(From,State#{events:=queue:in(Event,Events)}) end.
%% Acceptance releases only distribution handoff credit, not native slot credit.
-spec accepted(gen_server:from(),map()) -> map().
accepted(From,State=#{source_messages:=Count})->gen_server:reply(From,ok),State#{handoff:=none,source_messages:=Count+1}.
%% Select one physical write, prioritizing completed host admissions and ordered control over source data.
-spec send_work(map()) -> map().
send_work(State=#{writer:=Writer}) when Writer=/=none->State;
send_work(State=#{phase:=attaching})->State;
send_work(State=#{reverse:=Reverse})->
    case [{L,P}||{L,{ack,P}}<-lists:sort(maps:to_list(Reverse))] of
        [{Link,Packet}|_]->write(ack,hls_protocol_bridge_wire:packet(Packet#{kind:=2,frame:=0}),
            State#{reverse:=maps:remove(Link,Reverse)});
        []->command(State)
    end.
%% A single rectangle retains its record while its selected host recipients admit in order.
-spec command(map()) -> map().
command(State=#{commands:=Commands,session:=Session})->
    case queue:out(Commands) of
        {empty,_}->data(State);
        {{value,start},Rest}->
            #{connected:=true,plan:=Plan,pids:=Pids,handles:=Handles,phase:=attached}=State,
            ok=hls_protocol_mixed_host:connect(Plan,Pids,Handles),
            write(start,hls_protocol_bridge_wire:command(Session,start),State#{commands:=Rest,phase:=starting,beam_connected:=true});
        {{value,{control,Bytes,Targets,Record}},Rest}->
            {Remaining,Next}=admit_targets(Targets,Record,State),
            case Remaining of []->write(control,hls_protocol_bridge_wire:command(Session,Bytes),Next#{commands:=Rest});
                _->Next#{commands:=queue:in_r({control,Bytes,Remaining,Record},Rest)} end
    end.
%% Preserve one control's recipient cursor; each accepted recipient is removed before any later retry.
-spec admit_targets([non_neg_integer()],tuple(),map()) -> {[non_neg_integer()],map()}.
admit_targets([],_,State)->{[],State};
admit_targets([I|Rest]=Targets,Record,State=#{admission:=Admission})->
    case hls_protocol_mixed_admission:deliver(I,Record,Admission) of
        {ok,Next}->admit_targets(Rest,Record,State#{admission:=Next});
        {busy,Next}->{Targets,State#{admission:=Next}};
        {error,Reason,_}->error(Reason) end.
%% Reserve source credit/sequence before asynchronous physical transmission; no rollback path exists.
-spec data(map()) -> map().
data(State=#{queue:=Queue})->case hls_protocol_mixed_queue:next(Queue) of none->State;
    {Packet,Next}->write(data,hls_protocol_bridge_wire:packet(Packet#{kind=>1}),State#{queue:=Next}) end.
%% One broker send may be in flight; receipt, write response and actual BEAM admission are distinct events.
-spec write(atom(),{hls_fabric:header(),binary()},map()) -> map().
write(Kind,{Header,Payload},State=#{broker:=Broker,route:=Route,writer:=none,sends:=Sends})->
    Ref=hls_fabric:send_request(Broker,Route,Header,Payload,infinity),
    State#{writer:=Kind,sends:=gen_server:reqids_add(Ref,Kind,Sends)}.
%% One timer rechecks only local capacity waits; never retransmits a reserved packet.
-spec retry(map()) -> map().
retry(State=#{retry:=true})->State;
retry(State=#{reverse:=Reverse,handoff:=Handoff,commands:=Commands,held:=Held})->
    Pending=map_size(Reverse)>0 orelse Handoff=/=none orelse not queue:is_empty(Commands) orelse Held=/=none,
    case Pending of true->erlang:send_after(5,self(),retry),State#{retry:=true};false->State end.
%% Count one occupied transport category without exposing its record.
-spec occupied(term()) -> 0|1.
occupied(none)->0;
occupied(_)->1.
