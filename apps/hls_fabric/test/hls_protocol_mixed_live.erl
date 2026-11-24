-module(hls_protocol_mixed_live).
-moduledoc "Actual BEAM data actors, source distribution and live-broker RTL repetition witness. Compared with a fresh independent BEAM reference; never equates simulation wall time with routed timing.".
-export([run/4]).
-doc "Exercises a fresh source-bound mixed incarnation through actual ERTS distribution and a live broker. Checks finite correction/readout and public retirement; simulator/oracle comparison is performed by the outer harness.".
-spec run(file:filename(),file:filename(),pos_integer(),pos_integer()) -> ok.
run(Binding,Stage,N,Session)->execute(Binding,Stage,N,Session).
%% The source owner admits setup, connects actual actors, then performs coordinated retirement.
-spec execute(file:filename(),file:filename(),pos_integer(),pos_integer()) -> ok.
execute(Binding,Stage,N,Session)->
    hls_test_nodes:distribution(),{ok,_}=application:ensure_all_started(crypto),
    {ok,Artifact}=hls_deployment_artifact:load(filename:join(Binding,"mixed.etf")),
    #{actors:=Actors}=hls_deployment_artifact:descriptor(mixed_application,Artifact),
    Pids=maps:map(fun(_,#{module:=Module})->{ok,P}=Module:start_link(),unlink(P),P end,Actors),
    {ok,App}=hls_fabric:start_link(filename:join(Stage,"app_tx"),filename:join(Stage,"app_rx"),#{rx_route_limit=>1}),
    {ok,Debug}=hls_actor_broker_fixture:start(debug),
    {ok,Stream}=hls_protocol_mixed_stream:start_link(Artifact,App,Pids,Session,#{}),unlink(Stream),
    [_Local,Host]=string:split(atom_to_list(node()),"@"),
    Name=list_to_atom("mixed_live_"++integer_to_list(erlang:unique_integer([positive]))++"@"++Host),
    {ok,Node}=hls_node:start_link(Name,#{application=>App,debug=>Debug},[hls_protocol_mixed_host:service(Artifact,Stream,Pids)],#{}),unlink(Node),
    try
        pong=net_adm:ping(Name),
        Result=phi_protocol_repetition:run(hls_protocol_mixed_stream,Stream,N,8,123,60000),
        ok=file:write_file(filename:join(Stage,"application.json"),json:encode(Result#{replies:=[tuple_to_list(T)||T<-maps:get(replies,Result)]}),[exclusive]),
        ok=file:write_file(filename:join(Stage,"stream.json"),json:encode(hls_protocol_mixed_stream:info(Stream)),[exclusive]),
        #{io:=#{lease:=ALease}}=hls_fabric:info(App),
        ok=hls_protocol_mixed_stream:stop(Stream),catch hls_node:stop(Node),
        ok=hls_fabric:stop(App),ok=hls_actor_broker_fixture:stop(Debug),
        ok=file:write_file(filename:join(Stage,"done"),<<>>,[exclusive]),
        ok=hls_fabric:await_closed(ALease,5000),
        ok=file:write_file(filename:join(Stage,"result.json"),json:encode(Result#{descriptors_closed=>true,
            replies:=[tuple_to_list(T)||T<-maps:get(replies,Result)]}),[exclusive]),
        io:format("PASS actual mixed repetition ~p~n",[maps:without([events],Result)])
    after
        catch hls_protocol_mixed_stream:stop(Stream),catch hls_node:stop(Node),
        catch hls_fabric:stop(App),catch hls_actor_broker_fixture:stop(Debug),
        maps:foreach(fun(_,P)->catch hls_statem:stop(P) end,Pids)
    end.
