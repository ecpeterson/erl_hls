-module(hls_protocol_relay_peer).
-moduledoc "Single-credit broker model for deployment relay tests. Attachment is modeled; start and data replies are explicitly injected. This is not hardware evidence.".
-behaviour(gen_server).
-export([start/1,set/2,emit/3,stats/1]).
-export([init/1,handle_call/3,handle_cast/2,handle_info/2]).

-doc "Starts an unlinked broker model with one endpoint binding.".
-spec start(map()) -> {ok,pid()}.
start(Binding)->gen_server:start(?MODULE,Binding,[]).
-doc "Holds or releases definite physical write completion.".
-spec set(pid(),hold|normal) -> ok.
set(Pid,Mode)->gen_server:call(Pid,{mode,Mode}).
-doc "Queues a simulated device reply behind the broker's single receipt credit.".
-spec emit(pid(),tuple(),binary()) -> ok.
emit(Pid,Header,Payload)->gen_server:call(Pid,{emit,Header,Payload}).
-doc "Reports physical writes, retained receipt and route retirement for assertions.".
-spec stats(pid()) -> map().
stats(Pid)->gen_server:call(Pid,stats).

-doc "Starts with no route, receipt or physical write.".
-spec init(map()) -> {ok,map()}.
init(B)->{ok,#{binding=>B,owner=>none,monitor=>none,route=>none,mode=>normal,
    held=>none,receipt=>none,events=>queue:new(),writes=>[]}}.

-doc "Models route ownership, session attachment and controlled completion of writes.".
-spec handle_call(term(),gen_server:from(),map()) -> {reply,term(),map()}|{noreply,map()}.
%% A fresh route is owned by one monitored deployment stream.
handle_call({register_route,Route,Owner},_,S=#{owner:=none,binding:=#{host:=H,service:=V}})->
    {V,H}=Route,{reply,ok,S#{owner:=Owner,monitor:=monitor(process,Owner),route:=Route}};
%% Attachment validates the bound identity and echoes the selected session.
handle_call({send,{H,V},{1,0,0},<<Session:64/little,I:32/binary>>,infinity},_,
        S=#{binding:=#{host:=H,service:=V,identity:=I}})->
    {reply,ok,output({{16#81,0,0},<<Session:64/little>>},S)};
%% Every non-attachment write is retained before its controlled completion.
handle_call({send,{H,V}=Route,Header,Bytes,infinity},From,
        S=#{binding:=#{host:=H,service:=V},mode:=Mode,held:=none,writes:=Writes})->
    Next=S#{writes:=[{Route,Header,Bytes}|Writes]},
    case Mode of normal->{reply,ok,Next};hold->{noreply,Next#{held:=From}} end;
%% Completion releases the one writer without fabricating a device acknowledgment.
handle_call({mode,Mode},_,S=#{held:=Held})->
    case {Mode,Held} of {normal,From} when From=/=none->gen_server:reply(From,ok);
        _->ok end,
    {reply,ok,S#{mode:=Mode,held:=case Mode of normal->none;hold->Held end}};
%% Start, credits and external records are independent device observations.
handle_call({emit,H,B},_,S)->{reply,ok,output({H,B},S)};
%% Tests observe public packet writes and ownership only.
handle_call(stats,_,S)->{reply,maps:with([writes,held,receipt,owner],S),S}.

-doc "Releases a receipt only when acknowledged by its bound owner.".
-spec handle_cast(term(),map()) -> {noreply,map()}.
%% Receipt retirement permits the next hardware frame; it is separate from class credit.
handle_cast({ack,Owner,Ref},S=#{owner:=Owner,receipt:=Ref})->{noreply,pump(S#{receipt:=none})}.

-doc "Marks the route retired when its deployment owner exits.".
-spec handle_info(term(),map()) -> {noreply,map()}.
%% A failed deployment cannot reuse this connection's route.
handle_info({'DOWN',Ref,process,Owner,_},S=#{monitor:=Ref,owner:=Owner})->
    {noreply,S#{owner:=retired,receipt:=none,events:=queue:new()}}.

%% A simulated device may wait behind broker backpressure.
-spec output(tuple(),map()) -> map().
output(E,S=#{events:=Q})->pump(S#{events:=queue:in(E,Q)}).
%% Deliver at most one frame and bind its receipt to the registered owner.
-spec pump(map()) -> map().
pump(S=#{owner:=Owner,receipt:=none,events:=Q,route:=Route}) when is_pid(Owner)->
    case queue:out(Q) of {empty,_}->S;
        {{value,{H,B}},Rest}->Ref=make_ref(),gen_server:cast(Owner,{'$hls_fabric_frame',Ref,Route,H,B}),
            S#{receipt:=Ref,events:=Rest} end;
pump(S)->S.
