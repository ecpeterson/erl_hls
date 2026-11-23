-module(phi_protocol_deployment_live).
-moduledoc "Finite periodic repetition application across independent framed RTL roles and production brokers. The separate BEAM fixture supplies the oracle.".
-export([run/4]).

-doc "Runs cutoff-eight N6 feedback/readout with the source-bound typed relay, then stops every route and broker and awaits both leases. Pending algorithm chatter is explicitly cancelled by whole-deployment retirement; a quiet application fence is not global network quiescence. Each invocation requires reset hardware and distinct fresh sessions.".
-spec run(file:filename(),file:filename(),pos_integer(),pos_integer()) -> ok.
run(Build,Stage,Width,Incarnation) ->
    {ok,Bytes}=file:read_file(filename:join(Build,"deployment.etf")),
    Deployment=#{devices:=Devices}=binary_to_term(Bytes),
    Roles=lists:sort(maps:keys(Devices)),
    Brokers=maps:from_list([begin P=filename:join(Stage,"role"++integer_to_list(R)),
        {ok,B}=hls_fabric:start_link(P++"_tx",P++"_rx",#{rx_route_limit=>1}),{R,B} end||R<-Roles]),
    Sessions=maps:from_list([{R,Incarnation*2+R+1}||R<-Roles]),
    {ok,Stream}=hls_protocol_stream:start_application(Deployment,Brokers,Sessions),
    try
        Result=phi_protocol_repetition:run(hls_protocol_stream,Stream,Width,8,123,120000),
        Info=#{packets:=#{forwarded:=Forwarded,acknowledged:=Acknowledged}}=hls_protocol_stream:info(Stream),
        true=Forwarded>0,true=Acknowledged>0,
        #{replies:=Replies}=Result,
        Saved=Result#{replies:=[tuple_to_list(R)||R<-Replies],stream_at_retirement=>Info},
        ok=file:write_file(filename:join(Stage,"application.json"),json:encode(Saved),[exclusive]),
        Leases=[begin #{io:=#{lease:=L}}=hls_fabric:info(B),L end||B<-maps:values(Brokers)],
        ok=hls_protocol_stream:stop(Stream),[ok=hls_fabric:stop(B)||B<-maps:values(Brokers)],
        %% Release peer FIFO endpoints before waiting for the blocking readers to finish closing.
        ok=file:write_file(filename:join(Stage,"done"),<<>>,[exclusive]),
        [ok=hls_fabric:await_closed(L,5000)||L<-Leases],
        file:write_file(filename:join(Stage,"result.json"),json:encode(Saved#{descriptors_closed=>true,retirement=>cancel_remaining_chatter}),[exclusive])
    after catch hls_protocol_stream:stop(Stream),[catch hls_fabric:stop(B)||B<-maps:values(Brokers)] end.
