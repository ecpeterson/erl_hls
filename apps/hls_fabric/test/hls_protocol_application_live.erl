-module(hls_protocol_application_live).
-moduledoc "Finite host-feedback witness through real application brokers and a freshly compiled source application.".
-export([run/2]).

-doc "Attaches the emitted deployment, configures four sources, orders start, then feeds each returned sample into its next point command. Checks all 24 records against ordinary source callbacks, per-producer order and started acknowledgment. Stops the client/broker and awaits descriptor closure. This is a finite simulation witness, not a progress or device timing claim.".
-spec run(file:filename(),file:filename()) -> ok.
run(Build,Stage) ->
    {ok,Deployment}=hls_deployment_artifact:load(filename:join(Build,"deployment.etf")),
    {ok,Broker}=hls_fabric:start_link(filename:join(Stage,"app_tx"),filename:join(Stage,"app_rx"),#{rx_route_limit=>1}),
    {ok,Stream}=hls_partition_stream:start_link(Deployment,#{board=>Broker},#{queue_limit=>32,write_timeout=>30000}),
    try
        send(Stream,1,{cfg,1}),send(Stream,2,{cfg,2}),
        {ok,1}=hls_partition_stream:submit(Stream,start),
        Deadline=erlang:monotonic_time(millisecond)+45000,
        ok=initial(Stream,#{},false,Deadline),
        lists:foreach(fun(Id)->send(Stream,Id,{work,1}) end,lists:seq(1,4)),
        ok=feedback(Stream,maps:from_list([{Id,[1,2,10,11,12]}||Id<-lists:seq(1,4)]),Deadline),
        timeout=hls_partition_stream:next(Stream,10),
        #{io:=#{lease:=Lease}}=hls_fabric:info(Broker),
        ok=hls_partition_stream:stop(Stream),ok=hls_fabric:stop(Broker),
        %% Let the physical simulator close its FIFO ends before waiting for raw-read retirement.
        ok=file:write_file(filename:join(Stage,"done"),<<>>,[exclusive]),
        ok=hls_fabric:await_closed(Lease,5000),
        ok=file:write_file(filename:join(Stage,"result.json"),json:encode(#{passed=>true,frames=>24,starts=>1,
            controls=>22,reference=>ordinary_source_callbacks,order=>per_producer,descriptors_closed=>true}),[exclusive]),ok
    after catch hls_partition_stream:stop(Stream),catch hls_fabric:stop(Broker) end.

%% Attachment may release declared startup publications before the start acknowledgment.
-spec initial(pid(),map(),boolean(),integer()) -> ok.
initial(_Stream,Seen,true,_Deadline) when map_size(Seen)=:=4 -> ok;
initial(Stream,Seen,Started,Deadline) ->
    case next(Stream,Deadline) of
        {ok,board,application,{started}} when not Started->initial(Stream,Seen,true,Deadline);
        {ok,board,Endpoint,Record={sample,Id,0}}->
            false=maps:is_key(Id,Seen),ok=check(Endpoint,Record,Id,0),
            initial(Stream,Seen#{Id=>true},Started,Deadline);
        Other->error({unexpected_setup_event,Other})
    end.

%% Only one command per producer awaits its corresponding event, while other producers advance independently.
-spec feedback(pid(),map(),integer()) -> ok.
feedback(_Stream,Pending,_Deadline) when map_size(Pending)=:=0 -> ok;
feedback(Stream,Pending,Deadline) ->
    {ok,board,Endpoint,Record={sample,Id,Seq}}=next(Stream,Deadline),
    [Seq|Rest]=maps:get(Id,Pending),ok=check(Endpoint,Record,Id,Seq),
    New=case Rest of []->maps:remove(Id,Pending);[N|_]->send(Stream,Id,{work,N}),Pending#{Id:=Rest} end,
    feedback(Stream,New,Deadline).

%% Ordinary BEAM callbacks supply the expected record; generated hardware is not the oracle.
-spec check(term(),tuple(),pos_integer(),non_neg_integer()) -> ok.
check(Endpoint,Record,Id,Seq) when Id>=1,Id=<4 ->
    Endpoint=case Id of 4->single;_->shared end,
    M=hls_protocol_boundary_fixture,
    {ok,boot,C0}=M:init([]),{sending,C1,consume}=M:boot(cast,{cfg,Id},C0),
    {repeat_phase,C2,consume}=M:sending(cast,{work,Seq},C1),
    {_,[{cast,monitor,Record}]}=M:sending(enter,boot,C2),ok.

%% Coordinates are point-addressed, preserving each producer's distinct command stream.
-spec send(pid(),pos_integer(),tuple()) -> ok.
send(Stream,Id,Record) ->
    X=Id-1,{ok,1}=hls_partition_stream:submit(Stream,{host,cells,{X,0,X,0},Record}),ok.

%% One absolute deadline covers setup, activation, all feedback and readout.
-spec next(pid(),integer()) -> term().
next(Stream,Deadline) ->
    Left=Deadline-erlang:monotonic_time(millisecond),true=Left>0,
    hls_partition_stream:next(Stream,Left).
