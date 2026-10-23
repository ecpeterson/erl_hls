-module(hls_protocol_inspection_live).
-moduledoc "Concurrent finite repetition and process-query witness over separate real brokers and public RTL streams.".
-export([run/3]).

-doc "Runs fresh N3 correction feedback and final readout while sampling every process through hls_debug. Rejects wrong fingerprints/catalogs, exercises independent output stalls and retires both transports. Queries are sparse pre-edge snapshots, not event history. The RTL harness compares application ports with an unqueried twin on every exercised clock.".
-spec run(file:filename(),file:filename(),pos_integer()) -> ok.
run(Build,Stage,N) ->
    {ok,Bytes}=file:read_file(filename:join(Build,"network/inspection.etf")),
    Plan=#{manifest:=Manifest,actors:=Actors}=binary_to_term(Bytes),
    {ok,Debug}=hls_fabric:start_link(filename:join(Stage,"debug_tx"),filename:join(Stage,"debug_rx"),#{rx_route_limit=>1}),
    {ok,Client}=hls_debug:start_link(undefined,{fabric,Debug,2}),
    {ok,DeployBytes}=file:read_file(filename:join(Build,"deployment.etf")),Deployment=binary_to_term(DeployBytes),
    {ok,App}=hls_fabric:start_link(filename:join(Stage,"app_tx"),filename:join(Stage,"app_rx"),#{rx_route_limit=>1}),
    {ok,Stream}=hls_partition_stream:start_link(Deployment,#{board=>App},#{queue_limit=>128,write_timeout=>30000}),
    try
        {error,corrupt_topology_manifest}=hls_protocol_observation:open(Client,Manifest#{<<"fingerprint">>:=binary:copy(<<"0">>,64)}),
        {ok,Session}=hls_protocol_observation:open(Client,Manifest),
        Catalog=hls_protocol_observation:catalog(Plan,Session),
        Ids=[{actor,Id}||#{id:=Id}<-Actors],
        [{actor,First}|_]=Ids,{ok,Target}=hls_debug_catalog:actor(Catalog,{actor,First}),
        {capabilities,#{trace:=false}}=hls_debug:info(Target,capabilities),
        {error,{unsupported_operation,_,get_trace}}=hls_debug:get_trace(Target),
        Parent=self(),{Worker,Ref}=spawn_monitor(fun()->Parent!{capture,hls_process_profile:capture(Catalog,Ids,
            #{session=><<"fresh-RTL-incarnation">>,reset_free=>true,rounds=>3,timeout_ms=>10000,interval_ms=>0,budget_ms=>60000})} end),
        %% The application remains in its stream-owning process; queries use the shared debug client.
        {Result,Capture}=try
            R=phi_protocol_repetition:run(Stream,N,8,123,60000),
            C=receive {capture,V}->V;{'DOWN',Ref,process,Worker,Why}->error({sampling_failed,Why}) after 65000->error(sampling_timeout) end,
            receive {'DOWN',Ref,process,Worker,normal}->ok after 5000->error(sampler_did_not_exit) end,
            {R,C}
        after exit(Worker,kill) end,
        #{stop:=complete,unattempted:=0}=Capture,
        true=lists:all(fun(#{fields:=#{initialized:=Init,failed:=Failed}})->Init andalso not Failed end,maps:get(rows,Capture)),
        ok=hls_process_profile:write(filename:join(Stage,"samples.json"),Capture),
        #{io:=#{lease:=DL}}=hls_fabric:info(Debug),#{io:=#{lease:=AL}}=hls_fabric:info(App),
        ok=hls_partition_stream:stop(Stream),ok=hls_debug:stop(Client),ok=hls_fabric:stop(Debug),ok=hls_fabric:stop(App),
        ok=file:write_file(filename:join(Stage,"done"),<<>>,[exclusive]),
        ok=hls_fabric:await_closed(DL,5000),ok=hls_fabric:await_closed(AL,5000),
        ok=file:write_file(filename:join(Stage,"result.json"),json:encode(Result#{descriptors_closed=>true,
            replies=>[tuple_to_list(P)||P<-maps:get(replies,Result)],samples=>length(maps:get(rows,Capture))}),[exclusive]),ok
    after catch hls_partition_stream:stop(Stream),catch hls_debug:stop(Client),catch hls_fabric:stop(Debug),catch hls_fabric:stop(App) end.
