-module(hls_protocol_mixed_admission).
-moduledoc "Single-owner admission into actual hls_statem actors without changing their runtime. The owner must be the exclusive input writer, including setup, control and host-host routes. Other Erlang processes are trusted not to bypass it; this module does not isolate PIDs.".
-export([new/2, deliver/3, down/3, retire/1, info/1]).

-doc "Binds exact local actor PIDs and source mailbox capacities, installing lifetime monitors. Caller becomes the sole owner and must serialize all input through deliver/3, process monitor notifications and retain only the newest state. Actors may initially be disconnected for ordered setup. Timeout bounds each public runtime barrier; finite callback work and same-sender ordering are required. No hardware session is activated here.".
-spec new(#{non_neg_integer()=>#{pid:=pid(),capacity:=1..255}},pos_integer()) -> map().
new(Bindings,Timeout) when map_size(Bindings)>0,Timeout>0 ->
    Pids=[P||#{pid:=P}<-maps:values(Bindings)],
    true=length(Pids)=:=map_size(Bindings),
    true=length(Pids)=:=length(lists:usort(Pids)),
    true=lists:all(fun(P)->is_pid(P) andalso node(P)=:=node() end,Pids),
    true=lists:all(fun(#{capacity:=C})->is_integer(C) andalso C>0 andalso C=<255 end,maps:values(Bindings)),
    Monitors=maps:from_list([{monitor(process,P),I}||{I,#{pid:=P}}<-maps:to_list(Bindings)]),
    State=#{owner=>self(),live=>true,actors=>Bindings,monitors=>Monitors,timeout=>Timeout,admitted=>0},
    try maps:foreach(fun(_,A)->snapshot(A,Timeout) end,Bindings),State
    catch Class:Reason:Stack->retire(State),erlang:raise(Class,Reason,Stack) end.

-doc "Admits one record or returns busy without sending when the actor mailbox is full. Checks capacity, sends the cast, then awaits a public runtime state barrier from the same owner. Only ok authorizes a delivery ACK; it means admission completed, not consumption. Timeout/death after sending is ambiguous and returns a permanently retired state; never replay. Exclusive writer and finite runtime work are explicit composition assumptions, not conclusions from observing occupancy.".
-spec deliver(non_neg_integer(),tuple(),map()) -> {ok,map()} | {busy,map()} | {error,term(),map()}.
deliver(Id,Message,State=#{owner:=Owner,live:=true,actors:=Actors,timeout:=Timeout,admitted:=Count}) when Owner=:=self() ->
    try
        Actor=#{pid:=Pid}=maps:get(Id,Actors),
        case snapshot(Actor,Timeout) of
            #{available:=0}->{busy,State};
            #{available:=Free} when Free>0->
                ok=hls_statem:cast(Pid,Message),
                _=snapshot(Actor,Timeout),
                {ok,State#{admitted:=Count+1}}
        end
    catch Class:Reason->{error,{admission_failed,Class,Reason},retire(State)} end.

%% Both barriers use the public runtime API; no private record layout or state mutation is used.
-spec snapshot(#{pid:=pid(),capacity:=pos_integer()},pos_integer()) -> map().
snapshot(#{pid:=Pid,capacity:=Capacity},Timeout) ->
    #{mailbox:=M=#{capacity:=Capacity,occupied:=Occupied,available:=Available,
        committed:=Occupied,reserved:=0}}=hls_statem:info(Pid,Timeout),
    true=Occupied>=0 andalso Available>=0 andalso Occupied+Available=:=Capacity,M.

-doc "Retires all bindings on a known actor monitor notification; ignores unrelated monitors. The transport owner must also retire on broker/connection death and stop acknowledging hardware packets.".
-spec down(reference(),term(),map()) -> {unrelated,map()} | {error,term(),map()}.
down(Ref,Reason,State=#{owner:=Owner,live:=true,monitors:=Monitors}) when Owner=:=self() ->
    case maps:find(Ref,Monitors) of
        error->{unrelated,State};
        {ok,Id}->{error,{actor_down,Id,Reason},retire(State)}
    end.

-doc "Permanently releases monitors and removes actor bindings without stopping the actors. Does not undo any admitted or ambiguous cast. Caller must cancel transport/session ownership separately; a retired state cannot admit another record.".
-spec retire(map()) -> map().
retire(State=#{owner:=Owner,monitors:=Monitors}) when Owner=:=self() ->
    maps:foreach(fun(Ref,_)->demonitor(Ref,[flush]) end,Monitors),
    State#{live:=false,actors:=#{},monitors:=#{}}.

-doc "Reports only lifecycle, actor count and completed admissions; excludes actor payloads and PID bindings.".
-spec info(map()) -> map().
info(#{live:=Live,actors:=Actors,admitted:=Count})->
    #{live=>Live,actors=>map_size(Actors),admitted=>Count}.
