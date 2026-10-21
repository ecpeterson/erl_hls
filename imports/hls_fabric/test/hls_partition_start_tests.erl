-module(hls_partition_start_tests).
-moduledoc "Finite broker-model witnesses for ordered, credited application activation; hardware handshake tests are separate.".
-include_lib("eunit/include/eunit.hrl").

%% A start cannot pass a stalled setup write, and write completion is not activation.
-spec ordered_start_test() -> ok.
ordered_start_test() ->
    with_connection(4, fun(S, P) ->
        ok = hls_partition_peer:set(P, hold),
        ?assertEqual({ok, 1}, hls_partition_stream:submit(S, command())),
        ?assertEqual({ok, 1}, hls_partition_stream:submit(S, start)),
        ?assertMatch({error, {invalid_command, start_unavailable}}, hls_partition_stream:submit(S, start)),
        await(fun() -> length(maps:get(controls, hls_partition_peer:stats(P))) =:= 1 end),
        ?assertMatch(#{activation := #{a := start_pending}}, hls_partition_stream:info(S)),
        ok = hls_partition_peer:set(P, normal),
        await(fun() -> maps:get(pending, hls_partition_stream:info(S)) =:= 0 end),
        ?assertMatch([{{1,7}, _}, {start,{1,7}}], maps:get(controls, hls_partition_peer:stats(P))),
        ?assertEqual(timeout, hls_partition_stream:next(S, 1)),
        ?assertMatch(#{activation := #{a := start_pending}}, hls_partition_stream:info(S)),
        ok = hls_partition_peer:emit(P, reply()),
        await(fun() -> maps:get(received, hls_partition_stream:info(S)) =:= 1 end),
        ?assertEqual(1, maps:get(receipts, hls_partition_peer:stats(P))),
        ?assertEqual({ok, a, application, {started}}, hls_partition_stream:next(S, 1000)),
        ?assertMatch(#{activation := #{a := running}}, hls_partition_stream:info(S)),
        await(fun() -> maps:get(receipts, hls_partition_peer:stats(P)) =:= 0 end),
        ?assertMatch({error, {invalid_command, start_unavailable}}, hls_partition_stream:submit(S, start))
    end).

%% Failed queue admission does not consume the activation opportunity.
-spec busy_start_test() -> ok.
busy_start_test() ->
    with_connection(1, fun(S, P) ->
        ok = hls_partition_peer:set(P, hold),
        ?assertEqual({ok, 1}, hls_partition_stream:submit(S, command())),
        ?assertEqual({error, busy}, hls_partition_stream:submit(S, start)),
        ?assertMatch(#{activation := #{a := configured}}, hls_partition_stream:info(S)),
        ok = hls_partition_peer:set(P, normal),
        await(fun() -> maps:get(pending, hls_partition_stream:info(S)) =:= 0 end),
        ?assertEqual({ok, 1}, hls_partition_stream:submit(S, start))
    end).

%% Unsolicited, duplicate and noncanonical replies cannot become plausible activation.
-spec invalid_start_reply_test() -> ok.
invalid_start_reply_test() ->
    lists:foreach(fun(Kind) -> with_connection(4, fun(S,P) ->
        Ref = monitor(process,S),
        case Kind of
            duplicate ->
                {ok,1} = hls_partition_stream:submit(S,start),
                ok = hls_partition_peer:emit(P,reply()),
                {ok,a,application,{started}} = hls_partition_stream:next(S,1000);
            _ -> ok
        end,
        Packet = case Kind of
            malformed -> {{7,1},{16#83,0,0},<<1:32>>};
            _ -> reply()
        end,
        ok = hls_partition_peer:emit(P,Packet),
        receive {'DOWN',Ref,process,S,Reason} -> ?assertMatch({invalid_event,a,_,_},Reason)
        after 1000 -> error(no_abort) end
    end) end,[unsolicited,duplicate,malformed]).

%% Device B can acknowledge while A is stalled; neither receipt is a global barrier.
-spec independent_devices_test() -> ok.
independent_devices_test() ->
    D = #{devices := Devices} = deployment(),
    Peers = maps:map(fun(_, B) -> {ok, P} = hls_partition_peer:start(B), P end, Devices),
    {ok, S} = hls_partition_stream:start_link(D, Peers, #{queue_limit => 4}),
    unlink(S),
    try
        A = maps:get(a, Peers), B = maps:get(b, Peers),
        ok = hls_partition_peer:set(A, hold),
        ?assertEqual({ok, 1}, hls_partition_stream:submit(S, command())),
        ?assertEqual({ok, 2}, hls_partition_stream:submit(S, start)),
        await(fun() -> maps:get(controls, hls_partition_peer:stats(B)) =:= [{start, {2,7}}] end),
        ok = hls_partition_peer:emit(B, {{7,2}, {16#83,0,0}, <<0:32>>}),
        ?assertEqual({ok, b, application, {started}}, hls_partition_stream:next(S, 1000)),
        ?assertMatch(#{activation := #{a := start_pending, b := running}}, hls_partition_stream:info(S)),
        ok = hls_partition_peer:set(A, normal),
        await(fun() -> maps:get(pending, hls_partition_stream:info(S)) =:= 0 end),
        ?assertMatch([{{1,7}, _}, {start,{1,7}}], maps:get(controls, hls_partition_peer:stats(A))),
        ok = hls_partition_peer:emit(A, reply()),
        ?assertEqual({ok, a, application, {started}}, hls_partition_stream:next(S, 1000)),
        ?assertMatch(#{activation := #{a := running, b := running}}, hls_partition_stream:info(S))
    after
        catch hls_partition_stream:stop(S),
        maps:foreach(fun(_, P) -> catch gen_server:stop(P) end, Peers)
    end.

%% Automatic bindings cannot silently acquire explicit-start semantics.
-spec automatic_start_rejected_test() -> ok.
automatic_start_rejected_test() ->
    #{devices := #{a := B0}} = deployment(),
    B = maps:remove(activation, B0),
    {ok, P} = hls_partition_peer:start(B),
    {ok, S} = hls_partition_stream:start_link(#{devices => #{a => B}}, #{a => P}, #{}),
    unlink(S),
    try
        ?assertMatch({error, {invalid_command, start_unavailable}}, hls_partition_stream:submit(S, start)),
        ?assertEqual([], maps:get(controls, hls_partition_peer:stats(P))),
        ?assertMatch(#{activation := #{a := automatic}}, hls_partition_stream:info(S))
    after catch hls_partition_stream:stop(S), catch gen_server:stop(P) end.

%% Reuse public topology codecs for two independently attached device models.
-spec deployment() -> map().
deployment() ->
    Spec = #{version => 1, actors => #{}, families => #{cells => #{module => hls_partition_fixture, shape => [2,1]}},
        ingresses => [{control,{rectangle,[2,1]},[{cells,[work],[{family,cells,{embed,[1,1],[0,0]}}]}]}],
        externals => [{reports,out,[work]}], routes => [], startup => [],
        route_relations => [{{cells,Port},[{external,reports}]} || Port <- [left,right,report]]},
    Partition = hls_partition:normalize(hls_topology:normalize(Spec),
        #{{family,cells,[0,0]} => a,{family,cells,[1,0]} => b}),
    D = #{devices := Devices} = hls_partition_wire:deployment(Partition),
    D#{devices := maps:map(fun(_,B) -> B#{activation => explicit_start} end,Devices)}.

%% Reset ownership between model cases; real deployment reset covers hardware and transport.
-spec with_connection(pos_integer(), fun((pid(),pid()) -> term())) -> ok.
with_connection(Limit,Fun) ->
    D0 = #{devices := #{a := B}} = deployment(),
    D = D0#{devices := #{a => B}},
    {ok,P} = hls_partition_peer:start(B),
    {ok,S} = hls_partition_stream:start_link(D,#{a => P},#{queue_limit => Limit}),
    unlink(S),
    try Fun(S,P),ok after catch hls_partition_stream:stop(S),catch gen_server:stop(P) end.

%% One setup-like typed command precedes activation in the same device queue.
-spec command() -> tuple().
command() -> {control,cells,{0,0,0,0},{work,42}}.

%% Canonical start completion has one zero payload word and no flags or transaction tag.
-spec reply() -> tuple().
reply() -> {{7,1},{16#83,0,0},<<0:32>>}.

%% Observe asynchronous broker state without assuming relative process scheduling.
-spec await(fun(() -> boolean())) -> ok.
await(Fun) -> hls_bridge_phi_live:await(Fun,1000).
