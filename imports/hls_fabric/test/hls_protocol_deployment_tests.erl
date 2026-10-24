-module(hls_protocol_deployment_tests).
-moduledoc "Fresh multi-device bindings check ownership and the actual command/event codecs; these are compiler/host tests, not RTL witnesses.".
-include_lib("eunit/include/eunit.hrl").

%% The two native roles preserve global endpoint indices but accept only their own producers.
-spec binding_test() -> ok.
binding_test() ->
    Dir=filename:join("_build","deployment-binding-"++integer_to_list(erlang:system_time(nanosecond))),
    D=#{application:=A,devices:=Devices}=hls_protocol_deployment:write(config(),Dir),
    ?assertEqual([north,south],lists:sort(maps:keys(Devices))),
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

%% Arbitrary role names/addresses ensure the builder does not assume integer roles or service 7.
-spec config() -> map().
config() -> #{sources=>[{"test/hls_protocol_network_fixture.erl",[]},{"test/hls_protocol_inbox_fixture.erl",[]}],
    topology=>{hls_protocol_network_fixture,framed,[]},actor_limit=>3,control=>rectangle,
    devices=>#{north=>#{native_actors=>[left,sink],host=>2,service=>29},
        south=>#{native_actors=>[right],host=>3,service=>31}},limits=>#{crossings=>8,commands=>8,events=>8}}.
