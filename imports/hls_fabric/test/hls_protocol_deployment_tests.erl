-module(hls_protocol_deployment_tests).
-moduledoc "Fresh multi-device bindings check ownership and the actual command/event codecs; these are compiler/host tests, not RTL witnesses.".
-include_lib("eunit/include/eunit.hrl").

%% The two native roles preserve global endpoint indices but accept only their own producers.
-spec binding_test() -> ok.
binding_test() ->
    Dir=filename:join("_build","deployment-binding-"++integer_to_list(erlang:system_time(nanosecond))),
    D=#{application:=A,devices:=Devices}=hls_protocol_deployment:write(config(),Dir),
    ?assertEqual([north,south],lists:sort(maps:keys(Devices))),
    #{partition := #{actors := BoundActors}} = A,
    ?assertEqual([{left, 0, north}, {right, 1, south}, {sink, 2, north}],
        [{Id, Index, Device} || #{id := Id, index := Index, device := Device} <- BoundActors]),
    #{directories := Directories} = D,
    [FirstBundle, SecondBundle] = [begin
        {ok, TransportBytes} = file:read_file(filename:join([Dir, Name, "transport.etf"])),
        #{bundle := Bundle} = binary_to_term(TransportBytes),
        Bundle
    end || {_Device, Name} <- lists:sort(maps:to_list(Directories))],
    %% Even fresh compiler-origin references agree: there was one preparation, not two recompilations.
    ?assertEqual(FirstBundle, SecondBundle),
    Payload=hls_protocol_application_binding:control(A,{host,all,{0,0,1,0},{total,12}}),
    ?assertEqual(20,byte_size(Payload)),
    ?assertEqual(20,byte_size(hls_protocol_application_binding:control(A,{host,all,{0,0,0,0},{total,12}}))),
    ok=events(A),
    ?assertException(error,_,hls_protocol_application_binding:control(A,{host,all,{0,0,2,0},{total,12}})),
    ?assertException(error,_,hls_protocol_application_binding:control(A,{host,all,{0,0,1,0},{value,12}})),
    {ok,Bytes}=file:read_file(filename:join(Dir,"deployment.etf")),?assertEqual(D,binary_to_term(Bytes)),ok.

%% Canonical record bytes and source ownership are both required for a typed external event.
-spec events(map()) -> ok.
events(A) ->
    Frame=(12 bsl 32) bor (3 bsl 24) bor 1,
    ?assertEqual({left,{value,12}},hls_protocol_application_binding:event(A,north,0,Frame)),
    ?assertEqual({right,{value,12}},hls_protocol_application_binding:event(A,south,1,Frame)),
    ?assertException(error,_,hls_protocol_application_binding:event(A,south,0,Frame)),
    ?assertException(error,_,hls_protocol_application_binding:event(A,north,0,Frame bor (1 bsl 64))),
    ?assertException(error,_,hls_protocol_application_binding:event(A,north,0,Frame bor (1 bsl 8))),ok.

%% Missing/duplicate ownership cannot yield a valid typed application, even with valid codecs.
-spec ownership_test() -> ok.
ownership_test() ->
    lists:foreach(fun(Is)->
        Dir=filename:join("_build","deployment-invalid-"++integer_to_list(erlang:system_time(nanosecond))),
        C=#{devices:=Ds}=config(),S=maps:get(south,Ds),
        ?assertException(error,_,hls_protocol_deployment:write(C#{devices:=Ds#{south:=S#{native_actors:=Is}}},Dir)),
        ?assertEqual(false, filelib:is_dir(Dir))
    end,[[left],[right,sink],[],[unknown],[right,right]]),ok.

%% Conflicting return addresses and malformed role maps also reject before output exists.
-spec endpoints_test() -> ok.
endpoints_test() ->
    C = #{devices := Ds = #{north := North, south := South}} = config(),
    lists:foreach(fun(Placement) ->
        Dir = filename:join("_build", "deployment-endpoint-" ++ integer_to_list(erlang:system_time(nanosecond))),
        ?assertException(error, _, hls_protocol_deployment:write(C#{devices := Ds#{south := Placement}}, Dir)),
        ?assertEqual(false, filelib:is_dir(Dir))
    end, [South#{host := maps:get(host, North), service := maps:get(service, North)},
          South#{host := 0}, South#{service := 65536}, South#{host := maps:get(service, South)},
          South#{sources => []}]),
    ok.

%% An undersized crossing budget rejects before hardware rendering, not merely before file writes.
-spec routing_before_render_test_() -> term().
routing_before_render_test_() -> {timeout, 30, fun routing_before_render/0}.

%% The positive control proves tracing observes both real role emitters.
-spec routing_before_render() -> ok.
routing_before_render() ->
    Config = #{limits := Limits} = config(),
    Directory = filename:join("_build", "deployment-routing-" ++ integer_to_list(erlang:system_time(nanosecond))),
    {ok, 0} = trace_bridges(fun() ->
        ?assertException(error, _, hls_protocol_deployment:write(
            Config#{limits := Limits#{crossings := 1}}, Directory)),
        ok
    end),
    ?assertEqual(false, filelib:is_dir(Directory)),
    {#{result := #{devices := Devices}}, Calls} = trace_bridges(fun() -> hls_protocol_deployment:emit(Config) end),
    ?assertEqual(2, map_size(Devices)),
    ?assertEqual(2, Calls).

%% A private session traces only this process; a delivery barrier excludes delayed trace messages.
-spec trace_bridges(fun(() -> term())) -> {term(), non_neg_integer()}.
trace_bridges(Build) ->
    {module, hls_protocol_bridge} = code:ensure_loaded(hls_protocol_bridge),
    {Collector, Monitor} = spawn_monitor(fun() -> collect_bridges(0) end),
    Session = trace:session_create(deployment_bridge_emission, Collector, []),
    try
        1 = trace:process(Session, self(), true, [call]),
        1 = trace:function(Session, {hls_protocol_bridge, emit, 1}, [], []),
        Result = Build(),
        1 = trace:process(Session, self(), false, [call]),
        Ref = trace:delivered(Session, self()),
        receive {trace_delivered, _, Ref} -> ok
        after 5000 -> error(bridge_trace_delivery_timeout) end,
        Collector ! {collect, self(), Ref},
        receive {Ref, Count} -> {Result, Count}
        after 5000 -> error(bridge_trace_collection_timeout) end
    after
        trace:session_destroy(Session),
        exit(Collector, kill),
        receive {'DOWN', Monitor, process, Collector, _} -> ok
        after 5000 -> error(bridge_trace_cleanup_timeout) end
    end.

%% Count actual bridge emission calls without retaining the source program arguments.
-spec collect_bridges(non_neg_integer()) -> ok.
collect_bridges(Count) ->
    receive
        %% A traced role has reached hardware generation.
        {trace, _, call, {hls_protocol_bridge, emit, [_]}} -> collect_bridges(Count + 1);
        %% Trace delivery was confirmed before this request was sent.
        {collect, Owner, Ref} -> Owner ! {Ref, Count}, ok
    end.

%% Arbitrary role names/addresses ensure the builder does not assume integer roles or service 7.
-spec config() -> map().
config() -> #{sources=>[{"test/hls_protocol_network_fixture.erl",[]},{"test/hls_protocol_inbox_fixture.erl",[]}],
    topology=>{hls_protocol_network_fixture,framed,[]},actor_limit=>3,control=>rectangle,
    devices=>#{north=>#{native_actors=>[left,sink],host=>2,service=>29},
        south=>#{native_actors=>[right],host=>3,service=>31}},limits=>#{crossings=>8,commands=>8,events=>8}}.
