-module(hls_protocol_relay_tests).
-moduledoc "Bounded relay rejection and physical-completion ownership tests; these do not model a device.".
-include_lib("eunit/include/eunit.hrl").

%% A pair head waits for credit; its source reservation spans two definite writes.
-spec ownership_test() -> ok.
ownership_test() ->
    Q=new(),P=packet(1,11,0,0),Q1=hls_protocol_relay_queue:event(0,P,Q),
    none=hls_protocol_relay_queue:next(Q1),
    Q2=hls_protocol_relay_queue:event(1,packet(2,12,0,0),Q1),
    {1,#{session:=12,sequence:=0,frame:=0},{data,0,0}=T,Q3}=hls_protocol_relay_queue:next(Q2),
    none=hls_protocol_relay_queue:next(Q3),
    Q4=hls_protocol_relay_queue:complete(T,Q3),
    {0,#{session:=11,sequence:=0,kind:=2},{ack,0,0}=A,Q5}=hls_protocol_relay_queue:next(Q4),
    #{records:=1}=hls_protocol_relay_queue:info(Q5),
    #{records:=0,forwarded:=1,acknowledged:=1}=hls_protocol_relay_queue:info(hls_protocol_relay_queue:complete(A,Q5)).

%% Stale/duplicate sequence, wrong endpoint, noncanonical payload and duplicate grants reject.
-spec rejection_test() -> ok.
rejection_test() ->
    Q=new(),
    lists:foreach(fun({R,P})->?assertException(error,_,hls_protocol_relay_queue:event(R,P,Q)) end,
        [{0,packet(1,99,0,0)},{0,packet(1,11,1,0)},{1,packet(1,12,0,0)},
         {0,(packet(1,11,0,0))#{frame:=1}},{0,(packet(1,11,0,0))#{slot:=1}}]),
    Pending=hls_protocol_relay_queue:event(0,packet(1,11,0,0),Q),
    ?assertException(error,_,hls_protocol_relay_queue:event(0,packet(1,11,1,0),Pending)),
    G=hls_protocol_relay_queue:event(1,packet(2,12,0,0),Q),
    ?assertException(error,_,hls_protocol_relay_queue:event(1,packet(2,12,1,0),G)),
    ?assertException(error,_,hls_protocol_relay_queue:next(hls_protocol_relay_queue:invalidate(Q))),ok.

%% ABI round trips preserve all packet fields and distinguish attach/start from actor traffic.
-spec wire_test() -> ok.
wire_test() ->
    Identity= <<42:256>>,{{1,0,0},<<11:64/little,Identity/binary>>}=hls_protocol_bridge_wire:attach(Identity,11),
    {{3,0,0},<<11:64/little,0:32>>}=hls_protocol_bridge_wire:command(11,start),
    P=packet(1,11,4,0),{{4,0,0},B}=hls_protocol_bridge_wire:packet(P),
    {packet,P}=hls_protocol_bridge_wire:event(11,{16#84,0,0},B),
    ?assertException(error,_,hls_protocol_bridge_wire:event(12,{16#84,0,0},B)),
    ?assertException(error,_,hls_protocol_bridge_wire:packet((packet(2,11,0,0))#{frame:=1})),ok.

%% Invalid endpoint types fail before reading sources or creating a build directory.
-spec endpoint_test() -> ok.
endpoint_test() ->
    lists:foreach(fun({H,S})->?assertError(function_clause,
        hls_protocol_bridge:write(#{native_actors=>[a],host=>H,service=>S},"unused")) end,
        [{1.5,7},{1,7.5},{0,7},{1,1},{1,65536}]),ok.

%% Session binding requires every checked role exactly once and distinct nonzero 64-bit identities.
-spec session_rejection_test() -> ok.
session_rejection_test() ->
    Routing = hls_protocol_routing:plan(deployment()),
    Sessions = sessions(),
    Invalid = [maps:remove(42, Sessions), Sessions#{unknown => 104}] ++
        [Sessions#{north := Value} || Value <- [0, -1, 1 bsl 64, 101.0, session, 102]],
    lists:foreach(fun(Binding) ->
        ?assertException(error, _, hls_protocol_relay_queue:new(Routing, Binding))
    end, Invalid).

%% Reusing checked routes never carries credit, counters or packet sequences into a fresh incarnation.
-spec reusable_routing_test() -> ok.
reusable_routing_test() ->
    Routing = hls_protocol_routing:plan(plan()),
    First = hls_protocol_relay_queue:new(Routing, #{0 => 11, 1 => 12}),
    Second = hls_protocol_relay_queue:new(Routing, #{0 => 21, 1 => 22}),
    FirstData = hls_protocol_relay_queue:event(0, packet(1, 11, 0, 0), First),
    FirstReady = hls_protocol_relay_queue:event(1, packet(2, 12, 0, 0), FirstData),
    {1, #{session := 12, sequence := 0}, Data, Writing} = hls_protocol_relay_queue:next(FirstReady),
    {0, _, Ack, Acking} = hls_protocol_relay_queue:next(hls_protocol_relay_queue:complete(Data, Writing)),
    Completed = hls_protocol_relay_queue:complete(Ack, Acking),
    ?assertMatch(#{forwarded := 1, acknowledged := 1}, hls_protocol_relay_queue:info(Completed)),
    ?assertMatch(#{events := #{0 := 0, 1 := 0}, available_credits := 0,
        records := 0, forwarded := 0, acknowledged := 0}, hls_protocol_relay_queue:info(Second)),
    SecondData = hls_protocol_relay_queue:event(0, packet(1, 21, 0, 0), Second),
    ?assertEqual(none, hls_protocol_relay_queue:next(SecondData)),
    SecondReady = hls_protocol_relay_queue:event(1, packet(2, 22, 0, 0), SecondData),
    ?assertMatch({1, #{session := 22, sequence := 0}, {data, 0, 0}, _},
        hls_protocol_relay_queue:next(SecondReady)).

%% One fully constant canonical frame suffices to test ownership without a fake compiler.
-spec plan() -> map().
plan() ->
    C=#{slot=>0,codec=>hls_protocol_codec_plan:plan(#{message_bits=>0,payload_bits=>0,fields=>[]},0)},
    L=#{index=>0,source_index=>0,destination_index=>1,classes=>[C]},
    #{actors=>2,limits=>#{crossings=>8},devices=>maps:from_list([{R,#{native_indices=>[R],links=>[L#{direction=>D}]}}
        ||{R,D}<-[{0,outgoing},{1,incoming}]])}.

%% Every test starts with no granted credits and distinct fresh sessions.
-spec new() -> hls_protocol_relay_queue:state().
new() -> hls_protocol_relay_queue:new(hls_protocol_routing:plan(plan()), #{0 => 11, 1 => 12}).
%% One packet identity is retained across destination forwarding and source acknowledgment.
-spec packet(1|2,pos_integer(),non_neg_integer(),non_neg_integer()) -> hls_protocol_relay_queue:packet().
packet(Kind,Session,Seq,Link) -> #{kind=>Kind,session=>Session,sequence=>Seq,link=>Link,slot=>0,frame=>0}.

%% Three arbitrary device keys and irregular endpoints expose accidental two-board assumptions.
-spec deployment_stream_test() -> ok.
deployment_stream_test() ->
    with_deployment(fun(Stream,Peers,Sessions)->
        First=maps:get(42,Peers),North=maps:get(north,Peers),South=maps:get({tile,south},Peers),
        ok=hls_protocol_relay_peer:set(First,hold),
        {ok,1}=hls_protocol_stream:submit(Stream,{control,<<0:128>>}),
        await(fun()->maps:get(held,hls_protocol_relay_peer:stats(First))=/=none end),
        ?assertEqual({error,busy},hls_protocol_stream:submit(Stream,{control,<<0:128>>})),
        ok=hls_protocol_relay_peer:set(First,normal),
        await(fun()->#{counts:=C}=hls_protocol_stream:info(Stream),maps:get(commands,C)+maps:get(writer,C)=:=0 end),
        {ok,1}=hls_protocol_stream:submit(Stream,start),
        await(fun()->#{phases:=P}=hls_protocol_stream:info(Stream),lists:usort(maps:values(P))=:=[starting] end),
        [ok=started(R,Peers,Sessions)||R<-[42,north]],
        ok=hls_protocol_relay_peer:emit(North,{16#85,0,0},<<101:64/little,0:128>>),
        ?assertEqual(timeout,hls_protocol_stream:next(Stream,10)),
        ok=started({tile,south},Peers,Sessions),
        ?assertEqual({ok,application,{started}},hls_protocol_stream:next(Stream,1000)),
        ?assertEqual({ok,{north,0},0},hls_protocol_stream:next(Stream,1000)),
        %% One source has two actual destinations; the uncredited first route is bypassed.
        ok=emit_packet(North,packet(1,101,0,0)),ok=emit_packet(North,packet(1,101,1,1)),
        ok=emit_packet(South,packet(2,103,0,1)),
        await(fun()->#{packets:=#{acknowledged:=N}}=hls_protocol_stream:info(Stream),N=:=1 end),
        ?assertEqual([#{kind=>1,session=>103,sequence=>0,link=>1,slot=>0,frame=>0}],packets(South)),
        ?assertEqual([#{kind=>2,session=>101,sequence=>1,link=>1,slot=>0,frame=>0}],packets(North)),
        %% A delayed forwarding completion cannot release the original source reservation.
        ok=hls_protocol_relay_peer:set(First,hold),ok=emit_packet(First,packet(2,102,0,0)),
        await(fun()->maps:get(held,hls_protocol_relay_peer:stats(First))=/=none end),
        #{packets:=#{records:=1,acknowledged:=1},record_limit:=9}=hls_protocol_stream:info(Stream),
        ?assertEqual(1,length(packets(North))),
        ok=hls_protocol_relay_peer:set(First,normal),
        await(fun()->#{packets:=#{acknowledged:=N}}=hls_protocol_stream:info(Stream),N=:=2 end),
        ?assertEqual([#{kind=>1,session=>102,sequence=>0,link=>0,slot=>0,frame=>0}],packets(First)),
        ok=hls_protocol_stream:stop(Stream),
        await(fun()->lists:all(fun(P)->maps:get(owner,hls_protocol_relay_peer:stats(P))=:=retired end,maps:values(Peers)) end)
    end).

%% Artifact projection retains the bounded external interface consumed by relay events.
-spec artifact_external_event_test() -> ok.
artifact_external_event_test() ->
    with_deployment(fun(Stream, Peers, Sessions) ->
        {ok, 1} = hls_protocol_stream:submit(Stream, start),
        [ok = started(Role, Peers, Sessions) || Role <- [42, north, {tile, south}]],
        ?assertEqual({ok, application, {started}}, hls_protocol_stream:next(Stream, 1000)),
        ok = hls_protocol_relay_peer:emit(
            maps:get(north, Peers),
            {16#85, 0, 0},
            <<101:64/little, 0:128>>
        ),
        ?assertEqual({ok, {north, 0}, 0}, hls_protocol_stream:next(Stream, 1000))
    end).

%% A raw relay artifact cannot silently enter the typed application path.
-spec raw_application_rejection_test() -> ok.
raw_application_rejection_test() ->
    Artifact = hls_deployment_artifact:new(protocol_deployment, deployment()),
    ?assertException(
        error,
        {badmatch, _},
        hls_protocol_stream:start_application(Artifact, #{}, #{})
    ),
    ok.

%% A peer can consume an ACK and reply before the broker reports that write's completion.
-spec acknowledgment_completion_race_test() -> ok.
acknowledgment_completion_race_test() ->
    with_deployment(fun(Stream, Peers, _) ->
        Source = maps:get(north, Peers), Destination = maps:get(42, Peers),
        ok = hls_protocol_relay_peer:set(Source, hold),
        try
            ok = emit_packet(Destination, packet(2, 102, 0, 0)),
            ok = emit_packet(Source, packet(1, 101, 0, 0)),
            await(fun() -> maps:get(held, hls_protocol_relay_peer:stats(Source)) =/= none end),
            %% The ACK is on the wire, but its local completion notification is delayed.
            ok = emit_packet(Source, packet(1, 101, 1, 0)),
            await(fun() -> #{counts := #{held := Held}} = hls_protocol_stream:info(Stream), Held =:= 1 end),
            #{counts := #{writer := 1}, packets := #{records := 1, acknowledged := 0}} = hls_protocol_stream:info(Stream),
            ?assertNotEqual(none, maps:get(receipt, hls_protocol_relay_peer:stats(Source))),
            ?assertEqual(1, length(packets(Destination))),
            ok = emit_packet(Destination, packet(2, 102, 1, 0)),
            ok = hls_protocol_relay_peer:set(Source, normal),
            await(fun() -> #{packets := #{acknowledged := N}} = hls_protocol_stream:info(Stream), N =:= 2 end),
            ?assertEqual([0, 1], [N || #{kind := 1, sequence := N} <- packets(Destination)]),
            ?assertEqual([0, 1], [N || #{kind := 2, sequence := N} <- packets(Source)]),
            #{counts := #{held := 0}, packets := #{records := 0}} = hls_protocol_stream:info(Stream)
        after
            catch hls_protocol_relay_peer:set(Source, normal)
        end
    end).

%% Losing any member retires the remaining participants without replay or replacement.
-spec deployment_failure_test() -> ok.
deployment_failure_test() ->
    with_deployment(fun(Stream,Peers,_)->
        Ref=monitor(process,Stream),exit(maps:get({tile,south},Peers),kill),
        receive {'DOWN',Ref,process,Stream,_}->ok after 1000->error(owner_survived) end,
        await(fun()->lists:all(fun(R)->maps:get(owner,hls_protocol_relay_peer:stats(maps:get(R,Peers)))=:=retired end,[42,north]) end)
    end).

%% A three-node fanout uses ordinary constant codecs, not application arithmetic.
-spec deployment() -> map().
deployment() ->
    C=#{slot=>0,codec=>hls_protocol_codec_plan:plan(#{message_bits=>0,payload_bits=>0,fields=>[]},0)},
    Links=[#{index=>I,source_index=>0,destination_index=>I+1,classes=>[C]}||I<-[0,1]],
    Devices=maps:from_list([{R,#{native_indices=>[I],host=>H,service=>V,identity=><<I:256>>,externals=>[#{index=>0}],
        links=>[L#{direction=>case I of 0->outgoing;_->incoming end}||L=#{destination_index:=D}<-Links,I=:=0 orelse I=:=D]}}
        ||{R,I,H,V}<-[{north,0,55,301},{42,1,55,911},{{tile,south},2,77,301}]]),
    #{actors=>3,devices=>Devices,limits=>#{crossings=>2,commands=>1,events=>2}}.
%% Incarnation identities are independent of arbitrary device keys.
-spec sessions() -> map().
sessions()->#{north=>101,42=>102,{tile,south}=>103}.
%% Every test gets fresh brokers and a fresh deployment owner; no model claims physical reset.
-spec with_deployment(fun((pid(),map(),map())->term())) -> ok.
with_deployment(Fun)->
    Plan=#{devices:=Devices}=deployment(),Sessions=sessions(),
    Peers=maps:map(fun(_,B)->{ok,P}=hls_protocol_relay_peer:start(B),P end,Devices),
    Artifact=hls_deployment_artifact:new(protocol_deployment,Plan),
    {ok,Stream}=hls_protocol_stream:start_link(Artifact,Peers,Sessions),unlink(Stream),
    try await(fun()->maps:get(phase,hls_protocol_stream:info(Stream))=:=attached end),Fun(Stream,Peers,Sessions),ok
    after catch hls_protocol_stream:stop(Stream),[catch gen_server:stop(P)||P<-maps:values(Peers)] end.
%% Inject a start acknowledgment only after the test observes the actual start write.
-spec started(term(),map(),map()) -> ok.
started(R,Peers,Sessions)->S=maps:get(R,Sessions),hls_protocol_relay_peer:emit(maps:get(R,Peers),{16#83,0,0},<<S:64/little,0:32>>).
%% Device output and host forwarding use the same packet layout with different envelope operations.
-spec emit_packet(pid(),map()) -> ok.
emit_packet(P,Packet)->{_,Bytes}=hls_protocol_bridge_wire:packet(Packet),hls_protocol_relay_peer:emit(P,{16#84,0,0},Bytes).
%% Inspect only complete public packet writes, retaining their issue order.
-spec packets(pid()) -> [map()].
packets(P)->
    #{writes:=Writes}=hls_protocol_relay_peer:stats(P),
    [begin <<_:8,S:64,_/bitstring>>= <<(binary:decode_unsigned(B,little)):256>>,
        {packet,Packet}=hls_protocol_bridge_wire:event(S,{16#84,0,0},B),Packet end
        ||{_,{4,0,0},B}<-lists:reverse(Writes)].
%% Wait on meaningful asynchronous state transitions with a finite deadline.
-spec await(fun(()->boolean())) -> ok.
await(F)->hls_bridge_phi_live:await(F,1000).

%% Invalid endpoints, event capacities and static crossing budgets fail before broker registration.
-spec endpoint_binding_rejection_test() -> ok.
endpoint_binding_rejection_test() ->
    P=#{devices:=D}=deployment(),Sessions=sessions(),
    Peers=maps:map(fun(_,B)->{ok,Peer}=hls_protocol_relay_peer:start(B),Peer end,D),
    try
        South=maps:get({tile,south},D),North=maps:get(north,D),
        Ambiguous=P#{devices:=D#{{tile,south}:=South#{host:=maps:get(host,North),service:=maps:get(service,North)}}},
        ?assertError({badmatch,false},hls_protocol_stream:init({Ambiguous,Peers,Sessions,self(),raw})),
        ?assertError(function_clause,hls_protocol_stream:init({P#{limits:=#{crossings=>2,commands=>1,events=>1}},Peers,Sessions,self(),raw})),
        ?assertException(error, _, hls_protocol_stream:init({
            P#{limits := #{crossings => 1, commands => 1, events => 2}}, Peers, Sessions, self(), raw})),
        [?assertEqual(none,maps:get(owner,hls_protocol_relay_peer:stats(Peer)))||Peer<-maps:values(Peers)]
    after [gen_server:stop(Peer)||Peer<-maps:values(Peers)] end,ok.


%% A queued fanout precedes eligible ACKs; an ACK precedes another credited pair.
%% Held broker completions expose each boundary without timing assumptions.
-spec write_priority_test() -> ok.
write_priority_test() ->
    with_deployment(fun(Stream, Peers, _) ->
        Source = maps:get(north, Peers),
        First = maps:get(42, Peers),
        Second = maps:get({tile,south}, Peers),
        [ok = hls_protocol_relay_peer:set(Peer, hold) || Peer <- maps:values(Peers)],
        try
            ok = emit_packet(First, packet(2, 102, 0, 0)),
            ok = emit_packet(Source, packet(1, 101, 0, 0)),
            await_held(First),
            {ok, 1} = hls_protocol_stream:submit(Stream, {control, <<0:128>>}),
            ok = emit_packet(Second, packet(2, 103, 0, 1)),
            ok = emit_packet(Source, packet(1, 101, 1, 1)),
            await(fun() -> #{received := Count} = hls_protocol_stream:info(Stream), Count =:= 7 end),
            ok = hls_protocol_relay_peer:set(First, normal),
            await_held(Source),
            ?assertEqual([2], operations(Source)),
            ?assertEqual([], operations(Second)),
            ok = hls_protocol_relay_peer:set(Source, normal),
            await_held(Second),
            ?assertEqual([2], operations(Source)),
            ?assertEqual([2], operations(Second)),
            ok = hls_protocol_relay_peer:set(Source, hold),
            ok = hls_protocol_relay_peer:set(Second, normal),
            await_held(Source),
            ?assertMatch([#{kind := 2, link := 0}], packets(Source)),
            ?assertEqual([2], operations(Second)),
            ok = hls_protocol_relay_peer:set(Source, normal),
            await(fun() -> #{packets := #{acknowledged := Count}} = hls_protocol_stream:info(Stream), Count =:= 2 end),
            ?assertEqual([4, 2], operations(First)),
            ?assertEqual([2, 4], operations(Second)),
            ?assertEqual([0, 1], [Link || #{kind := 2, link := Link} <- packets(Source)])
        after
            [catch hls_protocol_relay_peer:set(Peer, normal) || Peer <- maps:values(Peers)]
        end
    end).

%% Graceful retirement waits for its physical writer and abandons queued fanout.
-spec retire_held_writer_test() -> ok.
retire_held_writer_test() ->
    with_deployment(fun(Stream, Peers, _) ->
        First = maps:get(42, Peers),
        ok = hls_protocol_relay_peer:set(First, hold),
        try
            {ok, 1} = hls_protocol_stream:submit(Stream, {control, <<0:128>>}),
            await_held(First),
            Monitor = monitor(process, Stream),
            Request = gen_server:send_request(Stream, retire),
            #{counts := #{writer := 1}} = hls_protocol_stream:info(Stream),
            ?assertEqual(timeout, gen_server:wait_response(Request, 0)),
            ok = hls_protocol_relay_peer:set(First, normal),
            ?assertEqual({reply, ok}, gen_server:wait_response(Request, 1000)),
            receive {'DOWN', Monitor, process, Stream, normal} -> ok
            after 1000 -> error(retirement_timeout) end,
            ?assertEqual([], operations(maps:get(north, Peers))),
            ?assertEqual([], operations(maps:get({tile,south}, Peers)))
        after
            catch hls_protocol_relay_peer:set(First, normal)
        end
    end).

%% Even a definitely-unsent error retires every route without advancing or replaying fanout.
-spec write_failure_test() -> ok.
write_failure_test() ->
    with_deployment(fun(Stream, Peers, _) ->
        First = maps:get(42, Peers),
        ok = hls_protocol_relay_peer:set(First, hold),
        try
            {ok, 1} = hls_protocol_stream:submit(Stream, {control, <<0:128>>}),
            await_held(First),
            Monitor = monitor(process, Stream),
            ok = hls_protocol_relay_peer:fail(First, {error, unsent}),
            receive {'DOWN', Monitor, process, Stream, {shutdown, {write_failed, {error, unsent}}}} -> ok
            after 1000 -> error(failed_owner_survived) end,
            await(fun() -> lists:all(fun(Peer) ->
                maps:get(owner, hls_protocol_relay_peer:stats(Peer)) =:= retired
            end, maps:values(Peers)) end),
            ?assertEqual([2], operations(First)),
            ?assertEqual([], operations(maps:get(north, Peers))),
            ?assertEqual([], operations(maps:get({tile,south}, Peers)))
        after
            catch hls_protocol_relay_peer:set(First, normal)
        end
    end).

%% Observe request issue order through the broker model's public wire log.
-spec operations(pid()) -> [byte()].
operations(Peer) ->
    #{writes := Writes} = hls_protocol_relay_peer:stats(Peer),
    [Operation || {_, {Operation, _, _}, _} <- lists:reverse(Writes)].

%% Each pause ends only when the selected broker has retained a real request.
-spec await_held(pid()) -> ok.
await_held(Peer) ->
    await(fun() -> maps:get(held, hls_protocol_relay_peer:stats(Peer)) =/= none end).


%% Only the exact reserved write may complete; completion cannot be replayed across phases.
-spec completion_token_test() -> ok.
completion_token_test() ->
    Pending = hls_protocol_relay_queue:event(0, packet(1, 11, 0, 0), new()),
    Ready = hls_protocol_relay_queue:event(1, packet(2, 12, 0, 0), Pending),
    {1, _, Data, Writing} = hls_protocol_relay_queue:next(Ready),
    ?assertException(error, _, hls_protocol_relay_queue:complete({ack, 0, 0}, Writing)),
    ?assertEqual(none, hls_protocol_relay_queue:next(Writing)),
    AckReady = hls_protocol_relay_queue:complete(Data, Writing),
    ?assertException(error, _, hls_protocol_relay_queue:complete(Data, AckReady)),
    {0, _, Ack, Acking} = hls_protocol_relay_queue:next(AckReady),
    ?assertException(error, _, hls_protocol_relay_queue:complete({ack, 0, 1}, Acking)),
    Done = hls_protocol_relay_queue:complete(Ack, Acking),
    ?assertMatch(#{records := 0, forwarded := 1, acknowledged := 1}, hls_protocol_relay_queue:info(Done)).
