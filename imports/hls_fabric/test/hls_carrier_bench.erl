-module(hls_carrier_bench).
%% Host-path microbenchmark. The broker double replies immediately to a packed
%% ping: this deliberately excludes physical I/O and device execution time.
-behaviour(gen_server).
-export([run/1, init/1, handle_call/3, handle_cast/2]).

run(Mode) ->
    hls_test_nodes:distribution(),
    application:ensure_all_started(crypto),
    Existing = processes(),
    {ok, App} = gen_server:start_link(?MODULE, [], []),
    {ok, Debug} = gen_server:start_link(?MODULE, [], []),
    {Pid, Stop} = endpoint(Mode, App, Debug),
    [V = regsvc:ping(Pid, V) || V <- lists:seq(1, 300)],
    Owned = [self() | processes() -- Existing],
    [catch erlang:garbage_collect(P) || P <- Owned],
    {GC0, Words0, _} = erlang:statistics(garbage_collection),
    {Reductions0, _} = erlang:statistics(reductions),
    Start = erlang:monotonic_time(microsecond),
    Latencies = [begin
        T = erlang:monotonic_time(nanosecond),
        V = regsvc:ping(Pid, V),
        (erlang:monotonic_time(nanosecond) - T) / 1000
    end || V <- lists:seq(1, 3000)],
    LatencyElapsed = erlang:monotonic_time(microsecond) - Start,
    StartBatch = erlang:monotonic_time(microsecond),
    pipeline(Pid, 12800, 64),
    BatchElapsed = erlang:monotonic_time(microsecond) - StartBatch,
    {Reductions1, _} = erlang:statistics(reductions),
    [catch erlang:garbage_collect(P) || P <- Owned],
    {GC1, Words1, _} = erlang:statistics(garbage_collection),
    %% Separate memory pass: sampling and its allocations must not perturb the
    %% timed results. Full GC above makes the starting condition explicit.
    Parent = self(),
    Sampler = spawn_link(fun() -> sample(Parent, Owned, 0) end),
    pipeline(Pid, 12800, 64),
    Sampler ! stop,
    Peak = receive {sampled_memory, Sampler, Bytes} -> Bytes end,
    Sorted = lists:sort(Latencies),
    Result = #{mode => Mode, otp => list_to_binary(erlang:system_info(otp_release)),
        erts => list_to_binary(erlang:system_info(version)), schedulers => erlang:system_info(schedulers_online),
        sequential_calls => 3000, pipeline_calls => 12800, pipeline_window => 64,
        latency_mean_us => lists:sum(Latencies) / 3000,
        latency_p50_us => lists:nth(1500, Sorted), latency_p99_us => lists:nth(2970, Sorted),
        sequential_elapsed_us => LatencyElapsed, pipeline_elapsed_us => BatchElapsed,
        pipeline_calls_per_second => 12800 * 1000000 / BatchElapsed,
        gc_count => GC1 - GC0, gc_words_reclaimed => Words1 - Words0,
        reductions => Reductions1 - Reductions0,
        sampled_process_memory_bytes => Peak, owned_process_count => length(Owned)},
    io:format("BENCH ~s~n", [json:encode(Result)]),
    Stop(), gen_server:stop(App), gen_server:stop(Debug), ok.

endpoint(proxy, App, _Debug) ->
    {ok, Pid} = hls_gs:start_link(regsvc, [], [{fabric, App, 1, 1}]),
    {Pid, fun() -> hls_gs:stop(Pid) end};
endpoint(Mode, App, Debug) when Mode =:= tcp; Mode =:= local ->
    [_Name, Host] = string:split(atom_to_list(node()), "@"),
    Name = list_to_atom("benchmark_fpga@" ++ Host),
    {ok, Node} = hls_node:start_link(Name, #{application => App, debug => Debug},
        [#{name => registers, module => regsvc, endpoint => 1}], #{}),
    #{registers := #{application := Pid}} = hls_node:services(Node),
    0 = regsvc:ping(Pid, 0),
    #{connections := Connections} = hls_node:info(Node),
    [#{carrier := Mode}] = maps:values(Connections),
    {Pid, fun() -> hls_node:stop(Node) end}.

pipeline(_Pid, 0, _Window) -> ok;
pipeline(Pid, Remaining, Window) ->
    IDs = [{V, gen_server:send_request(Pid, {ping, V})} || V <- lists:seq(1, Window)],
    [{reply, {ack, V}} = gen_server:receive_response(ID, 5000) || {V, ID} <- IDs],
    pipeline(Pid, Remaining - Window, Window).

sample(Parent, Pids, Peak) ->
    Size = lists:sum([N || P <- Pids, {memory, N} <- [process_info(P, memory)]]),
    Next = max(Peak, Size),
    receive stop -> Parent ! {sampled_memory, self(), Next}
    after 1 -> sample(Parent, Pids, Next) end.

init([]) -> {ok, #{}}.
handle_call(info, _From, Routes) -> {reply, #{routes => Routes}, Routes};
handle_call({register_route, Route, Owner}, _From, Routes) ->
    {reply, ok, Routes#{Route => Owner}};
handle_call({send, {Source, Dest}, {Tag, Tx, 0}, <<Value:32/little>>, _Deadline}, From, Routes) ->
    Tag = regsvc:pack_tag(ping),
    Owner = maps:get({Dest, Source}, Routes),
    gen_server:reply(From, ok),
    gen_server:cast(Owner, {'$hls_fabric_frame', make_ref(), {Dest, Source},
        {regsvc:pack_tag(ack), Tx, 0}, <<Value:32/little>>}),
    {noreply, Routes}.
handle_cast({ack, _, _}, Routes) -> {noreply, Routes}.
