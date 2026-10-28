-module(phi_protocol_repetition_fixture).
-moduledoc "Fresh ordinary-BEAM reference and live broker witness for the finite repetition application.".
-export([oracle/2,live/3]).

-doc "Runs independent ordinary BEAM actors at half-rate noise and cutoff eight, feeding every correction back before final readout. Retains per-sender events; no cross-sender chronology or convergence theorem is implied.".
-spec oracle(file:filename(),pos_integer()) -> ok.
oracle(Stage,N) ->
    Plan=#{families:=Families,startup:=Startup}=hls_topology:normalize(phi_repetition_topology:topology(N)),
    Owner=self(),Sink=spawn_link(fun()->forward(Owner) end),
    Actors=maps:from_list([begin {ok,P}=M:start_link(),{{F,X,0},{M,P}} end
        ||#{id:=F,module:=M}<-Families,X<-lists:seq(0,N-1)]),
    try
        lists:foreach(fun(#{target:=Id,messages:=Ms})->
            {_,P}=maps:get(Id,Actors),[hls_statem:cast(P,M)||M<-Ms]
        end,Startup),
        [hls_statem:cast(element(2,maps:get({F,X,0},Actors)),{noise_cutoff,8})
            ||F<-[data,syndrome],X<-lists:seq(0,N-1)],
        %% Connect data before checks, and checks before phi; same-sender setup is already queued.
        lists:foreach(fun(F)->lists:foreach(fun(X)->
            {M,P}=maps:get({F,X,0},Actors),
            Outputs=maps:from_list([{Port,case T of
                {actor,Id}->element(2,maps:get(Id,Actors));{external,_}->Sink
            end}||#{source:={_,Port},recipients:=[T]}<-hls_topology:routes_for_instance(Plan,F,[X,0])]),
            ok=M:connect(P,Outputs)
        end,lists:seq(0,N-1)) end,[data,syndrome,phi]),
        Deadline=erlang:monotonic_time(millisecond)+20000,
        {Fence,Events,Corrections}=collect(N,Actors,#{},[],[],Deadline),
        [hls_statem:cast(element(2,maps:get({data,X,0},Actors)),{pauli_query,123,x})||X<-lists:seq(0,N-1)],
        Replies=replies(N,#{},Deadline),
        save(Stage,"oracle.json",#{fence=>Fence,events=>lists:reverse(Events),
            corrections=>lists:reverse(Corrections),replies=>lists:sort(maps:to_list(Replies)),cutoff=>8,request=>123,basis=>x})
    after
        maps:foreach(fun(_,{_,P})->unlink(P),exit(P,kill) end,Actors),
        unlink(Sink),exit(Sink,kill)
    end.

-doc "Runs the production helper over real brokers and public RTL ports, then retires stream and FIFO descriptors. Uses only the freshly emitted deployment and pinned source codecs.".
-spec live(file:filename(),file:filename(),pos_integer()) -> ok.
live(Build,Stage,N) ->
    {ok,Bytes}=file:read_file(filename:join(Build,"deployment.etf")),Deployment=binary_to_term(Bytes),
    {ok,Broker}=hls_fabric:start_link(filename:join(Stage,"app_tx"),filename:join(Stage,"app_rx"),#{rx_route_limit=>1}),
    {ok,Stream}=hls_partition_stream:start_link(Deployment,#{board=>Broker},#{queue_limit=>128,write_timeout=>30000}),
    try
        Result=phi_protocol_repetition:run(Stream,N,8,123,60000),
        #{io:=#{lease:=Lease}}=hls_fabric:info(Broker),
        ok=hls_partition_stream:stop(Stream),ok=hls_fabric:stop(Broker),
        ok=file:write_file(filename:join(Stage,"done"),<<>>,[exclusive]),
        ok=hls_fabric:await_closed(Lease,5000),
        save(Stage,"result.json",Result#{descriptors_closed=>true})
    after catch hls_partition_stream:stop(Stream),catch hls_fabric:stop(Broker) end.

%% One sink preserves each emitting process's message order while allowing arbitrary interleaving.
-spec forward(pid()) -> no_return().
forward(Owner) ->
    receive {'$gen_cast',Event}->Owner!{event,Event},forward(Owner) end.

%% The ordinary actor graph, without hardware or the production helper, supplies reference events.
-spec collect(pos_integer(),map(),map(),[list()],[list()],integer()) -> {non_neg_integer(),[list()],[list()]}.
collect(N,Actors,Rounds,Events,Corrections,Deadline) ->
    case event(Deadline) of
        C={phi_correction,Step,X,0,V}->
            {{DX,0},Pauli}=phi_repetition_topology:correction_update(C,N),
            hls_statem:cast(element(2,maps:get({data,DX,0},Actors)),{pauli_update,Pauli}),
            collect(N,Actors,Rounds,[[X,0,Step,phi_correction,V]|Events],[[X,0,Step,V,DX]|Corrections],Deadline);
        {phi_status,Step,X,0,Flags} when Step>=0,Step<512,X>=0,X<N,Flags>=0,Flags=<3->
            Round=maps:get(Step,Rounds,#{}),false=maps:is_key(X,Round),Updated=Round#{X=>Flags},
            NewEvents=[[X,0,Step,phi_status,Flags]|Events],
            case map_size(Updated)=:=N andalso lists:all(fun(F)->F=:=2 end,maps:values(Updated)) of
                true->{Step,NewEvents,Corrections};
                false->collect(N,Actors,Rounds#{Step=>Updated},NewEvents,Corrections,Deadline)
            end;
        Other->error({unexpected_reference_event,Other})
    end.

%% Readout follows every correction sent by this same host process.
-spec replies(pos_integer(),map(),integer()) -> map().
replies(N,Replies,_) when map_size(Replies)=:=N -> Replies;
replies(N,Replies,Deadline) ->
    case event(Deadline) of
        {pauli_reply,123,X,0,Bit} when X>=0,X<N,Bit>=0,Bit=<1->
            false=maps:is_key(X,Replies),replies(N,Replies#{X=>Bit},Deadline);
        {phi_status,_,_,_,2}->replies(N,Replies,Deadline);
        Other->error({unexpected_reference_readout,Other})
    end.

%% One bounded receive covers only public actor output terms.
-spec event(integer()) -> tuple().
event(Deadline) ->
    receive {event,E}->E after max(0,Deadline-erlang:monotonic_time(millisecond))->error(reference_timeout) end.

%% Tuple readouts become JSON arrays while event atoms become their ordinary string names.
-spec save(file:filename(),file:filename(),map()) -> ok.
save(Stage,Name,Result=#{replies:=Replies}) ->
    file:write_file(filename:join(Stage,Name),json:encode(Result#{replies:=[tuple_to_list(R)||R<-Replies]}),[exclusive]).
